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

  /// @notice Deposit `rewardAssetAmount_` assets into the `rewardPoolId_` reward pool on behalf of `from_`.
  /// @dev Assumes that `msg.sender` has approved the rewards manager to spend `rewardAssetAmount_` of the reward pool's
  /// asset.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param rewardAssetAmount_ The amount of the reward pool's asset to deposit.
  /// @param receiver_ The address to mint the deposit receipt tokens to.
  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) external {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    IERC20 asset_ = rewardPool_.asset;

    // Pull in deposited assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    asset_.safeTransferFrom(msg.sender, address(this), rewardAssetAmount_);
    _executeRewardDeposit(rewardPoolId_, asset_, rewardAssetAmount_, receiver_, rewardPool_);
  }

  /// @notice Deposit `rewardAssetAmount_` assets into the `rewardPoolId_` reward pool.
  /// @dev Assumes that the user has already transferred `rewardAssetAmount_` of the reward pool's asset to the rewards
  /// manager.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param rewardAssetAmount_ The amount of the reward pool's asset to deposit.
  /// @param receiver_ The address to mint the deposit receipt tokens to.
  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
  {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    _executeRewardDeposit(rewardPoolId_, rewardPool_.asset, rewardAssetAmount_, receiver_, rewardPool_);
  }

  function _executeRewardDeposit(
    uint16 rewardPoolId_,
    IERC20 token_,
    uint256 rewardAssetAmount_,
    address receiver_,
    RewardPool storage rewardPool_
  ) internal {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();
    _assertValidDepositBalance(token_, assetPools[token_].amount, rewardAssetAmount_);

    // To ensure reward drip times are in sync with reward deposit times we drip rewards before depositing.
    _dripRewardPool(rewardPool_);

    rewardPool_.undrippedRewards += rewardAssetAmount_;
    assetPools[token_].amount += rewardAssetAmount_;

    emit Deposited(msg.sender, receiver_, rewardPoolId_, rewardAssetAmount_);
  }

  function _assertValidDepositBalance(IERC20 token_, uint256 assetPoolBalance_, uint256 depositAmount_)
    internal
    view
    override
  {
    if (token_.balanceOf(address(this)) - assetPoolBalance_ < depositAmount_) revert InvalidDeposit();
  }
}
