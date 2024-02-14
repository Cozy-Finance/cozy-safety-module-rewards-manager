// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";
import {CozyManager} from "../src/CozyManager.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {RewardsManagerFactory} from "../src/RewardsManagerFactory.sol";
import {StkToken} from "../src/StkToken.sol";
import {StakePoolConfig, RewardPoolConfig} from "../src/lib/structs/Configs.sol";
import {ICozyManager} from "../src/interfaces/ICozyManager.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {IRewardsManagerFactory} from "../src/interfaces/IRewardsManagerFactory.sol";

/**
 * @dev Deploy procedure is below. Numbers in parenthesis represent the transaction count which can be used
 * to infer the nonce of that deploy.
 *   1. Pre-compute addresses.
 *   2. Deploy the protocol:
 *        1. (0)  Deploy: Manager
 *        2. (1)  Deploy: RewardsManager logic
 *        3. (2)  Transaction: RewardsManager logic initialization
 *        4. (3)  Deploy: RewardsManagerFactory
 *        5. (4)  Deploy: DepositToken logic
 *        6. (5)  Transaction: DepositToken logic initialization
 *        7. (6)  Deploy: StkToken logic
 *        8. (7)  Transaction: StkToken logic initialization
 *        9. (8)  Deploy: ReceiptTokenFactory
 *
 * To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $OPTIMISM_RPC_URL
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/DeployProtocol.s.sol \
 *   --sig "run(string)" "deploy-protocol-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv
 *
 * # Or, to broadcast transactions.
 * forge script script/DeployProtocol.s.sol \
 *   --sig "run(string)" "deploy-protocol-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --private-key $OWNER_PRIVATE_KEY \
 *   --broadcast \
 *   -vvvv
 * ```
 */
contract DeployProtocol is ScriptUtils {
  using stdJson for string;

  // Owner and pauser are configured per-network.
  address owner;
  address pauser;

  // Global restrictions on the number of reserve and reward pools.
  uint8 allowedStakePools;
  uint8 allowedRewardPools;

  // Core contracts to deploy.
  CozyManager manager;
  RewardsManager rewardsManagerLogic;
  RewardsManagerFactory rewardsManagerFactory;
  ReceiptToken depositTokenLogic;
  StkToken stkTokenLogic;
  ReceiptTokenFactory receiptTokenFactory;

  function run(string memory fileName_) public virtual {
    // -------------------------------
    // -------- Configuration --------
    // -------------------------------

    // -------- Load json --------
    string memory json_ = readInput(fileName_);

    // -------- Authentication --------
    owner = json_.readAddress(".owner");
    pauser = json_.readAddress(".pauser");

    // -------- Pool Limits --------
    allowedStakePools = uint8(json_.readUint(".allowedStakePools"));
    allowedRewardPools = uint8(json_.readUint(".allowedRewardPools"));

    // -------------------------------------
    // -------- Address Computation --------
    // -------------------------------------

    uint256 nonce_ = vm.getNonce(msg.sender);
    ICozyManager computedAddrManager_ = ICozyManager(vm.computeCreateAddress(msg.sender, nonce_));
    IRewardsManager computedAddrRewardsManagerLogic_ = IRewardsManager(vm.computeCreateAddress(msg.sender, nonce_ + 1));
    // nonce + 2 is initialization of the RewardsManager logic.
    IRewardsManagerFactory computedAddrRewardsManagerFactory_ =
      IRewardsManagerFactory(vm.computeCreateAddress(msg.sender, nonce_ + 3));
    IReceiptToken computedAddrDepositTokenLogic_ = IReceiptToken(vm.computeCreateAddress(msg.sender, nonce_ + 4));
    // nonce + 5 is initialization of the DepositToken logic.
    IReceiptToken computedAddrStkTokenLogic_ = IReceiptToken(vm.computeCreateAddress(msg.sender, nonce_ + 6));
    // nonce + 7 is initialization of the StkToken logic.
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(msg.sender, nonce_ + 8));

    // ------------------------------------------
    // -------- Core Protocol Deployment --------
    // ------------------------------------------

    // -------- Deploy: CozyManager --------
    vm.broadcast();
    manager = new CozyManager(owner, pauser, computedAddrRewardsManagerFactory_);
    console2.log("CozyManager deployed:", address(manager));
    require(address(manager) == address(computedAddrManager_), "CozyManager address mismatch");

    // -------- Deploy: RewardsManager Logic --------
    vm.broadcast();
    rewardsManagerLogic =
      new RewardsManager(computedAddrManager_, computedAddrReceiptTokenFactory_, allowedStakePools, allowedRewardPools);
    console2.log("RewardsManager logic deployed:", address(rewardsManagerLogic));
    require(
      address(rewardsManagerLogic) == address(computedAddrRewardsManagerLogic_), "RewardsManager logic address mismatch"
    );

    vm.broadcast();
    rewardsManagerLogic.initialize(address(0), address(0), new StakePoolConfig[](0), new RewardPoolConfig[](0));

    // -------- Deploy: RewardsManagerFactory --------
    vm.broadcast();
    rewardsManagerFactory = new RewardsManagerFactory(computedAddrManager_, computedAddrRewardsManagerLogic_);
    console2.log("RewardsManagerFactory deployed:", address(rewardsManagerFactory));
    require(
      address(rewardsManagerFactory) == address(computedAddrRewardsManagerFactory_),
      "RewardsManagerFactory address mismatch"
    );

    // -------- Deploy: DepositToken Logic --------
    vm.broadcast();
    depositTokenLogic = new ReceiptToken();
    console2.log("DepositToken logic deployed:", address(depositTokenLogic));
    require(
      address(depositTokenLogic) == address(computedAddrDepositTokenLogic_), "DepositToken logic address mismatch"
    );

    vm.broadcast();
    depositTokenLogic.initialize(address(0), "", "", 0);

    // -------- Deploy: StkToken Logic --------
    vm.broadcast();
    stkTokenLogic = new StkToken();
    console2.log("StkToken logic deployed:", address(stkTokenLogic));
    require(address(stkTokenLogic) == address(computedAddrStkTokenLogic_), "StkToken logic address mismatch");

    vm.broadcast();
    stkTokenLogic.initialize(address(0), "", "", 0);

    // -------- Deploy: ReceiptTokenFactory --------
    vm.broadcast();
    receiptTokenFactory = new ReceiptTokenFactory(computedAddrDepositTokenLogic_, computedAddrStkTokenLogic_);
    console2.log("ReceiptTokenFactory deployed:", address(receiptTokenFactory));
    require(
      address(receiptTokenFactory) == address(computedAddrReceiptTokenFactory_), "ReceiptTokenFactory address mismatch"
    );
  }
}
