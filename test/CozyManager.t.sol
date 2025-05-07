// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-libs/lib/Ownable.sol";
import {StakePoolConfig, RewardPoolConfig} from "../src/lib/structs/Configs.sol";
import {CozyManager} from "../src/CozyManager.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {RewardsManagerState} from "../src/lib/RewardsManagerStates.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {ICozyManagerEvents} from "../src/interfaces/ICozyManagerEvents.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";

abstract contract CozyManagerTestSetup is TestBase {
  function _defaultSetUp()
    internal
    returns (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_)
  {
    IERC20 asset_ = IERC20(address(new MockERC20("MockAsset", "MOCK", 18)));

    stakePoolConfigs_ = new StakePoolConfig[](1);
    stakePoolConfigs_[0] = StakePoolConfig({asset: asset_, rewardsWeight: uint16(MathConstants.ZOC)});

    rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: asset_, dripModel: IDripModel(address(new MockDripModel(1e18)))});
  }
}

contract CozyManagerTestSetupWithRewardsManagers is MockDeployProtocol, CozyManagerTestSetup {
  IRewardsManager[] rewardsManagers;

  IRewardsManager rewardsManagerA;
  IRewardsManager rewardsManagerB;

  MockERC20 mockAsset;
  IERC20 asset;

  function setUp() public virtual override {
    super.setUp();
    asset = IERC20(address(mockAsset));

    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _defaultSetUp();

    rewardsManagerA = cozyManager.createRewardsManager(
      _randomAddress(), _randomAddress(), stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32()
    );
    rewardsManagerB = cozyManager.createRewardsManager(
      _randomAddress(), _randomAddress(), stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32()
    );
    rewardsManagers.push(rewardsManagerA);
    rewardsManagers.push(rewardsManagerB);
  }
}

contract CozyManagerTestCreateRewardsManager is MockDeployProtocol, CozyManagerTestSetup {
  function test_createRewardsManager() public {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _defaultSetUp();

    address owner_ = _randomAddress();
    address pauser_ = _randomAddress();
    bytes32 salt_ = _randomBytes32();
    address caller_ = _randomAddress();

    address expectedDeployAddress_ = cozyManager.computeRewardsManagerAddress(caller_, salt_);

    vm.prank(caller_);
    IRewardsManager rewardsManager_ =
      cozyManager.createRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, salt_);

    assertEq(address(rewardsManager_), expectedDeployAddress_);

    // Loosely validate the rewards manager.
    assertEq(address(rewardsManagerLogic.cozyManager()), address(cozyManager));
    assertEq(rewardsManager_.rewardsManagerState(), RewardsManagerState.ACTIVE);
    assertEq(address(getStakePool(rewardsManager_, 0).asset), address(stakePoolConfigs_[0].asset));
  }

  function test_rewardsManager_revertInvalidOwnerAddress() public {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _defaultSetUp();

    vm.expectRevert(Ownable.InvalidAddress.selector);
    cozyManager.createRewardsManager(
      address(0), _randomAddress(), stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32()
    );
  }

  function test_rewardsManager_revertInvalidPauserAddress() public {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _defaultSetUp();

    vm.expectRevert(Ownable.InvalidAddress.selector);
    cozyManager.createRewardsManager(
      _randomAddress(), address(0), stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32()
    );
  }

  function test_createRewardsManager_cannotFrontRun() public {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _defaultSetUp();
    address owner_ = _randomAddress();
    address pauser_ = _randomAddress();
    bytes32 salt_ = _randomBytes32();
    address caller_ = _randomAddress();
    address frontRunCaller_ = _randomAddress();

    // To avoid front-running of RewardsManager deploys, msg.sender is used for the deploy salt in
    // CozyManager.createRewardsManager.
    bytes32 deploySalt_ = keccak256(abi.encodePacked(salt_, caller_));

    address expectedDeployAddress_ = rewardsManagerFactory.computeAddress(deploySalt_);
    address managerExpectedDeployAddress_ = cozyManager.computeRewardsManagerAddress(caller_, salt_);
    assertEq(expectedDeployAddress_, managerExpectedDeployAddress_);

    vm.prank(frontRunCaller_);
    IRewardsManager rewardsManager_ =
      cozyManager.createRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, salt_);
    // The deployed rewards manager has a different than expected address - cannot front-run even if using the same
    // configs and salt.
    assertFalse(address(rewardsManager_) == expectedDeployAddress_);

    vm.prank(caller_);
    rewardsManager_ = cozyManager.createRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, salt_);
    // The deployed rewards manager has the expected address when deployed by the correct caller.
    assertTrue(address(rewardsManager_) == expectedDeployAddress_);
  }
}

