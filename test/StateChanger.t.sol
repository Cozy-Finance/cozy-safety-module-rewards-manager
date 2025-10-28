// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Ownable} from "cozy-safety-module-libs/lib/Ownable.sol";
import {ICommonErrors} from "cozy-safety-module-libs/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {ICozyManager} from "../src/interfaces/ICozyManager.sol";
import {IStateChangerEvents} from "../src/interfaces/IStateChangerEvents.sol";
import {RewardPool, StakePool} from "../src/lib/structs/Pools.sol";
import {
  ClaimRewardsArgs,
  ClaimableRewardsData,
  UserRewardsData,
  DepositorRewardsData,
  ClaimRewardsPoolData
} from "../src/lib/structs/Rewards.sol";
import {RewardsManagerState} from "../src/lib/RewardsManagerStates.sol";
import {StateChanger} from "../src/lib/StateChanger.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";
import {IRewardsDistributorErrors} from "../src/interfaces/IRewardsDistributorErrors.sol";

interface StateChangerTestMockEvents {
  event DripRewardsCalled();
}

contract StateChangerUnitTest is TestBase, StateChangerTestMockEvents, IStateChangerEvents, ICommonErrors {
  enum TestCaller {
    NONE,
    OWNER,
    PAUSER,
    MANAGER
  }

  struct ComponentParams {
    address owner;
    address pauser;
    RewardsManagerState initialState;
  }

  function _initializeComponent(ComponentParams memory testParams_, MockManager manager_)
    internal
    returns (TestableStateChanger)
  {
    TestableStateChanger component_ =
      new TestableStateChanger(testParams_.owner, testParams_.pauser, ICozyManager(address(manager_)));
    component_.mockSetRewardsManagerState(testParams_.initialState);
    return component_;
  }

  function _initializeComponent(ComponentParams memory testParams_) internal returns (TestableStateChanger) {
    return _initializeComponent(testParams_, new MockManager());
  }

  function _initializeComponentAndCaller(ComponentParams memory testParams_, TestCaller testCaller_)
    internal
    returns (TestableStateChanger component_, address testCallerAddress_)
  {
    component_ = _initializeComponent(testParams_);

    if (testCaller_ == TestCaller.OWNER) testCallerAddress_ = testParams_.owner;
    else if (testCaller_ == TestCaller.PAUSER) testCallerAddress_ = testParams_.pauser;
    else if (testCaller_ == TestCaller.MANAGER) testCallerAddress_ = address(component_.cozyManager());
    else testCallerAddress_ = _randomAddress();
  }
}

