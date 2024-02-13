// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {StakePool, RewardPool, AssetPool} from "../../src/lib/structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData, PreviewClaimableRewards} from "../../src/lib/structs/Rewards.sol";
import {ICommonErrors} from "../../src/interfaces/ICommonErrors.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract RedeemerInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  struct RedeemRewardPoolData {
    uint256 undrippedRewards;
    uint256 cumulativeDrippedRewards;
    uint256 assetPoolAmount;
    uint256 assetAmount;
    uint256 depositReceiptTokenTotalSupply;
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
        depositReceiptTokenTotalSupply: rewardPool_.depositReceiptToken.totalSupply()
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
    uint256 depositReceiptTokenRedeemAmount_ =
      bound(_randomUint256(), 1, redeemedRewardPool_.depositReceiptToken.balanceOf(actor_));
    uint256 receiverPreBalance_ = redeemedRewardPool_.asset.balanceOf(receiver_);

    vm.startPrank(actor_);
    redeemedRewardPool_.depositReceiptToken.approve(address(rewardsManager), depositReceiptTokenRedeemAmount_);
    rewardsManager.redeemUndrippedRewards(redeemedRewardPoolId_, depositReceiptTokenRedeemAmount_, receiver_, actor_);
    vm.stopPrank();

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
      }
    }
  }

  function invariant_redeemZeroAmountReverts() public syncCurrentTimestamp(rewardsManagerHandler) {
    address actor_ = rewardsManagerHandler.getActorWithRewardDeposits(_randomUint256());
    uint16 redeemedRewardPoolId_ =
      rewardsManagerHandler.getRewardPoolIdForActorWithRewardDeposits(_randomUint256(), actor_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(actor_);
    rewardsManager.redeemUndrippedRewards(redeemedRewardPoolId_, 0, _randomAddress(), actor_);
  }
}

contract RedeemerInvariantsSingleStakePoolSingleRewardPool is
  RedeemerInvariants,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract RedeemerInvariantsMultipleStakePoolsMultipleRewardPools is
  RedeemerInvariants,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
