// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IWithdrawerEvents} from "../src/interfaces/IWithdrawerEvents.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {AssetPool, StakePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {StakePoolConfig, RewardPoolConfig} from "../src/lib/structs/Configs.sol";
import {DepositorRewardsData} from "../src/lib/structs/Rewards.sol";
import {RewardsMathLib} from "../src/lib/RewardsMathLib.sol";
import {RewardsManagerState} from "../src/lib/RewardsManagerStates.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {RewardsManagerCommon} from "../src/lib/RewardsManagerCommon.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockDripModelFlexible} from "./utils/MockDripModelFlexible.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {TestBase} from "./utils/TestBase.sol";
import {MockERC1271Signer} from "./utils/MockERC1271Signer.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract WithdrawerTest is TestBase, MockDeployProtocol {
  using FixedPointMathLib for uint256;

  MockERC20 rewardAsset;
  MockDripModelFlexible flexibleDripModel;
  IRewardsManager rewardsManager;

  uint256 constant WAD = 1e18;
  uint16 constant DEFAULT_REWARD_POOL_ID = 0;
  uint16 constant DEFAULT_STAKE_POOL_ID = 0;

  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  function setUp() public override {
    super.setUp();

    rewardAsset = new MockERC20("Reward Asset", "REWARD", 18);
    flexibleDripModel = new MockDripModelFlexible();

    StakePoolConfig[] memory stakePoolConfigs = new StakePoolConfig[](1);
    stakePoolConfigs[0] = StakePoolConfig({
      asset: IERC20(address(new MockERC20("Stake Asset", "STAKE", 18))),
      rewardsWeight: uint16(MathConstants.ZOC)
    });

    RewardPoolConfig[] memory rewardPoolConfigs = new RewardPoolConfig[](1);
    rewardPoolConfigs[0] =
      RewardPoolConfig({asset: IERC20(address(rewardAsset)), dripModel: IDripModel(address(flexibleDripModel))});

    rewardsManager = IRewardsManager(
      address(
        cozyManager.createRewardsManager(
          owner,
          pauser,
          stakePoolConfigs,
          rewardPoolConfigs,
          bytes32(0) // salt
        )
      )
    );

    // Set deposit fee to 0 for simpler testing
    vm.prank(owner);
    cozyManager.updateDepositFee(0);
  }

  function _depositRewardAssets(address depositor_, uint256 amount_) internal {
    rewardAsset.mint(depositor_, amount_);

    vm.startPrank(depositor_);
    rewardAsset.approve(address(rewardsManager), amount_);
    rewardsManager.depositRewardAssets(DEFAULT_REWARD_POOL_ID, amount_);
    vm.stopPrank();
  }

  function _performDrip(uint256 dripFactor_) internal {
    flexibleDripModel.setNextDripFactor(dripFactor_);
    vm.warp(block.timestamp + 1);
    rewardsManager.dripRewardPool(DEFAULT_REWARD_POOL_ID);
  }

  function _buildWithdrawDigest(
    address owner_,
    uint16 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address caller_,
    address receiver_,
    uint256 deadline_
  ) internal view returns (bytes32) {
    bytes32 typeHash_ = RewardsManager(address(rewardsManager)).WITHDRAW_REWARD_ASSETS_BY_SIG_TYPEHASH();
    uint256 nonce_ = rewardsManager.eip712Nonces(owner_, typeHash_);
    bytes32 structHash_ =
      keccak256(abi.encode(typeHash_, owner_, rewardPoolId_, rewardAssetAmount_, caller_, receiver_, deadline_, nonce_));

    string memory domainName_ = rewardsManager.eip712DomainName();
    string memory domainVersion_ = Strings.toString(uint256(rewardsManager.eip712DomainVersion()));

    bytes32 domainSeparator_ = keccak256(
      abi.encode(
        EIP712_DOMAIN_TYPEHASH,
        keccak256(bytes(domainName_)),
        keccak256(bytes(domainVersion_)),
        block.chainid,
        address(rewardsManager)
      )
    );

    return keccak256(abi.encodePacked("\x19\x01", domainSeparator_, structHash_));
  }

  function test_depositNoWithdraw() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = bound(_randomUint256(), 1, type(uint64).max);

    _depositRewardAssets(depositor_, depositAmount_);

    uint256 withdrawableRewards_ = rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_);
    assertEq(withdrawableRewards_, depositAmount_, "Should be able to withdraw full amount");

    RewardPool memory pool_ = getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID);
    assertEq(pool_.undrippedRewards, depositAmount_, "Pool should have full deposit");
    assertEq(pool_.epoch, 0, "Epoch should be 0");
    assertEq(pool_.logIndexSnapshot, 0, "Log index snapshot should be 0");
  }

  function test_depositAndWithdraw() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = bound(_randomUint256(), 1, type(uint64).max);

    _depositRewardAssets(depositor_, depositAmount_);

    assertEq(rewardAsset.balanceOf(depositor_), 0, "Depositor should have fully deposited rewards");

    _expectEmit();
    emit IWithdrawerEvents.Withdrawn(depositor_, DEFAULT_REWARD_POOL_ID, depositAmount_, depositor_);
    vm.prank(depositor_);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, depositAmount_, depositor_);

    assertEq(rewardAsset.balanceOf(depositor_), depositAmount_, "Depositor should get full amount");
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      0,
      "Depositor should have no withdrawable rewards"
    );

    RewardPool memory pool_ = getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID);
    assertEq(pool_.undrippedRewards, 0, "Pool should be empty");
    assertEq(pool_.epoch, 0, "Epoch should be 0");
    assertEq(pool_.logIndexSnapshot, 0, "Log index snapshot should be 0");
    assertEq(rewardsManager.assetPools(IERC20(address(rewardAsset))).amount, 0, "Asset pool should be empty");
  }

  function test_depositDripWithdraw() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = 100e18;

    _depositRewardAssets(depositor_, depositAmount_);

    assertEq(rewardAsset.balanceOf(depositor_), 0, "Depositor shouldn't have deposited rewards");

    _performDrip(0.5e18);

    // Check withdrawable rewards (should be 50% of original, up to rounding down)
    uint256 withdrawableRewards_ = rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_);
    assertLe(withdrawableRewards_, 50e18);
    assertApproxEqRel(withdrawableRewards_, 50e18, 1e15, "Should have 50% remaining after 50% drip");

    _expectEmit();
    emit IWithdrawerEvents.Withdrawn(depositor_, DEFAULT_REWARD_POOL_ID, withdrawableRewards_, depositor_);
    vm.prank(depositor_);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, withdrawableRewards_, depositor_);

    assertEq(rewardAsset.balanceOf(depositor_), withdrawableRewards_, "Depositor should get 50%");
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      0,
      "Depositor should have no balance left"
    );
    assertEq(
      rewardsManager.assetPools(IERC20(address(rewardAsset))).amount,
      depositAmount_ - withdrawableRewards_,
      "Asset pool should be empty"
    );
  }

  function test_depositFullDripWithdraw() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = bound(_randomUint256(), 1, type(uint64).max);

    _depositRewardAssets(depositor_, depositAmount_);

    // Perform 100% drip
    _performDrip(WAD);

    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      0,
      "Should have nothing after 100% drip"
    );

    vm.prank(depositor_);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, 1, depositor_);

    RewardPool memory pool = getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID);
    assertEq(pool.epoch, 1, "Epoch should increment after 100% drip");
    assertEq(pool.logIndexSnapshot, 0, "Log index should reset after 100% drip");
    assertEq(pool.undrippedRewards, 0, "Undripped rewards should be 0");
    assertEq(
      rewardsManager.assetPools(IERC20(address(rewardAsset))).amount,
      depositAmount_,
      "Asset pool should contain all assets"
    );
  }

  function test_withdrawAutoDrips() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = 100e18;

    _depositRewardAssets(depositor_, depositAmount_);

    uint256 warpTime_ = block.timestamp + 1;
    vm.warp(warpTime_);

    // Set up a 50% drip but do not manually drip before withdrawal.
    flexibleDripModel.setNextDripFactor(0.5e18);

    // Withdrawable rewards should still reflect the full deposit before withdrawing.
    uint256 expectedWithdraw_ = depositAmount_.mulWadDown(MathConstants.WAD - 0.5e18);
    uint256 expectedDrippedRewards_ = depositAmount_.mulWadDown(0.5e18);
    assertApproxEqRel(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      expectedWithdraw_,
      0.001e18,
      "Withdrawable should not change before auto drip"
    );

    uint256 previewWithdrawable_ = rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_);

    _expectEmit();
    emit IWithdrawerEvents.Withdrawn(depositor_, DEFAULT_REWARD_POOL_ID, previewWithdrawable_, depositor_);
    vm.prank(depositor_);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, type(uint256).max, depositor_);

    assertEq(rewardAsset.balanceOf(depositor_), previewWithdrawable_);
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      0,
      "Depositor should have no withdrawable rewards"
    );

    RewardPool memory pool_ = getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID);
    assertEq(pool_.undrippedRewards, depositAmount_ - previewWithdrawable_ - expectedDrippedRewards_);
    assertEq(pool_.cumulativeDrippedRewards, expectedDrippedRewards_);
    assertEq(pool_.lastDripTime, warpTime_);
    assertGt(pool_.logIndexSnapshot, 0);
  }

  function test_withdrawZeroAmountStillDrips() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = 200e18;

    _depositRewardAssets(depositor_, depositAmount_);

    uint256 warpTime_ = block.timestamp + 1;
    vm.warp(warpTime_);
    flexibleDripModel.setNextDripFactor(0.4e18);

    vm.prank(depositor_);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, 0, depositor_);

    uint256 expectedWithdrawable_ = depositAmount_.mulWadDown(MathConstants.WAD - 0.4e18);
    uint256 expectedDrip_ = depositAmount_ - expectedWithdrawable_;

    RewardPool memory pool_ = getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID);
    assertEq(pool_.lastDripTime, uint128(warpTime_));
    assertEq(pool_.cumulativeDrippedRewards, expectedDrip_);
    assertEq(pool_.undrippedRewards, expectedWithdrawable_);
    assertEq(pool_.epoch, 0);
    assertEq(pool_.logIndexSnapshot, RewardsMathLib.negLn(MathConstants.WAD - 0.4e18));

    DepositorRewardsData memory depositorData_ =
      RewardsManager(address(rewardsManager)).getDepositorRewards(DEFAULT_REWARD_POOL_ID, depositor_);
    assertLe(depositorData_.withdrawableRewards, expectedWithdrawable_);
    assertApproxEqRel(depositorData_.withdrawableRewards, expectedWithdrawable_, 0.01e18);
    assertEq(depositorData_.logIndexSnapshot, pool_.logIndexSnapshot);
    assertEq(depositorData_.epoch, pool_.epoch);

    assertEq(rewardAsset.balanceOf(depositor_), 0);
    assertLe(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_), expectedWithdrawable_
    );
    assertApproxEqRel(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      expectedWithdrawable_,
      0.01e18
    );
    assertEq(rewardsManager.assetPools(IERC20(address(rewardAsset))).amount, depositAmount_);
  }

  function test_withdrawMultipleDripsCompound() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = 1000e18;

    _depositRewardAssets(depositor_, depositAmount_);

    // Perform multiple drips: 10%, 20%, 30%
    // Retention factors: 0.9, 0.8, 0.7
    // Compound retention: 0.9 * 0.8 * 0.7 = 0.504
    _performDrip(0.1e18); // 10% drip, 90% retention
    _performDrip(0.2e18); // 20% drip, 80% retention
    _performDrip(0.3e18); // 30% drip, 70% retention

    uint256 withdrawableRewards_ = rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_);
    assertLe(withdrawableRewards_, 504e18);
    assertApproxEqRel(withdrawableRewards_, 504e18, 1e15, "Should have 50.4% remaining after compound drips");
  }

  function test_epochTransitionSingle() public {
    address depositor1_ = address(0x1);
    address depositor2_ = address(0x2);
    uint256 depositAmount_ = bound(_randomUint256(), 1, type(uint64).max);

    // Depositor 1 deposits before epoch transition
    _depositRewardAssets(depositor1_, depositAmount_);

    // Verify initial state
    RewardPool memory poolBefore_ = getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID);
    assertEq(poolBefore_.epoch, 0, "Should start at epoch 0");

    // Perform 100% drip (epoch transition)
    _performDrip(WAD);

    // Verify epoch incremented
    RewardPool memory poolAfter_ = getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID);
    assertEq(poolAfter_.epoch, 1, "Epoch should increment to 1");
    assertEq(poolAfter_.logIndexSnapshot, 0, "Log index should reset to 0");

    // Depositor 1 should have no balance
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor1_),
      0,
      "Old epoch depositor should have 0 balance"
    );

    // Depositor 2 deposits in new epoch
    _depositRewardAssets(depositor2_, depositAmount_);
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor2_),
      depositAmount_,
      "New epoch depositor should have full balance"
    );

    // Depositor 1 still has 0
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor1_),
      0,
      "Old epoch depositor should still have 0"
    );
  }

  function test_epochTransitionMultiple() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = bound(_randomUint256(), 1, type(uint64).max);

    // Deposit in epoch 0
    _depositRewardAssets(depositor_, depositAmount_);
    assertEq(getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID).epoch, 0, "Should be epoch 0");

    // First 100% drip -> epoch 1
    _performDrip(WAD);
    assertEq(getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID).epoch, 1, "Should be epoch 1");
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      0,
      "Should have 0 balance after epoch change"
    );

    // Deposit in epoch 1
    _depositRewardAssets(depositor_, depositAmount_);
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      depositAmount_,
      "Should have full balance in new epoch"
    );

    // Second 100% drip -> epoch 2
    _performDrip(WAD);
    assertEq(getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID).epoch, 2, "Should be epoch 2");
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      0,
      "Should have 0 balance after second epoch change"
    );
  }

  function test_epochTransitionWithPartialDrips() public {
    address depositor_ = _randomAddress();
    uint256 depositAmount_ = bound(_randomUint256(), 1, type(uint64).max);

    // Deposit in epoch 0
    _depositRewardAssets(depositor_, depositAmount_);

    // Partial drips in same epoch
    _performDrip(0.1e18); // 10% drip
    _performDrip(0.2e18); // 20% drip

    assertGt(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      0,
      "Should have balance before epoch transition"
    );

    // 100% drip -> new epoch
    _performDrip(WAD);
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      0,
      "Should have 0 after epoch transition"
    );
    assertEq(getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID).epoch, 1, "Should be in new epoch");

    // New deposit in new epoch works normally
    _depositRewardAssets(depositor_, depositAmount_);
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, depositor_),
      depositAmount_,
      "New deposit should work in new epoch"
    );
  }

  function test_withdraw_complexScenario() public {
    address alice_ = address(0x1);
    address bob_ = address(0x2);
    address charlie_ = address(0x3);

    // Epoch 0: Initial deposits
    _depositRewardAssets(alice_, 1000e18);
    _depositRewardAssets(bob_, 500e18);
    assertEq(rewardsManager.assetPools(IERC20(address(rewardAsset))).amount, 1000e18 + 500e18);

    // Verify initial balances
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, alice_), 1000e18);
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, bob_), 500e18);

    // First partial drip: 10%
    _performDrip(0.1e18);

    // Alice: 1000 * 0.9 = 900
    // Bob: 500 * 0.9 = 450
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, alice_), 900e18, 1e16);
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, bob_), 450e18, 1e16);

    // Charlie joins with deposit
    _depositRewardAssets(charlie_, 300e18);
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, charlie_), 300e18);
    assertEq(rewardsManager.assetPools(IERC20(address(rewardAsset))).amount, 1000e18 + 500e18 + 300e18);

    // Second partial drip: 20%
    _performDrip(0.2e18);

    // Alice: 900 * 0.8 = 720
    // Bob: 450 * 0.8 = 360
    // Charlie: 300 * 0.8 = 240
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, alice_), 720e18, 1e16);
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, bob_), 360e18, 1e16);
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, charlie_), 240e18, 1e16);

    // Alice makes partial withdrawal
    _expectEmit();
    emit IWithdrawerEvents.Withdrawn(alice_, DEFAULT_REWARD_POOL_ID, 200e18, alice_);
    vm.prank(alice_);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, 200e18, alice_);
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, alice_), 520e18, 1e16);
    assertEq(rewardAsset.balanceOf(alice_), 200e18);
    assertEq(rewardsManager.assetPools(IERC20(address(rewardAsset))).amount, 1000e18 + 500e18 + 300e18 - 200e18);

    // Bob adds more deposits
    _depositRewardAssets(bob_, 100e18);
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, bob_), 460e18, 1e16); // 360
      // + 100
    assertEq(
      rewardsManager.assetPools(IERC20(address(rewardAsset))).amount, 1000e18 + 500e18 + 300e18 - 200e18 + 100e18
    );

    // Third partial drip: 25%
    _performDrip(0.25e18);

    // Alice: 520 * 0.75 = 390
    // Bob: 460 * 0.75 = 345
    // Charlie: 240 * 0.75 = 180
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, alice_), 390e18, 1e16);
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, bob_), 345e18, 1e16);
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, charlie_), 180e18, 1e16);

    // 100% drip - Epoch transition
    _performDrip(WAD);

    // All balances should be 0 in new epoch
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, alice_), 0);
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, bob_), 0);
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, charlie_), 0);

    // Verify epoch changed
    assertEq(getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID).epoch, 1, "Should be in epoch 1");

    // Epoch 1: New deposits
    _depositRewardAssets(alice_, 200e18);
    _depositRewardAssets(charlie_, 400e18);
    assertEq(
      rewardsManager.assetPools(IERC20(address(rewardAsset))).amount,
      1000e18 + 500e18 + 300e18 - 200e18 + 100e18 + 200e18 + 400e18
    );

    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, alice_), 200e18);
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, bob_), 0); // Bob didn't deposit
      // in new epoch
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, charlie_), 400e18);

    // Partial drip in new epoch: 30%
    _performDrip(0.3e18);

    // Alice: 200 * 0.7 = 140
    // Bob: still 0
    // Charlie: 400 * 0.7 = 280
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, alice_), 140e18, 1e16);
    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, bob_), 0);
    assertApproxEqAbs(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, charlie_), 280e18, 1e16);

    // Charlie withdraws everything
    uint256 charlieWithdrawableRewards_ =
      rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, charlie_);
    _expectEmit();
    emit IWithdrawerEvents.Withdrawn(charlie_, DEFAULT_REWARD_POOL_ID, charlieWithdrawableRewards_, charlie_);
    vm.prank(charlie_);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, charlieWithdrawableRewards_, charlie_);

    assertEq(rewardsManager.previewCurrentWithdrawableRewards(DEFAULT_REWARD_POOL_ID, charlie_), 0);
    assertApproxEqAbs(rewardAsset.balanceOf(charlie_), 280e18, 1e16);
    assertEq(
      rewardsManager.assetPools(IERC20(address(rewardAsset))).amount,
      1000e18 + 500e18 + 300e18 - 200e18 + 100e18 + 200e18 + 400e18 - charlieWithdrawableRewards_
    );

    // Final state
    // Alice has 140e18 withdrawable + 200e18 already withdrawn = 340e18 total value extracted
    // Bob has 0 withdrawable (lost funds in epoch transition)
    // Charlie has 0 withdrawable + 280e18 withdrawn = 280e18 total value extracted
    RewardPool memory finalPool = getRewardPool(rewardsManager, DEFAULT_REWARD_POOL_ID);
    assertEq(finalPool.epoch, 1, "Should still be in epoch 1");
    assertGt(finalPool.logIndexSnapshot, 0, "Log index should have accumulated");
  }

  function test_withdrawRewardAssetsBySig_validEOASignature() external {
    (address ownerEOA, uint256 ownerPK) = makeAddrAndKey("owner");
    address receiver_ = _randomAddress();
    uint16 rewardPoolId_ = DEFAULT_REWARD_POOL_ID;
    uint256 rewardAssetAmount_ = 1e18;

    _depositRewardAssets(ownerEOA, rewardAssetAmount_);

    uint256 deadline_ = block.timestamp + 1 hours;
    bytes32 digest_ =
      _buildWithdrawDigest(ownerEOA, rewardPoolId_, rewardAssetAmount_, address(this), receiver_, deadline_);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPK, digest_);
    bytes memory signature_ = abi.encodePacked(r, s, v);

    _expectEmit();
    emit IWithdrawerEvents.Withdrawn(ownerEOA, rewardPoolId_, rewardAssetAmount_, receiver_);

    rewardsManager.withdrawRewardAssetsBySig(
      rewardPoolId_, rewardAssetAmount_, ownerEOA, receiver_, deadline_, signature_
    );

    assertEq(rewardAsset.balanceOf(receiver_), rewardAssetAmount_, "receiver should receive reward assets");
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(rewardPoolId_, ownerEOA),
      0,
      "owner should have no withdrawable rewards"
    );
    assertEq(rewardsManager.assetPools(IERC20(address(rewardAsset))).amount, 0, "asset pool should be empty");
  }

  function test_withdrawRewardAssetsBySig_validContractSignature() external {
    MockERC1271Signer mockSigner_ = new MockERC1271Signer(_randomAddress());
    address owner_ = address(mockSigner_);
    address receiver_ = _randomAddress();
    uint16 rewardPoolId_ = DEFAULT_REWARD_POOL_ID;
    uint256 rewardAssetAmount_ = 5e17;

    _depositRewardAssets(owner_, rewardAssetAmount_);

    bytes32 typeHash_ = RewardsManager(address(rewardsManager)).WITHDRAW_REWARD_ASSETS_BY_SIG_TYPEHASH();
    uint256 nonceBefore_ = rewardsManager.eip712Nonces(owner_, typeHash_);
    uint256 deadline_ = block.timestamp + 1 hours;
    bytes32 digest_ =
      _buildWithdrawDigest(owner_, rewardPoolId_, rewardAssetAmount_, address(this), receiver_, deadline_);
    bytes memory signature_ = mockSigner_.signMessage(digest_);

    _expectEmit();
    emit IWithdrawerEvents.Withdrawn(owner_, rewardPoolId_, rewardAssetAmount_, receiver_);

    rewardsManager.withdrawRewardAssetsBySig(
      rewardPoolId_, rewardAssetAmount_, owner_, receiver_, deadline_, signature_
    );

    assertEq(rewardAsset.balanceOf(receiver_), rewardAssetAmount_, "receiver should receive reward assets");
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(rewardPoolId_, owner_),
      0,
      "owner should have no withdrawable rewards"
    );
    assertEq(rewardsManager.assetPools(IERC20(address(rewardAsset))).amount, 0, "asset pool should be empty");
    assertEq(rewardsManager.eip712Nonces(owner_, typeHash_), nonceBefore_ + 1, "nonce should increment");
  }

  function test_withdrawRewardAssetsBySig_invalidSignature() external {
    (address owner_,) = makeAddrAndKey("owner");
    address receiver_ = _randomAddress();
    uint16 rewardPoolId_ = DEFAULT_REWARD_POOL_ID;
    uint256 rewardAssetAmount_ = 1e18;

    _depositRewardAssets(owner_, rewardAssetAmount_);

    bytes32 typeHash_ = RewardsManager(address(rewardsManager)).WITHDRAW_REWARD_ASSETS_BY_SIG_TYPEHASH();
    uint256 nonceBefore_ = rewardsManager.eip712Nonces(owner_, typeHash_);
    uint256 deadline_ = block.timestamp + 1 hours;
    bytes memory invalidSignature_ = "0xdeadbeef";

    vm.expectRevert(RewardsManagerCommon.InvalidSignature.selector);
    rewardsManager.withdrawRewardAssetsBySig(
      rewardPoolId_, rewardAssetAmount_, owner_, receiver_, deadline_, invalidSignature_
    );

    assertEq(rewardsManager.eip712Nonces(owner_, typeHash_), nonceBefore_, "nonce should remain unchanged");
  }

  function test_withdrawRewardAssetsBySig_expiredSignature() external {
    (address owner_, uint256 ownerPK) = makeAddrAndKey("owner");
    address receiver_ = _randomAddress();
    uint16 rewardPoolId_ = DEFAULT_REWARD_POOL_ID;
    uint256 rewardAssetAmount_ = 1e18;

    _depositRewardAssets(owner_, rewardAssetAmount_);

    bytes32 typeHash_ = RewardsManager(address(rewardsManager)).WITHDRAW_REWARD_ASSETS_BY_SIG_TYPEHASH();
    uint256 nonceBefore_ = rewardsManager.eip712Nonces(owner_, typeHash_);
    uint256 deadline_ = block.timestamp - 1; // already expired
    bytes32 digest_ =
      _buildWithdrawDigest(owner_, rewardPoolId_, rewardAssetAmount_, address(this), receiver_, deadline_);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPK, digest_);
    bytes memory signature_ = abi.encodePacked(r, s, v);

    vm.expectRevert(RewardsManagerCommon.SignatureExpired.selector);
    rewardsManager.withdrawRewardAssetsBySig(
      rewardPoolId_, rewardAssetAmount_, owner_, receiver_, deadline_, signature_
    );

    assertEq(rewardsManager.eip712Nonces(owner_, typeHash_), nonceBefore_, "nonce should remain unchanged");
  }

  function test_withdrawRewardAssetsBySig_unauthorizedCaller() external {
    (address owner_, uint256 ownerPK) = makeAddrAndKey("owner");
    address receiver_ = _randomAddress();
    uint16 rewardPoolId_ = DEFAULT_REWARD_POOL_ID;
    uint256 rewardAssetAmount_ = 1e18;
    address authorizedCaller_ = _randomAddress();

    _depositRewardAssets(owner_, rewardAssetAmount_);

    bytes32 typeHash_ = RewardsManager(address(rewardsManager)).WITHDRAW_REWARD_ASSETS_BY_SIG_TYPEHASH();
    uint256 nonceBefore_ = rewardsManager.eip712Nonces(owner_, typeHash_);
    uint256 deadline_ = block.timestamp + 1 hours;
    bytes32 digest_ =
      _buildWithdrawDigest(owner_, rewardPoolId_, rewardAssetAmount_, authorizedCaller_, receiver_, deadline_);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPK, digest_);
    bytes memory signature_ = abi.encodePacked(r, s, v);

    vm.expectRevert(RewardsManagerCommon.InvalidSignature.selector);
    rewardsManager.withdrawRewardAssetsBySig(
      rewardPoolId_, rewardAssetAmount_, owner_, receiver_, deadline_, signature_
    );
    assertEq(rewardsManager.eip712Nonces(owner_, typeHash_), nonceBefore_, "nonce should remain unchanged after revert");

    _expectEmit();
    emit IWithdrawerEvents.Withdrawn(owner_, rewardPoolId_, rewardAssetAmount_, receiver_);

    vm.prank(authorizedCaller_);
    rewardsManager.withdrawRewardAssetsBySig(
      rewardPoolId_, rewardAssetAmount_, owner_, receiver_, deadline_, signature_
    );

    assertEq(rewardAsset.balanceOf(receiver_), rewardAssetAmount_, "receiver should receive reward assets");
    assertEq(
      rewardsManager.previewCurrentWithdrawableRewards(rewardPoolId_, owner_),
      0,
      "owner should have no withdrawable rewards"
    );
    assertEq(rewardsManager.eip712Nonces(owner_, typeHash_), nonceBefore_ + 1, "nonce should increment on success");
  }
}
