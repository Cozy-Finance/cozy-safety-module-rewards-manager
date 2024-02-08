// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IRewardsManager} from "../../src/interfaces/IRewardsManager.sol";
import {IRewardsManagerFactory} from "../../src/interfaces/IRewardsManagerFactory.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {StkToken} from "../../src/StkToken.sol";
import {StakePoolConfig, RewardPoolConfig} from "../../src/lib/structs/Configs.sol";
import {RewardsManager} from "../../src/RewardsManager.sol";
import {RewardsManagerFactory} from "../../src/RewardsManagerFactory.sol";
import {IManager} from "../../src/interfaces/IManager.sol";
import {TestBase} from "../utils/TestBase.sol";

contract MockDeployer is TestBase {
  RewardsManagerFactory rewardsManagerFactory;
  ReceiptToken depositTokenLogic;
  StkToken stkTokenLogic;
  ReceiptTokenFactory receiptTokenFactory;
  IRewardsManager rewardsManagerLogic;

  address owner = address(this);
  address pauser = address(this);

  uint8 constant ALLOWED_STAKE_POOLS = 100;
  uint8 constant ALLOWED_REWARD_POOLS = 100;

  function deployMockProtocol() public virtual {
    uint256 nonce_ = vm.getNonce(address(this));
    IRewardsManager computedAddrRewardsManagerLogic_ = IRewardsManager(vm.computeCreateAddress(address(this), nonce_));
    IReceiptToken depositTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 2));
    IReceiptToken stkTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 3));
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(address(this), nonce_ + 4));

    rewardsManagerLogic = IRewardsManager(
      address(
        new RewardsManager(
          IManager(_randomAddress()), computedAddrReceiptTokenFactory_, ALLOWED_STAKE_POOLS, ALLOWED_REWARD_POOLS
        )
      )
    );
    rewardsManagerLogic.initialize(owner, pauser, new StakePoolConfig[](0), new RewardPoolConfig[](0));
    rewardsManagerFactory = new RewardsManagerFactory(computedAddrRewardsManagerLogic_);

    depositTokenLogic = new ReceiptToken();
    stkTokenLogic = new StkToken();
    depositTokenLogic.initialize(address(0), "", "", 0);
    stkTokenLogic.initialize(address(0), "", "", 0);
    receiptTokenFactory = new ReceiptTokenFactory(depositTokenLogic_, stkTokenLogic_);
  }
}

contract MockDeployProtocol is MockDeployer {
  function setUp() public virtual {
    deployMockProtocol();
  }
}
