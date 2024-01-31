// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {StkToken} from "../src/StkToken.sol";
import {ReservePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {RewardPoolConfig} from "../src/lib/structs/Rewards.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {RewardsManagerFactory} from "../src/RewardsManagerFactory.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockSafetyModule} from "./utils/MockSafetyModule.sol";
import {TestBase} from "./utils/TestBase.sol";

contract RewardsManagerFactoryTest is TestBase {
  RewardsManager rewardsManagerLogic;
  RewardsManagerFactory rewardsManagerFactory;

  ReceiptToken safetyModuleReceiptTokenLogic;
  StkToken stkTokenLogic;
  IReceiptTokenFactory receiptTokenFactory;

  IManager mockManager = IManager(_randomAddress());

  /// @dev Emitted when a new Rewards Manager is deployed.
  event RewardsManagerDeployed(IRewardsManager rewardsManager, ISafetyModule safetyModule);

  function setUp() public {
    safetyModuleReceiptTokenLogic = new ReceiptToken();
    stkTokenLogic = new StkToken();

    safetyModuleReceiptTokenLogic.initialize(address(0), "", "", 0);
    stkTokenLogic.initialize(address(0), "", "", 0);

    receiptTokenFactory = new ReceiptTokenFactory(
      IReceiptToken(address(safetyModuleReceiptTokenLogic)), IReceiptToken(address(stkTokenLogic))
    );

    rewardsManagerLogic = new RewardsManager(mockManager, receiptTokenFactory);
    rewardsManagerLogic.initialize(
      address(0),
      address(0),
      address(new MockSafetyModule(SafetyModuleState.ACTIVE)),
      new RewardPoolConfig[](0),
      new uint16[](0)
    );

    rewardsManagerFactory = new RewardsManagerFactory(mockManager, IRewardsManager(address(rewardsManagerLogic)));
  }

  function test_deployRewardsManagerFactory() public {
    assertEq(address(rewardsManagerFactory.cozyManager()), address(mockManager));
    assertEq(address(rewardsManagerFactory.rewardsManagerLogic()), address(rewardsManagerLogic));
  }

  function test_revertDeployRewardsManagerFactoryZeroAddressParams() public {
    vm.expectRevert(RewardsManagerFactory.InvalidAddress.selector);
    new RewardsManagerFactory(mockManager, IRewardsManager(address(0)));

    vm.expectRevert(RewardsManagerFactory.InvalidAddress.selector);
    new RewardsManagerFactory(IManager(address(0)), IRewardsManager(address(rewardsManagerLogic)));

    vm.expectRevert(RewardsManagerFactory.InvalidAddress.selector);
    new RewardsManagerFactory(IManager(address(0)), IRewardsManager(address(0)));
  }

  function test_deployRewardsManager() public {
    address owner_ = _randomAddress();
    address pauser_ = _randomAddress();
    IERC20 asset_ = IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6)));

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: asset_, dripModel: IDripModel(address(_randomAddress()))});

    uint16[] memory rewardsWeights_ = new uint16[](1);
    rewardsWeights_[0] = uint16(MathConstants.ZOC);

    MockSafetyModule safetyModule_ = new MockSafetyModule(SafetyModuleState.ACTIVE);
    safetyModule_.setNumReservePools(1);
    IReceiptToken safetyModuleReceiptToken_ = IReceiptToken(address(new ReceiptToken()));
    safetyModule_.setReservePoolReceiptToken(0, safetyModuleReceiptToken_);

    bytes32 baseSalt_ = _randomBytes32();
    address computedRewardsManagerAddress_ = rewardsManagerFactory.computeAddress(baseSalt_);

    _expectEmit();
    emit RewardsManagerDeployed(IRewardsManager(computedRewardsManagerAddress_), ISafetyModule(address(safetyModule_)));
    vm.prank(address(mockManager));
    IRewardsManager rewardsManager_ = rewardsManagerFactory.deployRewardsManager(
      owner_, pauser_, address(safetyModule_), rewardPoolConfigs_, rewardsWeights_, baseSalt_
    );

    assertEq(address(rewardsManager_), computedRewardsManagerAddress_);
    assertEq(address(rewardsManager_.cozyManager()), address(mockManager));
    assertEq(address(rewardsManager_.receiptTokenFactory()), address(receiptTokenFactory));
    assertEq(address(rewardsManager_.owner()), owner_);
    assertEq(address(rewardsManager_.pauser()), pauser_);

    // Loosely validate config applied.
    RewardPool memory rewardPool_ = getRewardPool(rewardsManager_, 0);
    assertEq(address(rewardPool_.asset), address(asset_));
    assertEq(address(rewardPool_.dripModel), address(rewardPoolConfigs_[0].dripModel));

    ReservePool memory reservePool_ = getReservePool(rewardsManager_, 0);
    assertEq(address(reservePool_.safetyModuleReceiptToken), address(safetyModuleReceiptToken_));
    assertEq(reservePool_.rewardsWeight, rewardsWeights_[0]);
  }

  function test_revertDeployRewardsManagerNotCozyManager() public {
    address caller_ = _randomAddress();

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({
      asset: IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6))),
      dripModel: IDripModel(address(_randomAddress()))
    });
    uint16[] memory rewardsWeights_ = new uint16[](1);

    bytes32 baseSalt_ = _randomBytes32();

    vm.expectRevert(RewardsManagerFactory.Unauthorized.selector);
    vm.prank(caller_);
    rewardsManagerFactory.deployRewardsManager(
      _randomAddress(), _randomAddress(), _randomAddress(), rewardPoolConfigs_, rewardsWeights_, baseSalt_
    );
  }
}
