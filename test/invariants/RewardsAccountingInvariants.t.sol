// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {StakePool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData} from "../../src/lib/structs/Rewards.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract RewardsAccountingInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  function invariant_cumulativeClaimedRewardsLeScaledCumulativeDrippedRewards()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    uint256 numStakePools_ = numStakePools;
    uint256 numRewardPools_ = numRewardPools;

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      uint256 cumulativeDrippedRewards_ = rewardsManager.rewardPools(rewardPoolId_).cumulativeDrippedRewards;
      uint256 sumCumulativeClaimedRewards_ = 0;

      for (uint16 stakePoolId_ = 0; stakePoolId_ < numStakePools_; stakePoolId_++) {
        uint256 cumulativeClaimedRewards_ =
          rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_).cumulativeClaimedRewards;
        sumCumulativeClaimedRewards_ += cumulativeClaimedRewards_;

        uint256 rewardsWeight_ = rewardsManager.stakePools(stakePoolId_).rewardsWeight;
        uint256 scaledCumulativeDrippedRewards_ =
          cumulativeDrippedRewards_.mulDivDown(rewardsWeight_, MathConstants.ZOC);
        require(
          cumulativeClaimedRewards_ <= scaledCumulativeDrippedRewards_,
          string.concat(
            "Invariant Violated: The cumulative claimed rewards must be less than or equal to the scaled cumulative dripped rewards.",
            " scaledCumulativeDrippedRewards: ",
            Strings.toString(scaledCumulativeDrippedRewards_),
            ", cumulativeClaimedRewards: ",
            Strings.toString(cumulativeClaimedRewards_),
            ", stakePoolId: ",
            Strings.toString(stakePoolId_),
            ", rewardPoolId: ",
            Strings.toString(rewardPoolId_)
          )
        );
      }

      require(
        sumCumulativeClaimedRewards_ <= cumulativeDrippedRewards_,
        string.concat(
          "Invariant Violated: The sum of cumulative claimed rewards must be less than or equal to the cumulative dripped rewards.",
          " totalClaimedRewards: ",
          Strings.toString(sumCumulativeClaimedRewards_),
          ", cumulativeDrippedRewards: ",
          Strings.toString(cumulativeDrippedRewards_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );
    }
  }

  // Mapping of (stakePoolId => (rewardPoolId => sumUserAccruedRewards)) to track the sum of user accrued rewards for a
  // given (stakePoolId, rewardPoolId) pair.
  mapping(uint16 => mapping(uint16 => uint256)) private sumUserAccruedRewards;

  function invariant_userRewardsAccounting() public syncCurrentTimestamp(rewardsManagerHandler) {
    address[] memory actorsWithStakes_ = rewardsManagerHandler.getActorsWithStakes();
    uint256 numActorsWithStakes_ = actorsWithStakes_.length;
    for (uint256 i = 0; i < numActorsWithStakes_; i++) {
      _invariant_userRewardsAccounting(actorsWithStakes_[i]);
    }

    uint256 numStakePools_ = numStakePools;
    uint256 numRewardPools_ = numRewardPools;
    for (uint16 stakePoolId_ = 0; stakePoolId_ < numStakePools_; stakePoolId_++) {
      for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
        uint256 sumUserAccruedRewards_ = sumUserAccruedRewards[stakePoolId_][rewardPoolId_];
        uint256 cumulativeClaimedRewards_ =
          rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_).cumulativeClaimedRewards;

        require(
          sumUserAccruedRewards_ <= cumulativeClaimedRewards_,
          string.concat(
            "Invariant Violated: The sum of user accrued rewards must be less than or equal to the cumulative claimed rewards.",
            " sumUserAccruedRewards: ",
            Strings.toString(sumUserAccruedRewards_),
            ", cumulativeClaimedRewards: ",
            Strings.toString(cumulativeClaimedRewards_),
            ", stakePoolId: ",
            Strings.toString(stakePoolId_),
            ", rewardPoolId: ",
            Strings.toString(rewardPoolId_)
          )
        );
      }
    }
  }

  function _invariant_userRewardsAccounting(address user_) internal {
    uint16 stakePoolId_ = rewardsManagerHandler.getStakePoolIdForActorWithStake(_randomUint256(), user_);
    UserRewardsData[] memory userRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, user_);

    // We only check the invariant for reward pools registered in `userRewardsData_`. New/unregistered reward pools are
    // not checked because we will get a out-of-bounds error.
    uint256 numRewardPools_ = userRewardsData_.length;
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      uint256 globalIndexSnapshot_ = rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_).indexSnapshot;
      require(
        userRewardsData_[rewardPoolId_].indexSnapshot <= globalIndexSnapshot_,
        string.concat(
          "Invariant Violated: The user index snapshot must be less than or equal to the global index snapshot.",
          " userIndexSnapshot: ",
          Strings.toString(userRewardsData_[rewardPoolId_].indexSnapshot),
          ", globalIndexSnapshot: ",
          Strings.toString(globalIndexSnapshot_),
          ", user: ",
          Strings.toHexString(uint160(user_)),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );

      sumUserAccruedRewards[stakePoolId_][rewardPoolId_] += userRewardsData_[rewardPoolId_].accruedRewards;
    }
  }
}

contract RewardsAccountingInvariantsSingleStakePoolSingleRewardPool is
  RewardsAccountingInvariants,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract RewardsAccountingInvariantsMultipleStakePoolsMultipleRewardPools is
  RewardsAccountingInvariants,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
