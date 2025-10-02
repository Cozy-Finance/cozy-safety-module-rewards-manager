// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-libs/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {RewardsManagerBaseStorage} from "./RewardsManagerBaseStorage.sol";
import {
  ClaimRewardsArgs,
  ClaimableRewardsData,
  UserRewardsData,
  DepositorRewardsData,
  ClaimRewardsPoolData
} from "./structs/Rewards.sol";
import {StakePool, RewardPool} from "./structs/Pools.sol";

abstract contract RewardsManagerCommon is RewardsManagerBaseStorage, ICommonErrors {
  /// @dev Defined in RewardsDistributor.
  function _claimRewards(ClaimRewardsArgs memory args_, ClaimRewardsPoolData[] memory claimRewardsPoolData_)
    internal
    virtual;

  /// @dev Defined in RewardsDistributor.
  function dripRewards() public virtual;

  /// @notice Helper to assert that the rewards manager has a balance of tokens that matches the required amount for a
  /// deposit/stake.
  /// @dev Defined in Depositor.
  function _assertValidDepositBalance(IERC20 token_, uint256 tokenPoolBalance_, uint256 depositAmount_)
    internal
    view
    virtual;

  /// @notice Returns the next amount of rewards/fees to be dripped given a base amount, drip model and last drip time.
  /// @dev Defined in RewardsDistributor.
  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    virtual
    returns (uint256);

  /// @notice Returns the next drip factor given a base amount, drip model and last drip time.
  /// @dev Defined in RewardsDistributor.
  function _getNextDripFactor(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    virtual
    returns (uint256);

  /// @dev Defined in RewardsDistributor.
  function _updateUserRewards(
    uint256 userStkReceiptTokenBalance_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_,
    UserRewardsData[] storage userRewards_
  ) internal virtual;

  /// @dev Defined in RewardsDistributor.
  function _dripRewardPool(RewardPool storage rewardPool_) internal virtual;

  /// @dev Defined in RewardsDistributor.
  function _dripAndApplyPendingDrippedRewards(
    StakePool storage stakePool_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_
  ) internal virtual;

  /// @dev Defined in RewardsDistributor.
  function _dripAndResetCumulativeRewardsValues(StakePool[] storage stakePools_, RewardPool[] storage rewardPools_)
    internal
    virtual;

  /// @dev Defined in Withdrawer.
  function _previewCurrentWithdrawableRewards(
    RewardPool storage rewardPool_,
    DepositorRewardsData storage depositorRewardsData_
  ) internal view virtual returns (uint256);
}
