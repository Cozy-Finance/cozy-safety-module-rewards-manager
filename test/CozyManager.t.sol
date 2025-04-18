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