contract StateChangerPauseTest is StateChangerUnitTest {
  function _testPauseSuccess(ComponentParams memory testParams_, TestCaller testCaller_) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);

    _expectEmit();
    emit DripRewardsCalled();
    _expectEmit();
    emit RewardsManagerStateUpdated(RewardsManagerState.PAUSED);

    vm.prank(caller_);
    component_.pause();

    assertEq(component_.rewardsManagerState(), RewardsManagerState.PAUSED);
  }

  function _testPauseInvalidStateTransition(ComponentParams memory testParams_, TestCaller testCaller_) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);
    vm.expectRevert(InvalidStateTransition.selector);
    vm.prank(caller_);
    component_.pause();
  }

  function _testPauseUnauthorized(ComponentParams memory testParams_, TestCaller testCaller_) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(caller_);
    component_.pause();
  }

  function test_pause() public {
    RewardsManagerState[1] memory validStartStates_ = [RewardsManagerState.ACTIVE];
    TestCaller[3] memory validCallers_ = [TestCaller.OWNER, TestCaller.PAUSER, TestCaller.MANAGER];

    for (uint256 i = 0; i < validStartStates_.length; i++) {
      for (uint256 j = 0; j < validCallers_.length; j++) {
        _testPauseSuccess(
          ComponentParams({owner: address(0xBEEF), pauser: address(0x1331), initialState: validStartStates_[i]}),
          validCallers_[j]
        );
      }
    }
  }

  function test_pause_Unauthorized() public {
    RewardsManagerState[1] memory validStartStates_ = [RewardsManagerState.ACTIVE];
    TestCaller[1] memory invalidCaller_ = [TestCaller.NONE];

    for (uint256 i = 0; i < validStartStates_.length; i++) {
      for (uint256 j = 0; j < invalidCaller_.length; j++) {
        _testPauseUnauthorized(
          ComponentParams({owner: address(0xBEEF), pauser: address(0x1331), initialState: validStartStates_[i]}),
          invalidCaller_[j]
        );
      }
    }
  }

  function test_pause_InvalidStateTransition() public {
    // Any call to pause when the Safety Module is already paused should revert.
    TestCaller[3] memory callers_ = [TestCaller.OWNER, TestCaller.PAUSER, TestCaller.MANAGER];
    for (uint256 i = 0; i < callers_.length; i++) {
      _testPauseInvalidStateTransition(
        ComponentParams({owner: address(0xBEEF), pauser: address(0x1331), initialState: RewardsManagerState.PAUSED}),
        callers_[i]
      );
    }
  }

  function test_pause_revertsWithInvalidDripRewardPoolLength() public {
    address owner_ = _randomAddress();
    TestableStateChanger component_ = _initializeComponent(
      ComponentParams({owner: owner_, pauser: _randomAddress(), initialState: RewardsManagerState.ACTIVE})
    );

    component_.mockAddRewardPool(
      RewardPool({
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        lastDripTime: 0,
        asset: IERC20(address(0xA1)),
        dripModel: IDripModel(address(0)),
        epoch: 0,
        logIndexSnapshot: 0
      })
    );

    // Mismatched length (2 != rewardPools.length=1)
    bool[] memory selection_ = new bool[](2);

    vm.expectRevert(IRewardsDistributorErrors.InvalidLength.selector);
    vm.prank(owner_);
    component_.pause(selection_);
  }

  function test_pause_dripsSelectedRewardPools() public {
    address owner_ = _randomAddress();
    TestableStateChanger component_ = _initializeComponent(
      ComponentParams({owner: owner_, pauser: _randomAddress(), initialState: RewardsManagerState.ACTIVE})
    );

    component_.mockAddRewardPool(
      RewardPool({
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        lastDripTime: 0,
        asset: IERC20(address(0xA1)),
        dripModel: IDripModel(address(0)),
        epoch: 0,
        logIndexSnapshot: 0
      })
    );
    component_.mockAddRewardPool(
      RewardPool({
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        lastDripTime: 0,
        asset: IERC20(address(0xB2)),
        dripModel: IDripModel(address(0)),
        epoch: 0,
        logIndexSnapshot: 0
      })
    );
    component_.mockAddRewardPool(
      RewardPool({
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        lastDripTime: 0,
        asset: IERC20(address(0xC3)),
        dripModel: IDripModel(address(0)),
        epoch: 0,
        logIndexSnapshot: 0
      })
    );

    // Drip pools 0 and 2 only
    bool[] memory selection_ = new bool[](3);
    selection_[0] = true;
    selection_[1] = false;
    selection_[2] = true;

    uint256 ts_ = block.timestamp + 4567;
    vm.warp(ts_);

    vm.prank(owner_);
    component_.pause(selection_);

    // State should be PAUSED
    assertEq(component_.rewardsManagerState(), RewardsManagerState.PAUSED);

    // Only selected pools should have updated lastDripTime
    RewardPool memory p0_ = component_.getRewardPool(0);
    RewardPool memory p1_ = component_.getRewardPool(1);
    RewardPool memory p2_ = component_.getRewardPool(2);

    assertEq(p0_.lastDripTime, uint128(ts_), "pool 0 lastDripTime");
    assertEq(p1_.lastDripTime, 0, "pool 1 lastDripTime should remain 0");
    assertEq(p2_.lastDripTime, uint128(ts_), "pool 2 lastDripTime");
  }
}

