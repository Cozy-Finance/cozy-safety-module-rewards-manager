// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, ReservePool} from "./structs/Pools.sol";
import {ClaimableRewardsData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsManagerCalculationsLib} from "./RewardsManagerCalculationsLib.sol";

abstract contract Staker is RewardsManagerCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IReceiptToken;

  /// @dev Emitted when a user stakes.
  event Staked(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed stkReceiptToken_,
    uint256 safetyModuleReceiptTokenAmount_,
    uint256 stkReceiptTokenAmount_
  );

  /// @dev Emitted when a user unstakes.
  event Unstaked(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed stkReceiptToken_,
    uint256 stkReceiptTokenAmount_,
    uint256 safetyModuleReceiptTokenAmount_
  );

  error InsufficientBalance();

  /// @notice Stake by minting `stkReceiptTokenAmount_` stkTokens to `receiver_` after depositing exactly
  /// `safetyModuleReceiptTokenAmount_` of the safety module receipt token.
  /// @dev Assumes that `from_` has already approved this contract to transfer `safetyModuleReceiptTokenAmount_` of the
  /// safety module receipt token.
  function stake(uint16 reservePoolId_, uint256 safetyModuleReceiptTokenAmount_, address receiver_, address from_)
    external
    returns (uint256 stkReceiptTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IReceiptToken safetyModuleReceiptToken_ = reservePool_.safetyModuleReceiptToken;
    AssetPool storage assetPool_ = assetPools[safetyModuleReceiptToken_];

    // We don't need to check if the rewards manager received enough safety module receipt tokens after the transfer
    // because they are not fee on transfer tokens, and the rewards manager can only be configured with them.
    safetyModuleReceiptToken_.safeTransferFrom(from_, address(this), safetyModuleReceiptTokenAmount_);
    stkReceiptTokenAmount_ =
      _executeStake(reservePoolId_, safetyModuleReceiptTokenAmount_, receiver_, assetPool_, reservePool_);
  }

  /// @notice Stake by minting `stkReceiptTokenAmount_` stkTokens to `receiver_`.
  /// @dev Assumes that `safetyModuleReceiptTokenAmount_` of the safety module receipt token has already been
  /// transferred to this rewards manager contract.
  function stakeWithoutTransfer(uint16 reservePoolId_, uint256 safetyModuleReceiptTokenAmount_, address receiver_)
    external
    returns (uint256 stkReceiptTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 safetyModuleReceiptToken_ = reservePool_.safetyModuleReceiptToken;
    AssetPool storage assetPool_ = assetPools[safetyModuleReceiptToken_];

    _assertValidDepositBalance(safetyModuleReceiptToken_, assetPool_.amount, safetyModuleReceiptTokenAmount_);

    stkReceiptTokenAmount_ =
      _executeStake(reservePoolId_, safetyModuleReceiptTokenAmount_, receiver_, assetPool_, reservePool_);
  }

  /// @notice Unstakes by burning `stkReceiptTokenAmount_` of `reservePoolId_` reserve pool stake tokens and sending
  /// `safetyModuleReceiptTokenAmount_` of `reservePoolId_` safety module receipt tokens to `receiver_`. Also
  /// claims any outstanding rewards for `reservePoolId_` and sends them to `receiver_`.
  /// @dev Assumes that user has approved this rewards manager to spend its stake tokens.
  function unstake(uint16 reservePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_)
    external
    returns (uint256 safetyModuleReceiptTokenAmount_)
  {
    _claimRewards(reservePoolId_, receiver_, owner_);

    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IReceiptToken stkReceiptToken_ = reservePool_.stkReceiptToken;
    IReceiptToken safetyModuleReceiptToken_ = reservePool_.safetyModuleReceiptToken;

    safetyModuleReceiptTokenAmount_ = _previewUnstake(stkReceiptToken_, stkReceiptTokenAmount_, reservePool_.amount);

    reservePool_.amount -= safetyModuleReceiptTokenAmount_;
    assetPools[safetyModuleReceiptToken_].amount -= safetyModuleReceiptTokenAmount_;
    // Burn also ensures that the sender has sufficient allowance if they're not the owner.
    stkReceiptToken_.burn(msg.sender, owner_, stkReceiptTokenAmount_);

    safetyModuleReceiptToken_.safeTransfer(receiver_, safetyModuleReceiptTokenAmount_);

    emit Unstaked(
      msg.sender, receiver_, owner_, stkReceiptToken_, stkReceiptTokenAmount_, safetyModuleReceiptTokenAmount_
    );
  }

  function previewUnstake(uint16 reservePoolId_, uint256 stkReceiptTokenAmount_)
    external
    view
    returns (uint256 safetyModuleReceiptTokenAmount_)
  {
    return _previewUnstake(
      reservePools[reservePoolId_].stkReceiptToken, stkReceiptTokenAmount_, reservePools[reservePoolId_].amount
    );
  }

  function _previewUnstake(IReceiptToken stkReceiptToken_, uint256 stkReceiptTokenAmount_, uint256 totalStakeAmount_)
    internal
    view
    returns (uint256 safetyModuleReceiptTokenAmount_)
  {
    safetyModuleReceiptTokenAmount_ = RewardsManagerCalculationsLib.convertToAssetAmount(
      stkReceiptTokenAmount_, stkReceiptToken_.totalSupply(), totalStakeAmount_
    );
    if (safetyModuleReceiptTokenAmount_ == 0) revert RoundsToZero();
  }

  function _executeStake(
    uint16 reservePoolId_,
    uint256 safetyModuleReceiptTokenAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    ReservePool storage reservePool_
  ) internal returns (uint256 stkReceiptTokenAmount_) {
    // TODO: Should we revert if the safety module is paused?
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) revert InvalidState();

    IReceiptToken stkReceiptToken_ = reservePool_.stkReceiptToken;

    stkReceiptTokenAmount_ = RewardsManagerCalculationsLib.convertToReceiptTokenAmount(
      safetyModuleReceiptTokenAmount_, stkReceiptToken_.totalSupply(), reservePool_.amount
    );
    if (stkReceiptTokenAmount_ == 0) revert RoundsToZero();

    // Increment reserve pool accounting only after calculating `stkReceiptTokenAmount_` to mint.
    reservePool_.amount += safetyModuleReceiptTokenAmount_;
    assetPool_.amount += safetyModuleReceiptTokenAmount_;

    // Update user rewards before minting any new stkTokens.
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[reservePoolId_];
    _dripAndApplyPendingDrippedRewards(reservePool_, claimableRewards_);
    _updateUserRewards(stkReceiptToken_.balanceOf(receiver_), claimableRewards_, userRewards[reservePoolId_][receiver_]);

    stkReceiptToken_.mint(receiver_, stkReceiptTokenAmount_);
    emit Staked(msg.sender, receiver_, stkReceiptToken_, safetyModuleReceiptTokenAmount_, stkReceiptTokenAmount_);
  }
}
