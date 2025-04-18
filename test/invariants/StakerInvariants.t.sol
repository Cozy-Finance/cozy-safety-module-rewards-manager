// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ICommonErrors} from "cozy-safety-module-libs/interfaces/ICommonErrors.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-libs/interfaces/IReceiptToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, StakePool} from "../../src/lib/structs/Pools.sol";
import {IDepositorErrors} from "../../src/interfaces/IDepositorErrors.sol";
import {RewardsManagerState} from "../../src/lib/RewardsManagerStates.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract StakerInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  struct InternalBalances {
    uint256 assetPoolAmount;
    uint256 stakePoolAmount;
    uint256 assetAmount;
    uint256 totalSupply;
  }

  function invariant_stakerReceiptTokenTotalSupplyAndInternalBalancesIncreaseOnStake()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    InternalBalances[] memory internalBalancesBeforeStake_ = new InternalBalances[](numStakePools);
    for (uint16 stakePoolId_; stakePoolId_ < numStakePools; stakePoolId_++) {
      StakePool memory stakePool_ = rewardsManager.stakePools(stakePoolId_);

      internalBalancesBeforeStake_[stakePoolId_] = InternalBalances({
        assetPoolAmount: rewardsManager.assetPools(stakePool_.asset).amount,
        stakePoolAmount: stakePool_.amount,
        assetAmount: stakePool_.asset.balanceOf(address(rewardsManager)),
        totalSupply: stakePool_.stkReceiptToken.totalSupply()
      });
    }

    rewardsManagerHandler.stakeWithoutTransferWithExistingActorWithoutCountingCall(_randomUint256());

    // rewardsManagerHandler.currentStakePoolId is set to the reserve pool that was just deposited into during
    // this invariant test.
    uint16 stakedPoolId_ = rewardsManagerHandler.currentStakePoolId();
    IERC20 stakedPoolAsset_ = rewardsManager.stakePools(stakedPoolId_).asset;

    for (uint16 stakePoolId_; stakePoolId_ < numStakePools; stakePoolId_++) {
      StakePool memory currentStakePool_ = rewardsManager.stakePools(stakePoolId_);
      AssetPool memory currentAssetPool_ = rewardsManager.assetPools(currentStakePool_.asset);

      if (stakePoolId_ == stakedPoolId_) {
        require(
          currentStakePool_.stkReceiptToken.totalSupply() > internalBalancesBeforeStake_[stakePoolId_].totalSupply,
          string.concat(
            "Invariant Violated: A stake pool's stake receipt token total supply must increase when a stake occurs.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.stkReceiptToken.totalSupply(): ",
            Strings.toString(currentStakePool_.stkReceiptToken.totalSupply()),
            ", internalBalancesBeforeStake_[stakePoolId_].totalSupply: ",
            Strings.toString(internalBalancesBeforeStake_[stakePoolId_].totalSupply)
          )
        );
        require(
          currentAssetPool_.amount > internalBalancesBeforeStake_[stakePoolId_].assetPoolAmount,
          string.concat(
            "Invariant Violated: An asset pool's internal balance must increase when a stake occurs into a stake pool using the asset.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentAssetPool_.amount: ",
            Strings.toString(currentAssetPool_.amount),
            ", internalBalancesBeforeStake_[stakePoolId_].assetPoolAmount: ",
            Strings.toString(internalBalancesBeforeStake_[stakePoolId_].assetPoolAmount)
          )
        );
        require(
          currentStakePool_.amount > internalBalancesBeforeStake_[stakePoolId_].stakePoolAmount,
          string.concat(
            "Invariant Violated: A stake pool's internally tracked amount must increase when a stake occurs.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.amount: ",
            Strings.toString(currentStakePool_.amount),
            ", internalBalancesBeforeStake_[stakePoolId_].stakePoolAmount: ",
            Strings.toString(internalBalancesBeforeStake_[stakePoolId_].stakePoolAmount)
          )
        );
        require(
          currentStakePool_.asset.balanceOf(address(rewardsManager))
            > internalBalancesBeforeStake_[stakePoolId_].assetAmount,
          string.concat(
            "Invariant Violated: The rewards manager's balance of the stake pool asset must increase when a stake occurs.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.asset.balanceOf(address(rewardsManager)): ",
            Strings.toString(currentStakePool_.asset.balanceOf(address(rewardsManager))),
            ", internalBalancesBeforeStake_[stakePoolId_].assetAmount: ",
            Strings.toString(internalBalancesBeforeStake_[stakePoolId_].assetAmount)
          )
        );
      } else {
        require(
          currentStakePool_.stkReceiptToken.totalSupply() == internalBalancesBeforeStake_[stakePoolId_].totalSupply,
          string.concat(
            "Invariant Violated: A stake pool's receipt token total supply must not change when a stake occurs in another stake pool.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.stkReceiptToken.totalSupply(): ",
            Strings.toString(currentStakePool_.stkReceiptToken.totalSupply()),
            ", internalBalancesBeforeStake_[stakePoolId_].totalSupply: ",
            Strings.toString(internalBalancesBeforeStake_[stakePoolId_].totalSupply)
          )
        );
        require(
          currentStakePool_.amount == internalBalancesBeforeStake_[stakePoolId_].stakePoolAmount,
          string.concat(
            "Invariant Violated: A stake pool's internally tracked amount must not change when a stake occurs in another stake pool.",
            " stakePoolId_: ",
            Strings.toString(stakePoolId_),
            ", currentStakePool_.amount: ",
            Strings.toString(currentStakePool_.amount),
            ", internalBalancesBeforeStake_[stakePoolId_].stakePoolAmount: ",
            Strings.toString(internalBalancesBeforeStake_[stakePoolId_].stakePoolAmount)
          )
        );
        if (currentStakePool_.asset != stakedPoolAsset_) {
          require(
            currentAssetPool_.amount == internalBalancesBeforeStake_[stakePoolId_].assetPoolAmount,
            string.concat(
              "Invariant Violated: An asset pool's internal balance must not change when a stake occurs in a stake pool with a different underlying asset.",
              " stakePoolId_: ",
              Strings.toString(stakePoolId_),
              ", currentAssetPool_.amount: ",
              Strings.toString(currentAssetPool_.amount),
              ", internalBalancesBeforeStake_[stakePoolId_].assetPoolAmount: ",
              Strings.toString(internalBalancesBeforeStake_[stakePoolId_].assetPoolAmount)
            )
          );
          require(
            currentStakePool_.asset.balanceOf(address(rewardsManager))
              == internalBalancesBeforeStake_[stakePoolId_].assetAmount,
            string.concat(
              "Invariant Violated: The reward manager's asset balance for a specific asset must not change when a stake occurs in a stake pool with a different underlying asset.",
              " stakePoolId_: ",
              Strings.toString(stakePoolId_),
              ", currentStakePool_.asset.balanceOf(address(rewardsManager)): ",
              Strings.toString(currentStakePool_.asset.balanceOf(address(rewardsManager))),
              ", internalBalancesBeforeStake_[stakePoolId_].assetAmount: ",
              Strings.toString(internalBalancesBeforeStake_[stakePoolId_].assetAmount)
            )
          );
        }
      }
    }
  }

  function invariant_cannotStakeZeroAssets() public syncCurrentTimestamp(rewardsManagerHandler) {
    uint16 stakePoolId_ = rewardsManagerHandler.pickValidStakePoolId(_randomUint256());
    address actor_ = rewardsManagerHandler.pickActor(_randomUint256());

    vm.prank(actor_);
    vm.expectRevert(ICommonErrors.AmountIsZero.selector);
    rewardsManager.stakeWithoutTransfer(stakePoolId_, 0, actor_);
  }

  function invariant_cannotStakeWithInsufficientAssets() public syncCurrentTimestamp(rewardsManagerHandler) {
    uint16 stakePoolId_ = rewardsManagerHandler.pickValidStakePoolId(_randomUint256());
    address actor_ = rewardsManagerHandler.pickActor(_randomUint256());
    uint256 assetAmount_ = rewardsManagerHandler.boundDepositAssetAmount(_randomUint256());

    vm.prank(actor_);
    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    rewardsManager.stakeWithoutTransfer(stakePoolId_, assetAmount_, actor_);
  }
}

contract StakerInvariantsSingleReservePool is StakerInvariants, InvariantTestWithSingleStakePoolAndSingleRewardPool {}

contract StakerInvariantsMultipleReservePools is
  StakerInvariants,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
