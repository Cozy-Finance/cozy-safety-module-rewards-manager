// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {RewardsManager} from "../../../src/RewardsManager.sol";
import {StakePoolConfig, RewardPoolConfig} from "../../../src/lib/structs/Configs.sol";
import {IRewardsManager} from "../../../src/interfaces/IRewardsManager.sol";
import {RewardsManagerHandler} from "../handlers/RewardsManagerHandler.sol";
import {MockDeployer} from "../../utils/MockDeployProtocol.sol";
import {MockERC20} from "../../utils/MockERC20.sol";
import {TestBase} from "../../utils/TestBase.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Base contract for creating new RewardsManager deployment types for
/// invariant tests. Any new RewardsManager deployments should inherit from this,
/// not InvariantTestBase.
abstract contract InvariantBaseDeploy is TestBase, MockDeployer {
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD

  IRewardsManager public rewardsManager;
  RewardsManagerHandler public rewardsManagerHandler;

  // Deploy with some sane params for default models.
  IDripModel public dripModel = IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)));

  uint256 public numStakePools;
  uint256 public numRewardPools;
  IERC20[] public assets;

  function _initRewardsManager() internal virtual;
}

/// @dev Base contract for creating new invariant test suites.
/// If necessary, child contracts should override _fuzzedSelectors
/// and _initHandler to set custom handlers and selectors.
abstract contract InvariantTestBase is InvariantBaseDeploy {
  function setUp() public {
    deployMockProtocol();

    _initRewardsManager();
    _initHandler();
  }

  function _fuzzedSelectors() internal pure virtual returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](14);
    selectors[0] = RewardsManagerHandler.depositRewardAssets.selector;
    selectors[1] = RewardsManagerHandler.depositRewardAssetsWithExistingActor.selector;
    selectors[2] = RewardsManagerHandler.depositRewardAssetsWithoutTransfer.selector;
    selectors[3] = RewardsManagerHandler.depositRewardAssetsWithoutTransferWithExistingActor.selector;
    selectors[4] = RewardsManagerHandler.stake.selector;
    selectors[5] = RewardsManagerHandler.stakeWithExistingActor.selector;
    selectors[6] = RewardsManagerHandler.stakeWithoutTransfer.selector;
    selectors[7] = RewardsManagerHandler.stakeWithoutTransferWithExistingActor.selector;
    selectors[8] = RewardsManagerHandler.unstake.selector;
    // RewardsDistributor selectors
    selectors[9] = RewardsManagerHandler.dripRewards.selector;
    selectors[10] = RewardsManagerHandler.dripRewardPool.selector;
    selectors[11] = RewardsManagerHandler.claimRewards.selector;
    selectors[12] = RewardsManagerHandler.stkReceiptTokenTransfer.selector;
    selectors[13] = RewardsManagerHandler.updateUserRewardsForStkReceiptTokenTransfer.selector;
    return selectors;
  }

  function _initHandler() internal {
    rewardsManagerHandler =
      new RewardsManagerHandler(rewardsManager, cozyManager, numStakePools, numRewardPools, block.timestamp);
    targetSelector(FuzzSelector({addr: address(rewardsManagerHandler), selectors: _fuzzedSelectors()}));
    targetContract(address(rewardsManagerHandler));
  }

  modifier syncCurrentTimestamp(RewardsManagerHandler rewardsManagerHandler_) {
    vm.warp(rewardsManagerHandler.currentTimestamp());
    _;
  }

  /// @dev Some invariant tests might modify the rewards manager to put pools in a temporarily terminal state,
  /// thus we might want to only run some invariants with some probability.
  modifier randomlyCall(uint256 callPercentageZoc_) {
    if (_randomUint256InRange(0, MathConstants.ZOC) >= callPercentageZoc_) return;
    _;
  }

  function invariant_callSummary() public view {
    rewardsManagerHandler.callSummary();
  }
}

