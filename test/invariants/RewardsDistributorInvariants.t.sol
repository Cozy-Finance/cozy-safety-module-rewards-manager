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

abstract contract RewardsDistributorInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  function invariant_claimRewardsUserRewardsAccounting() public syncCurrentTimestamp(rewardsManagerHandler) {
    address receiver_ = _randomAddress();
    uint256 numRewardPools_ = numRewardPools;

    uint256[] memory receiverPreBalances_ = new uint256[](numRewardPools_);
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      receiverPreBalances_[rewardPoolId_] = IERC20(rewardsManager.rewardPools(rewardPoolId_).asset).balanceOf(receiver_);
    }

    address actor_ = rewardsManagerHandler.claimRewards(receiver_, _randomUint256());
    // The default address is used when there are no actors with stakes, in which case we just skip this invariant.
    if (actor_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;

    uint16 stakePoolId_ = rewardsManagerHandler.currentStakePoolId();
    UserRewardsData[] memory userRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, actor_);
    uint256 userNumRewardPools_ = userRewardsData_.length;
    uint256 actorStkReceiptTokenBalance_ = rewardsManager.stakePools(stakePoolId_).stkReceiptToken.balanceOf(actor_);

    require(
      userNumRewardPools_ == numRewardPools_,
      string.concat(
        "Invariant Violated: The length of the user rewards data must be equal to the number of reward pools.",
        " userNumRewardPools_: ",
        Strings.toString(userNumRewardPools_),
        ", numRewardPools: ",
        Strings.toString(numRewardPools_)
      )
    );

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < userNumRewardPools_; rewardPoolId_++) {
      require(
        userRewardsData_[rewardPoolId_].accruedRewards == 0,
        string.concat(
          "Invariant Violated: The user accrued rewards must be zero after claiming rewards.",
          " userRewardsData_[rewardPoolId_].accruedRewards: ",
          Strings.toString(userRewardsData_[rewardPoolId_].accruedRewards),
          ", actor: ",
          Strings.toHexString(uint160(actor_)),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );

      ClaimableRewardsData memory claimableRewards_ = rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_);
      require(
        userRewardsData_[rewardPoolId_].indexSnapshot == claimableRewards_.indexSnapshot,
        string.concat(
          "Invariant Violated: The user index snapshot must be equal to the global index snapshot after claiming rewards.",
          " userIndexSnapshot: ",
          Strings.toString(userRewardsData_[rewardPoolId_].indexSnapshot),
          ", globalIndexSnapshot: ",
          Strings.toString(claimableRewards_.indexSnapshot),
          ", actor: ",
          Strings.toHexString(uint160(actor_)),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );

      uint256 receiverPostBalance_ = IERC20(rewardsManager.rewardPools(rewardPoolId_).asset).balanceOf(receiver_);
      require(
        receiverPostBalance_ >= receiverPreBalances_[rewardPoolId_],
        string.concat(
          "Invariant Violated: The receiver balance must be greater than or equal to the pre-balance after claiming rewards.",
          " receiverPostBalance: ",
          Strings.toString(receiverPostBalance_),
          ", receiverPreBalance: ",
          Strings.toString(receiverPreBalances_[rewardPoolId_]),
          ", receiver: ",
          Strings.toHexString(uint160(receiver_)),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );
    }
  }
}

contract RewardsDistributorInvariantsSingleStakePoolSingleRewardPool is
  RewardsDistributorInvariants,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract RewardsDistributorInvariantsMultipleStakePoolsMultipleRewardPools is
  RewardsDistributorInvariants,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
