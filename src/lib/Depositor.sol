// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IDepositorErrors} from "../interfaces/IDepositorErrors.sol";
import {IDepositorEvents} from "../interfaces/IDepositorEvents.sol";
import {IRewardsManager} from "../interfaces/IRewardsManager.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {RewardPool} from "./structs/Pools.sol";
import {DepositorRewardsData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsMathLib} from "./RewardsMathLib.sol";

abstract contract Depositor is RewardsManagerCommon, IDepositorErrors, IDepositorEvents {
  using SafeERC20 for IERC20;
  using FixedPointMathLib for uint256;

  /// @notice Deposit `rewardAssetAmount_` reward assets held by `msg.sender` into `rewardPoolId_`, crediting
  /// `receiver_`.
  /// @dev `msg.sender` is treated as the owner of the funds and must approve this contract to pull
  /// `rewardAssetAmount_` of the pool's underlying asset via `transferFrom`.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param rewardAssetAmount_ The amount of the reward pool's asset to deposit.
  /// @param receiver_ The address that will receive the resulting rewards.
  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) external {
    _depositRewardAssets(rewardPoolId_, rewardAssetAmount_, msg.sender, receiver_);
  }

  /// @notice Deposit `rewardAssetAmount_` reward assets into `rewardPoolId_` by pulling funds from `owner_`.
  /// @dev `owner_` must approve this contract to pull `rewardAssetAmount_` of the pool's underlying asset via
  /// `transferFrom`.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param rewardAssetAmount_ The amount of the reward pool's asset to deposit.
  /// @param owner_ The address from which the reward assets will be pulled and credited.
  function depositRewardAssetsOnBehalf(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address owner_) external {
    _depositRewardAssets(rewardPoolId_, rewardAssetAmount_, owner_, owner_);
  }

  function _depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address owner_, address receiver_)
    internal
  {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    IERC20 asset_ = rewardPool_.asset;

    // Pull in deposited assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    asset_.safeTransferFrom(owner_, address(this), rewardAssetAmount_);
    _executeRewardDeposit(rewardPoolId_, asset_, rewardAssetAmount_, rewardPool_, owner_, receiver_);
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
    RewardPool storage rewardPool_,
    address owner_,
    address receiver_
  ) internal {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();
    _assertValidDepositBalance(token_, assetPools[token_].amount, rewardAssetAmount_);

    // To ensure reward drip times are in sync with reward deposit times we drip rewards before depositing.
    _dripRewardPool(rewardPool_);

    uint256 depositFeeAmount_ = _computeDepositFeeAmount(rewardAssetAmount_);
    uint256 depositAmount_ = rewardAssetAmount_ - depositFeeAmount_;

    uint256 currentWithdrawableRewards_ =
      _previewCurrentWithdrawableRewards(rewardPool_, depositorRewards[rewardPoolId_][owner_]);
    depositorRewards[rewardPoolId_][owner_] = DepositorRewardsData({
      withdrawableRewards: currentWithdrawableRewards_ + depositAmount_,
      logIndexSnapshot: rewardPool_.logIndexSnapshot,
      epoch: rewardPool_.epoch
    });
    rewardPool_.undrippedRewards += depositAmount_;
    assetPools[token_].amount += depositAmount_;
    token_.safeTransfer(cozyManager.owner(), depositFeeAmount_);

    emit Deposited(msg.sender, owner_, receiver_, rewardPoolId_, depositAmount_, depositFeeAmount_);
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