abstract contract InvariantTestBaseWithStateTransitions is InvariantTestBase {
  function _fuzzedSelectors() internal pure override returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](16);
    selectors[0] = RewardsManagerHandler.depositRewardAssets.selector;
    selectors[1] = RewardsManagerHandler.depositRewardAssetsWithExistingActor.selector;
    selectors[2] = RewardsManagerHandler.depositRewardAssetsWithoutTransfer.selector;
    selectors[3] = RewardsManagerHandler.depositRewardAssetsWithoutTransferWithExistingActor.selector;
    selectors[4] = RewardsManagerHandler.stake.selector;
    selectors[5] = RewardsManagerHandler.stakeWithExistingActor.selector;
    selectors[6] = RewardsManagerHandler.stakeWithoutTransfer.selector;
    selectors[7] = RewardsManagerHandler.stakeWithoutTransferWithExistingActor.selector;
    selectors[8] = RewardsManagerHandler.unstake.selector;
    // RewardsDistributor selectors
    selectors[9] = RewardsManagerHandler.dripRewards.selector;
    selectors[10] = RewardsManagerHandler.dripRewardPool.selector;
    selectors[11] = RewardsManagerHandler.claimRewards.selector;
    selectors[12] = RewardsManagerHandler.stkReceiptTokenTransfer.selector;
    selectors[13] = RewardsManagerHandler.updateUserRewardsForStkReceiptTokenTransfer.selector;
    // State transition selectors
    selectors[14] = RewardsManagerHandler.pause.selector;
    selectors[15] = RewardsManagerHandler.unpause.selector;
    return selectors;
  }
}

abstract contract InvariantTestWithSingleStakePoolAndSingleRewardPool is InvariantBaseDeploy {
  function _initRewardsManager() internal override {
    IERC20 asset_ = IERC20(address(new MockERC20("Mock Asset", "MOCK", 18)));
    assets.push(asset_);

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](1);
    stakePoolConfigs_[0] = StakePoolConfig({asset: asset_, rewardsWeight: uint16(MathConstants.ZOC)});

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: asset_, dripModel: dripModel});

    numStakePools = stakePoolConfigs_.length;
    numRewardPools = rewardPoolConfigs_.length;
    rewardsManager =
      cozyManager.createRewardsManager(owner, pauser, stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32());

    vm.label(address(getStakePool(rewardsManager, 0).stkReceiptToken), "stakePool0StkReceiptToken");
  }
}

abstract contract InvariantTestWithMultipleStakePoolsAndMultipleRewardPools is InvariantBaseDeploy {
  uint16 internal constant MAX_STAKE_POOLS = 10;
  uint16 internal constant MAX_REWARD_POOLS = 15;

  function _initRewardsManager() internal override {
    uint256 numStakePools_ = _randomUint256InRange(1, MAX_STAKE_POOLS);
    uint256 numRewardPools_ = _randomUint256InRange(1, MAX_REWARD_POOLS);

    // Create some unique assets to use for the pools. We want to make sure the invariant tests cover the case where the
    // same asset is used for multiple reward pools. We need at least numStakePool_ unique assets though, since
    // stake pool assets must be unique.
    uint256 uniqueNumAssets_ = _randomUint256InRange(numStakePools_, numStakePools_ + numRewardPools_);
    for (uint256 i_; i_ < uniqueNumAssets_; i_++) {
      assets.push(IERC20(address(new MockERC20("Mock Asset", "MOCK", 18))));
    }

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numStakePools_);
    uint256 rewardsWeightSum_ = 0;
    for (uint256 i_; i_ < numStakePools_; i_++) {
      uint256 rewardsWeight_ = i_ < numStakePools_ - 1
        ? _randomUint256InRange(0, MathConstants.ZOC - rewardsWeightSum_)
        : MathConstants.ZOC - rewardsWeightSum_;
      rewardsWeightSum_ += rewardsWeight_;

      stakePoolConfigs_[i_] = StakePoolConfig({asset: assets[i_], rewardsWeight: uint16(rewardsWeight_)});
    }
    sortStakePoolConfigs(stakePoolConfigs_);

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](numRewardPools_);
    for (uint256 i_; i_ < numRewardPools_; i_++) {
      rewardPoolConfigs_[i_] = RewardPoolConfig({
        asset: assets[_randomUint256InRange(0, uniqueNumAssets_ - 1)],
        dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
      });
    }

    numStakePools = stakePoolConfigs_.length;
    numRewardPools = rewardPoolConfigs_.length;
    rewardsManager =
      cozyManager.createRewardsManager(owner, pauser, stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32());

    for (uint16 i_; i_ < numStakePools_; i_++) {
      vm.label(
        address(getStakePool(rewardsManager, i_).stkReceiptToken),
        string.concat("stakePool", Strings.toString(i_), "StkReceiptToken")
      );
    }
  }
}
