// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {RewardsModuleBaseStorage} from "./RewardsModuleBaseStorage.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {UserRewardsData, ClaimableRewardsData} from "./structs/Rewards.sol";
import {ReservePool, RewardPool} from "./structs/Pools.sol";

abstract contract RewardsModuleCommon is RewardsModuleBaseStorage, ICommonErrors {
  /// @notice Claim staking rewards for a given reserve pool.
  function _claimRewards(uint16 reservePoolId_, address receiver_, address owner_) internal virtual;

  /// @notice Updates the balances for each reward pool by applying a drip factor on them, and increment the
  /// claimable rewards index for each claimable rewards pool.
  /// @dev Defined in RewardsHandler.
  function dripRewards() public virtual;

  /// @dev Helper to assert that the rewards module has a balance of tokens that matches the required amount for a
  /// deposit/stake.
  function _assertValidDepositBalance(IERC20 token_, uint256 tokenPoolBalance_, uint256 depositAmount_)
    internal
    view
    virtual;

  // @dev Returns the next amount of rewards/fees to be dripped given a base amount and a drip model.
  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    virtual
    returns (uint256);

  // @dev Compute the next amount of rewards/fees to be dripped given a base amount and a drip factor.
  function _computeNextDripAmount(uint256 totalBaseAmount_, uint256 dripFactor_)
    internal
    view
    virtual
    returns (uint256);

  function _updateUserRewards(
    uint256 userStkTokenBalance_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_,
    UserRewardsData[] storage userRewards_
  ) internal virtual;

  function _dripRewardPool(RewardPool storage rewardPool_) internal virtual;

  function _dripAndApplyPendingDrippedRewards(
    ReservePool storage reservePool_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_
  ) internal virtual;

  function _dripAndResetCumulativeRewardsValues(ReservePool[] storage reservePools_, RewardPool[] storage rewardPools_)
    internal
    virtual;
}
