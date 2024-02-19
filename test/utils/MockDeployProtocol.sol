// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IRewardsManager} from "../../src/interfaces/IRewardsManager.sol";
import {IRewardsManagerFactory} from "../../src/interfaces/IRewardsManagerFactory.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {CozyManager} from "../../src/CozyManager.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {StkReceiptToken} from "../../src/StkReceiptToken.sol";
import {StakePoolConfig, RewardPoolConfig} from "../../src/lib/structs/Configs.sol";
import {RewardsManager} from "../../src/RewardsManager.sol";
import {RewardsManagerFactory} from "../../src/RewardsManagerFactory.sol";
import {ICozyManager} from "../../src/interfaces/ICozyManager.sol";
import {TestBase} from "../utils/TestBase.sol";

contract MockDeployer is TestBase {
  RewardsManagerFactory rewardsManagerFactory;
  ReceiptToken depositReceiptTokenLogic;
  StkReceiptToken stkReceiptTokenLogic;
  ReceiptTokenFactory receiptTokenFactory;
  IRewardsManager rewardsManagerLogic;
  ICozyManager cozyManager;

  address owner = address(this);
  address pauser = address(0xBEEF);

  uint8 constant ALLOWED_STAKE_POOLS = 100;
  uint8 constant ALLOWED_REWARD_POOLS = 100;

  function deployMockProtocol() public virtual {
    uint256 nonce_ = vm.getNonce(address(this));
    IRewardsManager computedAddrRewardsManagerLogic_ = IRewardsManager(vm.computeCreateAddress(address(this), nonce_));
    IReceiptToken depositReceiptTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 2));
    IReceiptToken stkReceiptTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 3));
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(address(this), nonce_ + 4));
    ICozyManager computedAddrCozyManager_ = ICozyManager(vm.computeCreateAddress(address(this), nonce_ + 5));

    rewardsManagerLogic = IRewardsManager(
      address(
        new RewardsManager(
          ICozyManager(computedAddrCozyManager_),
          computedAddrReceiptTokenFactory_,
          ALLOWED_STAKE_POOLS,
          ALLOWED_REWARD_POOLS
        )
      )
    );
    rewardsManagerLogic.initialize(owner, pauser, new StakePoolConfig[](0), new RewardPoolConfig[](0));
    rewardsManagerFactory = new RewardsManagerFactory(computedAddrCozyManager_, computedAddrRewardsManagerLogic_);

    depositReceiptTokenLogic = new ReceiptToken();
    stkReceiptTokenLogic = new StkReceiptToken();
    depositReceiptTokenLogic.initialize(address(0), "", "", 0);
    stkReceiptTokenLogic.initialize(address(0), "", "", 0);
    receiptTokenFactory = new ReceiptTokenFactory(depositReceiptTokenLogic_, stkReceiptTokenLogic_);
    cozyManager = new CozyManager(owner, pauser, rewardsManagerFactory);
  }
}

contract MockDeployProtocol is MockDeployer {
  function setUp() public virtual {
    deployMockProtocol();
  }
}
