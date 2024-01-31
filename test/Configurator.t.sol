// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {StkToken} from "../src/StkToken.sol";
import {RewardPoolConfig, StakePoolConfig} from "../src/lib/structs/Configs.sol";
import {StakePool, RewardPool, IdLookup} from "../src/lib/structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {RewardsManagerFactory} from "../src/RewardsManagerFactory.sol";
import {ConfiguratorLib} from "../src/lib/ConfiguratorLib.sol";
import {Configurator} from "../src/lib/Configurator.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {IConfiguratorEvents} from "../src/interfaces/IConfiguratorEvents.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockSafetyModule} from "./utils/MockSafetyModule.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract ConfiguratorUnitTest is TestBase, IConfiguratorEvents {
  TestableConfigurator component;
  StakePool stakePool1;
  StakePool stakePool2;
  RewardPool rewardPool1;
  RewardPool rewardPool2;

  function setUp() public {
    ReceiptToken receiptTokenLogic_ = new ReceiptToken();
    receiptTokenLogic_.initialize(address(0), "", "", 0);
    ReceiptTokenFactory receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(receiptTokenLogic_)), IReceiptToken(address(receiptTokenLogic_)));

    component = new TestableConfigurator(address(this), receiptTokenFactory, 3, 3);

    rewardPool1 = RewardPool({
      asset: IERC20(_randomAddress()),
      dripModel: IDripModel(_randomAddress()),
      depositReceiptToken: IReceiptToken(address(new ReceiptToken())),
      undrippedRewards: _randomUint256(),
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });
    rewardPool2 = RewardPool({
      asset: IERC20(_randomAddress()),
      dripModel: IDripModel(_randomAddress()),
      depositReceiptToken: IReceiptToken(address(new ReceiptToken())),
      undrippedRewards: _randomUint256(),
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });

    stakePool1 = StakePool({
      amount: _randomUint256(),
      asset: IERC20(address(new MockERC20("Mock Asset 1", "cozyMock1", 6))),
      stkReceiptToken: IReceiptToken(_randomAddress()),
      rewardsWeight: uint16(MathConstants.ZOC / 2)
    });
    stakePool2 = StakePool({
      amount: _randomUint256(),
      asset: IERC20(address(new MockERC20("Mock Asset 2", "cozyMock2", 18))),
      stkReceiptToken: IReceiptToken(_randomAddress()),
      rewardsWeight: uint16(MathConstants.ZOC / 2)
    });
  }

  function _generateValidRewardPoolConfig() private returns (RewardPoolConfig memory) {
    return RewardPoolConfig({
      asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyMock", 6))),
      dripModel: IDripModel(_randomAddress())
    });
  }

  function _generateValidStakePoolConfig(uint16 weight_) private returns (StakePoolConfig memory) {
    return StakePoolConfig({
      asset: IERC20(address(new MockERC20("Mock Stake Asset", "cozyMock", 6))),
      rewardsWeight: weight_
    });
  }

  function _setBasicConfigs() private returns (StakePoolConfig[] memory, RewardPoolConfig[] memory) {
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](2);
    stakePoolConfigs_[0] = _generateValidStakePoolConfig(uint16(MathConstants.ZOC / 2));
    stakePoolConfigs_[1] = _generateValidStakePoolConfig(uint16(MathConstants.ZOC / 2));
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

  function test_updateConfigs_basicSetup() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _setBasicConfigs();

    _expectEmit();
    emit TestableConfiguratorEvents.DripAndResetCumulativeRewardsValuesCalled();
    _expectEmit();
    emit ConfigUpdatesApplied(stakePoolConfigs_, rewardPoolConfigs_);

    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);

    _assertRewardPoolUpdatesApplied(component.getRewardPool(0), rewardPoolConfigs_[0]);
    _assertRewardPoolUpdatesApplied(component.getRewardPool(1), rewardPoolConfigs_[1]);
    _assertStakePoolUpdatesApplied(component.getStakePool(0), stakePoolConfigs_[0]);
    _assertStakePoolUpdatesApplied(component.getStakePool(1), stakePoolConfigs_[1]);
  }

  function test_updateConfigs_revertNonOwner() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _setBasicConfigs();

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);
  }

  function test_isValidConfiguration_TrueValidConfig() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _setBasicConfigs();
    assertTrue(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidConfiguration_FalseTooManyStakePools() external {
    (, RewardPoolConfig[] memory rewardPoolConfigs_) = _setBasicConfigs();
    // Only 3 stake pools are allowed.
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](4);
    stakePoolConfigs_[0] = _generateValidStakePoolConfig(uint16(MathConstants.ZOC / 4));
    stakePoolConfigs_[1] = _generateValidStakePoolConfig(uint16(MathConstants.ZOC / 4));
    stakePoolConfigs_[2] = _generateValidStakePoolConfig(uint16(MathConstants.ZOC / 4));
    stakePoolConfigs_[3] = _generateValidStakePoolConfig(uint16(MathConstants.ZOC / 4));

    assertFalse(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidConfiguration_FalseTooManyRewardsPools() external {
    (StakePoolConfig[] memory stakePoolConfigs_,) = _setBasicConfigs();
    // Only 3 reward pools are allowed.
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](4);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[1] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[2] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[3] = _generateValidRewardPoolConfig();

    assertFalse(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidConfiguration_FalseInvalidWeightSum() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _setBasicConfigs();
    stakePoolConfigs_[0].rewardsWeight = 0;
    assertFalse(component.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidUpdate_IsValidConfiguration() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _setBasicConfigs();

    assertTrue(component.isValidUpdate(stakePoolConfigs_, rewardPoolConfigs_));

    stakePoolConfigs_[0].rewardsWeight = 0; // Invalid weight sum
    assertFalse(component.isValidUpdate(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidUpdate_ExistingStakePoolsChecks() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _setBasicConfigs();
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

    // Valid update.
    assertTrue(component.isValidUpdate(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_isValidUpdate_ExistingRewardPoolsChecks() external {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _setBasicConfigs();
    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);

    // Invalid update because `invalidRewardPoolConfigs_.length < numExistingRewardPools`.
    RewardPoolConfig[] memory invalidRewardPoolConfigs_ = new RewardPoolConfig[](1);
    invalidRewardPoolConfigs_[0] = rewardPoolConfigs_[0];
    assertFalse(component.isValidUpdate(stakePoolConfigs_, invalidRewardPoolConfigs_));

    // Invalid update because `rewardPool2.asset != invalidRewardPoolConfigs_[1].asset`.
    invalidRewardPoolConfigs_ = new RewardPoolConfig[](2);
    invalidRewardPoolConfigs_[0] = rewardPoolConfigs_[0];
    invalidRewardPoolConfigs_[1] =
      RewardPoolConfig({asset: rewardPoolConfigs_[0].asset, dripModel: rewardPoolConfigs_[1].dripModel});
    assertFalse(component.isValidUpdate(stakePoolConfigs_, invalidRewardPoolConfigs_));

    // Valid update.
    assertTrue(component.isValidUpdate(stakePoolConfigs_, rewardPoolConfigs_));
  }

  function test_updateConfigs() external {
    // Add two existing stake pools.
    component.mockAddStakePool(stakePool1);
    component.mockAddStakePool(stakePool2);

    // Add two existing reward pools.
    component.mockAddRewardPool(rewardPool1);
    component.mockAddRewardPool(rewardPool2);

    // Create valid config update. Adds a new reward pool and chnages the drip model of the existing reward pools.
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](3);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: rewardPool1.asset, dripModel: IDripModel(_randomAddress())});
    rewardPoolConfigs_[1] = RewardPoolConfig({asset: rewardPool2.asset, dripModel: IDripModel(_randomAddress())});
    rewardPoolConfigs_[2] = _generateValidRewardPoolConfig();

    // Changes the rewards weights of the existing stake pools from 50%-50% to 0%-100%.
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](2);
    stakePoolConfigs_[0].rewardsWeight = 0;
    stakePoolConfigs_[0].asset = stakePool1.asset;
    stakePoolConfigs_[1].rewardsWeight = uint16(MathConstants.ZOC);
    stakePoolConfigs_[1].asset = stakePool2.asset;

    _expectEmit();
    emit TestableConfiguratorEvents.DripAndResetCumulativeRewardsValuesCalled();
    _expectEmit();
    emit ConfigUpdatesApplied(stakePoolConfigs_, rewardPoolConfigs_);

    component.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);

    // Stake pool config updates applied.
    StakePool[] memory stakePools_ = component.getStakePools();
    assertEq(stakePools_.length, 2);
    _assertStakePoolUpdatesApplied(stakePools_[0], stakePoolConfigs_[0]);
    _assertStakePoolUpdatesApplied(stakePools_[1], stakePoolConfigs_[1]);

    // Reward pool config updates applied.
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    assertEq(rewardPools_.length, 3);
    _assertRewardPoolUpdatesApplied(rewardPools_[0], rewardPoolConfigs_[0]);
    _assertRewardPoolUpdatesApplied(rewardPools_[1], rewardPoolConfigs_[1]);
    _assertRewardPoolUpdatesApplied(rewardPools_[2], rewardPoolConfigs_[2]);
  }

  function test_initializeStakePool() external {
    // One existing stake pool.
    component.mockAddStakePool(stakePool1);
    // New stake pool config.
    IReceiptToken asset_ = IReceiptToken(address(new ReceiptToken()));
    StakePoolConfig memory newStakePoolConfig_ =
      StakePoolConfig({asset: asset_, rewardsWeight: uint16(_randomUint16())});

    IReceiptTokenFactory receiptTokenFactory_ = component.getReceiptTokenFactory();
    address stkReceiptTokenAddress_ =
      receiptTokenFactory_.computeAddress(address(component), 1, IReceiptTokenFactory.PoolType.STAKE);

    _expectEmit();
    emit StakePoolCreated(1, IReceiptToken(stkReceiptTokenAddress_), asset_);
    component.initializeStakePool(newStakePoolConfig_);

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
  }

  function test_initializeRewardPool() external {
    // One existing reward pool.
    component.mockAddRewardPool(rewardPool1);
    // New reward pool config.
    RewardPoolConfig memory newRewardPoolConfig_ = _generateValidRewardPoolConfig();

    IReceiptTokenFactory receiptTokenFactory_ = component.getReceiptTokenFactory();
    address depositTokenAddress_ =
      receiptTokenFactory_.computeAddress(address(component), 1, IReceiptTokenFactory.PoolType.REWARD);

    _expectEmit();
    emit RewardPoolCreated(1, newRewardPoolConfig_.asset, IReceiptToken(depositTokenAddress_));
    component.initializeRewardPool(newRewardPoolConfig_);

    // One reward pool was added, so two total reward pools.
    assertEq(component.getRewardPools().length, 2);
    // Check that the new reward pool was initialized correctly.
    RewardPool memory newRewardPool_ = component.getRewardPool(1);
    _assertRewardPoolUpdatesApplied(newRewardPool_, newRewardPoolConfig_);
  }
}

interface TestableConfiguratorEvents {
  event DripAndResetCumulativeRewardsValuesCalled();
}

contract TestableConfigurator is Configurator, TestableConfiguratorEvents {
  constructor(
    address owner_,
    IReceiptTokenFactory receiptTokenFactory_,
    uint8 allowedStakePools_,
    uint8 allowedRewardPools_
  ) {
    __initGovernable(owner_, owner_);
    receiptTokenFactory = receiptTokenFactory_;
    allowedStakePools = allowedStakePools_;
    allowedRewardPools = allowedRewardPools_;
  }

  // -------- Mock setters --------
  function mockAddStakePool(StakePool memory stakePool_) external {
    stakePools.push(stakePool_);
  }

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  // -------- Mock getters --------
  function getStakePools() external view returns (StakePool[] memory) {
    return stakePools;
  }

  function getRewardPools() external view returns (RewardPool[] memory) {
    return rewardPools;
  }

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

  // -------- Internal function wrappers for testing --------
  function isValidConfiguration(
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_
  ) external view returns (bool) {
    return
      ConfiguratorLib.isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_, allowedStakePools, allowedRewardPools);
  }

  function isValidUpdate(StakePoolConfig[] calldata stakePoolConfigs_, RewardPoolConfig[] calldata rewardPoolConfigs_)
    external
    view
    returns (bool)
  {
    return ConfiguratorLib.isValidUpdate(
      stakePools, rewardPools, stakePoolConfigs_, rewardPoolConfigs_, allowedStakePools, allowedRewardPools
    );
  }

  function initializeStakePool(StakePoolConfig calldata stakePoolConfig_) external {
    ConfiguratorLib.initializeStakePool(
      stakePools, stkReceiptTokenToStakePoolIds, receiptTokenFactory, stakePoolConfig_
    );
  }

  function initializeRewardPool(RewardPoolConfig calldata rewardPoolConfig_) external {
    ConfiguratorLib.initializeRewardPool(rewardPools, receiptTokenFactory, rewardPoolConfig_);
  }

  function _dripAndResetCumulativeRewardsValues(
    StakePool[] storage, /* stakePools_ */
    RewardPool[] storage /* rewardPools_ */
  ) internal override {
    emit DripAndResetCumulativeRewardsValuesCalled();
  }

  // -------- Overridden abstract function placeholders --------

  function _claimRewards(uint16, /* stakePoolId_ */ address, /* receiver_ */ address /* owner */ ) internal override {
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
    uint256, /*userStkTokenBalance_*/
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
