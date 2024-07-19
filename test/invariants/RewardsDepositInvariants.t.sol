// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {RewardsManagerState} from "../../src/lib/RewardsManagerStates.sol";
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

  function invariant_rewardsDepositInternalBalancesIncreaseOnRewardsDeposit()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    InternalBalances[] memory internalBalancesBeforeDepositRewards_ = new InternalBalances[](numRewardPools);
    for (uint16 rewardPoolId_; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      RewardPool memory rewardPool_ = rewardsManager.rewardPools(rewardPoolId_);

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

  function invariant_cannotRewardsDepositWithInsufficientAssets() public syncCurrentTimestamp(rewardsManagerHandler) {
    uint16 rewardPoolId_ = rewardsManagerHandler.pickValidRewardPoolId(_randomUint256());
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