contract StateChangerUnpauseTest is StateChangerUnitTest {
  function _testUnpauseSuccess(
    ComponentParams memory testParams_,
    RewardsManagerState expectedState_,
    TestCaller testCaller_
  ) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);

    _expectEmit();
    emit DripRewardsCalled();
    _expectEmit();
    emit RewardsManagerStateUpdated(expectedState_);

    vm.prank(caller_);
    component_.unpause();

    assertEq(component_.rewardsManagerState(), expectedState_);
  }

  function _testUnpauseInvalidStateTransitionRevert(ComponentParams memory testParams_, TestCaller testCaller_)
    internal
  {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);

    vm.expectRevert(InvalidStateTransition.selector);
    vm.prank(caller_);
    component_.unpause();
  }

  function _testUnpauseUnauthorizedRevert(ComponentParams memory testParams_, TestCaller testCaller_) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(caller_);
    component_.unpause();
  }

  function test_unpause_zeroPendingRaises() public {
    TestCaller[2] memory validCallers_ = [TestCaller.OWNER, TestCaller.MANAGER];

    for (uint256 i = 0; i < validCallers_.length; i++) {
      _testUnpauseSuccess(
        ComponentParams({owner: address(0xBEEF), pauser: address(0x1331), initialState: RewardsManagerState.PAUSED}),
        RewardsManagerState.ACTIVE,
        validCallers_[i]
      );
    }
  }

  function test_unpause_revertsWithInvalidStartState() public {
    TestCaller[2] memory callers_ = [TestCaller.OWNER, TestCaller.MANAGER];
    RewardsManagerState[1] memory invalidStartStates_ = [RewardsManagerState.ACTIVE];

    for (uint256 i = 0; i < callers_.length; i++) {
      for (uint256 j = 0; j < invalidStartStates_.length; j++) {
        _testUnpauseInvalidStateTransitionRevert(
          ComponentParams({owner: address(0xBEEF), pauser: address(0x1331), initialState: invalidStartStates_[j]}),
          callers_[i]
        );
      }
    }
  }

  function test_unpause_revertsWithInvalidCaller() public {
    TestCaller[2] memory invalidCallers_ = [TestCaller.PAUSER, TestCaller.NONE];

    for (uint256 i = 0; i < invalidCallers_.length; i++) {
      _testUnpauseUnauthorizedRevert(
        ComponentParams({owner: address(0xBEEF), pauser: address(0x1331), initialState: RewardsManagerState.PAUSED}),
        invalidCallers_[i]
      );
    }
  }

  function test_unpause_revertsWithInvalidDripRewardPoolLength() public {
    address owner_ = _randomAddress();
    TestableStateChanger component_ = _initializeComponent(
      ComponentParams({owner: owner_, pauser: _randomAddress(), initialState: RewardsManagerState.PAUSED})
    );

    component_.mockAddRewardPool(
      RewardPool({
        asset: IERC20(address(0xA1)),
        dripModel: IDripModel(address(0)),
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        lastDripTime: 0,
        epoch: 0,
        logIndexSnapshot: 0
      })
    );

    bool[] memory selection_ = new bool[](2);

    vm.expectRevert(IRewardsDistributorErrors.InvalidLength.selector);
    vm.prank(owner_);
    component_.unpause(selection_);
  }

  function test_unpause_dripsSelectedRewardPools() public {
    address owner_ = _randomAddress();
    TestableStateChanger component_ = _initializeComponent(
      ComponentParams({owner: owner_, pauser: _randomAddress(), initialState: RewardsManagerState.PAUSED})
    );

    component_.mockAddRewardPool(
      RewardPool({
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        lastDripTime: 0,
        asset: IERC20(address(0xA1)),
        dripModel: IDripModel(address(0)),
        epoch: 0,
        logIndexSnapshot: 0
      })
    );
    component_.mockAddRewardPool(
      RewardPool({
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        lastDripTime: 0,
        asset: IERC20(address(0xB2)),
        dripModel: IDripModel(address(0)),
        epoch: 0,
        logIndexSnapshot: 0
      })
    );
    component_.mockAddRewardPool(
      RewardPool({
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        lastDripTime: 0,
        asset: IERC20(address(0xC3)),
        dripModel: IDripModel(address(0)),
        epoch: 0,
        logIndexSnapshot: 0
      })
    );

    bool[] memory selection_ = new bool[](3);
    selection_[0] = true;
    selection_[1] = false;
    selection_[2] = true;

    uint256 ts_ = block.timestamp + 1234;
    vm.warp(ts_);

    vm.prank(owner_);
    component_.unpause(selection_);

    assertEq(component_.rewardsManagerState(), RewardsManagerState.ACTIVE);

    // Only selected pools should have updated lastDripTime
    RewardPool memory p0_ = component_.getRewardPool(0);
    RewardPool memory p1_ = component_.getRewardPool(1);
    RewardPool memory p2_ = component_.getRewardPool(2);

    assertEq(p0_.lastDripTime, uint128(ts_), "pool 0 lastDripTime");
    assertEq(p1_.lastDripTime, 0, "pool 1 lastDripTime should remain 0");
    assertEq(p2_.lastDripTime, uint128(ts_), "pool 2 lastDripTime");
  }
}

