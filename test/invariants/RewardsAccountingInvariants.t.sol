// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {StakePool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {ClaimableRewardsData} from "../../src/lib/structs/Rewards.sol";
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
      for (uint16 stakePoolId_ = 0; stakePoolId_ < numStakePools_; stakePoolId_++) {
        uint256 cumulativeClaimedRewards_ =
          rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_).cumulativeClaimedRewards;
        uint256 rewardsWeight_ = rewardsManager.stakePools(stakePoolId_).rewardsWeight;
        uint256 scaledCumulativeDrippedRewards_ = cumulativeDrippedRewards_.mulDivDown(rewardsWeight_, MathConstants.ZOC);
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
