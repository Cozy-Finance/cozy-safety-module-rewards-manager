// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {StakePool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {StakePoolConfig, RewardPoolConfig} from "../../src/lib/structs/Configs.sol";
import {ClaimableRewardsData} from "../../src/lib/structs/Rewards.sol";
import {ICozyManager} from "../../src/interfaces/ICozyManager.sol";
import {IConfiguratorErrors} from "../../src/interfaces/IConfiguratorErrors.sol";
import {
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";
import {MockDripModel} from "../utils/MockDripModel.sol";

abstract contract ConfiguratorInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  function invariant_updateConfigsUpdatesConfigs() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory updatedStakePoolConfigs_, RewardPoolConfig[] memory updatedRewardPoolConfigs_) =
      _createValidConfigUpdate();

    RewardPool[] memory preRewardPools_ = rewardsManager.getRewardPools();
    ClaimableRewardsData[][] memory preClaimableRewards_ = rewardsManager.getClaimableRewards();

    vm.prank(rewardsManager.owner());
    rewardsManager.updateConfigs(updatedStakePoolConfigs_, updatedRewardPoolConfigs_);

    for (uint8 i = 0; i < updatedStakePoolConfigs_.length; i++) {
      _assertStakePoolUpdatesApplied(rewardsManager.stakePools(i), updatedStakePoolConfigs_[i]);
    }

    for (uint8 i = 0; i < updatedRewardPoolConfigs_.length; i++) {
      _assertRewardPoolUpdatesApplied(rewardsManager.rewardPools(i), updatedRewardPoolConfigs_[i]);
    }

    _requireDripAndResetCumulativeRewardsValues(preRewardPools_, preClaimableRewards_);
  }

  function invariant_updateConfigsRevertsForNonOwner() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    address nonOwner_ = _randomAddress();
    vm.assume(rewardsManager.owner() != nonOwner_);

    vm.prank(nonOwner_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    rewardsManager.updateConfigs(currentStakePoolConfigs_, currentRewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsTooManyStakePools() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    uint8 allowedStakePools_ = rewardsManager.allowedStakePools();
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](allowedStakePools_ + 1);
    for (uint256 i = 0; i < numStakePools; i++) {
      stakePoolConfigs_[i] = currentStakePoolConfigs_[i];
    }
    for (uint256 i = numStakePools; i < allowedStakePools_ + 1; i++) {
      stakePoolConfigs_[i] = StakePoolConfig({asset: IERC20(_randomAddress()), rewardsWeight: 0});
    }

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(stakePoolConfigs_, currentRewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsTooManyRewardPools() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    uint8 allowedRewardPools_ = rewardsManager.allowedRewardPools();
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](allowedRewardPools_ + 1);
    for (uint256 i = 0; i < numRewardPools; i++) {
      rewardPoolConfigs_[i] = currentRewardPoolConfigs_[i];
    }
    for (uint256 i = numRewardPools; i < allowedRewardPools_ + 1; i++) {
      rewardPoolConfigs_[i] =
        RewardPoolConfig({asset: IERC20(_randomAddress()), dripModel: IDripModel(_randomAddress())});
    }

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(currentStakePoolConfigs_, rewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsInvalidWeightSum() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    StakePoolConfig[] memory stakePoolConfigs_ = currentStakePoolConfigs_;
    stakePoolConfigs_[_randomUint256() % stakePoolConfigs_.length].rewardsWeight += 1;

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(stakePoolConfigs_, currentRewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsRemovesExistingStakePool() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numStakePools - 1);
    for (uint256 i = 0; i < numStakePools - 1; i++) {
      stakePoolConfigs_[i] = currentStakePoolConfigs_[i];
    }

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(stakePoolConfigs_, currentRewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsChangesExistingStakePoolAsset()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    StakePoolConfig[] memory stakePoolConfigs_ = currentStakePoolConfigs_;
    stakePoolConfigs_[_randomUint256() % stakePoolConfigs_.length].asset = IERC20(address(0xBEEF));

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(stakePoolConfigs_, currentRewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsNewStakePoolUsesExistingStakePoolAsset()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numStakePools + 1);
    for (uint256 i = 0; i < numStakePools; i++) {
      stakePoolConfigs_[i] = currentStakePoolConfigs_[i];
    }
    stakePoolConfigs_[numStakePools] = StakePoolConfig({
      asset: currentStakePoolConfigs_[_randomUint256() % currentStakePoolConfigs_.length].asset,
      rewardsWeight: 0
    });

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(stakePoolConfigs_, currentRewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsNewStakePoolsContainDuplicates()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numStakePools + 3);
    for (uint256 i = 0; i < numStakePools; i++) {
      stakePoolConfigs_[i] = currentStakePoolConfigs_[i];
    }
    uint160 randomAddress_ = _randomUint160();
    stakePoolConfigs_[numStakePools] = StakePoolConfig({asset: IERC20(address(randomAddress_)), rewardsWeight: 0});
    stakePoolConfigs_[numStakePools + 1] = StakePoolConfig({asset: IERC20(address(randomAddress_)), rewardsWeight: 0});
    stakePoolConfigs_[numStakePools + 2] =
      StakePoolConfig({asset: IERC20(address(randomAddress_ + 2)), rewardsWeight: 0});

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(stakePoolConfigs_, currentRewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsNewStakePoolsAreNotSorted() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numStakePools + 3);
    for (uint256 i = 0; i < numStakePools; i++) {
      stakePoolConfigs_[i] = currentStakePoolConfigs_[i];
    }
    uint160 randomAddress_ = _randomUint160();
    stakePoolConfigs_[numStakePools] = StakePoolConfig({asset: IERC20(address(randomAddress_)), rewardsWeight: 0});
    stakePoolConfigs_[numStakePools + 1] =
      StakePoolConfig({asset: IERC20(address(randomAddress_ + 2)), rewardsWeight: 0});
    stakePoolConfigs_[numStakePools + 2] =
      StakePoolConfig({asset: IERC20(address(randomAddress_ + 1)), rewardsWeight: 0});

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(stakePoolConfigs_, currentRewardPoolConfigs_);
  }

  function invariant_updateConfigsRevertsRemovesExistingRewardPool() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](numRewardPools - 1);
    for (uint256 i = 0; i < numRewardPools - 1; i++) {
      rewardPoolConfigs_[i] = currentRewardPoolConfigs_[i];
    }

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(currentStakePoolConfigs_, rewardPoolConfigs_);
  }

  function invariant_updateConfigsChangesExistingRewardPoolAsset() public syncCurrentTimestamp(rewardsManagerHandler) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _createValidConfigUpdate();

    RewardPoolConfig[] memory rewardPoolConfigs_ = currentRewardPoolConfigs_;
    rewardPoolConfigs_[_randomUint256() % rewardPoolConfigs_.length].asset = IERC20(address(0xBEEF));

    vm.prank(rewardsManager.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    rewardsManager.updateConfigs(currentStakePoolConfigs_, rewardPoolConfigs_);
  }

  function _createValidConfigUpdate() internal view returns (StakePoolConfig[] memory, RewardPoolConfig[] memory) {
    (StakePoolConfig[] memory currentStakePoolConfigs_, RewardPoolConfig[] memory currentRewardPoolConfigs_) =
      _copyCurrentConfig();

    // Foundry invariant tests seem to revert at some random point into a run when you try to deploy new reward deposit
    // receipt tokens or stkReceiptTokens, so these tests do not add new stake pools or reward pools. Those cases are
    // checked
    // in unit tests.
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](currentStakePoolConfigs_.length);
    uint256 rewardsWeightSum_ = 0;
    for (uint8 i = 0; i < currentStakePoolConfigs_.length; i++) {
      uint256 rewardsWeight_ = i < currentStakePoolConfigs_.length - 1
        ? _randomUint256InRange(0, MathConstants.ZOC - rewardsWeightSum_)
        : MathConstants.ZOC - rewardsWeightSum_;
      rewardsWeightSum_ += rewardsWeight_;
      // We cannot update the asset of the copied current config, since it will cause a revert.
      stakePoolConfigs_[i] =
        StakePoolConfig({asset: currentStakePoolConfigs_[i].asset, rewardsWeight: uint16(rewardsWeight_)});
    }

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](currentRewardPoolConfigs_.length);
    for (uint8 i = 0; i < currentRewardPoolConfigs_.length; i++) {
      // We cannot update the asset of the copied current config, since it will cause a revert.
      rewardPoolConfigs_[i] =
        RewardPoolConfig({asset: currentRewardPoolConfigs_[i].asset, dripModel: IDripModel(_randomAddress())});
    }

    return (stakePoolConfigs_, rewardPoolConfigs_);
  }

  function _copyCurrentConfig() internal view returns (StakePoolConfig[] memory, RewardPoolConfig[] memory) {
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numStakePools);
    for (uint8 i = 0; i < numStakePools; i++) {
      StakePool memory stakePool_ = rewardsManager.stakePools(i);
      stakePoolConfigs_[i] = StakePoolConfig({asset: stakePool_.asset, rewardsWeight: stakePool_.rewardsWeight});
    }

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](numRewardPools);
    for (uint8 i = 0; i < numRewardPools; i++) {
      RewardPool memory rewardPool_ = rewardsManager.rewardPools(i);
      rewardPoolConfigs_[i] = RewardPoolConfig({asset: rewardPool_.asset, dripModel: rewardPool_.dripModel});
    }

    return (stakePoolConfigs_, rewardPoolConfigs_);
  }

  function _assertRewardPoolUpdatesApplied(RewardPool memory rewardPool_, RewardPoolConfig memory rewardPoolConfig_)
    private
  {
    assertEq(address(rewardPool_.asset), address(rewardPoolConfig_.asset));
    assertEq(address(rewardPool_.dripModel), address(rewardPoolConfig_.dripModel));
  }

  function _assertStakePoolUpdatesApplied(StakePool memory stakePool_, StakePoolConfig memory stakePoolConfig_) private {
    assertEq(address(stakePool_.asset), address(stakePoolConfig_.asset));
    assertEq(stakePool_.rewardsWeight, stakePoolConfig_.rewardsWeight);
  }

  function _requireDripAndResetCumulativeRewardsValues(
    RewardPool[] memory preRewardPools_,
    ClaimableRewardsData[][] memory preClaimableRewards_
  ) private view {
    for (uint8 rewardPoolId_ = 0; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      RewardPool memory rewardPool_ = rewardsManager.rewardPools(rewardPoolId_);
      require(
        rewardPool_.undrippedRewards <= preRewardPools_[rewardPoolId_].undrippedRewards,
        "Reward pool undripped rewards must decrease before a config update."
      );
      require(
        rewardPool_.cumulativeDrippedRewards == 0,
        "Reward pool cumulative dripped rewards must be reset to 0 before a config update."
      );
      for (uint8 stakePoolId_ = 0; stakePoolId_ < numStakePools; stakePoolId_++) {
        ClaimableRewardsData memory claimableRewards_ = rewardsManager.claimableRewards(stakePoolId_, rewardPoolId_);
        require(
          claimableRewards_.cumulativeClaimedRewards == 0,
          "Claimable rewards cumulative claimed rewards must be reset to 0 before a config update."
        );
        require(
          claimableRewards_.indexSnapshot >= preClaimableRewards_[stakePoolId_][rewardPoolId_].indexSnapshot,
          "Claimable rewards cumulative claimed rewards must increase before a config update."
        );
      }
    }
  }
}

contract ConfiguratorInvariantsWithStateTransitionsSingleStakePoolAndSingleRewardPool is
  ConfiguratorInvariantsWithStateTransitions,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract ConfiguratorInvariantsWithStateTransitionsMultipleStakePoolsAndMultipleRewardPools is
  ConfiguratorInvariantsWithStateTransitions,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