contract CozyManagerUpdateClaimFees is MockDeployProtocol, CozyManagerTestSetup {
  function test_claimFeeCorrectlyInitialized() public {
    assertEq(cozyManager.claimFee(), DEFAULT_CLAIM_FEE);
  }

  function test_updateClaimFee_revertNonOwnerAddress() public {
    uint16 newClaimFee_ = uint16(bound(_randomUint16(), 0, MathConstants.ZOC));

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    cozyManager.updateClaimFee(newClaimFee_);
  }

  function test_updateClaimFee_revertInvalidClaimFee() public {
    uint16 newClaimFee_ = uint16(bound(_randomUint16(), MathConstants.ZOC + 1, type(uint16).max));

    vm.expectRevert(ICozyManagerEvents.InvalidClaimFee.selector);
    vm.prank(owner);
    cozyManager.updateClaimFee(newClaimFee_);
  }

  function test_updateOverrideClaimFee_revertInvalidClaimFee() public {
    uint16 claimFee_ = uint16(bound(_randomUint16(), MathConstants.ZOC + 1, type(uint16).max));
    IRewardsManager rewardsManager_ = IRewardsManager(_randomAddress());

    vm.expectRevert(ICozyManagerEvents.InvalidClaimFee.selector);
    vm.prank(owner);
    cozyManager.updateOverrideClaimFee(rewardsManager_, claimFee_);
  }

  function test_updateOverrideClaimFee_revertNonOwnerAddress() public {
    uint16 newClaimFee_ = uint16(bound(_randomUint16(), 0, MathConstants.ZOC));
    IRewardsManager rewardsManager_ = IRewardsManager(_randomAddress());

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    cozyManager.updateOverrideClaimFee(rewardsManager_, newClaimFee_);
  }

  function test_resetOverrideFeeDripModel_revertNonOwnerAddress() public {
    IRewardsManager rewardsManager_ = IRewardsManager(_randomAddress());

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    cozyManager.resetOverrideClaimFee(rewardsManager_);
  }

  function testFuzz_updateClaimFee(uint16 claimFee_) public {
    uint16 newClaimFee_ = uint16(bound(claimFee_, 0, MathConstants.ZOC));

    _expectEmit();
    emit ICozyManagerEvents.ClaimFeeUpdated(newClaimFee_);
    vm.prank(owner);
    cozyManager.updateClaimFee(newClaimFee_);

    assertEq(cozyManager.claimFee(), newClaimFee_);
  }

  function testFuzz_updateOverrideClaimFee(uint16 claimFee_, address rewardsManagerAddress_) public {
    uint16 newClaimFee_ = uint16(bound(claimFee_, 0, MathConstants.ZOC));
    IRewardsManager rewardsManager_ = IRewardsManager(rewardsManagerAddress_);

    assertEq(cozyManager.claimFee(), cozyManager.claimFee());
    assertEq(cozyManager.getClaimFee(rewardsManager_), cozyManager.claimFee());

    _expectEmit();
    emit ICozyManagerEvents.OverrideClaimFeeUpdated(rewardsManager_, newClaimFee_);
    vm.prank(owner);
    cozyManager.updateOverrideClaimFee(rewardsManager_, newClaimFee_);

    assertEq(cozyManager.getClaimFee(rewardsManager_), newClaimFee_);
  }

  function testFuzz_resetOverrideClaimFee(uint16 claimFee_, uint16 newClaimFee_, address rewardsManagerAddress_) public {
    IRewardsManager rewardsManager_ = IRewardsManager(rewardsManagerAddress_);
    claimFee_ = uint16(bound(claimFee_, 0, MathConstants.ZOC));
    newClaimFee_ = uint16(bound(newClaimFee_, 0, MathConstants.ZOC));

    vm.prank(owner);
    cozyManager.updateOverrideClaimFee(rewardsManager_, claimFee_);
    assertEq(cozyManager.getClaimFee(rewardsManager_), claimFee_);

    _expectEmit();
    emit ICozyManagerEvents.OverrideClaimFeeUpdated(rewardsManager_, cozyManager.claimFee());
    vm.prank(owner);
    cozyManager.resetOverrideClaimFee(rewardsManager_);
    assertEq(cozyManager.getClaimFee(rewardsManager_), cozyManager.claimFee());

    vm.prank(owner);
    cozyManager.updateClaimFee(newClaimFee_);
    assertEq(cozyManager.claimFee(), newClaimFee_);
  }

  function testFuzz_getClaimFee(uint16 claimFee_, address rewardsManagerAddress_, address otherRewardsManagerAddress_)
    public
  {
    vm.assume(rewardsManagerAddress_ != otherRewardsManagerAddress_);

    claimFee_ = uint16(bound(claimFee_, 0, MathConstants.ZOC));
    IRewardsManager rewardsManager_ = IRewardsManager(rewardsManagerAddress_);
    IRewardsManager otherRewardsManager_ = IRewardsManager(otherRewardsManagerAddress_);

    vm.prank(owner);
    cozyManager.updateOverrideClaimFee(rewardsManager_, claimFee_);

    assertEq(cozyManager.getClaimFee(rewardsManager_), claimFee_);
    assertEq(cozyManager.getClaimFee(otherRewardsManager_), cozyManager.claimFee());
  }
}

