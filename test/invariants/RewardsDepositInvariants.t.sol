// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {RewardsManagerState} from "../../src/lib/RewardsManagerStates.sol";
import {ICommonErrors} from "../../src/interfaces/ICommonErrors.sol";
import {IDepositorErrors} from "../../src/interfaces/IDepositorErrors.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract RewardsDepositInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  struct InternalBalances {
    uint256 assetPoolAmount;
    uint256 rewardPoolAmount;
    uint256 assetAmount;
  }

  function invariant_rewardsDepositReceiptTokenTotalSupplyAndInternalBalancesIncreaseOnRewardsDeposit()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    // Can't deposit if the rewards manager is paused.
    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) return;

    uint256[] memory totalSupplyBeforeDepositRewards_ = new uint256[](numRewardPools);
    InternalBalances[] memory internalBalancesBeforeDepositRewards_ = new InternalBalances[](numRewardPools);
    for (uint8 rewardPoolId_; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      RewardPool memory rewardPool_ = rewardsManager.rewardPools(rewardPoolId_);

      totalSupplyBeforeDepositRewards_[rewardPoolId_] = rewardPool_.depositReceiptToken.totalSupply();
      internalBalancesBeforeDepositRewards_[rewardPoolId_] = InternalBalances({
        assetPoolAmount: rewardsManager.assetPools(rewardPool_.asset).amount,
        rewardPoolAmount: rewardPool_.undrippedRewards,
        assetAmount: rewardPool_.asset.balanceOf(address(rewardsManager))
      });
    }

    rewardsManagerHandler.depositRewardAssetsWithExistingActorWithoutCountingCall(_randomUint256());

    // rewardsManagerHandler.currentRewardPoolId is set to the reserve pool that was just deposited into during
    // this invariant test.
    uint16 depositedRewardPoolId_ = rewardsManagerHandler.currentRewardPoolId();
    IERC20 depositRewardPoolAsset_ = getRewardPool(rewardsManager, depositedRewardPoolId_).asset;

    for (uint16 rewardPoolId_; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      RewardPool memory currentRewardPool_ = getRewardPool(rewardsManager, rewardPoolId_);
      AssetPool memory currentAssetPool_ = rewardsManager.assetPools(currentRewardPool_.asset);

      if (rewardPoolId_ == depositedRewardPoolId_) {
        require(
          currentRewardPool_.depositReceiptToken.totalSupply() > totalSupplyBeforeDepositRewards_[rewardPoolId_],
          string.concat(
            "Invariant Violated: A reward pool's deposit receipt token total supply must increase when a deposit occurs.",
            " rewardPoolId_: ",
            Strings.toString(rewardPoolId_),
            ", currentRewardPool_.depositReceiptToken.totalSupply(): ",
            Strings.toString(currentRewardPool_.depositReceiptToken.totalSupply()),
            ", totalSupplyBeforeDepositRewards_[rewardPoolId_]: ",
            Strings.toString(totalSupplyBeforeDepositRewards_[rewardPoolId_])
          )
        );
        require(
          currentAssetPool_.amount > internalBalancesBeforeDepositRewards_[rewardPoolId_].assetPoolAmount,
          string.concat(
            "Invariant Violated: An asset pool's internal balance must increase when a deposit occurs into a reward pool using the asset.",
            " rewardPoolId_: ",
            Strings.toString(rewardPoolId_),
            ", currentAssetPool_.amount: ",
            Strings.toString(currentAssetPool_.amount),
            ", internalBalancesBeforeDepositRewards_[rewardPoolId_].assetPoolAmount: ",
            Strings.toString(internalBalancesBeforeDepositRewards_[rewardPoolId_].assetPoolAmount)
          )
        );
        require(
          currentRewardPool_.undrippedRewards > internalBalancesBeforeDepositRewards_[rewardPoolId_].rewardPoolAmount,
          string.concat(
            "Invariant Violated: A reward pool's undripped rewards amount must increase when a deposit occurs.",
            " rewardPoolId_: ",
            Strings.toString(rewardPoolId_),
            ", currentRewardPool_.undrippedRewards: ",
            Strings.toString(currentRewardPool_.undrippedRewards),
            ", internalBalancesBeforeDepositRewards_[rewardPoolId_].rewardPoolAmount: ",
            Strings.toString(internalBalancesBeforeDepositRewards_[rewardPoolId_].rewardPoolAmount)
          )
        );
        require(
          currentRewardPool_.asset.balanceOf(address(rewardsManager))
            > internalBalancesBeforeDepositRewards_[rewardPoolId_].assetAmount,
          string.concat(
            "Invariant Violated: The rewards manager's balance of the reward pool asset must increase when a deposit occurs.",
            " rewardPoolId_: ",
            Strings.toString(rewardPoolId_),
            ", currentRewardPool_.asset.balanceOf(address(rewardsManager)): ",
            Strings.toString(currentRewardPool_.asset.balanceOf(address(rewardsManager))),
            ", internalBalancesBeforeDepositRewards_[rewardPoolId_].assetAmount: ",
            Strings.toString(internalBalancesBeforeDepositRewards_[rewardPoolId_].assetAmount)
          )
        );
      } else {
        require(
          currentRewardPool_.depositReceiptToken.totalSupply() == totalSupplyBeforeDepositRewards_[rewardPoolId_],
          string.concat(
            "Invariant Violated: A reward pool's receipt token total supply must not change when a deposit occurs in another reward pool.",
            " rewardPoolId_: ",
            Strings.toString(rewardPoolId_),
            ", currentRewardPool_.depositReceiptToken.totalSupply(): ",
            Strings.toString(currentRewardPool_.depositReceiptToken.totalSupply()),
            ", totalSupplyBeforeDepositRewards_[rewardPoolId_]: ",
            Strings.toString(totalSupplyBeforeDepositRewards_[rewardPoolId_])
          )
        );
        require(
          currentRewardPool_.undrippedRewards == internalBalancesBeforeDepositRewards_[rewardPoolId_].rewardPoolAmount,
          string.concat(
            "Invariant Violated: A reserve pool's undripped rewards amount must not change when a deposit occurs in another reward pool.",
            " rewardPoolId_: ",
            Strings.toString(rewardPoolId_),
            ", currentRewardPool_.undrippedRewards: ",
            Strings.toString(currentRewardPool_.undrippedRewards),
            ", internalBalancesBeforeDepositRewards_[rewardPoolId_].rewardPoolAmount: ",
            Strings.toString(internalBalancesBeforeDepositRewards_[rewardPoolId_].rewardPoolAmount)
          )
        );
        if (currentRewardPool_.asset != depositRewardPoolAsset_) {
          require(
            currentAssetPool_.amount == internalBalancesBeforeDepositRewards_[rewardPoolId_].assetPoolAmount,
            string.concat(
              "Invariant Violated: An asset pool's internal balance must not change when a deposit occurs in a reward pool with a different underlying asset.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentAssetPool_.amount: ",
              Strings.toString(currentAssetPool_.amount),
              ", internalBalancesBeforeDepositRewards_[rewardPoolId_].assetPoolAmount: ",
              Strings.toString(internalBalancesBeforeDepositRewards_[rewardPoolId_].assetPoolAmount)
            )
          );
          require(
            currentRewardPool_.asset.balanceOf(address(rewardsManager))
              == internalBalancesBeforeDepositRewards_[rewardPoolId_].assetAmount,
            string.concat(
              "Invariant Violated: The reward manager's asset balance for a specific asset must not change when a deposit occurs in a reward pool with a different underlying asset.",
              " rewardPoolId_: ",
              Strings.toString(rewardPoolId_),
              ", currentRewardPool_.asset.balanceOf(address(rewardsManager)): ",
              Strings.toString(currentRewardPool_.asset.balanceOf(address(rewardsManager))),
              ", internalBalancesBeforeDepositRewards_[rewardPoolId_].assetAmount: ",
              Strings.toString(internalBalancesBeforeDepositRewards_[rewardPoolId_].assetAmount)
            )
          );
        }
      }
    }
  }

  function invariant_rewardsDepositMintsReceiptTokensMatchesPreview() public syncCurrentTimestamp(rewardsManagerHandler) {
    // Can't deposit if the rewards manager is paused.
    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) return;

    uint256 assetAmount_ = rewardsManagerHandler.boundDepositAssetAmount(_randomUint256());
    uint8 rewardPoolId_ = rewardsManagerHandler.pickValidRewardPoolId(_randomUint256());
    address actor_ = rewardsManagerHandler.pickActor(_randomUint256());
    uint256 expectedReceiptTokenAmount_ =
      rewardsManager.convertRewardAssetToReceiptTokenAmount(rewardPoolId_, assetAmount_);

    IReceiptToken depositReceiptToken_ = rewardsManager.rewardPools(rewardPoolId_).depositReceiptToken;
    uint256 actorReceiptTokenBalBeforeDeposit_ = depositReceiptToken_.balanceOf(actor_);
    rewardsManagerHandler.depositRewardAssetsWithExistingActorWithoutCountingCall(rewardPoolId_, assetAmount_, actor_);
    uint256 receivedReceiptTokenAmount_ = depositReceiptToken_.balanceOf(actor_) - actorReceiptTokenBalBeforeDeposit_;

    require(
      receivedReceiptTokenAmount_ == expectedReceiptTokenAmount_,
      string.concat(
        "Invariant Violated: The amount of receipt tokens received from a deposit must be 1:1 with the asset amount deposited.",
        " assetAmount_: ",
        Strings.toString(assetAmount_),
        ", expectedReceiptTokenAmount_: ",
        Strings.toString(expectedReceiptTokenAmount_),
        ", receivedReceiptTokenAmount_: ",
        Strings.toString(receivedReceiptTokenAmount_),
        ", actorReceiptTokenBalBeforeDeposit_",
        Strings.toString(actorReceiptTokenBalBeforeDeposit_),
        ", depositReceiptToken_.balanceOf(actor_)",
        Strings.toString(depositReceiptToken_.balanceOf(actor_))
      )
    );
  }

  function invariant_cannotRewardsDepositZeroAssets() public syncCurrentTimestamp(rewardsManagerHandler) {
    // Can't deposit if the rewards manager is paused.
    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) return;

    uint8 rewardPoolId_ = rewardsManagerHandler.pickValidRewardPoolId(_randomUint256());
    address actor_ = rewardsManagerHandler.pickActor(_randomUint256());

    vm.prank(actor_);
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    rewardsManager.depositRewardAssetsWithoutTransfer(rewardPoolId_, 0, actor_);
  }

  function invariant_cannotRewardsDepositWithInsufficientAssets() public syncCurrentTimestamp(rewardsManagerHandler) {
    // Can't deposit if the rewards manager is paused.
    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) return;

    uint8 rewardPoolId_ = rewardsManagerHandler.pickValidRewardPoolId(_randomUint256());
    address actor_ = rewardsManagerHandler.pickActor(_randomUint256());
    uint256 assetAmount_ = rewardsManagerHandler.boundDepositAssetAmount(_randomUint256());

    vm.prank(actor_);
    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    rewardsManager.depositRewardAssetsWithoutTransfer(rewardPoolId_, assetAmount_, actor_);
  }
}

contract RewardsDepositInvariantsSingleReservePool is
  RewardsDepositInvariants,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract RewardsDepositInvariantsMultipleReservePools is
  RewardsDepositInvariants,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
