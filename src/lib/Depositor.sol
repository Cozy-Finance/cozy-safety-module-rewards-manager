// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import { PRBMathSD59x18 } from "@prb/math/contracts/PRBMathSD59x18.sol";
import {IDepositorErrors} from "../interfaces/IDepositorErrors.sol";
import {IDepositorEvents} from "../interfaces/IDepositorEvents.sol";
import {IRewardsManager} from "../interfaces/IRewardsManager.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {RewardPool} from "./structs/Pools.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {DepositorRewardState} from "./structs/Rewards.sol";

abstract contract Depositor is RewardsManagerCommon, IDepositorErrors, IDepositorEvents {
  using SafeERC20 for IERC20;
  using FixedPointMathLib for uint256;
  using PRBMathSD59x18 for int256;

  /// @notice Deposit `rewardAssetAmount_` assets into the `rewardPoolId_` reward pool on behalf of `from_`.
  /// @dev Assumes that `msg.sender` has approved the rewards manager to spend `rewardAssetAmount_` of the reward pool's
  /// asset.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param rewardAssetAmount_ The amount of the reward pool's asset to deposit.
  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_) external {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    IERC20 asset_ = rewardPool_.asset;

    // Pull in deposited assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    asset_.safeTransferFrom(msg.sender, address(this), rewardAssetAmount_);
    _executeRewardDeposit(rewardPoolId_, asset_, rewardAssetAmount_, rewardPool_);
  }

  /// @notice Deposit `rewardAssetAmount_` assets into the `rewardPoolId_` reward pool.
  /// @dev Assumes that the user has already transferred `rewardAssetAmount_` of the reward pool's asset to the rewards
  /// manager.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param rewardAssetAmount_ The amount of the reward pool's asset to deposit.
  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_) external {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    _executeRewardDeposit(rewardPoolId_, rewardPool_.asset, rewardAssetAmount_, rewardPool_);
  }

  /// @notice Preview the current amount of undripped rewards in the `rewardPoolId_` reward pool with unrealized drip
  /// applied.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @return nextTotalPoolAmount_ The amount of undripped rewards in the reward pool with unrealized drip applied.
  function previewCurrentUndrippedRewards(uint16 rewardPoolId_) external view returns (uint256 nextTotalPoolAmount_) {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    uint256 totalPoolAmount_ = rewardPool_.undrippedRewards;
    uint128 lastDripTime_ = rewardPool_.lastDripTime;
    uint256 nextDripAmount_ = (lastDripTime_ != block.timestamp)
      ? _getNextDripAmount(totalPoolAmount_, rewardPool_.dripModel, lastDripTime_)
      : 0;
    nextTotalPoolAmount_ = totalPoolAmount_ - nextDripAmount_;
  }

  function _executeRewardDeposit(
    uint16 rewardPoolId_,
    IERC20 token_,
    uint256 rewardAssetAmount_,
    RewardPool storage rewardPool_
  ) internal {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();
    _assertValidDepositBalance(token_, assetPools[token_].amount, rewardAssetAmount_);

    // To ensure reward drip times are in sync with reward deposit times we drip rewards before depositing.
    _dripRewardPool(rewardPool_,rewardPoolId_);

    uint256 depositFeeAmount_ = _computeDepositFeeAmount(rewardAssetAmount_);
    uint256 depositAmount_ = rewardAssetAmount_ - depositFeeAmount_;

    DepositorRewardState storage depositorState_ = rewardPoolDepositorStates[rewardPoolId_][msg.sender];

    uint256 updatedWithdrawable_ = PRBMathSD59x18.fromUint(depositorState_.lastAvailableToWithdraw).mul((rewardPool_.lnCumulativeDripFactor - depositorState_.lnLastDripFactor).exp()).toUint();

    depositorState_.lastAvailableToWithdraw = updatedWithdrawable_ + depositAmount_;
    depositorState_.lnLastDripFactor = rewardPool_.lnCumulativeDripFactor;

    rewardPool_.undrippedRewards += depositAmount_;
    assetPools[token_].amount += depositAmount_;
    token_.safeTransfer(cozyManager.owner(), depositFeeAmount_);

    emit Deposited(msg.sender, rewardPoolId_, depositAmount_, depositFeeAmount_);
  }

  function _assertValidDepositBalance(IERC20 token_, uint256 assetPoolBalance_, uint256 depositAmount_)
    internal
    view
    override
  {
    if (token_.balanceOf(address(this)) - assetPoolBalance_ < depositAmount_) revert InvalidDeposit();
  }

  function _computeDepositFeeAmount(uint256 rewardAssetAmount_) internal view returns (uint256) {
    return rewardAssetAmount_.mulDivUp(cozyManager.getDepositFee(IRewardsManager(address(this))), MathConstants.ZOC);
  }
}
