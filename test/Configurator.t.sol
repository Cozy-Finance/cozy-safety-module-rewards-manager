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
import {ReservePool, RewardPool, IdLookup} from "../src/lib/structs/Pools.sol";
import {RewardPoolConfig, ClaimableRewardsData, UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {RewardsManagerFactory} from "../src/RewardsManagerFactory.sol";
import {ConfiguratorLib} from "../src/lib/ConfiguratorLib.sol";
import {Configurator} from "../src/lib/Configurator.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IManager} from "../src/interfaces/IManager.sol";
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
  ReservePool reservePool1;
  ReservePool reservePool2;
  RewardPool rewardPool1;
  RewardPool rewardPool2;

  MockManager mockManager = new MockManager();
  MockSafetyModule mockSafetyModule = new MockSafetyModule(SafetyModuleState.ACTIVE);

  function setUp() public {
    mockManager.initGovernable(address(0xBEEF), address(0xABCD));
    mockManager.setAllowedReservePools(30);
    mockManager.setAllowedRewardPools(25);

    ReceiptToken receiptTokenLogic_ = new ReceiptToken();
    receiptTokenLogic_.initialize(address(0), "", "", 0);
    ReceiptTokenFactory receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(receiptTokenLogic_)), IReceiptToken(address(receiptTokenLogic_)));

    component = new TestableConfigurator(
      address(this), IManager(address(mockManager)), receiptTokenFactory, ISafetyModule(address(mockSafetyModule))
    );

    rewardPool1 = RewardPool({
      asset: IERC20(_randomAddress()),
      dripModel: IDripModel(_randomAddress()),
      depositToken: IReceiptToken(address(new ReceiptToken())),
      undrippedRewards: _randomUint256(),
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });
    rewardPool2 = RewardPool({
      asset: IERC20(_randomAddress()),
      dripModel: IDripModel(_randomAddress()),
      depositToken: IReceiptToken(address(new ReceiptToken())),
      undrippedRewards: _randomUint256(),
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });

    reservePool1 = ReservePool({
      amount: _randomUint256(),
      safetyModuleReceiptToken: IReceiptToken(address(new ReceiptToken())),
      stkReceiptToken: IReceiptToken(_randomAddress()),
      rewardsWeight: uint16(MathConstants.ZOC / 2)
    });
    reservePool2 = ReservePool({
      amount: _randomUint256(),
      safetyModuleReceiptToken: IReceiptToken(address(new ReceiptToken())),
      stkReceiptToken: IReceiptToken(_randomAddress()),
      rewardsWeight: uint16(MathConstants.ZOC / 2)
    });
  }

  function _generateValidRewardPoolConfig() private returns (RewardPoolConfig memory) {
    return RewardPoolConfig({
      asset: IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6))),
      dripModel: IDripModel(_randomAddress())
    });
  }

  function _setBasicConfigs() private returns (RewardPoolConfig[] memory, uint16[] memory) {
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](2);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[1] = _generateValidRewardPoolConfig();
    uint16[] memory rewardsWeights_ = new uint16[](2);
    rewardsWeights_[0] = uint16(MathConstants.ZOC / 2);
    rewardsWeights_[1] = uint16(MathConstants.ZOC / 2);

    mockSafetyModule.setReservePoolStkReceiptToken(0, reservePool1.safetyModuleReceiptToken);
    mockSafetyModule.setReservePoolStkReceiptToken(1, reservePool2.safetyModuleReceiptToken);
    mockSafetyModule.setNumReservePools(2);

    return (rewardPoolConfigs_, rewardsWeights_);
  }

  function _assertRewardPoolUpdatesApplied(RewardPool memory rewardPool_, RewardPoolConfig memory rewardPoolConfig_)
    private
  {
    assertEq(address(rewardPool_.asset), address(rewardPoolConfig_.asset));
    assertEq(address(rewardPool_.dripModel), address(rewardPoolConfig_.dripModel));
  }

  function _assertReservePoolRewardsWeightApplied(ReservePool memory reservePool_, uint16 rewardsWeight_) private {
    assertEq(reservePool_.rewardsWeight, rewardsWeight_);
  }

  function test_updateConfigs_basicSetup() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();

    _expectEmit();
    emit TestableConfiguratorEvents.DripAndResetCumulativeRewardsValuesCalled();
    _expectEmit();
    emit ConfigUpdatesApplied(rewardPoolConfigs_, rewardsWeights_);

    component.updateConfigs(rewardPoolConfigs_, rewardsWeights_);

    _assertRewardPoolUpdatesApplied(component.getRewardPool(0), rewardPoolConfigs_[0]);
    _assertRewardPoolUpdatesApplied(component.getRewardPool(1), rewardPoolConfigs_[1]);
    _assertReservePoolRewardsWeightApplied(component.getReservePool(0), rewardsWeights_[0]);
    _assertReservePoolRewardsWeightApplied(component.getReservePool(1), rewardsWeights_[1]);
  }

  function test_updateConfigs_revertNonOwner() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    component.updateConfigs(rewardPoolConfigs_, rewardsWeights_);
  }

  function test_updateConfigs_revertSafetyModuleTriggered() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();
    mockSafetyModule.setSafetyModuleState(SafetyModuleState.TRIGGERED);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    component.updateConfigs(rewardPoolConfigs_, rewardsWeights_);
  }

  function test_isValidConfiguration_TrueValidConfig() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();
    assertTrue(component.isValidConfiguration(rewardPoolConfigs_, rewardsWeights_));
  }

  function test_isValidConfiguration_FalseTooManyRewardsPools() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();
    mockManager.setAllowedRewardPools(1);
    assertFalse(component.isValidConfiguration(rewardPoolConfigs_, rewardsWeights_));
  }

  function test_isValidConfiguration_FalseRewardsWeightReservePoolMismatch() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();
    mockSafetyModule.setNumReservePools(3);
    assertFalse(component.isValidConfiguration(rewardPoolConfigs_, rewardsWeights_));
  }

  function test_isValidConfiguration_FalseInvalidWeightSum() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();
    rewardsWeights_[0] = 0;
    assertFalse(component.isValidConfiguration(rewardPoolConfigs_, rewardsWeights_));
  }

  function test_isValidUpdate_IsValidConfiguration() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();

    assertTrue(component.isValidUpdate(rewardPoolConfigs_, rewardsWeights_));

    rewardsWeights_[0] = 0; // Invalid weight sum
    assertFalse(component.isValidUpdate(rewardPoolConfigs_, rewardsWeights_));
  }

  function test_isValidUpdate_ExistingRewardPoolsChecks() external {
    (RewardPoolConfig[] memory rewardPoolConfigs_, uint16[] memory rewardsWeights_) = _setBasicConfigs();
    component.updateConfigs(rewardPoolConfigs_, rewardsWeights_);

    // Invalid update because `invalidRewardPoolConfigs_.length < numExistingRewardPools`.
    RewardPoolConfig[] memory invalidRewardPoolConfigs_ = new RewardPoolConfig[](1);
    invalidRewardPoolConfigs_[0] = rewardPoolConfigs_[0];
    assertFalse(component.isValidUpdate(invalidRewardPoolConfigs_, rewardsWeights_));

    // Invalid update because `rewardPool2.asset != invalidRewardPoolConfigs_[1].asset`.
    invalidRewardPoolConfigs_ = new RewardPoolConfig[](2);
    invalidRewardPoolConfigs_[0] = rewardPoolConfigs_[0];
    invalidRewardPoolConfigs_[1] =
      RewardPoolConfig({asset: rewardPoolConfigs_[0].asset, dripModel: rewardPoolConfigs_[1].dripModel});
    assertFalse(component.isValidUpdate(invalidRewardPoolConfigs_, rewardsWeights_));

    // Valid update.
    assertTrue(component.isValidUpdate(rewardPoolConfigs_, rewardsWeights_));
  }

  function test_updateConfigsActive() external {
    _test_updateConfigs(SafetyModuleState.ACTIVE);
  }

  function test_updateConfigsPaused() external {
    _test_updateConfigs(SafetyModuleState.PAUSED);
  }

  function _test_updateConfigs(SafetyModuleState state_) internal {
    mockSafetyModule.setSafetyModuleState(state_);

    // Add two existing reserve pools.
    component.mockAddReservePool(reservePool1);
    component.mockAddReservePool(reservePool2);
    mockSafetyModule.setReservePoolStkReceiptToken(0, reservePool1.safetyModuleReceiptToken);
    mockSafetyModule.setReservePoolStkReceiptToken(1, reservePool2.safetyModuleReceiptToken);
    mockSafetyModule.setNumReservePools(2);

    // Add two existing reward pools.
    component.mockAddRewardPool(rewardPool1);
    component.mockAddRewardPool(rewardPool2);

    // Create valid config update. Adds a new reward pool and chnages the drip model of the existing reward pools.
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](3);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: rewardPool1.asset, dripModel: IDripModel(_randomAddress())});
    rewardPoolConfigs_[1] = RewardPoolConfig({asset: rewardPool2.asset, dripModel: IDripModel(_randomAddress())});
    rewardPoolConfigs_[2] = _generateValidRewardPoolConfig();

    // Changes the rewards weights of the existing reserve pools from 50%-50% to 0%-100%.
    uint16[] memory rewardsWeights_ = new uint16[](2);
    rewardsWeights_[0] = 0;
    rewardsWeights_[1] = uint16(MathConstants.ZOC);

    _expectEmit();
    emit TestableConfiguratorEvents.DripAndResetCumulativeRewardsValuesCalled();
    _expectEmit();
    emit ConfigUpdatesApplied(rewardPoolConfigs_, rewardsWeights_);

    component.updateConfigs(rewardPoolConfigs_, rewardsWeights_);

    // Reserve pool config updates applied.
    ReservePool[] memory reservePools_ = component.getReservePools();
    assertEq(reservePools_.length, 2);
    _assertReservePoolRewardsWeightApplied(reservePools_[0], rewardsWeights_[0]);
    _assertReservePoolRewardsWeightApplied(reservePools_[1], rewardsWeights_[1]);

    // Reward pool config updates applied.
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    assertEq(rewardPools_.length, 3);
    _assertRewardPoolUpdatesApplied(rewardPools_[0], rewardPoolConfigs_[0]);
    _assertRewardPoolUpdatesApplied(rewardPools_[1], rewardPoolConfigs_[1]);
    _assertRewardPoolUpdatesApplied(rewardPools_[2], rewardPoolConfigs_[2]);
  }

  function test_initializeReservePool() external {
    // One existing reserve pool.
    component.mockAddReservePool(reservePool1);
    // New reserve pool config.
    IReceiptToken newSafetyModuleReceiptToken_ = IReceiptToken(address(new ReceiptToken()));
    uint16 newRewardsWeight_ = uint16(_randomUint16());

    IReceiptTokenFactory receiptTokenFactory_ = component.getReceiptTokenFactory();
    address stkReceiptTokenAddress_ =
      receiptTokenFactory_.computeAddress(address(component), 1, IReceiptTokenFactory.PoolType.STAKE);

    _expectEmit();
    emit ReservePoolCreated(1, IReceiptToken(stkReceiptTokenAddress_), newSafetyModuleReceiptToken_);
    component.initializeReservePool(newSafetyModuleReceiptToken_, newRewardsWeight_);

    // One reserve pool was added, so two total reserve pools.
    assertEq(component.getReservePools().length, 2);
    // Check that the new reserve pool was initialized correctly.
    ReservePool memory newReservePool_ = component.getReservePool(1);
    _assertReservePoolRewardsWeightApplied(newReservePool_, newRewardsWeight_);
    assertEq(address(newReservePool_.safetyModuleReceiptToken), address(newSafetyModuleReceiptToken_));
    assertEq(address(newReservePool_.stkReceiptToken), stkReceiptTokenAddress_);
    assertEq(newReservePool_.amount, 0);

    IdLookup memory idLookup_ = component.getStkReceiptTokenToReservePoolId(stkReceiptTokenAddress_);
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
    IManager manager_,
    IReceiptTokenFactory receiptTokenFactory_,
    ISafetyModule safetyModule_
  ) {
    __initGovernable(owner_, owner_);
    cozyManager = manager_;
    receiptTokenFactory = receiptTokenFactory_;
    safetyModule = safetyModule_;
  }

  // -------- Mock setters --------
  function mockAddReservePool(ReservePool memory reservePool_) external {
    reservePools.push(reservePool_);
  }

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  // -------- Mock getters --------
  function getReservePools() external view returns (ReservePool[] memory) {
    return reservePools;
  }

  function getRewardPools() external view returns (RewardPool[] memory) {
    return rewardPools;
  }

  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getRewardPool(uint16 rewardPoolId_) external view returns (RewardPool memory) {
    return rewardPools[rewardPoolId_];
  }

  function getReceiptTokenFactory() external view returns (IReceiptTokenFactory) {
    return receiptTokenFactory;
  }

  function getStkReceiptTokenToReservePoolId(address stkReceiptTokenAddress_) external view returns (IdLookup memory) {
    return stkReceiptTokenToReservePoolIds[IReceiptToken(stkReceiptTokenAddress_)];
  }

  // -------- Internal function wrappers for testing --------
  function isValidConfiguration(RewardPoolConfig[] calldata rewardPoolConfigs_, uint16[] calldata rewardsWeights_)
    external
    view
    returns (bool)
  {
    return ConfiguratorLib.isValidConfiguration(
      rewardPoolConfigs_, rewardsWeights_, safetyModule, cozyManager.allowedRewardPools()
    );
  }

  function isValidUpdate(RewardPoolConfig[] calldata rewardPoolConfigs_, uint16[] calldata rewardsWeights_)
    external
    view
    returns (bool)
  {
    return ConfiguratorLib.isValidUpdate(rewardPools, rewardPoolConfigs_, rewardsWeights_, safetyModule, cozyManager);
  }

  function initializeReservePool(IReceiptToken safetyModuleReceiptToken_, uint16 rewardsWeight_) external {
    ConfiguratorLib.initializeReservePool(
      reservePools, stkReceiptTokenToReservePoolIds, receiptTokenFactory, safetyModuleReceiptToken_, rewardsWeight_
    );
  }

  function initializeRewardPool(RewardPoolConfig calldata rewardPoolConfig_) external {
    ConfiguratorLib.initializeRewardPool(rewardPools, receiptTokenFactory, rewardPoolConfig_);
  }

  function _dripAndResetCumulativeRewardsValues(
    ReservePool[] storage, /* reservePools_ */
    RewardPool[] storage /* rewardPools_ */
  ) internal override {
    emit DripAndResetCumulativeRewardsValuesCalled();
  }

  // -------- Overridden abstract function placeholders --------

  function _claimRewards(uint16, /* reservePoolId_ */ address, /* receiver_ */ address /* owner */ ) internal override {
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
    ReservePool storage, /*reservePool_*/
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