contract CozyManagerUpdateDepositFees is MockDeployProtocol, CozyManagerTestSetup {
  function test_depositFeeCorrectlyInitialized() public {
    assertEq(cozyManager.depositFee(), DEFAULT_DEPOSIT_FEE);
  }

  function test_updateDepositFee_revertNonOwnerAddress() public {
    uint16 newDepositFee_ = uint16(bound(_randomUint16(), 0, MathConstants.ZOC));

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    cozyManager.updateDepositFee(newDepositFee_);
  }

  function test_updateDepositFee_revertInvalidDepositFee() public {
    uint16 newDepositFee_ = uint16(bound(_randomUint16(), MathConstants.ZOC + 1, type(uint16).max));

    vm.expectRevert(ICozyManagerEvents.InvalidDepositFee.selector);
    vm.prank(owner);
    cozyManager.updateDepositFee(newDepositFee_);
  }

  function test_updateOverrideDepositFee_revertInvalidDepositFee() public {
    uint16 depositFee_ = uint16(bound(_randomUint16(), MathConstants.ZOC + 1, type(uint16).max));
    IRewardsManager rewardsManager_ = IRewardsManager(_randomAddress());

    vm.expectRevert(ICozyManagerEvents.InvalidDepositFee.selector);
    vm.prank(owner);
    cozyManager.updateOverrideDepositFee(rewardsManager_, depositFee_);
  }

  function test_updateOverrideDepositFee_revertNonOwnerAddress() public {
    uint16 newDepositFee_ = uint16(bound(_randomUint16(), 0, MathConstants.ZOC));
    IRewardsManager rewardsManager_ = IRewardsManager(_randomAddress());

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    cozyManager.updateOverrideDepositFee(rewardsManager_, newDepositFee_);
  }

  function test_resetOverrideFeeDripModel_revertNonOwnerAddress() public {
    IRewardsManager rewardsManager_ = IRewardsManager(_randomAddress());

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    cozyManager.resetOverrideDepositFee(rewardsManager_);
  }

  function testFuzz_updateDepositFee(uint16 depositFee_) public {
    uint16 newDepositFee_ = uint16(bound(depositFee_, 0, MathConstants.ZOC));

    _expectEmit();
    emit ICozyManagerEvents.DepositFeeUpdated(newDepositFee_);
    vm.prank(owner);
    cozyManager.updateDepositFee(newDepositFee_);

    assertEq(cozyManager.depositFee(), newDepositFee_);
  }

  function testFuzz_updateOverrideDepositFee(uint16 depositFee_, address rewardsManagerAddress_) public {
    uint16 newDepositFee_ = uint16(bound(depositFee_, 0, MathConstants.ZOC));
    IRewardsManager rewardsManager_ = IRewardsManager(rewardsManagerAddress_);

    assertEq(cozyManager.depositFee(), cozyManager.depositFee());
    assertEq(cozyManager.getDepositFee(rewardsManager_), cozyManager.depositFee());

    _expectEmit();
    emit ICozyManagerEvents.OverrideDepositFeeUpdated(rewardsManager_, newDepositFee_);
    vm.prank(owner);
    cozyManager.updateOverrideDepositFee(rewardsManager_, newDepositFee_);

    assertEq(cozyManager.getDepositFee(rewardsManager_), newDepositFee_);
  }

  function testFuzz_resetOverrideDepositFee(uint16 depositFee_, uint16 newDepositFee_, address rewardsManagerAddress_)
    public
  {
    IRewardsManager rewardsManager_ = IRewardsManager(rewardsManagerAddress_);
    depositFee_ = uint16(bound(depositFee_, 0, MathConstants.ZOC));
    newDepositFee_ = uint16(bound(newDepositFee_, 0, MathConstants.ZOC));

    vm.prank(owner);
    cozyManager.updateOverrideDepositFee(rewardsManager_, depositFee_);
    assertEq(cozyManager.getDepositFee(rewardsManager_), depositFee_);

    _expectEmit();
    emit ICozyManagerEvents.OverrideDepositFeeUpdated(rewardsManager_, cozyManager.depositFee());
    vm.prank(owner);
    cozyManager.resetOverrideDepositFee(rewardsManager_);
    assertEq(cozyManager.getDepositFee(rewardsManager_), cozyManager.depositFee());

    vm.prank(owner);
    cozyManager.updateDepositFee(newDepositFee_);
    assertEq(cozyManager.depositFee(), newDepositFee_);
  }

  function testFuzz_getDepositFee(
    uint16 depositFee_,
    address rewardsManagerAddress_,
    address otherRewardsManagerAddress_
  ) public {
    vm.assume(rewardsManagerAddress_ != otherRewardsManagerAddress_);

    depositFee_ = uint16(bound(depositFee_, 0, MathConstants.ZOC));
    IRewardsManager rewardsManager_ = IRewardsManager(rewardsManagerAddress_);
    IRewardsManager otherRewardsManager_ = IRewardsManager(otherRewardsManagerAddress_);

    vm.prank(owner);
    cozyManager.updateOverrideDepositFee(rewardsManager_, depositFee_);

    assertEq(cozyManager.getDepositFee(rewardsManager_), depositFee_);
    assertEq(cozyManager.getDepositFee(otherRewardsManager_), cozyManager.depositFee());
  }
}

