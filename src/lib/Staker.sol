// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-libs/interfaces/IReceiptToken.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {AssetPool, StakePool} from "./structs/Pools.sol";
import {ClaimRewardsArgs, ClaimableRewardsData, ClaimRewardsPoolData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {IRewardsDistributorErrors} from "../interfaces/IRewardsDistributorErrors.sol";
import {IStakerEvents} from "../interfaces/IStakerEvents.sol";

abstract contract Staker is RewardsManagerCommon, IStakerEvents {
  using SafeERC20 for IERC20;

  /// @notice Stake by minting `assetAmount_` stkReceiptTokens to `receiver_` after depositing exactly `assetAmount_` of
  /// `stakePoolId_` stake pool asset.
  /// @dev Assumes that `msg.sender` has already approved this contract to transfer `assetAmount_` of the `stakePoolId_`
  /// stake pool asset.
  /// @param stakePoolId_ The ID of the stake pool to stake in.
  /// @param assetAmount_ The amount of the underlying asset to stake.
  /// @param receiver_ The address that will receive the stkReceiptTokens.
  function stake(uint16 stakePoolId_, uint256 assetAmount_, address receiver_) external {
    if (assetAmount_ == 0) revert AmountIsZero();

    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IERC20 asset_ = stakePool_.asset;
    AssetPool storage assetPool_ = assetPools[asset_];

    asset_.safeTransferFrom(msg.sender, address(this), assetAmount_);
    _assertValidDepositBalance(asset_, assetPool_.amount, assetAmount_);

    _executeStake(stakePoolId_, assetAmount_, receiver_, msg.sender, assetPool_, stakePool_);
  }

  /// @notice Stake by minting `assetAmount_` stkReceiptTokens to `receiver_`.
  /// @dev Assumes that `assetAmount_` of `stakePoolId_` stake pool asset has already been transferred to this rewards
  /// manager contract.
  /// @param stakePoolId_ The ID of the stake pool to stake in.
  /// @param assetAmount_ The amount of the underlying asset to stake.
  /// @param owner_ The owner of the staked assets (for event logging purposes).
  /// @param receiver_ The address that will receive the stkReceiptTokens.
  function stakeWithoutTransfer(uint16 stakePoolId_, uint256 assetAmount_, address owner_, address receiver_) external {
    if (assetAmount_ == 0) revert AmountIsZero();

    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IERC20 asset_ = stakePool_.asset;
    AssetPool storage assetPool_ = assetPools[asset_];

    _assertValidDepositBalance(asset_, assetPool_.amount, assetAmount_);

    _executeStake(stakePoolId_, assetAmount_, receiver_, owner_, assetPool_, stakePool_);
  }

  /// @notice Unstakes by burning `stkReceiptTokenAmount_` of `stakePoolId_` stake pool stake receipt tokens and
  /// sending `stkReceiptTokenAmount_` of `stakePoolId_` stake pool asset to `receiver_`. Also, claims ALL outstanding
  /// user rewards and sends them to `owner_`.
  /// @dev Assumes that user has approved this rewards manager to spend its stkReceiptTokens.
  /// @dev The `owner_` is transferred ALL claimable rewards of the `owner_`, not just those associated with the
  /// input amount, `stkReceiptTokenAmount_`.
  /// @dev Note that by default all reward pools are dripped and claimed when unstaking. If you want to unstake without
  /// dripping from specific reward pools, you can use the other unstake function which accepts bool[] memory
  /// dripRewardPool_ instead.
  /// @param stakePoolId_ The ID of the stake pool to unstake from.
  /// @param stkReceiptTokenAmount_ The amount of stkReceiptTokens to unstake.
  /// @param receiver_ The address that will receive the unstaked assets.
  /// @param owner_ The owner of the stkReceiptTokens being unstaked.
  function unstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_) external {
    if (stkReceiptTokenAmount_ == 0) revert AmountIsZero();

    ClaimRewardsPoolData[] memory claimRewardsPoolData_ = new ClaimRewardsPoolData[](rewardPools.length);
    for (uint16 i = 0; i < rewardPools.length; i++) {
      claimRewardsPoolData_[i] = ClaimRewardsPoolData({rewardPoolId: i, drip: true});
    }
    _claimRewards(ClaimRewardsArgs(stakePoolId_, owner_, owner_), claimRewardsPoolData_);
    _executeUnstake(stakePoolId_, stkReceiptTokenAmount_, receiver_, owner_);
  }

  /// @dev Rewards from all pools are claimed when unstaking. The `dripRewardPool_` array is used to specify whether to
  /// drip from each reward pool. It must be the same length as the number of reward pools.
  /// @param dripRewardPool_ Whether to drip and claim rewards for each reward pool.
  function unstake(
    uint16 stakePoolId_,
    uint256 stkReceiptTokenAmount_,
    address receiver_,
    address owner_,
    bool[] memory dripRewardPool_
  ) external {
    if (stkReceiptTokenAmount_ == 0) revert AmountIsZero();
    if (dripRewardPool_.length != rewardPools.length) revert IRewardsDistributorErrors.InvalidLength();

    ClaimRewardsPoolData[] memory claimRewardsPoolData_ = new ClaimRewardsPoolData[](rewardPools.length);
    for (uint16 i = 0; i < dripRewardPool_.length; i++) {
      claimRewardsPoolData_[i] = ClaimRewardsPoolData({rewardPoolId: i, drip: dripRewardPool_[i]});
    }
    _claimRewards(ClaimRewardsArgs(stakePoolId_, owner_, owner_), claimRewardsPoolData_);
    _executeUnstake(stakePoolId_, stkReceiptTokenAmount_, receiver_, owner_);
  }

  function _executeStake(
    uint16 stakePoolId_,
    uint256 assetAmount_,
    address receiver_,
    address owner_,
    AssetPool storage assetPool_,
    StakePool storage stakePool_
  ) internal {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();

    // Given the 1:1 conversion rate between the underlying asset and stkReceiptTokens, we always have `assetAmount_ ==
    // stkReceiptTokenAmount_`.
    stakePool_.amount += assetAmount_;
    assetPool_.amount += assetAmount_;

    // Update user rewards before minting any new stkReceiptTokens.
    IReceiptToken stkReceiptToken_ = stakePool_.stkReceiptToken;
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[stakePoolId_];
    _dripAndApplyPendingDrippedRewards(stakePool_, claimableRewards_);
    _updateUserRewards(stkReceiptToken_.balanceOf(receiver_), claimableRewards_, userRewards[stakePoolId_][receiver_]);

    stkReceiptToken_.mint(receiver_, assetAmount_);
    emit Staked(msg.sender, owner_, receiver_, stakePoolId_, stkReceiptToken_, assetAmount_);
  }

  function _executeUnstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_)
    internal
  {
    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IReceiptToken stkReceiptToken_ = stakePool_.stkReceiptToken;
    IERC20 asset_ = stakePool_.asset;

    // Given the 1:1 conversion rate between the underlying asset and stkReceiptTokens, we always have `assetAmount_ ==
    // stkReceiptTokenAmount_`.
    stakePool_.amount -= stkReceiptTokenAmount_;
    assetPools[asset_].amount -= stkReceiptTokenAmount_;
    // Burn also ensures that the sender has sufficient allowance if they're not the owner.
    stkReceiptToken_.burn(msg.sender, owner_, stkReceiptTokenAmount_);

    asset_.safeTransfer(receiver_, stkReceiptTokenAmount_);

    emit Unstaked(msg.sender, receiver_, owner_, stakePoolId_, stkReceiptToken_, stkReceiptTokenAmount_);
  }
}
