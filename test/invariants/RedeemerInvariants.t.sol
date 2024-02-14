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
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract RedeemerInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  using FixedPointMathLib for uint256;

  struct RedeemRewardPoolData {
    uint256 undrippedRewards;
    uint256 cumulativeDrippedRewards;
    uint256 assetPoolAmount;
    uint256 assetAmount;
    uint256 depositReceiptTokenTotalSupply;
    uint256 lastDripTime;
  }

  function invariant_redeemUndrippedRewards() public syncCurrentTimestamp(rewardsManagerHandler) {
    RedeemRewardPoolData[] memory redeemRewardPoolData_ = new RedeemRewardPoolData[](numRewardPools);
    for (uint8 rewardPoolId_; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      RewardPool memory rewardPool_ = rewardsManager.rewardPools(rewardPoolId_);
      redeemRewardPoolData_[rewardPoolId_] = RedeemRewardPoolData({
        undrippedRewards: rewardPool_.undrippedRewards,
        cumulativeDrippedRewards: rewardPool_.cumulativeDrippedRewards,
        assetPoolAmount: rewardsManager.assetPools(rewardPool_.asset).amount,
        assetAmount: rewardPool_.asset.balanceOf(address(rewardsManager)),
        depositReceiptTokenTotalSupply: rewardPool_.depositReceiptToken.totalSupply(),
        lastDripTime: rewardPool_.lastDripTime
      });
    }

    address receiver_ = _randomAddress();
    address actor_ = rewardsManagerHandler.getActorWithRewardDeposits(_randomUint256());
    // The default address is used when there are no actors with reward deposits, in which case we just skip this
    // invariant.
    if (actor_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;
    uint16 redeemedRewardPoolId_ =
      rewardsManagerHandler.getRewardPoolIdForActorWithRewardDeposits(_randomUint256(), actor_);
    RewardPool memory redeemedRewardPool_ = rewardsManager.rewardPools(redeemedRewardPoolId_);
    uint256 receiverPreBalance_ = redeemedRewardPool_.asset.balanceOf(receiver_);
    uint256 actorDepositReceiptTokenPreBalance_ = redeemedRewardPool_.depositReceiptToken.balanceOf(actor_);
    uint256 depositReceiptTokenRedeemAmount_ = bound(_randomUint256(), 1, actorDepositReceiptTokenPreBalance_);
    vm.prank(actor_);
    redeemedRewardPool_.depositReceiptToken.approve(address(rewardsManager), depositReceiptTokenRedeemAmount_);

    uint256 rewardAssetAmount_ =
      rewardsManager.previewUndrippedRewardsRedemption(redeemedRewardPoolId_, depositReceiptTokenRedeemAmount_);

    if (rewardAssetAmount_ == 0) {
      vm.expectRevert(ICommonErrors.RoundsToZero.selector);
      vm.prank(actor_);
      rewardsManager.redeemUndrippedRewards(redeemedRewardPoolId_, depositReceiptTokenRedeemAmount_, receiver_, actor_);
    } else {
      vm.prank(actor_);
      rewardsManager.redeemUndrippedRewards(redeemedRewardPoolId_, depositReceiptTokenRedeemAmount_, receiver_, actor_);

      for (uint8 rewardPoolId_; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
        RewardPool memory currentRewardPool_ = rewardsManager.rewardPools(rewardPoolId_);
        AssetPool memory currentAssetPool_ = rewardsManager.assetPools(currentRewardPool_.asset);

        if (rewardPoolId_ == redeemedRewardPoolId_) {
          require(
            currentRewardPool_.depositReceiptToken.totalSupply()
              == redeemRewardPoolData_[rewardPoolId_].depositReceiptTokenTotalSupply - depositReceiptTokenRedeemAmount_,
            string.concat(
              "Invariant Violated: A reward pool's deposit receipt token's total supply must decrease by the redeem amount.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.depositReceiptToken.totalSupply(): ",
              Strings.toString(currentRewardPool_.depositReceiptToken.totalSupply()),
              ", redeemRewardPoolData_[rewardPoolId_].depositReceiptTokenTotalSupply: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].depositReceiptTokenTotalSupply),
              ", depositReceiptTokenRedeemAmount_: ",
              Strings.toString(depositReceiptTokenRedeemAmount_)
            )
          );
          require(
            currentRewardPool_.depositReceiptToken.balanceOf(actor_)
              == actorDepositReceiptTokenPreBalance_ - depositReceiptTokenRedeemAmount_,
            string.concat(
              "Invariant Violated: A reward pool's actor's deposit receipt token balance must decrease by the redeem amount.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.depositReceiptToken.balanceOf(actor_): ",
              Strings.toString(currentRewardPool_.depositReceiptToken.balanceOf(actor_)),
              ", actorDepositReceiptTokenPreBalance_: ",
              Strings.toString(actorDepositReceiptTokenPreBalance_),
              ", depositReceiptTokenRedeemAmount_: ",
              Strings.toString(depositReceiptTokenRedeemAmount_)
            )
          );
          require(
            currentRewardPool_.undrippedRewards
              <= redeemRewardPoolData_[rewardPoolId_].undrippedRewards - rewardAssetAmount_,
            string.concat(
              "Invariant Violated: A reward pool's undripped rewards must decrease by at least the redeemed reward asset amount.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.undrippedRewards: ",
              Strings.toString(currentRewardPool_.undrippedRewards),
              ", redeemRewardPoolData_[rewardPoolId_].undrippedRewards: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].undrippedRewards),
              ", rewardAssetAmount_: ",
              Strings.toString(rewardAssetAmount_)
            )
          );
          require(
            currentRewardPool_.cumulativeDrippedRewards >= redeemRewardPoolData_[rewardPoolId_].cumulativeDrippedRewards,
            string.concat(
              "Invariant Violated: A reward pool's cumulative dripped rewards must increase.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.cumulativeDrippedRewards: ",
              Strings.toString(currentRewardPool_.cumulativeDrippedRewards),
              ", redeemRewardPoolData_[rewardPoolId_].cumulativeDrippedRewards: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].cumulativeDrippedRewards)
            )
          );
          require(
            currentRewardPool_.lastDripTime >= redeemRewardPoolData_[rewardPoolId_].lastDripTime,
            string.concat(
              "Invariant Violated: A reward pool's last drip time must increase.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.lastDripTime: ",
              Strings.toString(currentRewardPool_.lastDripTime),
              ", redeemRewardPoolData_[rewardPoolId_].lastDripTime: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].lastDripTime)
            )
          );
          require(
            currentAssetPool_.amount == redeemRewardPoolData_[rewardPoolId_].assetPoolAmount - rewardAssetAmount_,
            string.concat(
              "Invariant Violated: A reward pool's asset pool amount must decrease by the redeemed reward asset amount.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentAssetPool_.amount: ",
              Strings.toString(currentAssetPool_.amount),
              ", redeemRewardPoolData_[rewardPoolId_].assetPoolAmount: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].assetPoolAmount),
              ", rewardAssetAmount_: ",
              Strings.toString(rewardAssetAmount_)
            )
          );
          require(
            currentRewardPool_.asset.balanceOf(address(rewardsManager))
              == redeemRewardPoolData_[rewardPoolId_].assetAmount - rewardAssetAmount_,
            string.concat(
              "Invariant Violated: A reward pool's asset balance must decrease by the redeemed reward asset amount.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.asset.balanceOf(address(rewardsManager)): ",
              Strings.toString(currentRewardPool_.asset.balanceOf(address(rewardsManager))),
              ", redeemRewardPoolData_[rewardPoolId_].assetAmount: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].assetAmount)
            )
          );
        } else {
          require(
            currentRewardPool_.undrippedRewards == redeemRewardPoolData_[rewardPoolId_].undrippedRewards,
            string.concat(
              "Invariant Violated: A reward pool's undripped rewards must remain unchanged.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.undrippedRewards: ",
              Strings.toString(currentRewardPool_.undrippedRewards),
              ", redeemRewardPoolData_[rewardPoolId_].undrippedRewards: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].undrippedRewards)
            )
          );
          require(
            currentRewardPool_.cumulativeDrippedRewards == redeemRewardPoolData_[rewardPoolId_].cumulativeDrippedRewards,
            string.concat(
              "Invariant Violated: A reward pool's cumulative dripped rewards must remain unchanged.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.cumulativeDrippedRewards: ",
              Strings.toString(currentRewardPool_.cumulativeDrippedRewards),
              ", redeemRewardPoolData_[rewardPoolId_].cumulativeDrippedRewards: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].cumulativeDrippedRewards)
            )
          );
          require(
            currentRewardPool_.lastDripTime == redeemRewardPoolData_[rewardPoolId_].lastDripTime,
            string.concat(
              "Invariant Violated: A reward pool's last drip time must remain unchanged.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.lastDripTime: ",
              Strings.toString(currentRewardPool_.lastDripTime),
              ", redeemRewardPoolData_[rewardPoolId_].lastDripTime: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].lastDripTime)
            )
          );
          require(
            currentAssetPool_.amount
              == redeemRewardPoolData_[rewardPoolId_].assetPoolAmount
                - (currentRewardPool_.asset == redeemedRewardPool_.asset ? rewardAssetAmount_ : 0),
            string.concat(
              "Invariant Violated: A reward pool's asset pool amount must remain unchanged unless it is the same asset as the redeemed reward pool asset.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentAssetPool_.amount: ",
              Strings.toString(currentAssetPool_.amount),
              ", redeemRewardPoolData_[rewardPoolId_].assetPoolAmount: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].assetPoolAmount)
            )
          );
          require(
            currentRewardPool_.asset.balanceOf(address(rewardsManager))
              == redeemRewardPoolData_[rewardPoolId_].assetAmount
                - (currentRewardPool_.asset == redeemedRewardPool_.asset ? rewardAssetAmount_ : 0),
            string.concat(
              "Invariant Violated: A reward pool's asset balance must remain unchanged unless it is the same asset as the redeemed reward pool asset.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.asset.balanceOf(address(rewardsManager)): ",
              Strings.toString(currentRewardPool_.asset.balanceOf(address(rewardsManager))),
              ", redeemRewardPoolData_[rewardPoolId_].assetAmount: ",
              Strings.toString(redeemRewardPoolData_[rewardPoolId_].assetAmount)
            )
          );
        }
      }
    }

    uint256 receiverPostBalance_ = redeemedRewardPool_.asset.balanceOf(receiver_);
    require(
      receiverPostBalance_ - receiverPreBalance_ == rewardAssetAmount_,
      string.concat(
        "Invariant Violated: The receiver's balance must increase by the redeemed reward asset amount.",
        " receiverPostBalance_: ",
        Strings.toString(receiverPostBalance_),
        ", receiverPreBalance_: ",
        Strings.toString(receiverPreBalance_),
        ", rewardAssetAmount_: ",
        Strings.toString(rewardAssetAmount_)
      )
    );
  }

  function invariant_redeemZeroAmountReverts() public syncCurrentTimestamp(rewardsManagerHandler) {
    address actor_ = rewardsManagerHandler.getActorWithRewardDeposits(_randomUint256());
    uint16 redeemedRewardPoolId_ =
      rewardsManagerHandler.getRewardPoolIdForActorWithRewardDeposits(_randomUint256(), actor_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(actor_);
    rewardsManager.redeemUndrippedRewards(redeemedRewardPoolId_, 0, _randomAddress(), actor_);
  }

  function invariant_previewMatchesRedeem() public syncCurrentTimestamp(rewardsManagerHandler) {
    address actor_ = rewardsManagerHandler.getActorWithRewardDeposits(_randomUint256());
    if (actor_ == rewardsManagerHandler.DEFAULT_ADDRESS()) return;
    uint16 redeemedRewardPoolId_ =
      rewardsManagerHandler.getRewardPoolIdForActorWithRewardDeposits(_randomUint256(), actor_);
    RewardPool memory redeemedRewardPool_ = rewardsManager.rewardPools(redeemedRewardPoolId_);
    uint256 depositReceiptTokenRedeemAmount_ =
      bound(_randomUint256(), 1, redeemedRewardPool_.depositReceiptToken.balanceOf(actor_));

    vm.prank(actor_);
    redeemedRewardPool_.depositReceiptToken.approve(address(rewardsManager), depositReceiptTokenRedeemAmount_);

    uint256 previewedRewardAssetAmount_ =
      rewardsManager.previewUndrippedRewardsRedemption(redeemedRewardPoolId_, depositReceiptTokenRedeemAmount_);

    if (previewedRewardAssetAmount_ == 0) {
      vm.expectRevert(ICommonErrors.RoundsToZero.selector);
      vm.prank(actor_);
      rewardsManager.redeemUndrippedRewards(
        redeemedRewardPoolId_, depositReceiptTokenRedeemAmount_, _randomAddress(), actor_
      );
    } else {
      vm.prank(actor_);
      uint256 redeemedRewardAssetAmount_ = rewardsManager.redeemUndrippedRewards(
        redeemedRewardPoolId_, depositReceiptTokenRedeemAmount_, _randomAddress(), actor_
      );
      require(
        previewedRewardAssetAmount_ == redeemedRewardAssetAmount_,
        string.concat(
          "Invariant Violated: The previewed reward asset amount must match the redeemed reward asset amount.",
          " previewedRewardAssetAmount_: ",
          Strings.toString(previewedRewardAssetAmount_),
          ", redeemedRewardAssetAmount_: ",
          Strings.toString(redeemedRewardAssetAmount_)
        )
      );
    }
  }
}

contract RedeemerInvariantsWithStateTransitionsSingleStakePoolSingleRewardPool is
  RedeemerInvariantsWithStateTransitions,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract RedeemerInvariantsWithStateTransitionsMultipleStakePoolsMultipleRewardPools is
  RedeemerInvariantsWithStateTransitions,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
