// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {IDepositorErrors} from "../interfaces/IDepositorErrors.sol";
import {IDepositorEvents} from "../interfaces/IDepositorEvents.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {RewardPool} from "./structs/Pools.sol";
import {RewardsManagerCalculationsLib} from "./RewardsManagerCalculationsLib.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";

abstract contract Depositor is RewardsManagerCommon, IDepositorErrors, IDepositorEvents {
  using SafeERC20 for IERC20;

  /// @notice Deposit `rewardAssetAmount_` assets into the `rewardPoolId_` reward pool on behalf of `from_` and mint
  /// `depositReceiptTokenAmount_` tokens to `receiver_`.
  /// @dev Assumes that `msg.sender` has approved the rewards manager to spend `rewardAssetAmount_` of the reward pool's
  /// asset.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param rewardAssetAmount_ The amount of the reward pool's asset to deposit.
  /// @param receiver_ The address to mint the deposit receipt tokens to.
  /// @return depositReceiptTokenAmount_ The amount of deposit receipt tokens minted.
  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_)
  {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    IERC20 asset_ = rewardPool_.asset;

    // Pull in deposited assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    asset_.safeTransferFrom(msg.sender, address(this), rewardAssetAmount_);

    depositReceiptTokenAmount_ =
      _executeRewardDeposit(rewardPoolId_, asset_, rewardAssetAmount_, receiver_, rewardPool_);
  }

  /// @notice Deposit `rewardAssetAmount_` assets into the `rewardPoolId_` reward pool and mint
  /// `depositReceiptTokenAmount_` tokens to `receiver_`.
  /// @dev Assumes that the user has already transferred `rewardAssetAmount_` of the reward pool's asset to the rewards
  /// manager.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param rewardAssetAmount_ The amount of the reward pool's asset to deposit.
  /// @param receiver_ The address to mint the deposit receipt tokens to.
  /// @return depositReceiptTokenAmount_ The amount of deposit receipt tokens minted.
  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_)
  {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    depositReceiptTokenAmount_ =
      _executeRewardDeposit(rewardPoolId_, rewardPool_.asset, rewardAssetAmount_, receiver_, rewardPool_);
  }

  /// @notice Redeem by burning `depositReceiptTokenAmount_` of `rewardPoolId_` reward pool deposit receipt tokens and
  /// sending `rewardAssetAmount_` of `rewardPoolId_` reward pool assets to `receiver_`. Reward pool assets can only be
  /// redeemed
  /// if they have not been dripped yet.
  /// @dev Assumes that user has approved the rewards manager to spend its deposit receipt tokens.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to burn.
  /// @param receiver_ The address to send the reward pool's asset to.
  /// @param owner_ The owner of the deposit receipt tokens.
  /// @return rewardAssetAmount_ The amount of the reward pool's asset redeemed.
  function redeemUndrippedRewards(
    uint16 rewardPoolId_,
    uint256 depositReceiptTokenAmount_,
    address receiver_,
    address owner_
  ) external returns (uint256 rewardAssetAmount_) {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    if (rewardsManagerState == RewardsManagerState.ACTIVE) _dripRewardPool(rewardPool_);

    IReceiptToken depositReceiptToken_ = rewardPool_.depositReceiptToken;
    rewardAssetAmount_ = _previewRedemption(
      depositReceiptToken_,
      depositReceiptTokenAmount_,
      rewardPool_.dripModel,
      rewardPool_.undrippedRewards,
      rewardPool_.lastDripTime
    );
    if (rewardAssetAmount_ == 0) revert RoundsToZero(); // Check for rounding error since we round down in conversion.

    depositReceiptToken_.burn(msg.sender, owner_, depositReceiptTokenAmount_);

    IERC20 asset_ = rewardPool_.asset;
    rewardPool_.undrippedRewards -= rewardAssetAmount_;
    assetPools[asset_].amount -= rewardAssetAmount_;
    asset_.safeTransfer(receiver_, rewardAssetAmount_);

    emit RedeemedUndrippedRewards(
      msg.sender, receiver_, owner_, rewardPoolId_, depositReceiptToken_, depositReceiptTokenAmount_, rewardAssetAmount_
    );
  }

  /// @notice Preview the amount of undripped rewards that can be redeemed for `depositReceiptTokenAmount_` from a given
  /// reward pool.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to redeem.
  /// @return rewardAssetAmount_ The amount of the reward pool's asset that can be redeemed.
  function previewUndrippedRewardsRedemption(uint16 rewardPoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 rewardAssetAmount_)
  {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];

    rewardAssetAmount_ = _previewRedemption(
      rewardPool_.depositReceiptToken,
      depositReceiptTokenAmount_,
      rewardPool_.dripModel,
      rewardPool_.undrippedRewards,
      rewardPool_.lastDripTime
    );
  }

  function _executeRewardDeposit(
    uint16 rewardPoolId_,
    IERC20 token_,
    uint256 rewardAssetAmount_,
    address receiver_,
    RewardPool storage rewardPool_
  ) internal returns (uint256 depositReceiptTokenAmount_) {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();
    _assertValidDepositBalance(token_, assetPools[token_].amount, rewardAssetAmount_);

    IReceiptToken depositReceiptToken_ = rewardPool_.depositReceiptToken;

    depositReceiptTokenAmount_ = RewardsManagerCalculationsLib.convertToReceiptTokenAmount(
      rewardAssetAmount_, depositReceiptToken_.totalSupply(), _poolAmountWithFloor(rewardPool_.undrippedRewards)
    );
    if (depositReceiptTokenAmount_ == 0) revert RoundsToZero();

    // Increment reward pool accounting only after calculating `depositReceiptTokenAmount_` to mint.
    rewardPool_.undrippedRewards += rewardAssetAmount_;
    assetPools[token_].amount += rewardAssetAmount_;

    depositReceiptToken_.mint(receiver_, depositReceiptTokenAmount_);
    emit Deposited(
      msg.sender, receiver_, rewardPoolId_, depositReceiptToken_, rewardAssetAmount_, depositReceiptTokenAmount_
    );
  }

  function _previewRedemption(
    IReceiptToken receiptToken_,
    uint256 receiptTokenAmount_,
    IDripModel dripModel_,
    uint256 totalPoolAmount_,
    uint256 lastDripTime_
  ) internal view returns (uint256 assetAmount_) {
    uint256 nextDripAmount_ =
      (lastDripTime_ != block.timestamp) ? _getNextDripAmount(totalPoolAmount_, dripModel_, lastDripTime_) : 0;
    uint256 nextTotalPoolAmount_ = totalPoolAmount_ - nextDripAmount_;

    assetAmount_ = nextTotalPoolAmount_ == 0
      ? 0
      : RewardsManagerCalculationsLib.convertToAssetAmount(
        receiptTokenAmount_, receiptToken_.totalSupply(), nextTotalPoolAmount_
      );
  }

  function _assertValidDepositBalance(IERC20 token_, uint256 assetPoolBalance_, uint256 depositAmount_)
    internal
    view
    override
  {
    if (token_.balanceOf(address(this)) - assetPoolBalance_ < depositAmount_) revert InvalidDeposit();
  }
}
