// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {RewardPool} from "./structs/Pools.sol";
import {DepositorRewardsData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardMathLib} from "./RewardMathLib.sol";
import {IWithdrawerErrors} from "../interfaces/IWithdrawerErrors.sol";
import {IWithdrawerEvents} from "../interfaces/IWithdrawerEvents.sol";

abstract contract Withdrawer is RewardsManagerCommon, IWithdrawerErrors, IWithdrawerEvents {
  using SafeERC20 for IERC20;
  using FixedPointMathLib for uint256;

  /// @notice Withdraw undripped reward assets.
  /// @param rewardPoolId_ The ID of the reward pool to withdraw from.
  /// @param rewardAssetAmount_ The amount of reward assets to withdraw.
  /// @param receiver_ The address that will receive the withdrawn assets.
  function withdrawRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) external {
    // TODO: Should we revert if the RM is paused?
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];

    uint256 currentWithdrawableRewards_ =
      _previewCurrentWithdrawableRewards(rewardPool_, depositorRewards[rewardPoolId_][msg.sender]);
    if (rewardAssetAmount_ > currentWithdrawableRewards_) revert InvalidWithdraw();

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

  /// @notice Preview the current withdrawable rewards for the depositor.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param depositor_ The address of the depositor.
  /// @return The depositor's current withdrawable rewards.
  function previewCurrentWithdrawableRewards(uint16 rewardPoolId_, address depositor_) external view returns (uint256) {
    return _previewCurrentWithdrawableRewards(rewardPools[rewardPoolId_], depositorRewards[rewardPoolId_][depositor_]);
  }

  function _previewCurrentWithdrawableRewards(
    RewardPool storage rewardPool_,
    DepositorRewardsData storage depositorRewardsData_
  ) internal view override returns (uint256) {
    if (depositorRewardsData_.epoch < rewardPool_.epoch || depositorRewardsData_.withdrawableRewards == 0) {
      // Rewards have fully dripped or the depositor previously had no withdrawable rewards, so the depositor has no
      // withdrawable rewards.
      return 0;
    } else if (depositorRewardsData_.logIndexSnapshot == rewardPool_.logIndexSnapshot) {
      // Rewards have not dripped since the last update, so no update to the depositor's withdrawable rewards.
      return depositorRewardsData_.withdrawableRewards;
    } else {
      // Rewards have dripped since the last update, so scale down the depositor's withdrawable rewards by the amount of
      // drip.
      return depositorRewardsData_.withdrawableRewards.mulWadDown(
        RewardMathLib.expNeg(rewardPool_.logIndexSnapshot - depositorRewardsData_.logIndexSnapshot)
      );
    }
  }
}
