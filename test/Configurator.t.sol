// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ReceiptToken} from "cozy-safety-module-libs/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-libs/ReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-libs/lib/Ownable.sol";
import {ICommonErrors} from "cozy-safety-module-libs/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-libs/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-libs/interfaces/IReceiptTokenFactory.sol";
import {RewardPoolConfig, StakePoolConfig} from "../src/lib/structs/Configs.sol";
import {StakePool, RewardPool, IdLookup} from "../src/lib/structs/Pools.sol";
import {ClaimRewardsArgs, ClaimableRewardsData, UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {RewardsManagerFactory} from "../src/RewardsManagerFactory.sol";
import {RewardsManagerInspector} from "../src/lib/RewardsManagerInspector.sol";
import {ConfiguratorLib} from "../src/lib/ConfiguratorLib.sol";
import {Configurator} from "../src/lib/Configurator.sol";
import {RewardsManagerState} from "../src/lib/RewardsManagerStates.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {IConfiguratorEvents} from "../src/interfaces/IConfiguratorEvents.sol";
import {IConfiguratorErrors} from "../src/interfaces/IConfiguratorErrors.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract ConfiguratorUnitTest is TestBase, IConfiguratorEvents, IConfiguratorErrors {
  TestableConfigurator component;

  uint16 ALLOWED_STAKE_POOLS = 5;
  uint16 ALLOWED_REWARD_POOLS = 10;

  function setUp() public {
    ReceiptToken receiptTokenLogic_ = new ReceiptToken();
    receiptTokenLogic_.initialize(address(0), "", "", 0);
    ReceiptTokenFactory receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(receiptTokenLogic_)), IReceiptToken(address(receiptTokenLogic_)));

    component = new TestableConfigurator(address(this), receiptTokenFactory, ALLOWED_STAKE_POOLS, ALLOWED_REWARD_POOLS);
  }

  function _generateRewardPools(uint256 numPools_) private returns (RewardPool[] memory) {
    RewardPool[] memory rewardPools_ = new RewardPool[](numPools_);
    for (uint256 i = 0; i < numPools_; i++) {
      rewardPools_[i] = RewardPool({
        asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyMock", 6))),
        dripModel: IDripModel(_randomAddress()),
        undrippedRewards: _randomUint256(),
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp)
      });
    }
    return rewardPools_;
  }

  function _generateStakePools(uint256 numPools_) private returns (StakePool[] memory) {
    StakePool[] memory stakePools_ = new StakePool[](numPools_);
    for (uint256 i = 0; i < numPools_; i++) {
      stakePools_[i] = StakePool({
        amount: _randomUint256(),
        asset: IERC20(address(new MockERC20("Mock Stake Asset", "cozyMock", 6))),
        stkReceiptToken: IReceiptToken(_randomAddress()),
        rewardsWeight: uint16(MathConstants.ZOC / numPools_)
      });
    }
    sortStakePools(stakePools_);
    return stakePools_;
  }

  function _generateValidRewardPoolConfig() private returns (RewardPoolConfig memory) {
    return RewardPoolConfig({
      asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyMock", 6))),
      dripModel: IDripModel(new MockDripModel(_randomUint256()))
    });
  }

  function _generateValidStakePoolConfig(uint16 weight_) private returns (StakePoolConfig memory) {
    return StakePoolConfig({
      asset: IERC20(address(new MockERC20("Mock Stake Asset", "cozyMock", 6))),
      rewardsWeight: weight_
    });
  }

  function _generateValidConfigs(uint256 numStakePoolConfigs_, uint256 numRewardPoolConfigs_)
    private
    returns (StakePoolConfig[] memory, RewardPoolConfig[] memory)
  {
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numStakePoolConfigs_);
    uint256 rewardsWeightSum_ = 0;
    for (uint256 i = 0; i < numStakePoolConfigs_; i++) {
      uint256 rewardsWeight_ = i < numStakePoolConfigs_ - 1
        ? _randomUint256InRange(0, MathConstants.ZOC - rewardsWeightSum_)
        : MathConstants.ZOC - rewardsWeightSum_;
      rewardsWeightSum_ += rewardsWeight_;
      stakePoolConfigs_[i] = _generateValidStakePoolConfig(uint16(rewardsWeight_));
    }
    if (numStakePoolConfigs_ > 1) sortStakePoolConfigs(stakePoolConfigs_);

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](numRewardPoolConfigs_);
    for (uint256 i = 0; i < numRewardPoolConfigs_; i++) {
      rewardPoolConfigs_[i] = _generateValidRewardPoolConfig();
    }
    return (stakePoolConfigs_, rewardPoolConfigs_);
  }

  function _generateBasicValidConfigs() private returns (StakePoolConfig[] memory, RewardPoolConfig[] memory) {
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](2);
    stakePoolConfigs_[0] = _generateValidStakePoolConfig(uint16(MathConstants.ZOC / 2));
    stakePoolConfigs_[1] = _generateValidStakePoolConfig(uint16(MathConstants.ZOC / 2));
    sortStakePoolConfigs(stakePoolConfigs_);

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](2);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[1] = _generateValidRewardPoolConfig();

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

  function _convertToAllowedNumConfigs(uint16 numStakePoolConfigs_, uint16 numRewardPoolConfigs_)
    private
    view
    returns (uint16, uint16)
  {
    return (numStakePoolConfigs_ % (ALLOWED_STAKE_POOLS + 1), numRewardPoolConfigs_ % (ALLOWED_REWARD_POOLS + 1));
  }

  function testFuzz_updateConfigs_OnInitialization(uint16 numStakePoolConfigs_, uint16 numRewardPoolConfigs_) external {
    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    _expectEmit();
    emit TestableConfiguratorEvents.DripAndResetCumulativeRewardsValuesCalled();
    _expectEmit();
    emit ConfigUpdatesApplied(stakePoolConfigs_, rewardPoolConfigs_);

    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);

    for (uint16 i = 0; i < numStakePoolConfigs_; i++) {
      _assertStakePoolUpdatesApplied(component.getStakePool(i), stakePoolConfigs_[i]);
    }
    for (uint16 i = 0; i < numRewardPoolConfigs_; i++) {
      _assertRewardPoolUpdatesApplied(component.getRewardPool(i), rewardPoolConfigs_[i]);
    }
  }

  function testFuzz_updateConfigs_OnInitialization_WhenPaused(uint16 numStakePoolConfigs_, uint16 numRewardPoolConfigs_)
    external
  {
    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    _expectEmit();
    emit TestableConfiguratorEvents.DripAndResetCumulativeRewardsValuesCalled();
    _expectEmit();
    emit ConfigUpdatesApplied(stakePoolConfigs_, rewardPoolConfigs_);

    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);

    for (uint16 i = 0; i < numStakePoolConfigs_; i++) {
      _assertStakePoolUpdatesApplied(component.getStakePool(i), stakePoolConfigs_[i]);
    }
    for (uint16 i = 0; i < numRewardPoolConfigs_; i++) {
      _assertRewardPoolUpdatesApplied(component.getRewardPool(i), rewardPoolConfigs_[i]);
    }
  }

  function test_updateConfigs_OnInitialization_RevertsNonOwner() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateBasicValidConfigs();

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);
  }

  function testFuzz_updateConfigs_OnInitialization_RevertsUnsortedStakePoolAssets(
    uint16 numStakePoolConfigs_,
    uint16 numRewardPoolConfigs_
  ) external {
    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    numStakePoolConfigs_ = numStakePoolConfigs_ > 1 ? numStakePoolConfigs_ : 2;
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    uint256 swapIndex_ = _randomUint256InRange(1, numStakePoolConfigs_ - 1);
    (stakePoolConfigs_[swapIndex_], stakePoolConfigs_[0]) = (stakePoolConfigs_[0], stakePoolConfigs_[swapIndex_]);

    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);
  }

  function testFuzz_updateConfigs_OnInitialization_RevertsNonUniqueStakePoolAssets(
    uint16 numStakePoolConfigs_,
    uint16 numRewardPoolConfigs_
  ) external {
    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    numStakePoolConfigs_ = numStakePoolConfigs_ > 1 ? numStakePoolConfigs_ : 2;
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    uint256 dupIndex_ = _randomUint256InRange(1, numStakePoolConfigs_ - 1);
    stakePoolConfigs_[dupIndex_].asset = stakePoolConfigs_[0].asset;

    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);
  }

  function testFuzz_isValidConfiguration_TrueValidConfig(uint16 numStakePoolConfigs_, uint16 numRewardPoolConfigs_)
    external
  {
    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    assertTrue(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function testFuzz_isValidConfiguration_FalseTooManyStakePools(uint16 numRewardPoolConfigs_) external {
    (, numRewardPoolConfigs_) = _convertToAllowedNumConfigs(0, numRewardPoolConfigs_);
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(ALLOWED_STAKE_POOLS + 1, numRewardPoolConfigs_);

    assertFalse(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidConfiguration_TrueOnlyRewardPools() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(0, ALLOWED_REWARD_POOLS);
    assertTrue(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidConfiguration_revertInvalidDripModel() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(0, ALLOWED_REWARD_POOLS);
    rewardPoolConfigs_[1].dripModel = IDripModel(_randomAddress());
    vm.expectRevert();
    component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_);
  }

  function testFuzz_isValidConfiguration_FalseTooManyRewardPools(uint16 numStakePoolConfigs_) external {
    (numStakePoolConfigs_,) = _convertToAllowedNumConfigs(numStakePoolConfigs_, 0);
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, ALLOWED_REWARD_POOLS + 1);

    assertFalse(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidConfiguration_TrueOnlyStakePools() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(ALLOWED_STAKE_POOLS, 0);
    assertTrue(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function testFuzz_isValidConfiguration_FalseUnsortedStakePoolAssets(
    uint16 numStakePoolConfigs_,
    uint16 numRewardPoolConfigs_
  ) external {
    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    numStakePoolConfigs_ = numStakePoolConfigs_ > 1 ? numStakePoolConfigs_ : 2;
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    uint256 swapIndex_ = _randomUint256InRange(1, numStakePoolConfigs_ - 1);
    (stakePoolConfigs_[swapIndex_], stakePoolConfigs_[0]) = (stakePoolConfigs_[0], stakePoolConfigs_[swapIndex_]);

    assertFalse(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function testFuzz_isValidConfiguration_FalseNonUniqueStakePoolAssets(
    uint16 numStakePoolConfigs_,
    uint16 numRewardPoolConfigs_
  ) external {
    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    numStakePoolConfigs_ = numStakePoolConfigs_ > 1 ? numStakePoolConfigs_ : 2;
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    uint256 dupIndex_ = _randomUint256InRange(1, numStakePoolConfigs_ - 1);
    stakePoolConfigs_[dupIndex_].asset = stakePoolConfigs_[0].asset;

    assertFalse(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function testFuzz_isValidConfiguration_FalseInvalidWeightSum(
    uint16 numStakePoolConfigs_,
    uint16 numRewardPoolConfigs_
  ) external {
    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    numStakePoolConfigs_ = numStakePoolConfigs_ > 0 ? numStakePoolConfigs_ : 1;
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    stakePoolConfigs_[0].rewardsWeight += 1;

    assertFalse(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function testFuzz_isValidUpdate_TrueValidConfiguration(uint16 numStakePoolConfigs_, uint16 numRewardPoolConfigs_)
    external
  {
    (numStakePoolConfigs_, numRewardPoolConfigs_) =
      _convertToAllowedNumConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(numStakePoolConfigs_, numRewardPoolConfigs_);

    assertTrue(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidUpdate_ExistingStakePoolsChecks() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateBasicValidConfigs();
    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);

    // Invalid update because `invalidStakePoolConfigs_.length < numExistingStakePools`.
    StakePoolConfig[] memory invalidStakePoolConfigs_ = new StakePoolConfig[](1);
    invalidStakePoolConfigs_[0] = stakePoolConfigs_[0];
    assertFalse(component.isValidUpdate(invalidStakePoolConfigs_, rewardPoolConfigs_));

    // Invalid update because `stakePool2.asset != invalidStakePoolConfigs_[1].asset`.
    invalidStakePoolConfigs_ = new StakePoolConfig[](2);
    invalidStakePoolConfigs_[0] = stakePoolConfigs_[0];
    invalidStakePoolConfigs_[1] =
      StakePoolConfig({asset: stakePoolConfigs_[0].asset, rewardsWeight: stakePoolConfigs_[1].rewardsWeight});
    assertFalse(component.isValidUpdate(invalidStakePoolConfigs_, rewardPoolConfigs_));

    // Invalid update because the new stake pool config uses an asset already used by stake pool 0.
    invalidStakePoolConfigs_ = new StakePoolConfig[](3);
    invalidStakePoolConfigs_[0] = stakePoolConfigs_[0];
    invalidStakePoolConfigs_[1] = stakePoolConfigs_[1];
    invalidStakePoolConfigs_[2] = StakePoolConfig({asset: stakePoolConfigs_[0].asset, rewardsWeight: 0});
    assertFalse(component.isValidUpdate(invalidStakePoolConfigs_, rewardPoolConfigs_));
    invalidStakePoolConfigs_[2].asset = IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6)));
    assertTrue(component.isValidUpdate(invalidStakePoolConfigs_, rewardPoolConfigs_));

    // Valid update.
    assertTrue(component.isValidUpdate(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function _initializeExistingRewardsManagerSetup() internal returns (StakePool[] memory, RewardPool[] memory) {
    StakePool[] memory stakePools_ = _generateStakePools(2);
    RewardPool[] memory rewardPools_ = _generateRewardPools(2);

    for (uint16 i = 0; i < 2; i++) {
      component.mockAddStakePool(stakePools_[i]);
      component.mockAddRewardPool(rewardPools_[i]);
    }

    return (stakePools_, rewardPools_);
  }

  function test_updateConfigsConcrete() external {
    (StakePool[] memory stakePools_, RewardPool[] memory rewardPools_) = _initializeExistingRewardsManagerSetup();

    // Create valid config update. Adds a new reward pools and chnages the drip model of the existing reward pools.
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](5);
    rewardPoolConfigs_[0] =
      RewardPoolConfig({asset: rewardPools_[0].asset, dripModel: IDripModel(new MockDripModel(_randomUint256()))});
    rewardPoolConfigs_[1] =
      RewardPoolConfig({asset: rewardPools_[1].asset, dripModel: IDripModel(new MockDripModel(_randomUint256()))});
    rewardPoolConfigs_[2] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[3] =
      RewardPoolConfig({asset: rewardPools_[0].asset, dripModel: IDripModel(new MockDripModel(_randomUint256()))});
    rewardPoolConfigs_[4] =
      RewardPoolConfig({asset: rewardPools_[0].asset, dripModel: IDripModel(new MockDripModel(_randomUint256()))});

    // Adds new stake pools and changes the rewards weights of the existing stake pools from 50%-50% to 0%-100%.
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](5);
    stakePoolConfigs_[0].rewardsWeight = 0;
    stakePoolConfigs_[0].asset = stakePools_[0].asset;
    stakePoolConfigs_[1].rewardsWeight = uint16(MathConstants.ZOC);
    stakePoolConfigs_[1].asset = stakePools_[1].asset;
    stakePoolConfigs_[2] = _generateValidStakePoolConfig(0);
    stakePoolConfigs_[3] = _generateValidStakePoolConfig(0);
    stakePoolConfigs_[4] = _generateValidStakePoolConfig(0);
    sortStakePoolConfigs(stakePoolConfigs_, 2);

    IReceiptTokenFactory receiptTokenFactory_ = component.getReceiptTokenFactory();
    _expectEmit();
    emit TestableConfiguratorEvents.DripAndResetCumulativeRewardsValuesCalled();
    _expectEmit();
    emit StakePoolCreated(
      2,
      IReceiptToken(receiptTokenFactory_.computeAddress(address(component), 2, IReceiptTokenFactory.PoolType.STAKE)),
      stakePoolConfigs_[2].asset
    );
    _expectEmit();
    emit StakePoolCreated(
      3,
      IReceiptToken(receiptTokenFactory_.computeAddress(address(component), 3, IReceiptTokenFactory.PoolType.STAKE)),
      stakePoolConfigs_[3].asset
    );
    _expectEmit();
    emit StakePoolCreated(
      4,
      IReceiptToken(receiptTokenFactory_.computeAddress(address(component), 4, IReceiptTokenFactory.PoolType.STAKE)),
      stakePoolConfigs_[4].asset
    );
    _expectEmit();
    emit RewardPoolCreated(2, rewardPoolConfigs_[2].asset);
    _expectEmit();
    emit RewardPoolCreated(3, rewardPools_[0].asset);
    _expectEmit();
    emit RewardPoolCreated(4, rewardPools_[0].asset);
    _expectEmit();
    emit ConfigUpdatesApplied(stakePoolConfigs_, rewardPoolConfigs_);

    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);

    // Stake pool config updates applied.
    StakePool[] memory updatedStakePools_ = component.getStakePools();
    assertEq(updatedStakePools_.length, 5);
    for (uint16 i = 0; i < updatedStakePools_.length; i++) {
      _assertStakePoolUpdatesApplied(updatedStakePools_[i], stakePoolConfigs_[i]);
    }

    // Reward pool config updates applied.
    RewardPool[] memory updatedRewardPools_ = component.getRewardPools();
    assertEq(updatedRewardPools_.length, 5);
    for (uint16 i = 0; i < updatedRewardPools_.length; i++) {
      _assertRewardPoolUpdatesApplied(updatedRewardPools_[i], rewardPoolConfigs_[i]);
    }
  }

  function _concatStakePoolConfigs(
    StakePoolConfig[] memory stakePoolConfigs_,
    StakePoolConfig[] memory newStakePoolConfigs_
  ) private pure returns (StakePoolConfig[] memory) {
    StakePoolConfig[] memory combinedStakePoolConfigs_ =
      new StakePoolConfig[](stakePoolConfigs_.length + newStakePoolConfigs_.length);
    for (uint256 i = 0; i < stakePoolConfigs_.length; i++) {
      combinedStakePoolConfigs_[i] = stakePoolConfigs_[i];
    }
    for (uint256 i = 0; i < newStakePoolConfigs_.length; i++) {
      combinedStakePoolConfigs_[i + stakePoolConfigs_.length] =
        StakePoolConfig({asset: newStakePoolConfigs_[i].asset, rewardsWeight: 0});
    }
    return combinedStakePoolConfigs_;
  }

  function _concatRewardPoolConfigs(
    RewardPoolConfig[] memory rewardPoolConfigs_,
    RewardPoolConfig[] memory newRewardPoolConfigs_
  ) private pure returns (RewardPoolConfig[] memory) {
    RewardPoolConfig[] memory combinedRewardPoolConfigs_ =
      new RewardPoolConfig[](rewardPoolConfigs_.length + newRewardPoolConfigs_.length);
    for (uint256 i = 0; i < rewardPoolConfigs_.length; i++) {
      combinedRewardPoolConfigs_[i] = rewardPoolConfigs_[i];
    }
    for (uint256 i = 0; i < newRewardPoolConfigs_.length; i++) {
      combinedRewardPoolConfigs_[i + rewardPoolConfigs_.length] = newRewardPoolConfigs_[i];
    }
    return combinedRewardPoolConfigs_;
  }

  function test_updateConfigsConcrete_RevertCases() external {
    (StakePool[] memory stakePools_, RewardPool[] memory rewardPools_) = _initializeExistingRewardsManagerSetup();

    RewardPoolConfig[] memory baseRewardPoolConfigs_ = new RewardPoolConfig[](2);
    for (uint16 i = 0; i < rewardPools_.length; i++) {
      baseRewardPoolConfigs_[i] =
        RewardPoolConfig({asset: rewardPools_[i].asset, dripModel: IDripModel(new MockDripModel(_randomUint256()))});
    }

    StakePoolConfig[] memory baseStakePoolConfigs_ = new StakePoolConfig[](2);
    for (uint16 i = 0; i < stakePools_.length; i++) {
      baseStakePoolConfigs_[i] =
        StakePoolConfig({asset: stakePools_[i].asset, rewardsWeight: stakePools_[i].rewardsWeight});
    }

    // Create an invalid configuration update: Uses an existing stake asset.
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) =
      _generateValidConfigs(2, 2);
    stakePoolConfigs_[1] = StakePoolConfig({asset: stakePools_[0].asset, rewardsWeight: 0});
    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(
      _concatStakePoolConfigs(baseStakePoolConfigs_, stakePoolConfigs_),
      _concatRewardPoolConfigs(baseRewardPoolConfigs_, rewardPoolConfigs_)
    );

    // Create an invalid configuration update: Unsorted stake assets.
    (stakePoolConfigs_, rewardPoolConfigs_) = _generateValidConfigs(5, 2);
    (stakePoolConfigs_[2], stakePoolConfigs_[4]) = (stakePoolConfigs_[2], stakePoolConfigs_[4]);
    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(
      _concatStakePoolConfigs(baseStakePoolConfigs_, stakePoolConfigs_),
      _concatRewardPoolConfigs(baseRewardPoolConfigs_, rewardPoolConfigs_)
    );

    // Create an invalid configuration update: Duplicate new stake assets.
    (stakePoolConfigs_, rewardPoolConfigs_) = _generateValidConfigs(5, 2);
    stakePoolConfigs_[2].asset = stakePoolConfigs_[0].asset;
    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(
      _concatStakePoolConfigs(baseStakePoolConfigs_, stakePoolConfigs_),
      _concatRewardPoolConfigs(baseRewardPoolConfigs_, rewardPoolConfigs_)
    );

    // Create an invalid configuration update: Duplicate new stake assets.
    (stakePoolConfigs_, rewardPoolConfigs_) = _generateValidConfigs(3, 2);
    stakePoolConfigs_[2].asset = stakePoolConfigs_[0].asset;
    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(
      _concatStakePoolConfigs(baseStakePoolConfigs_, stakePoolConfigs_),
      _concatRewardPoolConfigs(baseRewardPoolConfigs_, rewardPoolConfigs_)
    );

    // Create an invalid configuration update: Invalid weight sum.
    (stakePoolConfigs_, rewardPoolConfigs_) = _generateValidConfigs(3, 2);
    StakePoolConfig[] memory concatenatedStakePoolConfigs_ =
      _concatStakePoolConfigs(baseStakePoolConfigs_, stakePoolConfigs_);
    concatenatedStakePoolConfigs_[2].rewardsWeight = 1;
    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(
      concatenatedStakePoolConfigs_, _concatRewardPoolConfigs(baseRewardPoolConfigs_, rewardPoolConfigs_)
    );

    // Create an invalid configuration update: Too many stake pools.
    (stakePoolConfigs_, rewardPoolConfigs_) =
      _generateValidConfigs(ALLOWED_STAKE_POOLS - baseStakePoolConfigs_.length + 1, 2);
    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(
      _concatStakePoolConfigs(baseStakePoolConfigs_, stakePoolConfigs_),
      _concatRewardPoolConfigs(baseRewardPoolConfigs_, rewardPoolConfigs_)
    );

    // Create an invalid configuration update: Duplicate new stake assets.
    (stakePoolConfigs_, rewardPoolConfigs_) =
      _generateValidConfigs(2, ALLOWED_REWARD_POOLS - baseRewardPoolConfigs_.length + 1);
    vm.expectRevert(InvalidConfiguration.selector);
    component.updateConfigs(
      _concatStakePoolConfigs(baseStakePoolConfigs_, stakePoolConfigs_),
      _concatRewardPoolConfigs(baseRewardPoolConfigs_, rewardPoolConfigs_)
    );

    // Create a valid configuration update.
    (stakePoolConfigs_, rewardPoolConfigs_) = _generateValidConfigs(3, 2);
    component.updateConfigs(
      _concatStakePoolConfigs(baseStakePoolConfigs_, stakePoolConfigs_),
      _concatRewardPoolConfigs(baseRewardPoolConfigs_, rewardPoolConfigs_)
    );
  }

  function test_initializeStakePool() external {
    StakePool[] memory mockStakePools_ = _generateStakePools(1);
    // One existing stake pool.
    component.mockAddStakePool(mockStakePools_[0]);
    // New stake pool config.
    IReceiptToken asset_ = IReceiptToken(address(new ReceiptToken()));
    StakePoolConfig memory newStakePoolConfig_ =
      StakePoolConfig({asset: asset_, rewardsWeight: uint16(_randomUint16())});

    IReceiptTokenFactory receiptTokenFactory_ = component.getReceiptTokenFactory();
    address stkReceiptTokenAddress_ =
      receiptTokenFactory_.computeAddress(address(component), 1, IReceiptTokenFactory.PoolType.STAKE);

    _expectEmit();
    emit StakePoolCreated(1, IReceiptToken(stkReceiptTokenAddress_), asset_);
    component.initializeStakePool(newStakePoolConfig_, 1);

    // One stake pool was added, so two total stake pools.
    assertEq(component.getStakePools().length, 2);
    // Check that the new stake pool was initialized correctly.
    StakePool memory newStakePool_ = component.getStakePool(1);
    _assertStakePoolUpdatesApplied(newStakePool_, newStakePoolConfig_);
    assertEq(address(newStakePool_.asset), address(asset_));
    assertEq(address(newStakePool_.stkReceiptToken), stkReceiptTokenAddress_);
    assertEq(newStakePool_.amount, 0);

    IdLookup memory idLookup_ = component.getStkReceiptTokenToStakePoolId(stkReceiptTokenAddress_);
    assertEq(idLookup_.exists, true);
    assertEq(idLookup_.index, 1);

    idLookup_ = component.getAssetToStakePoolId(newStakePool_.asset);
    assertEq(idLookup_.exists, true);
    assertEq(idLookup_.index, 1);
  }

  function test_initializeRewardPool() external {
    RewardPool[] memory rewardPools_ = _generateRewardPools(1);
    // One existing reward pool.
    component.mockAddRewardPool(rewardPools_[0]);
    // New reward pool config.
    RewardPoolConfig memory newRewardPoolConfig_ = _generateValidRewardPoolConfig();

    _expectEmit();
    emit RewardPoolCreated(1, newRewardPoolConfig_.asset);
    component.initializeRewardPool(newRewardPoolConfig_, 1);

    // One reward pool was added, so two total reward pools.
    assertEq(component.getRewardPools().length, 2);
    // Check that the new reward pool was initialized correctly.
    RewardPool memory newRewardPool_ = component.getRewardPool(1);
    _assertRewardPoolUpdatesApplied(newRewardPool_, newRewardPoolConfig_);
  }

  function testFuzz_updatePauser(address newPauser_) external {
    vm.assume(newPauser_ != address(component.cozyManager()));
    component.updatePauser(newPauser_);
    assertEq(component.pauser(), newPauser_);
  }

  function test_updatePauser_revertNewPauserCozyManager() external {
    address manager_ = address(component.cozyManager());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    component.updatePauser(manager_);
  }
}

interface TestableConfiguratorEvents {
  event DripAndResetCumulativeRewardsValuesCalled();
}

contract TestableConfigurator is Configurator, RewardsManagerInspector, TestableConfiguratorEvents {
  constructor(
    address owner_,
    IReceiptTokenFactory receiptTokenFactory_,
    uint16 allowedStakePools_,
    uint16 allowedRewardPools_
  ) {
    __initOwnable(owner_);
    receiptTokenFactory = receiptTokenFactory_;
    allowedStakePools = allowedStakePools_;
    allowedRewardPools = allowedRewardPools_;
  }

  // -------- Mock setters --------
  function mockAddStakePool(StakePool memory stakePool_) external {
    stakePools.push(stakePool_);
    assetToStakePoolIds[stakePool_.asset] = IdLookup({exists: true, index: uint16(stakePools.length - 1)});
  }

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function mockSetRewardsManagerState(RewardsManagerState state_) external {
    rewardsManagerState = state_;
  }

  // -------- Mock getters --------
  function getStakePool(uint16 stakePoolId_) external view returns (StakePool memory) {
    return stakePools[stakePoolId_];
  }

  function getRewardPool(uint16 rewardPoolId_) external view returns (RewardPool memory) {
    return rewardPools[rewardPoolId_];
  }

  function getReceiptTokenFactory() external view returns (IReceiptTokenFactory) {
    return receiptTokenFactory;
  }

  function getStkReceiptTokenToStakePoolId(address stkReceiptTokenAddress_) external view returns (IdLookup memory) {
    return stkReceiptTokenToStakePoolIds[IReceiptToken(stkReceiptTokenAddress_)];
  }

  function getAssetToStakePoolId(IERC20 asset_) external view returns (IdLookup memory) {
    return assetToStakePoolIds[asset_];
  }

  // -------- Internal function wrappers for testing --------
  function isValidConfiguration(
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_
  ) external view returns (bool) {
    return ConfiguratorLib.isValidConfiguration(
      stakePoolConfigs_,
      rewardPoolConfigs_,
      stakePools.length,
      rewardPools.length,
      allowedStakePools,
      allowedRewardPools
    );
  }

  function isValidUpdate(StakePoolConfig[] calldata stakePoolConfigs_, RewardPoolConfig[] calldata rewardPoolConfigs_)
    external
    view
    returns (bool)
  {
    return ConfiguratorLib.isValidUpdate(
      stakePools,
      rewardPools,
      assetToStakePoolIds,
      stakePoolConfigs_,
      rewardPoolConfigs_,
      allowedStakePools,
      allowedRewardPools
    );
  }

  function initializeStakePool(StakePoolConfig calldata stakePoolConfig_, uint16 stakePoolId_) external {
    ConfiguratorLib.initializeStakePool(
      stakePools,
      assetToStakePoolIds,
      stkReceiptTokenToStakePoolIds,
      receiptTokenFactory,
      stakePoolConfig_,
      stakePoolId_
    );
  }

  function initializeRewardPool(RewardPoolConfig calldata rewardPoolConfig_, uint16 rewardPoolId_) external {
    ConfiguratorLib.initializeRewardPool(rewardPools, rewardPoolConfig_, rewardPoolId_);
  }

  function _dripAndResetCumulativeRewardsValues(
    StakePool[] storage, /* stakePools_ */
    RewardPool[] storage /* rewardPools_ */
  ) internal override {
    emit DripAndResetCumulativeRewardsValuesCalled();
  }

  // -------- Overridden abstract function placeholders --------

  function _claimRewards(ClaimRewardsArgs memory /* args_ */ ) internal override {
    __writeStub__();
  }

  function dripRewards() public view override {
    __readStub__();
  }

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 /*lastDripTime_*/ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _computeNextDripAmount(uint256, /* totalBaseAmount_ */ uint256 /* dripFactor_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _updateUserRewards(
    uint256, /*userStkReceiptTokenBalance_*/
    mapping(uint16 => ClaimableRewardsData) storage, /*claimableRewards_*/
    UserRewardsData[] storage /*userRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _dripRewardPool(RewardPool storage /* rewardPool_ */ ) internal view override {
    __readStub__();
  }

  function _dripAndApplyPendingDrippedRewards(
    StakePool storage, /*stakePool_*/
    mapping(uint16 => ClaimableRewardsData) storage /*claimableRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _assertValidDepositBalance(IERC20, /*token_*/ uint256, /*tokenPoolBalance_*/ uint256 /*depositAmount_*/ )
    internal
    view
    override
  {
    __readStub__();
  }
}