contract TestableStateChanger is StateChanger, StateChangerTestMockEvents {
  constructor(address owner_, address pauser_, ICozyManager manager_) {
    __initGovernable(owner_, pauser_);
    cozyManager = manager_;
  }

  // -------- Mock setters --------
  function mockSetRewardsManagerState(RewardsManagerState state_) external {
    rewardsManagerState = state_;
  }

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function getRewardPool(uint256 index_) external view returns (RewardPool memory) {
    return rewardPools[index_];
  }

  // -------- Overridden abstract function placeholders --------

  function _claimRewards(
    ClaimRewardsArgs memory, /* args_ */
    ClaimRewardsPoolData[] memory /* claimRewardsPoolData_ */
  )
    internal
    override
  {
    __writeStub__();
  }

  function dripRewards() public override {
    emit DripRewardsCalled();
  }

  function _getNextDripAmount(
    uint256,
    /* totalBaseAmount_ */
    IDripModel,
    /* dripModel_ */
    uint256 /*lastDripTime_*/
  )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _getNextDripFactor(
    uint256,
    /* totalBaseAmount_ */
    IDripModel,
    /* dripModel_ */
    uint256 /*lastDripTime_*/
  )
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
  )
    internal
    view
    override
  {
    __readStub__();
  }

  function _dripRewardPool(RewardPool storage rewardPool_) internal override {
    rewardPool_.lastDripTime = uint128(block.timestamp);
  }

  function _dripAndApplyPendingDrippedRewards(
    StakePool storage, /*stakePool_*/
    mapping(uint16 => ClaimableRewardsData) storage /*claimableRewards_*/
  )
    internal
    view
    override
  {
    __readStub__();
  }

  function _assertValidDepositBalance(
    IERC20,
    /*token_*/
    uint256,
    /*tokenPoolBalance_*/
    uint256 /*depositAmount_*/
  )
    internal
    view
    override
  {
    __readStub__();
  }

  function _dripAndResetCumulativeRewardsValues(
    StakePool[] storage, /*stakePools_*/
    RewardPool[] storage /*rewardPools_*/
  )
    internal
    view
    override
  {
    __readStub__();
  }

  function _previewCurrentWithdrawableRewards(
    RewardPool storage, /*rewardPool_*/
    DepositorRewardsData storage /*depositorRewardsData_*/
  )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }
}
