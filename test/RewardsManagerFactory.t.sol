// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {IConfiguratorErrors} from "../src/interfaces/IConfiguratorErrors.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {StkToken} from "../src/StkToken.sol";
import {StakePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {StakePoolConfig, RewardPoolConfig} from "../src/lib/structs/Configs.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {RewardsManagerFactory} from "../src/RewardsManagerFactory.sol";
import {ICozyManager} from "../src/interfaces/ICozyManager.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {TestBase} from "./utils/TestBase.sol";

contract RewardsManagerFactoryTest is TestBase {
  RewardsManager rewardsManagerLogic;
  RewardsManagerFactory rewardsManagerFactory;

  ReceiptToken safetyModuleReceiptTokenLogic;
  StkToken stkTokenLogic;
  IReceiptTokenFactory receiptTokenFactory;

  ICozyManager cozyManager = ICozyManager(_randomAddress());

  /// @dev Emitted when a new Rewards Manager is deployed.
  event RewardsManagerDeployed(IRewardsManager rewardsManager);

  function setUp() public {
    safetyModuleReceiptTokenLogic = new ReceiptToken();
    stkTokenLogic = new StkToken();

    safetyModuleReceiptTokenLogic.initialize(address(0), "", "", 0);
    stkTokenLogic.initialize(address(0), "", "", 0);

    receiptTokenFactory = new ReceiptTokenFactory(
      IReceiptToken(address(safetyModuleReceiptTokenLogic)), IReceiptToken(address(stkTokenLogic))
    );

    rewardsManagerLogic = new RewardsManager(cozyManager, receiptTokenFactory, 30, 25);
    rewardsManagerLogic.initialize(address(0), address(0), new StakePoolConfig[](0), new RewardPoolConfig[](0));

    rewardsManagerFactory = new RewardsManagerFactory(cozyManager, IRewardsManager(address(rewardsManagerLogic)));
  }

  function test_deployRewardsManagerFactory() public {
    assertEq(address(rewardsManagerFactory.rewardsManagerLogic()), address(rewardsManagerLogic));
  }

  function test_revertDeployRewardsManagerFactoryZeroAddressParams() public {
    vm.expectRevert(RewardsManagerFactory.InvalidAddress.selector);
    new RewardsManagerFactory(cozyManager, IRewardsManager(address(0)));
  }

  function test_deployRewardsManager() public {
    address owner_ = _randomAddress();
    address pauser_ = _randomAddress();
    IERC20 asset_ = IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6)));

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](1);
    stakePoolConfigs_[0] = StakePoolConfig({asset: asset_, rewardsWeight: uint16(MathConstants.ZOC)});
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: asset_, dripModel: IDripModel(address(_randomAddress()))});

    uint16[] memory rewardsWeights_ = new uint16[](1);
    rewardsWeights_[0] = uint16(MathConstants.ZOC);

    bytes32 baseSalt_ = _randomBytes32();
    address computedRewardsManagerAddress_ = rewardsManagerFactory.computeAddress(baseSalt_);

    _expectEmit();
    emit RewardsManagerDeployed(IRewardsManager(computedRewardsManagerAddress_));
    vm.prank(address(cozyManager));
    IRewardsManager rewardsManager_ =
      rewardsManagerFactory.deployRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, baseSalt_);

    assertEq(address(rewardsManager_), computedRewardsManagerAddress_);
    assertEq(address(rewardsManager_.receiptTokenFactory()), address(receiptTokenFactory));
    assertEq(address(rewardsManager_.owner()), owner_);
    assertEq(address(rewardsManager_.pauser()), pauser_);

    // Loosely validate config applied.
    RewardPool memory rewardPool_ = getRewardPool(rewardsManager_, 0);
    assertEq(address(rewardPool_.asset), address(asset_));
    assertEq(address(rewardPool_.dripModel), address(rewardPoolConfigs_[0].dripModel));

    StakePool memory stakePool_ = getStakePool(rewardsManager_, 0);
    assertEq(address(stakePool_.asset), address(asset_));
    assertEq(stakePool_.rewardsWeight, rewardsWeights_[0]);

    // Cannot call initialize again on the rewards manager.
    vm.expectRevert(RewardsManager.Initialized.selector);
    rewardsManager_.initialize(_randomAddress(), _randomAddress(), stakePoolConfigs_, rewardPoolConfigs_);
  }

  function test_deployRewardsManager_invalidConfiguration() public {
    address owner_ = _randomAddress();
    address pauser_ = _randomAddress();
    IERC20 asset_ = IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6)));

    // Invalid configuration, rewards weight must sum to zoc.
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](1);
    stakePoolConfigs_[0] = StakePoolConfig({asset: asset_, rewardsWeight: 1});
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: asset_, dripModel: IDripModel(address(_randomAddress()))});

    bytes32 baseSalt_ = _randomBytes32();

    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    vm.prank(address(cozyManager));
    rewardsManagerFactory.deployRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, baseSalt_);
  }
}
