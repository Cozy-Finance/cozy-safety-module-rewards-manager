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

  function invariant_claimRewardsGlobalRewardsAccounting() public syncCurrentTimestamp(rewardsManagerHandler) {
    RewardPool[] memory preRewardPools_ = rewardsManager.getRewardPools();
    ClaimableRewardsData[][] memory preClaimableRewards_ = rewardsManager.getClaimableRewards();

    address actor_ = rewardsManagerHandler.claimRewards(_randomAddress(), _randomUint256());
    if (actor_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;

    uint16 stakePoolId_ = rewardsManagerHandler.currentStakePoolId();
    StakePool memory stakePool_ = rewardsManager.stakePools(stakePoolId_);
    RewardPool[] memory postRewardPools_ = rewardsManager.getRewardPools();
    ClaimableRewardsData[][] memory postClaimableRewards_ = rewardsManager.getClaimableRewards();

    uint256 numRewardPools_ = numRewardPools;
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      _invariant_dripRewardPoolChanged(preRewardPools_[rewardPoolId_], postRewardPools_[rewardPoolId_]);

      uint256 preCumulativeClaimedRewards_ = preClaimableRewards_[stakePoolId_][rewardPoolId_].cumulativeClaimedRewards;
      uint256 postCumulativeClaimedRewards_ =
        postClaimableRewards_[stakePoolId_][rewardPoolId_].cumulativeClaimedRewards;
      require(
        preCumulativeClaimedRewards_ <= postCumulativeClaimedRewards_,
        string.concat(
          "Invariant Violated: The post-cumulative claimed rewards must be greater than or equal to the pre-cumulative claimed rewards after claiming rewards.",
          " preCumulativeClaimedRewards: ",
          Strings.toString(preCumulativeClaimedRewards_),
          ", postCumulativeClaimedRewards: ",
          Strings.toString(postCumulativeClaimedRewards_),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );

      uint256 scaledCumulativeDrippedRewards_ =
        postRewardPools_[rewardPoolId_].cumulativeDrippedRewards.mulDivDown(stakePool_.rewardsWeight, MathConstants.ZOC);
      require(
        postCumulativeClaimedRewards_ == scaledCumulativeDrippedRewards_,
        string.concat(
          "Invariant Violated: The post-cumulative claimed rewards must be equal to the scaled cumulative dripped rewards after claiming rewards.",
          " scaledCumulativeDrippedRewards: ",
          Strings.toString(scaledCumulativeDrippedRewards_),
          ", postCumulativeClaimedRewards: ",
          Strings.toString(postCumulativeClaimedRewards_),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );

      uint256 preIndexSnapshot_ = preClaimableRewards_[stakePoolId_][rewardPoolId_].indexSnapshot;
      uint256 postIndexSnapshot_ = postClaimableRewards_[stakePoolId_][rewardPoolId_].indexSnapshot;
      require(
        preIndexSnapshot_ <= postIndexSnapshot_,
        string.concat(
          "Invariant Violated: The post-index snapshot must be greater than or equal to the pre-index snapshot after claiming rewards.",
          " preIndexSnapshot: ",
          Strings.toString(preIndexSnapshot_),
          ", postIndexSnapshot: ",
          Strings.toString(postIndexSnapshot_),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );
    }
  }

  function invariant_dripRewardPoolAccounting() public syncCurrentTimestamp(rewardsManagerHandler) {
    RewardPool[] memory preRewardPools_ = rewardsManager.getRewardPools();
    rewardsManagerHandler.dripRewardPool(_randomUint256());
    RewardPool[] memory postRewardPools_ = rewardsManager.getRewardPools();

    uint16 drippedRewardPoolId_ = rewardsManagerHandler.currentRewardPoolId();
    uint256 numRewardPools_ = numRewardPools;
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      if (rewardPoolId_ == drippedRewardPoolId_) {
        _invariant_dripRewardPoolChanged(preRewardPools_[rewardPoolId_], postRewardPools_[rewardPoolId_]);
      } else {
        _invariant_dripRewardPoolUnchanged(preRewardPools_[rewardPoolId_], postRewardPools_[rewardPoolId_]);
      }
    }
  }

  function invariant_dripRewardsAccounting() public syncCurrentTimestamp(rewardsManagerHandler) {
    RewardPool[] memory preRewardPools_ = rewardsManager.getRewardPools();
    rewardsManagerHandler.dripRewards(_randomUint256());
    RewardPool[] memory postRewardPools_ = rewardsManager.getRewardPools();

    uint256 numRewardPools_ = numRewardPools;
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      _invariant_dripRewardPoolChanged(preRewardPools_[rewardPoolId_], postRewardPools_[rewardPoolId_]);
    }
  }

  function invariant_updateUserRewardsForStkTokenTransferAccounting()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    address from_ = _randomAddress();
    address to_ = _randomAddress();
    rewardsManagerHandler.updateUserRewardsForStkTokenTransfer(from_, to_, _randomUint256());

    uint16 stakePoolId_ = rewardsManagerHandler.currentStakePoolId();
    UserRewardsData[] memory fromUserRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, from_);
    UserRewardsData[] memory toUserRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, to_);
    ClaimableRewardsData[] memory claimableRewards_ = rewardsManager.getClaimableRewards(stakePoolId_);

    _invariant_userRewardsDataUpdated(
      fromUserRewardsData_, toUserRewardsData_, claimableRewards_, stakePoolId_, from_, to_
    );
  }

  function invariant_updateUserRewardsForStkTokenTransferAccountingExistingStakers()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    address[] memory actorsWithStakes_ = rewardsManagerHandler.getActorsWithStakes();
    if (actorsWithStakes_.length < 2) return;

    address from_ = actorsWithStakes_[_randomUint256InRange(0, actorsWithStakes_.length - 1)];
    address to_ = actorsWithStakes_[_randomUint256InRange(0, actorsWithStakes_.length - 1)];
    uint16 stakePoolId_ = rewardsManagerHandler.getStakePoolIdForActorWithStake(_randomUint256(), from_);

    UserRewardsData[] memory preFromUserRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, from_);
    UserRewardsData[] memory preToUserRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, to_);

    IERC20 stkToken_ = getStakePool(rewardsManager, stakePoolId_).stkReceiptToken;
    vm.startPrank(address(stkToken_));
    rewardsManager.updateUserRewardsForStkTokenTransfer(from_, to_);
    vm.stopPrank();

    UserRewardsData[] memory postFromUserRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, from_);
    UserRewardsData[] memory postToUserRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, to_);
    ClaimableRewardsData[] memory claimableRewards_ = rewardsManager.getClaimableRewards(stakePoolId_);

    _invariant_userRewardsDataUpdated(
      postFromUserRewardsData_, postToUserRewardsData_, claimableRewards_, stakePoolId_, from_, to_
    );

    uint256 numRewardPools_ = preFromUserRewardsData_.length;
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      require(
        preFromUserRewardsData_[rewardPoolId_].accruedRewards <= postFromUserRewardsData_[rewardPoolId_].accruedRewards,
        string.concat(
          "Invariant Violated: The from user pre-accrued rewards must be less than or equal to the post-accrued rewards after updateUserRewardsForStkTokenTransfer.",
          " preAccruedRewards: ",
          Strings.toString(preFromUserRewardsData_[rewardPoolId_].accruedRewards),
          ", postAccruedRewards: ",
          Strings.toString(postFromUserRewardsData_[rewardPoolId_].accruedRewards),
          ", from: ",
          Strings.toHexString(uint160(from_)),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );
    }

    numRewardPools_ = preToUserRewardsData_.length;
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      require(
        preToUserRewardsData_[rewardPoolId_].accruedRewards <= postToUserRewardsData_[rewardPoolId_].accruedRewards,
        string.concat(
          "Invariant Violated: The to user pre-accrued rewards must be less than or equal to the post-accrued rewards after updateUserRewardsForStkTokenTransfer.",
          " preAccruedRewards: ",
          Strings.toString(preToUserRewardsData_[rewardPoolId_].accruedRewards),
          ", postAccruedRewards: ",
          Strings.toString(postToUserRewardsData_[rewardPoolId_].accruedRewards),
          ", to: ",
          Strings.toHexString(uint160(to_)),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );
    }
  }

  function invariant_stkTokenTransferAccounting() public syncCurrentTimestamp(rewardsManagerHandler) {
    address to_ = _randomAddress();
    (address from_,) = rewardsManagerHandler.stkTokenTransfer(_randomUint64(), to_, _randomUint256());
    if (from_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;

    uint16 stakePoolId_ = rewardsManagerHandler.currentStakePoolId();
    UserRewardsData[] memory fromUserRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, from_);
    UserRewardsData[] memory toUserRewardsData_ = rewardsManager.getUserRewards(stakePoolId_, to_);

    _invariant_userRewardsDataUpdated(
      fromUserRewardsData_,
      toUserRewardsData_,
      rewardsManager.getClaimableRewards(stakePoolId_),
      stakePoolId_,
      from_,
      to_
    );
  }

  function _invariant_dripRewardPoolChanged(RewardPool memory preRewardPool_, RewardPool memory postRewardPool_)
    internal
    view
  {
    bool expectDrip_ = preRewardPool_.undrippedRewards > 0 && preRewardPool_.lastDripTime < block.timestamp;

    require(
      (preRewardPool_.cumulativeDrippedRewards <= postRewardPool_.cumulativeDrippedRewards && expectDrip_)
        || (!expectDrip_ && preRewardPool_.cumulativeDrippedRewards == postRewardPool_.cumulativeDrippedRewards),
      string.concat(
        "Invariant Violated: The cumulative dripped rewards must be greater than or equal to pre-cumulative dripped rewards.",
        " preCumulativeDrippedRewards: ",
        Strings.toString(preRewardPool_.cumulativeDrippedRewards),
        ", postCumulativeDrippedRewards: ",
        Strings.toString(postRewardPool_.cumulativeDrippedRewards)
      )
    );

    require(
      (preRewardPool_.undrippedRewards >= postRewardPool_.undrippedRewards && expectDrip_)
        || (!expectDrip_ && preRewardPool_.undrippedRewards == postRewardPool_.undrippedRewards),
      string.concat(
        "Invariant Violated: The undripped rewards must be less than or equal to pre-undripped rewards.",
        " preUndrippedRewards: ",
        Strings.toString(preRewardPool_.undrippedRewards),
        ", postUndrippedRewards: ",
        Strings.toString(postRewardPool_.undrippedRewards)
      )
    );

    require(
      postRewardPool_.lastDripTime == block.timestamp,
      string.concat(
        "Invariant Violated: The last drip time must be equal to the current block timestamp.",
        " lastDripTime: ",
        Strings.toString(postRewardPool_.lastDripTime),
        ", block.timestamp: ",
        Strings.toString(block.timestamp)
      )
    );
  }

  function _invariant_dripRewardPoolUnchanged(RewardPool memory preRewardPool_, RewardPool memory postRewardPool_)
    internal
    pure
  {
    require(
      preRewardPool_.cumulativeDrippedRewards == postRewardPool_.cumulativeDrippedRewards,
      string.concat(
        "Invariant Violated: The cumulative dripped rewards must be equal to the pre-cumulative dripped rewards.",
        " preCumulativeDrippedRewards: ",
        Strings.toString(preRewardPool_.cumulativeDrippedRewards),
        ", postCumulativeDrippedRewards: ",
        Strings.toString(postRewardPool_.cumulativeDrippedRewards)
      )
    );

    require(
      preRewardPool_.undrippedRewards == postRewardPool_.undrippedRewards,
      string.concat(
        "Invariant Violated: The undripped rewards must be equal to the pre-undripped rewards.",
        " preUndrippedRewards: ",
        Strings.toString(preRewardPool_.undrippedRewards),
        ", postUndrippedRewards: ",
        Strings.toString(postRewardPool_.undrippedRewards)
      )
    );

    require(
      preRewardPool_.lastDripTime == postRewardPool_.lastDripTime,
      string.concat(
        "Invariant Violated: The last drip time must be equal to the pre-last drip time.",
        " lastDripTime: ",
        Strings.toString(postRewardPool_.lastDripTime),
        ", preLastDripTime: ",
        Strings.toString(preRewardPool_.lastDripTime)
      )
    );
  }

  function _invariant_userRewardsDataUpdated(
    UserRewardsData[] memory fromUserRewardsData_,
    UserRewardsData[] memory toUserRewardsData_,
    ClaimableRewardsData[] memory claimableRewards_,
    uint16 stakePoolId_,
    address from_,
    address to_
  ) internal view {
    uint256 numRewardPools_ = numRewardPools;
    require(
      fromUserRewardsData_.length == numRewardPools_ && toUserRewardsData_.length == numRewardPools_,
      string.concat(
        "Invariant Violated: The length of the user rewards data must be equal to the number of reward pools after updateUserRewardsForStkTokenTransfer.",
        " fromUserRewardsData_.length: ",
        Strings.toString(fromUserRewardsData_.length),
        ", toUserRewardsData_.length: ",
        Strings.toString(toUserRewardsData_.length),
        ", numRewardPools: ",
        Strings.toString(numRewardPools_)
      )
    );

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools_; rewardPoolId_++) {
      uint256 globalIndexSnapshot_ = claimableRewards_[rewardPoolId_].indexSnapshot;
      require(
        fromUserRewardsData_[rewardPoolId_].indexSnapshot == globalIndexSnapshot_,
        string.concat(
          "Invariant Violated: The user index snapshot must be equal to the global index snapshot after updateUserRewardsForStkTokenTransfer.",
          " userindexSnapshot: ",
          Strings.toString(fromUserRewardsData_[rewardPoolId_].indexSnapshot),
          ", globalIndexSnapshot: ",
          Strings.toString(globalIndexSnapshot_),
          ", from: ",
          Strings.toHexString(uint160(from_)),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );

      require(
        toUserRewardsData_[rewardPoolId_].indexSnapshot == globalIndexSnapshot_,
        string.concat(
          "Invariant Violated: The user index snapshot must be equal to the global index snapshot after updateUserRewardsForStkTokenTransfer.",
          " userindexSnapshot: ",
          Strings.toString(toUserRewardsData_[rewardPoolId_].indexSnapshot),
          ", globalIndexSnapshot: ",
          Strings.toString(globalIndexSnapshot_),
          ", to: ",
          Strings.toHexString(uint160(to_)),
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