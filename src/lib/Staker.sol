// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, StakePool} from "./structs/Pools.sol";
import {ClaimableRewardsData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsManagerCalculationsLib} from "./RewardsManagerCalculationsLib.sol";

abstract contract Staker is RewardsManagerCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;

  /// @dev Emitted when a user stakes.
  event Staked(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed stkReceiptToken_,
    uint256 assetAmount_,
    uint256 stkReceiptTokenAmount_
  );

  /// @dev Emitted when a user unstakes.
  event Unstaked(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed stkReceiptToken_,
    uint256 stkReceiptTokenAmount_,
    uint256 assetAmount_
  );

  error InsufficientBalance();

  /// @notice Stake by minting `stkReceiptTokenAmount_` stkTokens to `receiver_` after depositing exactly
  /// `assetAmount_` of `stakePoolId_` stake pool asset.
  /// @dev Assumes that `from_` has already approved this contract to transfer `assetAmount_` of the
  /// `stakePoolId_` stake pool asset.
  function stake(uint16 stakePoolId_, uint256 assetAmount_, address receiver_, address from_)
    external
    returns (uint256 stkReceiptTokenAmount_)
  {
    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IERC20 asset_ = stakePool_.asset;
    AssetPool storage assetPool_ = assetPools[asset_];

    // TODO: Add check for fee on transfe tokens
    asset_.safeTransferFrom(from_, address(this), assetAmount_);
    stkReceiptTokenAmount_ = _executeStake(stakePoolId_, assetAmount_, receiver_, assetPool_, stakePool_);
  }

  /// @notice Stake by minting `stkReceiptTokenAmount_` stkTokens to `receiver_`.
  /// @dev Assumes that `assetAmount_` of `stakePoolId_` stake pool asset has already been
  /// transferred to this rewards manager contract.
  function stakeWithoutTransfer(uint16 stakePoolId_, uint256 assetAmount_, address receiver_)
    external
    returns (uint256 stkReceiptTokenAmount_)
  {
    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IERC20 asset_ = stakePool_.asset;
    AssetPool storage assetPool_ = assetPools[asset_];

    _assertValidDepositBalance(asset_, assetPool_.amount, assetAmount_);

    stkReceiptTokenAmount_ = _executeStake(stakePoolId_, assetAmount_, receiver_, assetPool_, stakePool_);
  }

  /// @notice Unstakes by burning `stkReceiptTokenAmount_` of `stakePoolId_` stake pool stake receipt tokens and
  /// sending `assetAmount_` of `stakePoolId_` stake pool asset to `receiver_`. Also
  /// claims any outstanding rewards for `stakePoolId_` stake pool and sends them to `receiver_`.
  /// @dev Assumes that user has approved this rewards manager to spend its stake tokens.
  function unstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_)
    external
    returns (uint256 assetAmount_)
  {
    _claimRewards(stakePoolId_, receiver_, owner_);

    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IReceiptToken stkReceiptToken_ = stakePool_.stkReceiptToken;
    IERC20 asset_ = stakePool_.asset;

    assetAmount_ = _previewUnstake(stkReceiptToken_, stkReceiptTokenAmount_, stakePool_.amount);

    stakePool_.amount -= assetAmount_;
    assetPools[asset_].amount -= assetAmount_;
    // Burn also ensures that the sender has sufficient allowance if they're not the owner.
    stkReceiptToken_.burn(msg.sender, owner_, stkReceiptTokenAmount_);

    asset_.safeTransfer(receiver_, assetAmount_);

    emit Unstaked(msg.sender, receiver_, owner_, stkReceiptToken_, stkReceiptTokenAmount_, assetAmount_);
  }

  function previewUnstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_)
    external
    view
    returns (uint256 assetAmount_)
  {
    return
      _previewUnstake(stakePools[stakePoolId_].stkReceiptToken, stkReceiptTokenAmount_, stakePools[stakePoolId_].amount);
  }

  function _previewUnstake(IReceiptToken stkReceiptToken_, uint256 stkReceiptTokenAmount_, uint256 totalStakeAmount_)
    internal
    view
    returns (uint256 assetAmount_)
  {
    assetAmount_ = RewardsManagerCalculationsLib.convertToAssetAmount(
      stkReceiptTokenAmount_, stkReceiptToken_.totalSupply(), totalStakeAmount_
    );
    if (assetAmount_ == 0) revert RoundsToZero();
  }

  function _executeStake(
    uint16 stakePoolId_,
    uint256 assetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    StakePool storage stakePool_
  ) internal returns (uint256 stkReceiptTokenAmount_) {
    IReceiptToken stkReceiptToken_ = stakePool_.stkReceiptToken;

    stkReceiptTokenAmount_ = RewardsManagerCalculationsLib.convertToReceiptTokenAmount(
      assetAmount_, stkReceiptToken_.totalSupply(), stakePool_.amount
    );
    if (stkReceiptTokenAmount_ == 0) revert RoundsToZero();

    // Increment stake pool accounting only after calculating `stkReceiptTokenAmount_` to mint.
    stakePool_.amount += assetAmount_;
    assetPool_.amount += assetAmount_;

    // Update user rewards before minting any new stkTokens.
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[stakePoolId_];
    _dripAndApplyPendingDrippedRewards(stakePool_, claimableRewards_);
    _updateUserRewards(stkReceiptToken_.balanceOf(receiver_), claimableRewards_, userRewards[stakePoolId_][receiver_]);

    stkReceiptToken_.mint(receiver_, stkReceiptTokenAmount_);
    emit Staked(msg.sender, receiver_, stkReceiptToken_, assetAmount_, stkReceiptTokenAmount_);
  }
}
