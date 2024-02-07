// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {StakePool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract AccountingInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  function invariant_internalAssetPoolAmountEqualsERC20BalanceOfRewardsManager()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    uint256 numAssets_ = assets.length;
    for (uint16 assetId_; assetId_ < numAssets_; assetId_++) {
      IERC20 asset = assets[assetId_];
      uint256 internalAssetPoolAmount_ = rewardsManager.assetPools(asset).amount;
      uint256 erc20AssetBalance_ = asset.balanceOf(address(rewardsManager));
      require(
        internalAssetPoolAmount_ == erc20AssetBalance_,
        string.concat(
          "Invariant Violated: The internal asset pool amount for an asset must equal the asset's ERC20 balance of the rewards manager.",
          " internalAssetPoolAmount_: ",
          Strings.toString(internalAssetPoolAmount_),
          ", asset.balanceOf(address(rewardsManager)): ",
          Strings.toString(erc20AssetBalance_)
        )
      );
    }
  }

  mapping(IERC20 => uint256) internal accountingSums;
  mapping(IERC20 => bool) internal ghostRewardsClaimedIncluded;

  function invariant_internalAssetPoolAmountEqualsSumOfInternalAmounts()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    for (uint16 stakePoolId_; stakePoolId_ < numStakePools; stakePoolId_++) {
      StakePool memory stakePool_ = getStakePool(rewardsManager, stakePoolId_);
      accountingSums[stakePool_.asset] += stakePool_.amount;
    }

    for (uint16 rewardPoolId_; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      RewardPool memory rewardPool_ = getRewardPool(rewardsManager, rewardPoolId_);
      accountingSums[rewardPool_.asset] += rewardPool_.undrippedRewards + rewardPool_.cumulativeDrippedRewards;
    }

    for (uint16 rewardPoolId_; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      RewardPool memory rewardPool_ = getRewardPool(rewardsManager, rewardPoolId_);
      if (!ghostRewardsClaimedIncluded[rewardPool_.asset]) {
        accountingSums[rewardPool_.asset] -= rewardsManagerHandler.ghost_rewardsClaimed(IERC20(address(rewardPool_.asset)));
        ghostRewardsClaimedIncluded[rewardPool_.asset] = true;
      }
    }

    uint256 numAssets_ = assets.length;
    for (uint16 assetId_; assetId_ < numAssets_; assetId_++) {
      IERC20 asset = assets[assetId_];
      require(
        rewardsManager.assetPools(asset).amount == accountingSums[asset],
        string.concat(
          "Invariant Violated: The internal asset pool amount for an asset must equal the sum of the internal pool amounts.",
          " rewardsManager.assetPools(IERC20(address(asset))).amount): ",
          Strings.toString(rewardsManager.assetPools(IERC20(address(asset))).amount),
          ", accountingSums[asset]: ",
          Strings.toString(accountingSums[asset]),
          ", asset.balanceOf(address(rewardsManager)): ",
          Strings.toString(asset.balanceOf(address(rewardsManager))),
          ", rewardsManagerHandler.ghost_rewardsClaimed(asset): ",
          Strings.toString(rewardsManagerHandler.ghost_rewardsClaimed(asset))
        )
      );
    }
  }
}

contract AccountingInvariantsSingleStakePoolSingleRewardPool is
  AccountingInvariants,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract AccountingInvariantsMultipleStakePoolsMultipleRewardPools is
  AccountingInvariants,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
