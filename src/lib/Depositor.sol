// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IDepositorErrors} from "../interfaces/IDepositorErrors.sol";
import {IDepositorEvents} from "../interfaces/IDepositorEvents.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {ReservePool, AssetPool, RewardPool} from "./structs/Pools.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {RewardsModuleCalculationsLib} from "./RewardsModuleCalculationsLib.sol";
import {RewardsModuleCommon} from "./RewardsModuleCommon.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";

abstract contract Depositor is RewardsModuleCommon, IDepositorErrors, IDepositorEvents {
  using SafeERC20 for IERC20;

  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositReceiptTokenAmount_)
  {
    RewardPool storage rewardsPool_ = rewardPools[rewardPoolId_];
    IERC20 underlyingToken_ = rewardsPool_.asset;

    // Pull in deposited assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    underlyingToken_.safeTransferFrom(from_, address(this), rewardAssetAmount_);

    depositReceiptTokenAmount_ = _executeRewardDeposit(underlyingToken_, rewardAssetAmount_, receiver_, rewardsPool_);
  }

  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_)
  {
    RewardPool storage rewardsPool_ = rewardPools[rewardPoolId_];
    depositReceiptTokenAmount_ = _executeRewardDeposit(rewardsPool_.asset, rewardAssetAmount_, receiver_, rewardsPool_);
  }

  /// @notice Redeem by burning `depositReceiptTokenAmount_` of `rewardPoolId_` reward pool deposit tokens and sending
  /// `rewardAssetAmount_` of `rewardPoolId_` reward pool assets to `receiver_`. Reward pool assets can only be redeemed
  /// if they have not been dripped yet.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeemUndrippedRewards(
    uint16 rewardPoolId_,
    uint256 depositReceiptTokenAmount_,
    address receiver_,
    address owner_
  ) external returns (uint256 rewardAssetAmount_) {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    _dripRewardPool(rewardPool_);

    IReceiptToken depositReceiptToken_ = rewardPool_.depositToken;
    rewardAssetAmount_ = _previewRedemption(
      depositReceiptToken_,
      depositReceiptTokenAmount_,
      rewardPool_.dripModel,
      rewardPool_.undrippedRewards,
      rewardPool_.lastDripTime
    );

    depositReceiptToken_.burn(msg.sender, owner_, depositReceiptTokenAmount_);
    rewardPool_.undrippedRewards -= rewardAssetAmount_;
    assetPools[rewardPool_.asset].amount -= rewardAssetAmount_;
    rewardPool_.asset.safeTransfer(receiver_, rewardAssetAmount_);

    emit RedeemedUndrippedRewards(
      msg.sender, receiver_, owner_, depositReceiptToken_, depositReceiptTokenAmount_, rewardAssetAmount_
    );
  }

  function previewUndrippedRewardsRedemption(uint16 rewardPoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 rewardAssetAmount_)
  {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    uint256 lastDripTime_ = rewardPool_.lastDripTime;

    rewardAssetAmount_ = _previewRedemption(
      rewardPool_.depositToken,
      depositReceiptTokenAmount_,
      rewardPool_.dripModel,
      rewardPool_.undrippedRewards,
      lastDripTime_
    );
  }

  function _executeRewardDeposit(
    IERC20 token_,
    uint256 rewardAssetAmount_,
    address receiver_,
    RewardPool storage rewardPool_
  ) internal returns (uint256 depositReceiptTokenAmount_) {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) revert InvalidState();
    if (token_.balanceOf(address(this)) - assetPools[token_].amount < rewardAssetAmount_) revert InvalidDeposit();

    IReceiptToken depositReceiptToken_ = rewardPool_.depositToken;

    // TODO: Use reward module specific lib which doesn't floor the asset amount.
    // TODO: Rewards module inspector
    depositReceiptTokenAmount_ = RewardsModuleCalculationsLib.convertToReceiptTokenAmount(
      rewardAssetAmount_, depositReceiptToken_.totalSupply(), rewardPool_.undrippedRewards
    );
    if (depositReceiptTokenAmount_ == 0) revert RoundsToZero();

    // Increment reward pool accounting only after calculating `depositReceiptTokenAmount_` to mint.
    rewardPool_.undrippedRewards += rewardAssetAmount_;
    assetPools[token_].amount += rewardAssetAmount_;

    depositReceiptToken_.mint(receiver_, depositReceiptTokenAmount_);
    emit Deposited(msg.sender, receiver_, depositReceiptToken_, rewardAssetAmount_, depositReceiptTokenAmount_);
  }

  function _previewRedemption(
    IReceiptToken receiptToken_,
    uint256 receiptTokenAmount_,
    IDripModel dripModel_,
    uint256 totalPoolAmount_,
    uint256 lastDripTime_
  ) internal view returns (uint256 assetAmount_) {
    uint256 nextTotalPoolAmount_ = totalPoolAmount_ - _getNextDripAmount(totalPoolAmount_, dripModel_, lastDripTime_);

    // TODO: Use reward module specific lib which doesn't floor the asset amount.
    // TODO: Rewards module inspector
    assetAmount_ = nextTotalPoolAmount_ == 0
      ? 0
      : RewardsModuleCalculationsLib.convertToAssetAmount(
        receiptTokenAmount_, receiptToken_.totalSupply(), nextTotalPoolAmount_
      );
    if (assetAmount_ == 0) revert RoundsToZero(); // Check for rounding error since we round down in conversion.
  }
}