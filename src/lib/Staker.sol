// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReservePool} from "./structs/Pools.sol";
import {ClaimableRewardsData} from "./structs/Rewards.sol";
import {RewardsModuleCommon} from "./RewardsModuleCommon.sol";
import {RewardsModuleCalculationsLib} from "./RewardsModuleCalculationsLib.sol";

// TODO: Functions for staking and staking without transfer safety module depositReceiptTokens. The existing functions
// are for staking safety module reserve assets. Also for redeem.
abstract contract Staker is RewardsModuleCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;

  /// @dev Emitted when a user stakes.
  event Staked(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed stkToken_,
    uint256 depositReceiptTokenAmount_,
    uint256 reserveAssetAmount_,
    uint256 stkReceiptTokenAmount_
  );

  error InsufficientBalance();

  /// @notice Stake by minting `stkReceiptTokenAmount_` stkTokens to `receiver_` after depositing exactly
  /// `reserveAssetAmount_` of the reserve asset.
  /// @dev Assumes that `from_` has already approved this contract to transfer `amount_` of reserve asset.
  function stake(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 stkReceiptTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    // TODO: Fine to remove?
    // AssetPool storage assetPool_ = assetPools[reserveAsset_];

    // Pull in stake tokens. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    reservePool_.asset.safeTransferFrom(from_, address(safetyModule), reserveAssetAmount_);
    uint256 depositReceiptTokenAmount_ =
      safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, address(this));

    stkReceiptTokenAmount_ =
      _executeStake(reservePoolId_, reserveAssetAmount_, depositReceiptTokenAmount_, receiver_, reservePool_);
  }

  /// @notice Stake by minting `stkReceiptTokenAmount_` stkTokens to `receiver_`.
  /// @dev Assumes that `amount_` of reserve asset has already been transferred to the safety module contract.
  function stakeWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 stkReceiptTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    // TODO: Fine to remove?
    // AssetPool storage assetPool_ = assetPools[reserveAsset_];

    uint256 depositReceiptTokenAmount_ =
      safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, address(this));
    stkReceiptTokenAmount_ =
      _executeStake(reservePoolId_, reserveAssetAmount_, depositReceiptTokenAmount_, receiver_, reservePool_);
  }

  /// @notice Unstakes by burning `stkReceiptTokenAmount_` of `reservePoolId_` reserve pool stake tokens and sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`. Also claims any outstanding rewards
  /// and sends them to `receiver_`.
  /// @dev Assumes that user has approved the RewardsModule to spend its stake tokens.
  function unstake(uint16 reservePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_)
  {
    claimRewards(reservePoolId_, receiver_);

    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IReceiptToken stkToken_ = reservePool_.stkToken;

    if (stkReceiptTokenAmount_ > stkToken_.balanceOf(owner_)) revert InsufficientBalance();

    uint256 depositReceiptTokenAmount_ = RewardsModuleCalculationsLib.convertToAssetAmount(
      stkReceiptTokenAmount_, stkToken_.totalSupply(), reservePool_.asset.totalSupply()
    );

    // Receipt tokens are burned on the first step of redemption.
    stkToken_.burn(msg.sender, owner_, stkReceiptTokenAmount_);

    // SafetyModule.redeem requires that the caller (this RewardsModule) has approved the safety module to spend its
    // stkTokens.
    reservePool_.asset.safeIncreaseAllowance(address(safetyModule), depositReceiptTokenAmount_);
    (redemptionId_, reserveAssetAmount_) =
      safetyModule.redeem(reservePoolId_, depositReceiptTokenAmount_, receiver_, address(this));
  }

  function _executeStake(
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    uint256 depositReceiptTokenAmount_,
    address receiver_,
    ReservePool storage reservePool_
  ) internal returns (uint256 stkReceiptTokenAmount_) {
    IReceiptToken stkToken_ = reservePool_.stkToken;

    stkReceiptTokenAmount_ = RewardsModuleCalculationsLib.convertToReceiptTokenAmount(
      // TODO: Can we remove pending unstakes amount?
      depositReceiptTokenAmount_,
      stkToken_.totalSupply(),
      reservePool_.stakeAmount - reservePool_.pendingUnstakesAmount
    );
    if (stkReceiptTokenAmount_ == 0) revert RoundsToZero();

    // Increment reserve pool accounting only after calculating `stkReceiptTokenAmount_` to mint.
    reservePool_.stakeAmount += depositReceiptTokenAmount_;
    // TODO: Fine to remove?
    // assetPool_.amount += reserveAssetAmount_;

    // Update user rewards before minting any new stkTokens.
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[reservePoolId_];
    _dripAndApplyPendingDrippedRewards(reservePool_, claimableRewards_);
    _updateUserRewards(stkToken_.balanceOf(receiver_), claimableRewards_, userRewards[reservePoolId_][receiver_]);

    stkToken_.mint(receiver_, stkReceiptTokenAmount_);
    emit Staked(
      msg.sender, receiver_, stkToken_, reserveAssetAmount_, depositReceiptTokenAmount_, stkReceiptTokenAmount_
    );
  }
}
