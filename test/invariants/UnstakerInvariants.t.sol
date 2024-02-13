// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {StakePool, RewardPool, AssetPool} from "../../src/lib/structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData, PreviewClaimableRewards} from "../../src/lib/structs/Rewards.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract UnstakerInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  struct UnstakeStakePoolData {
    uint256 stakePoolAmount;
    uint256 assetPoolAmount;
    uint256 assetAmount;
    uint256 stkReceiptTokenTotalSupply;
  }

  mapping(IERC20 rewardAsset_ => uint256) public actorRewardsToBeClaimed;

  function invariant_unstake() public syncCurrentTimestamp(rewardsManagerHandler) {
    UnstakeStakePoolData[] memory unstakeStakePoolData_ = new UnstakeStakePoolData[](numStakePools);
    for (uint8 stakePoolId_; stakePoolId_ < numStakePools; stakePoolId_++) {
      StakePool memory stakePool_ = rewardsManager.stakePools(stakePoolId_);
      unstakeStakePoolData_[stakePoolId_] = UnstakeStakePoolData({
        stakePoolAmount: stakePool_.amount,
        assetPoolAmount: rewardsManager.assetPools(stakePool_.asset).amount,
        assetAmount: stakePool_.asset.balanceOf(address(rewardsManager)),
        stkReceiptTokenTotalSupply: stakePool_.stkReceiptToken.totalSupply()
      });
    }

    address receiver_ = _randomAddress();
    uint256[] memory receiverPreBalances_ = new uint256[](numRewardPools);
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      receiverPreBalances_[rewardPoolId_] = rewardsManager.rewardPools(rewardPoolId_).asset.balanceOf(receiver_);
    }

    address actor_ = rewardsManagerHandler.getActorWithStake(_randomUint256());
    // The default address is used when there are no actors with stakes, in which case we just skip this invariant.
    if (actor_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;
    uint16 unstakedStakePoolId_ = rewardsManagerHandler.getStakePoolIdForActorWithStake(_randomUint256(), actor_);
    StakePool memory unstakedStakePool_ = getStakePool(rewardsManager, unstakedStakePoolId_);
    uint256 stkReceiptTokenUnstakeAmount_ =
      bound(_randomUint256(), 1, unstakedStakePool_.stkReceiptToken.balanceOf(actor_));

    // An unstake triggers `claimRewards`, so we need to calculate the rewards to be claimed before the unstake.
    PreviewClaimableRewards memory actorPreviewClaimableRewards_ =
      rewardsManagerHandler.getActorRewardsToBeClaimed(unstakedStakePoolId_, actor_)[0];
    for (uint16 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      actorRewardsToBeClaimed[rewardsManager.rewardPools(rewardPoolId_).asset] +=
        actorPreviewClaimableRewards_.claimableRewardsData[rewardPoolId_].amount;
    }

    vm.prank(actor_);
    rewardsManager.unstake(unstakedStakePoolId_, stkReceiptTokenUnstakeAmount_, receiver_, actor_);

    for (uint8 stakePoolId_; stakePoolId_ < numStakePools; stakePoolId_++) {
      StakePool memory currentStakePool_ = rewardsManager.stakePools(stakePoolId_);
      AssetPool memory currentAssetPool_ = rewardsManager.assetPools(currentStakePool_.asset);

      if (stakePoolId_ == unstakedStakePoolId_) {
        require(
          currentStakePool_.stkReceiptToken.totalSupply()
            == unstakeStakePoolData_[stakePoolId_].stkReceiptTokenTotalSupply - stkReceiptTokenUnstakeAmount_,
          string.concat(
            "Invariant Violated: A stake pool stkReceiptTokens's total supply must decrease by the unstake amount.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.stkReceiptToken.totalSupply(): ",
            Strings.toString(currentStakePool_.stkReceiptToken.totalSupply()),
            ", unstakeStakePoolData_[stakePoolId_].stkReceiptTokenTotalSupply: ",
            Strings.toString(unstakeStakePoolData_[stakePoolId_].stkReceiptTokenTotalSupply),
            ", stkReceiptTokenUnstakeAmount_: ",
            Strings.toString(stkReceiptTokenUnstakeAmount_)
          )
        );
        require(
          currentStakePool_.amount
            == unstakeStakePoolData_[stakePoolId_].stakePoolAmount - stkReceiptTokenUnstakeAmount_,
          string.concat(
            "Invariant Violated: A stake pool's amount must decrease by the unstake amount.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.amount: ",
            Strings.toString(currentStakePool_.amount),
            ", unstakeStakePoolData_[stakePoolId_].stakePoolAmount: ",
            Strings.toString(unstakeStakePoolData_[stakePoolId_].stakePoolAmount),
            ", stkReceiptTokenUnstakeAmount_: ",
            Strings.toString(stkReceiptTokenUnstakeAmount_)
          )
        );
        require(
          currentAssetPool_.amount
            == unstakeStakePoolData_[stakePoolId_].assetPoolAmount - stkReceiptTokenUnstakeAmount_
              - actorRewardsToBeClaimed[currentStakePool_.asset],
          string.concat(
            "Invariant Violated: An asset pool's internal balance must decrease by the unstake amount + claimed rewards from reward pools using the same asset.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentAssetPool_.amount: ",
            Strings.toString(currentAssetPool_.amount),
            ", unstakeStakePoolData_[stakePoolId_].assetPoolAmount: ",
            Strings.toString(unstakeStakePoolData_[stakePoolId_].assetPoolAmount),
            ", stkReceiptTokenUnstakeAmount_: ",
            Strings.toString(stkReceiptTokenUnstakeAmount_)
          )
        );
        require(
          unstakedStakePool_.asset.balanceOf(address(rewardsManager))
            == unstakeStakePoolData_[stakePoolId_].assetAmount - stkReceiptTokenUnstakeAmount_
              - actorRewardsToBeClaimed[currentStakePool_.asset],
          string.concat(
            "Invariant Violated: The rewards manager's balance of the underlying stake asset must decrease by the unstake amount + claimed rewards from reward pools using the same asset.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", unstakedStakePool_.asset.balanceOf(address(rewardsManager)): ",
            Strings.toString(unstakedStakePool_.asset.balanceOf(address(rewardsManager))),
            ", unstakeStakePoolData_[stakePoolId_].assetAmount: ",
            Strings.toString(unstakeStakePoolData_[stakePoolId_].assetAmount),
            ", stkReceiptTokenUnstakeAmount_: ",
            Strings.toString(stkReceiptTokenUnstakeAmount_)
          )
        );
      } else {
        require(
          currentStakePool_.stkReceiptToken.totalSupply()
            == unstakeStakePoolData_[stakePoolId_].stkReceiptTokenTotalSupply,
          string.concat(
            "Invariant Violated: A stake pool stkReceiptTokens's total supply must not change.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.stkReceiptToken.totalSupply(): ",
            Strings.toString(currentStakePool_.stkReceiptToken.totalSupply()),
            ", unstakeStakePoolData_[stakePoolId_].stkReceiptTokenTotalSupply: ",
            Strings.toString(unstakeStakePoolData_[stakePoolId_].stkReceiptTokenTotalSupply),
            ", stkReceiptTokenUnstakeAmount_: ",
            Strings.toString(stkReceiptTokenUnstakeAmount_)
          )
        );
        require(
          currentStakePool_.amount == unstakeStakePoolData_[stakePoolId_].stakePoolAmount,
          string.concat(
            "Invariant Violated: A stake pool's amount must not change.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.amount: ",
            Strings.toString(currentStakePool_.amount),
            ", unstakeStakePoolData_[stakePoolId_].stakePoolAmount: ",
            Strings.toString(unstakeStakePoolData_[stakePoolId_].stakePoolAmount),
            ", stkReceiptTokenUnstakeAmount_: ",
            Strings.toString(stkReceiptTokenUnstakeAmount_)
          )
        );
        require(
          currentAssetPool_.amount
            == unstakeStakePoolData_[stakePoolId_].assetPoolAmount - actorRewardsToBeClaimed[currentStakePool_.asset],
          string.concat(
            "Invariant Violated: An asset pool's internal balance must not increase.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentAssetPool_.amount: ",
            Strings.toString(currentAssetPool_.amount),
            ", unstakeStakePoolData_[stakePoolId_].assetPoolAmount: ",
            Strings.toString(unstakeStakePoolData_[stakePoolId_].assetPoolAmount),
            ", stkReceiptTokenUnstakeAmount_: ",
            Strings.toString(stkReceiptTokenUnstakeAmount_)
          )
        );
        require(
          currentStakePool_.asset.balanceOf(address(rewardsManager))
            == unstakeStakePoolData_[stakePoolId_].assetAmount - actorRewardsToBeClaimed[currentStakePool_.asset],
          string.concat(
            "Invariant Violated: The rewards manager's balance of the underlying stake asset must not increase.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.asset.balanceOf(address(rewardsManager)): ",
            Strings.toString(currentStakePool_.asset.balanceOf(address(rewardsManager))),
            ", unstakeStakePoolData_[stakePoolId_].assetAmount: ",
            Strings.toString(unstakeStakePoolData_[stakePoolId_].assetAmount),
            ", stkReceiptTokenUnstakeAmount_: ",
            Strings.toString(stkReceiptTokenUnstakeAmount_)
          )
        );
      }
    }

    UserRewardsData[] memory userRewards_ = rewardsManager.getUserRewards(unstakedStakePoolId_, actor_);
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
          ", unstakedStakePoolId: ",
          Strings.toString(unstakedStakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );

      require(
        userRewards_[rewardPoolId_].indexSnapshot
          == rewardsManager.claimableRewards(unstakedStakePoolId_, rewardPoolId_).indexSnapshot,
        string.concat(
          "Invariant Violated: The user rewards index snapshot must be equal to the global rewards index snapshot after claimRewards.",
          " userIndexSnapshot: ",
          Strings.toString(userRewards_[rewardPoolId_].indexSnapshot),
          ", globalIndexSnapshot: ",
          Strings.toString(rewardsManager.claimableRewards(unstakedStakePoolId_, rewardPoolId_).indexSnapshot),
          ", actor: ",
          Strings.toHexString(uint160(actor_)),
          ", unstakedStakePoolId: ",
          Strings.toString(unstakedStakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );

      RewardPool memory rewardPool_ = rewardsManager.rewardPools(rewardPoolId_);
      require(
        rewardPool_.asset.balanceOf(receiver_)
          == receiverPreBalances_[rewardPoolId_] + actorRewardsToBeClaimed[rewardPool_.asset]
            + (rewardPool_.asset == unstakedStakePool_.asset ? stkReceiptTokenUnstakeAmount_ : 0),
        string.concat(
          "Invariant Violated: The receiver balance must be the pre-balance plus claimable rewards of that asset plus the unstaked assets if it matches the reward asset.",
          " receiverPostBalance: ",
          Strings.toString(IERC20(rewardsManager.rewardPools(rewardPoolId_).asset).balanceOf(receiver_)),
          ", receiverPreBalance: ",
          Strings.toString(receiverPreBalances_[rewardPoolId_]),
          ", claimableRewards: ",
          Strings.toString(actorRewardsToBeClaimed[rewardPool_.asset]),
          ", receiver: ",
          Strings.toHexString(uint160(receiver_)),
          ", stakePoolId: ",
          Strings.toString(unstakedStakePoolId_),
          ", rewardPoolId: ",
          Strings.toString(rewardPoolId_)
        )
      );
    }
  }

  function invariant_unstakeZeroAmountReverts() public syncCurrentTimestamp(rewardsManagerHandler) {
    vm.expectRevert(ICommonErrors.AmountIsZero.selector);
    rewardsManager.unstake(_randomUint16(), 0, _randomAddress(), _randomAddress());
  }

  function invariant_cannotUnstakeWithInsufficientStkReceiptTokens() public syncCurrentTimestamp(rewardsManagerHandler) {
    address actor_ = rewardsManagerHandler.getActorWithStake(_randomUint256());
    uint16 unstakedStakePoolId_ = rewardsManagerHandler.getStakePoolIdForActorWithStake(_randomUint256(), actor_);
    uint256 stkReceiptTokenUnstakeAmount_ =
      getStakePool(rewardsManager, unstakedStakePoolId_).stkReceiptToken.balanceOf(actor_) + 1;

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(actor_);
    rewardsManager.unstake(unstakedStakePoolId_, stkReceiptTokenUnstakeAmount_, _randomAddress(), actor_);
  }
}

contract UnstakerInvariantsSingleStakePoolSingleRewardPool is
  UnstakerInvariants,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract UnstakerInvariantsMultipleStakePoolsMultipleRewardPools is
  UnstakerInvariants,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
