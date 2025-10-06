// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RewardPool} from "./structs/Pools.sol";
import {DepositorRewardsData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsMathLib} from "./RewardsMathLib.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {IWithdrawerEvents} from "../interfaces/IWithdrawerEvents.sol";

abstract contract Withdrawer is RewardsManagerCommon, IWithdrawerEvents {
  using SafeERC20 for IERC20;
  using FixedPointMathLib for uint256;

  /// @notice Withdraw undripped reward assets.
  /// @param rewardPoolId_ The ID of the reward pool to withdraw from.
  /// @param rewardAssetAmount_ The maximum amount of reward assets to withdraw. If type(uint256).max, all withdrawable
  /// rewards will be withdrawn. Else, up to `rewardAssetAmount_` of withdrawable rewards will be withdrawn.
  /// @param receiver_ The address that will receive the withdrawn assets.
  function withdrawRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) external {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    if (rewardsManagerState != RewardsManagerState.PAUSED) _dripRewardPool(rewardPool_);

    uint256 currentWithdrawableRewards_ =
      _previewCurrentWithdrawableRewards(rewardPool_, depositorRewards[rewardPoolId_][msg.sender]);
    rewardAssetAmount_ = rewardAssetAmount_ == type(uint256).max
      ? currentWithdrawableRewards_
      : (rewardAssetAmount_ < currentWithdrawableRewards_ ? rewardAssetAmount_ : currentWithdrawableRewards_);

    depositorRewards[rewardPoolId_][msg.sender] = DepositorRewardsData({
      withdrawableRewards: currentWithdrawableRewards_ - rewardAssetAmount_,
      logIndexSnapshot: rewardPool_.logIndexSnapshot,
      epoch: rewardPool_.epoch
    });
    rewardPool_.undrippedRewards -= rewardAssetAmount_;
    assetPools[rewardPool_.asset].amount -= rewardAssetAmount_;

    rewardPool_.asset.safeTransfer(receiver_, rewardAssetAmount_);

    emit Withdrawn(msg.sender, rewardPoolId_, rewardAssetAmount_, receiver_);
  }

  /// @notice Preview the current withdrawable rewards for the owner.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param owner_ The owner of the rewards.
  /// @return The owner's current withdrawable rewards.
  function previewCurrentWithdrawableRewards(uint16 rewardPoolId_, address owner_) external view returns (uint256) {
    return _previewCurrentWithdrawableRewards(rewardPools[rewardPoolId_], depositorRewards[rewardPoolId_][owner_]);
  }

  function _previewCurrentWithdrawableRewards(
    RewardPool storage rewardPool_,
    DepositorRewardsData storage depositorRewardsData_
  ) internal view override returns (uint256) {
    (uint256 nextRewardPoolEpoch_, uint256 nextRewardPoolLogIndexSnapshot_) =
      _getNextRewardPoolEpochAndLogIndexSnapshot(rewardPool_);

    if (depositorRewardsData_.epoch < nextRewardPoolEpoch_ || depositorRewardsData_.withdrawableRewards == 0) {
      // Rewards have fully dripped or the depositor previously had no withdrawable rewards, so the depositor has no
      // withdrawable rewards.
      return 0;
    } else if (depositorRewardsData_.logIndexSnapshot == nextRewardPoolLogIndexSnapshot_) {
      // Rewards have not dripped since the last update, so no update to the depositor's withdrawable rewards.
      return depositorRewardsData_.withdrawableRewards;
    } else {
      // Rewards have dripped since the last update, so scale down the depositor's withdrawable rewards by the amount of
      // drip.
      return depositorRewardsData_.withdrawableRewards.mulWadDown(
        RewardsMathLib.expNeg(nextRewardPoolLogIndexSnapshot_ - depositorRewardsData_.logIndexSnapshot)
      );
    }
  }

  function _getNextRewardPoolEpochAndLogIndexSnapshot(RewardPool storage rewardPool_)
    internal
    view
    returns (uint256 nextRewardPoolEpoch_, uint256 nextRewardPoolLogIndexSnapshot_)
  {
    nextRewardPoolEpoch_ = rewardPool_.epoch;
    nextRewardPoolLogIndexSnapshot_ = rewardPool_.logIndexSnapshot;

    if (rewardPool_.lastDripTime != block.timestamp) {
      uint256 nextDripFactor_ =
        _getNextDripFactor(rewardPool_.undrippedRewards, rewardPool_.dripModel, rewardPool_.lastDripTime);

      if (nextDripFactor_ == MathConstants.WAD) {
        // Full drip, so increment epoch and reset log index
        nextRewardPoolEpoch_ += 1;
        nextRewardPoolLogIndexSnapshot_ = 0;
      } else {
        nextRewardPoolLogIndexSnapshot_ += RewardsMathLib.negLn(MathConstants.WAD - nextDripFactor_);
      }
    }
  }
}