contract CozyManagerTestDeploy is MockDeployProtocol {
  function test_governableOwnable() public {
    assertEq(cozyManager.owner(), owner);
    assertEq(cozyManager.pauser(), pauser);
  }

  function test_factoryAddress() public {
    assertEq(address(cozyManager.rewardsManagerFactory()), address(rewardsManagerFactory));
  }
}

contract CozyManagerPauseTest is CozyManagerTestSetupWithRewardsManagers {
  function test_pauseRewardsManagerArrayFromOwner() public {
    vm.prank(owner);
    cozyManager.pause(rewardsManagers);

    assertEq(RewardsManagerState.PAUSED, rewardsManagerA.rewardsManagerState());
    assertEq(RewardsManagerState.PAUSED, rewardsManagerB.rewardsManagerState());
  }

  function test_pauseRewardsManagerArrayFromPauser() public {
    vm.prank(pauser);
    cozyManager.pause(rewardsManagers);

    assertEq(RewardsManagerState.PAUSED, rewardsManagerA.rewardsManagerState());
    assertEq(RewardsManagerState.PAUSED, rewardsManagerB.rewardsManagerState());
  }

  function testFuzz_pauseRewardsManagerArrayRevertsWithUnauthorized(address addr_) public {
    vm.assume(addr_ != owner && addr_ != pauser);
    vm.prank(addr_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    cozyManager.pause(rewardsManagers);

    assertEq(RewardsManagerState.ACTIVE, rewardsManagerA.rewardsManagerState());
    assertEq(RewardsManagerState.ACTIVE, rewardsManagerB.rewardsManagerState());
  }
}

contract CozyManagerUnpauseRewardsManager is CozyManagerTestSetupWithRewardsManagers {
  function setUp() public override {
    super.setUp();
    vm.prank(owner);
    cozyManager.pause(rewardsManagers);
  }

  function test_unpauseRewardsManagerArrayFromOwner() public {
    vm.prank(owner);
    cozyManager.unpause(rewardsManagers);

    assertEq(RewardsManagerState.ACTIVE, rewardsManagerA.rewardsManagerState());
    assertEq(RewardsManagerState.ACTIVE, rewardsManagerB.rewardsManagerState());
  }

  function test_unpauseRewardsManagerArrayFromPauser() public {
    vm.prank(pauser);
    vm.expectRevert(Ownable.Unauthorized.selector);
    cozyManager.unpause(rewardsManagers);

    assertEq(RewardsManagerState.PAUSED, rewardsManagerA.rewardsManagerState());
    assertEq(RewardsManagerState.PAUSED, rewardsManagerB.rewardsManagerState());
  }

  function testFuzz_unpauseRewardsManagerArrayRevertsWithUnauthorized(address addr_) public {
    vm.assume(addr_ != owner);
    vm.prank(addr_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    cozyManager.unpause(rewardsManagers);

    assertEq(RewardsManagerState.PAUSED, rewardsManagerA.rewardsManagerState());
    assertEq(RewardsManagerState.PAUSED, rewardsManagerB.rewardsManagerState());
  }
}
