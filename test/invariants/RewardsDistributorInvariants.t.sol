// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {StakePool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData, PreviewClaimableRewards} from "../../src/lib/structs/Rewards.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract RewardsDistributorInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  mapping(IERC20 rewardAsset_ => uint256) public actorRewardsToBeClaimed;

  function invariant_claimRewardsUserRewardsAccounting() public syncCurrentTimestamp(rewardsManagerHandler) {
    address receiver_ = _randomAddress();

    uint256[] memory receiverPreBalances_ = new uint256[](numRewardPools);
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      receiverPreBalances_[rewardPoolId_] = rewardsManager.rewardPools(rewardPoolId_).asset.balanceOf(receiver_);
    }

    address actor_ = rewardsManagerHandler.getActorWithStake(_randomUint256());
    // The default address is used when there are no actors with stakes, in which case we just skip this invariant.
    if (actor_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;
    uint16 stakePoolId_ = rewardsManagerHandler.getStakePoolIdForActorWithStake(_randomUint256(), actor_);
    PreviewClaimableRewards memory actorPreviewClaimableRewards_ =
      rewardsManagerHandler.getActorRewardsToBeClaimed(stakePoolId_, actor_)[0];
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      actorRewardsToBeClaimed[rewardsManager.rewardPools(rewardPoolId_).asset] +=
        actorPreviewClaimableRewards_.claimableRewardsData[rewardPoolId_].amount;
    }

    vm.prank(actor_);
    rewardsManager.claimRewards(stakePoolId_, receiver_);

    UserRewardsData[] memory userRewards_ = rewardsManager.getUserRewards(stakePoolId_, actor_);
    require(
      userRewards_.length == numRewardPools,
      string.concat(
        "Invariant Violated: The length of the user rewards must be equal to the number of reward pools after claimRewards.",
        " userRewards_.length: ",
        Strings.toString(userRewards_.length),
        ", numRewardPools: ",
        Strings.toString(numRewardPools)
      )
    );

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < userRewards_.length; rewardPoolId_++) {
      require(
        userRewards_[rewardPoolId_].accruedRewards == 0,
        string.concat(
          "Invariant Violated: The user accrued rewards must be zero after claimRewards.",
          " userRewards_[rewardPoolId_].accruedRewards: ",
          Strings.toString(userRewards_[rewardPoolId_].accruedRewards),
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
        userRewards_[rewardPoolId_].indexSnapshot == claimableRewards_.indexSnapshot,
        string.concat(
          "Invariant Violated: The user rewards index snapshot must be equal to the global rewards index snapshot after claimRewards.",
          " userIndexSnapshot: ",
          Strings.toString(userRewards_[rewardPoolId_].indexSnapshot),
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

      RewardPool memory rewardPool_ = rewardsManager.rewardPools(rewardPoolId_);
      require(
        rewardPool_.asset.balanceOf(receiver_)
          == receiverPreBalances_[rewardPoolId_] + actorRewardsToBeClaimed[rewardPool_.asset],
        string.concat(
          "Invariant Violated: The receiver balance must be the pre-balance plus claimable rewards of that asset.",
          " receiverPostBalance: ",
          Strings.toString(rewardPool_.asset.balanceOf(receiver_)),
          ", receiverPreBalance: ",
          Strings.toString(receiverPreBalances_[rewardPoolId_]),
          ", claimableRewards: ",
          Strings.toString(actorRewardsToBeClaimed[rewardPool_.asset]),
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
    // The default address is used when there are no actors with stakes, in which case we just skip this invariant.
    if (actor_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;

    uint16 stakePoolId_ = rewardsManagerHandler.currentStakePoolId();
    StakePool memory stakePool_ = rewardsManager.stakePools(stakePoolId_);
    RewardPool[] memory postRewardPools_ = rewardsManager.getRewardPools();
    ClaimableRewardsData[][] memory postClaimableRewards_ = rewardsManager.getClaimableRewards();

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      _invariant_dripRewardPoolChanged(preRewardPools_[rewardPoolId_], postRewardPools_[rewardPoolId_]);

      uint256 preCumulativeClaimedRewards_ = preClaimableRewards_[stakePoolId_][rewardPoolId_].cumulativeClaimedRewards;
      uint256 postCumulativeClaimedRewards_ =
        postClaimableRewards_[stakePoolId_][rewardPoolId_].cumulativeClaimedRewards;
      require(
        preCumulativeClaimedRewards_ <= postCumulativeClaimedRewards_,
        string.concat(
          "Invariant Violated: The post-cumulative claimed rewards must be greater than or equal to the pre-cumulative claimed rewards after claimRewards.",
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
          "Invariant Violated: The post-cumulative claimed rewards must be equal to the scaled cumulative dripped rewards after claimRewards.",
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
          "Invariant Violated: The post-index rewards snapshot must be greater than or equal to the pre-index rewards snapshot after claimRewards.",
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

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      if (rewardPoolId_ == rewardsManagerHandler.currentRewardPoolId()) {
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

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
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
    UserRewardsData[] memory fromUserRewards_ = rewardsManager.getUserRewards(stakePoolId_, from_);
    UserRewardsData[] memory toUserRewards_ = rewardsManager.getUserRewards(stakePoolId_, to_);
    ClaimableRewardsData[] memory claimableRewards_ = rewardsManager.getClaimableRewards(stakePoolId_);

    _invariant_userRewardsSnapshotsUpdated(
      fromUserRewards_, toUserRewards_, claimableRewards_, stakePoolId_, from_, to_
    );
  }

  function invariant_updateUserRewardsForStkTokenTransferAccountingForExistingStakers()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    address[] memory actorsWithStakes_ = rewardsManagerHandler.getActorsWithStakes();
    if (actorsWithStakes_.length < 2) return;

    address from_ = rewardsManagerHandler.getActorWithStake(_randomUint256());
    address to_ = rewardsManagerHandler.getActorWithStake(_randomUint256());
    uint16 stakePoolId_ = rewardsManagerHandler.getStakePoolIdForActorWithStake(_randomUint256(), from_);

    UserRewardsData[] memory preFromUserRewards_ = rewardsManager.getUserRewards(stakePoolId_, from_);
    UserRewardsData[] memory preToUserRewards_ = rewardsManager.getUserRewards(stakePoolId_, to_);

    vm.prank(address(getStakePool(rewardsManager, stakePoolId_).stkReceiptToken));
    rewardsManager.updateUserRewardsForStkTokenTransfer(from_, to_);

    UserRewardsData[] memory postFromUserRewards_ = rewardsManager.getUserRewards(stakePoolId_, from_);
    UserRewardsData[] memory postToUserRewards_ = rewardsManager.getUserRewards(stakePoolId_, to_);
    ClaimableRewardsData[] memory claimableRewards_ = rewardsManager.getClaimableRewards(stakePoolId_);

    _invariant_userRewardsSnapshotsUpdated(
      postFromUserRewards_, postToUserRewards_, claimableRewards_, stakePoolId_, from_, to_
    );

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < preFromUserRewards_.length; rewardPoolId_++) {
      require(
        preFromUserRewards_[rewardPoolId_].accruedRewards <= postFromUserRewards_[rewardPoolId_].accruedRewards,
        string.concat(
          "Invariant Violated: The from user pre-accrued rewards must be less than or equal to the post-accrued rewards after updateUserRewardsForStkTokenTransfer.",
          " preAccruedRewards: ",
          Strings.toString(preFromUserRewards_[rewardPoolId_].accruedRewards),
          ", postAccruedRewards: ",
          Strings.toString(postFromUserRewards_[rewardPoolId_].accruedRewards),
          ", from: ",
          Strings.toHexString(uint160(from_)),
          ", stakePoolId: ",
          Strings.toString(stakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );
    }

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < preToUserRewards_.length; rewardPoolId_++) {
      require(
        preToUserRewards_[rewardPoolId_].accruedRewards <= postToUserRewards_[rewardPoolId_].accruedRewards,
        string.concat(
          "Invariant Violated: The to user pre-accrued rewards must be less than or equal to the post-accrued rewards after updateUserRewardsForStkTokenTransfer.",
          " preAccruedRewards: ",
          Strings.toString(preToUserRewards_[rewardPoolId_].accruedRewards),
          ", postAccruedRewards: ",
          Strings.toString(postToUserRewards_[rewardPoolId_].accruedRewards),
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

  function invariant_updateUserRewardsForStkTokenTransferRevertsForUnauthorizedAddress()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    address unauthorizedAddress_ = _randomAddress();
    for (uint16 stakePoolId_ = 0; stakePoolId_ < numStakePools; stakePoolId_++) {
      vm.assume(address(rewardsManager.stakePools(stakePoolId_).stkReceiptToken) != unauthorizedAddress_);
    }

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(unauthorizedAddress_);
    rewardsManager.updateUserRewardsForStkTokenTransfer(_randomAddress(), _randomAddress());
  }

  function invariant_stkTokenTransferAccounting() public syncCurrentTimestamp(rewardsManagerHandler) {
    address to_ = _randomAddress();
    (address from_,) = rewardsManagerHandler.stkTokenTransfer(_randomUint64(), to_, _randomUint256());
    if (from_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;

    uint16 stakePoolId_ = rewardsManagerHandler.currentStakePoolId();
    UserRewardsData[] memory fromUserRewards_ = rewardsManager.getUserRewards(stakePoolId_, from_);
    UserRewardsData[] memory toUserRewards_ = rewardsManager.getUserRewards(stakePoolId_, to_);

    _invariant_userRewardsSnapshotsUpdated(
      fromUserRewards_, toUserRewards_, rewardsManager.getClaimableRewards(stakePoolId_), stakePoolId_, from_, to_
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

  function _invariant_userRewardsSnapshotsUpdated(
    UserRewardsData[] memory fromUserRewards_,
    UserRewardsData[] memory toUserRewards_,
    ClaimableRewardsData[] memory claimableRewards_,
    uint16 stakePoolId_,
    address from_,
    address to_
  ) internal view {
    require(
      fromUserRewards_.length == numRewardPools && toUserRewards_.length == numRewardPools,
      string.concat(
        "Invariant Violated: The length of the user rewards data must be equal to the number of reward pools after updateUserRewardsForStkTokenTransfer.",
        " fromUserRewards_.length: ",
        Strings.toString(fromUserRewards_.length),
        ", toUserRewards_.length: ",
        Strings.toString(toUserRewards_.length),
        ", numRewardPools: ",
        Strings.toString(numRewardPools)
      )
    );

    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      uint256 globalIndexSnapshot_ = claimableRewards_[rewardPoolId_].indexSnapshot;
      require(
        fromUserRewards_[rewardPoolId_].indexSnapshot == globalIndexSnapshot_,
        string.concat(
          "Invariant Violated: The user rewards index snapshot must be equal to the global rewards index snapshot after updateUserRewardsForStkTokenTransfer.",
          " userindexSnapshot: ",
          Strings.toString(fromUserRewards_[rewardPoolId_].indexSnapshot),
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
        toUserRewards_[rewardPoolId_].indexSnapshot == globalIndexSnapshot_,
        string.concat(
          "Invariant Violated: The user rewards index snapshot must be equal to the global rewards index snapshot after updateUserRewardsForStkTokenTransfer.",
          " userindexSnapshot: ",
          Strings.toString(toUserRewards_[rewardPoolId_].indexSnapshot),
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
