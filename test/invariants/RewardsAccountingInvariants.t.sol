// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {StakePool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData} from "../../src/lib/structs/Rewards.sol";
import {
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract RewardsAccountingInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  using FixedPointMathLib for uint256;

  function invariant_cumulativeClaimableRewardsLteScaledCumulativeDrippedRewards()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      uint256 cumulativeDrippedRewards_ = rewardsManager.rewardPools(rewardPoolId_).cumulativeDrippedRewards;
      uint256 sumCumulativeClaimableRewards_ = 0;

      for (uint16 stakePoolId_ = 0; stakePoolId_ < numStakePools; stakePoolId_++) {
        uint256 cumulativeClaimableRewards_ =
          rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_).cumulativeClaimableRewards;
        sumCumulativeClaimableRewards_ += cumulativeClaimableRewards_;

        uint256 rewardsWeight_ = rewardsManager.stakePools(stakePoolId_).rewardsWeight;
        uint256 scaledCumulativeDrippedRewards_ =
          cumulativeDrippedRewards_.mulDivDown(rewardsWeight_, MathConstants.ZOC);
        require(
          cumulativeClaimableRewards_ <= scaledCumulativeDrippedRewards_,
          string.concat(
            "Invariant Violated: The cumulative claimed rewards for a specific (stake pool, reward pool) pair must be less than or equal to the scaled cumulative dripped rewards for the pair.",
            " scaledCumulativeDrippedRewards: ",
            Strings.toString(scaledCumulativeDrippedRewards_),
            ", cumulativeClaimableRewards: ",
            Strings.toString(cumulativeClaimableRewards_),
            ", stakePoolId: ",
            Strings.toString(stakePoolId_),
            ", rewardPoolId: ",
            Strings.toString(rewardPoolId_)
          )
        );
      }

      require(
        sumCumulativeClaimableRewards_ <= cumulativeDrippedRewards_,
        string.concat(
          "Invariant Violated: Invariant Violated: The sum of every stake pool's cumulative claimed rewards from a reward pool must be less than or equal to the cumulative dripped rewards from the reward pool.",
          " totalClaimedRewards: ",
          Strings.toString(sumCumulativeClaimableRewards_),
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
    for (uint256 i = 0; i < actorsWithStakes_.length; i++) {
      _invariant_userRewardsAccounting(actorsWithStakes_[i]);
    }

    for (uint16 stakePoolId_ = 0; stakePoolId_ < numStakePools; stakePoolId_++) {
      for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
        uint256 sumUserAccruedRewards_ = sumUserAccruedRewards[stakePoolId_][rewardPoolId_];
        uint256 cumulativeClaimableRewards_ =
          rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_).cumulativeClaimableRewards;

        require(
          sumUserAccruedRewards_ <= cumulativeClaimableRewards_,
          string.concat(
            "Invariant Violated: The sum of user accrued rewards for a (stake pool, reward pool) pair must be less than or equal to the cumulative claimed rewards for the pair.",
            " sumUserAccruedRewards: ",
            Strings.toString(sumUserAccruedRewards_),
            ", cumulativeClaimedRewards: ",
            Strings.toString(cumulativeClaimableRewards_),
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

    // The invariant only checks for reward pools registered in `userRewardsData_`. Reward pools that have not been yet
    // registered into the users rewards data are skip to avoid an out-of-bounds error.
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < userRewardsData_.length; rewardPoolId_++) {
      uint256 globalIndexSnapshot_ = rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_).indexSnapshot;
      require(
        userRewardsData_[rewardPoolId_].indexSnapshot <= globalIndexSnapshot_,
        string.concat(
          "Invariant Violated: Invariant Violated: The user rewards index snapshot must be less than or equal to the global rewards index snapshot.",
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

contract RewardsAccountingInvariantsWithStateTransitionsSingleStakePoolSingleRewardPool is
  RewardsAccountingInvariantsWithStateTransitions,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract RewardsAccountingInvariantsWithStateTransitionsMultipleStakePoolsMultipleRewardPools is
  RewardsAccountingInvariantsWithStateTransitions,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
