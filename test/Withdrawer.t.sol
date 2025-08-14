// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-libs/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ICozyManager} from "../src/interfaces/ICozyManager.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {Withdrawer} from "../src/lib/Withdrawer.sol";
import {RewardMathLib} from "../src/lib/RewardMathLib.sol";
import {AssetPool, StakePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {StakePoolConfig, RewardPoolConfig} from "../src/lib/structs/Configs.sol";
import {DepositorRewardsData} from "../src/lib/structs/Rewards.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {TestBase} from "./utils/TestBase.sol";

contract FlexibleMockDripModel is IDripModel {
  uint256 public nextDripFactor;

  function setNextDripFactor(uint256 dripFactor_) external {
    nextDripFactor = dripFactor_;
  }

  function dripFactor(uint256 lastDripTime_, uint256 /* initialAmount_ */ ) external view override returns (uint256) {
    if (block.timestamp <= lastDripTime_) return 0;
    return nextDripFactor;
  }
}

contract WithdrawerTest is TestBase, MockDeployProtocol {
  using FixedPointMathLib for uint256;

  MockERC20 rewardAsset;
  MockERC20 stakeAsset;
  FlexibleMockDripModel flexibleDripModel;
  RewardsManager rewardsManager;

  event Withdrawn(address indexed depositor_, uint16 indexed rewardPoolId_, uint256 amount_, address receiver_);

  uint256 constant WAD = 1e18;
  uint256 constant HALF_WAD = 0.5e18;
  uint16 constant DEFAULT_REWARD_POOL_ID = 0;
  uint16 constant DEFAULT_STAKE_POOL_ID = 0;

  function setUp() public override {
    super.setUp();

    // Create assets
    rewardAsset = new MockERC20("Reward Asset", "REWARD", 18);
    stakeAsset = new MockERC20("Stake Asset", "STAKE", 18);

    // Create flexible drip model
    flexibleDripModel = new FlexibleMockDripModel();

    // Deploy rewards manager with initial config
    StakePoolConfig[] memory stakePoolConfigs = new StakePoolConfig[](1);
    stakePoolConfigs[0] =
      StakePoolConfig({asset: IERC20(address(stakeAsset)), rewardsWeight: uint16(MathConstants.ZOC)});

    RewardPoolConfig[] memory rewardPoolConfigs = new RewardPoolConfig[](1);
    rewardPoolConfigs[0] =
      RewardPoolConfig({asset: IERC20(address(rewardAsset)), dripModel: IDripModel(address(flexibleDripModel))});

    rewardsManager = RewardsManager(
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

  // Basic Withdrawal Flow Tests

  function test_withdrawal_singleDepositNoWithdraw() public {
    address depositor = address(0x1);
    uint256 depositAmount = 100e18;

    _depositRewardAssets(depositor, depositAmount);

    // Check withdrawable balance
    uint256 withdrawable = rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor);
    assertEq(withdrawable, depositAmount, "Should be able to withdraw full amount");

    // Verify reward pool state
    RewardPool memory pool = _getRewardPool(DEFAULT_REWARD_POOL_ID);
    assertEq(pool.undrippedRewards, depositAmount, "Pool should have full deposit");
    assertEq(pool.epoch, 0, "Epoch should be 0");
    assertEq(pool.logIndexSnapshot, 0, "Log index should be 0");
  }

  function test_withdrawal_singleDepositFullWithdraw() public {
    address depositor = address(0x1);
    uint256 depositAmount = 100e18;

    _depositRewardAssets(depositor, depositAmount);

    // Check withdrawable balance
    uint256 withdrawable = rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor);
    assertEq(withdrawable, depositAmount, "Should be able to withdraw full amount");

    // Check user rewards asset balance
    uint256 depositorBalanceBeforeWithdrawal = rewardAsset.balanceOf(depositor);
    assertEq(depositorBalanceBeforeWithdrawal, 0, "Depositor should have fully deposited rewards");

    // Withdraw full amount
    vm.prank(depositor);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, depositAmount, depositor);

    // Verify balances
    assertEq(rewardAsset.balanceOf(depositor), depositAmount, "Depositor should get full amount");
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor),
      0,
      "Depositor should have no balance left"
    );

    // Verify pool state
    RewardPool memory pool = _getRewardPool(DEFAULT_REWARD_POOL_ID);
    assertEq(pool.undrippedRewards, 0, "Pool should be empty");
  }

  function test_withdrawal_depositDrip50Withdraw() public {
    address depositor = address(0x1);
    uint256 depositAmount = 100e18;

    _depositRewardAssets(depositor, depositAmount);

    // Check user balance before withdrawal
    uint256 depositorBalanceBeforeWithdrawal = rewardAsset.balanceOf(depositor);
    assertEq(depositorBalanceBeforeWithdrawal, 0, "Depositor shouldn't have deposited rewards");

    // Perform 50% drip
    _performDrip(HALF_WAD);

    // Check withdrawable balance (should be 50% of original)
    uint256 withdrawable = rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor);
    assertEq(withdrawable, 50e18, "Should have 50% remaining after 50% drip");

    // Withdraw remaining
    vm.prank(depositor);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, 50e18, depositor);

    assertEq(rewardAsset.balanceOf(depositor), 50e18, "Depositor should get 50%");
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor),
      0,
      "Depositor should have no balance left"
    );
  }

  function test_withdrawal_depositDrip100Withdraw() public {
    address depositor = address(0x1);
    uint256 depositAmount = 100e18;

    _depositRewardAssets(depositor, depositAmount);

    // Perform 100% drip
    _performDrip(WAD);

    // Check user balance before withdrawal
    uint256 depositorBalanceBeforeWithdrawal = rewardAsset.balanceOf(depositor);
    assertEq(depositorBalanceBeforeWithdrawal, 0, "Depositor shouldn't have deposited rewards");

    // Check withdrawable balance (should be 0)
    uint256 withdrawable = rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor);
    assertEq(withdrawable, 0, "Should have nothing after 100% drip");

    // Try to withdraw (should revert)
    vm.prank(depositor);
    vm.expectRevert(Withdrawer.InvalidWithdraw.selector);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, 1, depositor);

    // Verify pool state
    RewardPool memory pool = _getRewardPool(DEFAULT_REWARD_POOL_ID);
    assertEq(pool.epoch, 1, "Epoch should increment after 100% drip");
    assertEq(pool.logIndexSnapshot, 0, "Log index should reset after 100% drip");
  }

  function test_withdrawal_multipleDripsCompound() public {
    address depositor = address(0x1);
    uint256 depositAmount = 1000e18;

    _depositRewardAssets(depositor, depositAmount);

    // Perform multiple drips: 10%, 20%, 30%
    // Retention factors: 0.9, 0.8, 0.7
    // Compound retention: 0.9 * 0.8 * 0.7 = 0.504
    _performDrip(0.1e18); // 10% drip, 90% retention
    _performDrip(0.2e18); // 20% drip, 80% retention
    _performDrip(0.3e18); // 30% drip, 70% retention

    uint256 withdrawable = rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor);
    assertApproxEqRel(withdrawable, 504e18, 1e15, "Should have 50.4% remaining after compound drips");
  }

  // Epoch Transition Tests

  function test_withdrawal_epochTransitionBasic() public {
    address depositor1 = address(0x1);
    address depositor2 = address(0x2);
    uint256 depositAmount = 100e18;

    // Depositor 1 deposits before epoch transition
    _depositRewardAssets(depositor1, depositAmount);

    // Verify initial state
    RewardPool memory poolBefore = _getRewardPool(DEFAULT_REWARD_POOL_ID);
    assertEq(poolBefore.epoch, 0, "Should start at epoch 0");

    // Perform 100% drip (epoch transition)
    _performDrip(WAD);

    // Verify epoch incremented
    RewardPool memory poolAfter = _getRewardPool(DEFAULT_REWARD_POOL_ID);
    assertEq(poolAfter.epoch, 1, "Epoch should increment to 1");
    assertEq(poolAfter.logIndexSnapshot, 0, "Log index should reset to 0");

    // Depositor 1 should have no balance
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor1),
      0,
      "Old epoch depositor should have 0 balance"
    );

    // Depositor 2 deposits in new epoch
    _depositRewardAssets(depositor2, depositAmount);
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor2),
      depositAmount,
      "New epoch depositor should have full balance"
    );

    // Depositor 1 still has 0
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor1),
      0,
      "Old epoch depositor should still have 0"
    );
  }

  function test_withdrawal_multipleEpochTransitions() public {
    address depositor = address(0x1);
    uint256 depositAmount = 100e18;

    // Deposit in epoch 0
    _depositRewardAssets(depositor, depositAmount);
    assertEq(_getRewardPool(DEFAULT_REWARD_POOL_ID).epoch, 0, "Should be epoch 0");

    // First 100% drip -> epoch 1
    _performDrip(WAD);
    assertEq(_getRewardPool(DEFAULT_REWARD_POOL_ID).epoch, 1, "Should be epoch 1");
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor),
      0,
      "Should have 0 balance after epoch change"
    );

    // Deposit in epoch 1
    _depositRewardAssets(depositor, depositAmount);
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor),
      depositAmount,
      "Should have full balance in new epoch"
    );

    // Second 100% drip -> epoch 2
    _performDrip(WAD);
    assertEq(_getRewardPool(DEFAULT_REWARD_POOL_ID).epoch, 2, "Should be epoch 2");
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor),
      0,
      "Should have 0 balance after second epoch change"
    );
  }

  function test_withdrawal_epochTransitionWithPartialDrips() public {
    address depositor = address(0x1);
    uint256 depositAmount = 1000e18;

    // Deposit in epoch 0
    _depositRewardAssets(depositor, depositAmount);

    // Partial drips in same epoch
    _performDrip(0.1e18); // 10% drip
    _performDrip(0.2e18); // 20% drip

    uint256 balanceBeforeEpoch = rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor);
    assertGt(balanceBeforeEpoch, 0, "Should have balance before epoch transition");

    // 100% drip -> new epoch
    _performDrip(WAD);

    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor),
      0,
      "Should have 0 after epoch transition"
    );
    assertEq(_getRewardPool(DEFAULT_REWARD_POOL_ID).epoch, 1, "Should be in new epoch");

    // New deposit in new epoch works normally
    _depositRewardAssets(depositor, depositAmount);
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, depositor),
      depositAmount,
      "New deposit should work in new epoch"
    );
  }

  function test_withdrawal_oldEpochDepositorCannotStealFromNewEpoch() public {
    address oldDepositor = address(0x1);
    address newDepositor = address(0x2);
    uint256 depositAmount = 100e18;

    // Old depositor in epoch 0
    _depositRewardAssets(oldDepositor, depositAmount);

    // Epoch transition
    _performDrip(WAD);

    // New depositor in epoch 1
    _depositRewardAssets(newDepositor, depositAmount * 2);

    // Old depositor tries to withdraw
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, oldDepositor), 0, "Old depositor should have 0"
    );

    vm.prank(oldDepositor);
    vm.expectRevert(Withdrawer.InvalidWithdraw.selector);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, 1, oldDepositor);

    // New depositor can withdraw their full amount
    assertEq(
      rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, newDepositor),
      depositAmount * 2,
      "New depositor should have full amount"
    );
  }

  // Complex Scenario Test

  function test_withdrawal_complexScenarioWithAllElements() public {
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    // Epoch 0: Initial deposits
    _depositRewardAssets(alice, 1000e18);
    _depositRewardAssets(bob, 500e18);

    // Verify initial balances
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, alice), 1000e18);
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, bob), 500e18);

    // First partial drip: 10%
    _performDrip(0.1e18);

    // Alice: 1000 * 0.9 = 900
    // Bob: 500 * 0.9 = 450
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, alice), 900e18, 1e16);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, bob), 450e18, 1e16);

    // Charlie joins with deposit
    _depositRewardAssets(charlie, 300e18);
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, charlie), 300e18);

    // Second partial drip: 20%
    _performDrip(0.2e18);

    // Alice: 900 * 0.8 = 720
    // Bob: 450 * 0.8 = 360
    // Charlie: 300 * 0.8 = 240
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, alice), 720e18, 1e16);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, bob), 360e18, 1e16);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, charlie), 240e18, 1e16);

    // Alice makes partial withdrawal
    vm.prank(alice);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, 200e18, alice);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, alice), 520e18, 1e16);
    assertEq(rewardAsset.balanceOf(alice), 200e18);

    // Bob adds more deposits
    _depositRewardAssets(bob, 100e18);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, bob), 460e18, 1e16); // 360 + 100

    // Third partial drip: 25%
    _performDrip(0.25e18);

    // Alice: 520 * 0.75 = 390
    // Bob: 460 * 0.75 = 345
    // Charlie: 240 * 0.75 = 180
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, alice), 390e18, 1e16);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, bob), 345e18, 1e16);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, charlie), 180e18, 1e16);

    // 100% drip - Epoch transition
    _performDrip(WAD);

    // All balances should be 0 in new epoch
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, alice), 0);
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, bob), 0);
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, charlie), 0);

    // Verify epoch changed
    assertEq(_getRewardPool(DEFAULT_REWARD_POOL_ID).epoch, 1, "Should be in epoch 1");

    // Epoch 1: New deposits
    _depositRewardAssets(alice, 200e18);
    _depositRewardAssets(charlie, 400e18);

    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, alice), 200e18);
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, bob), 0); // Bob didn't deposit in new epoch
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, charlie), 400e18);

    // Partial drip in new epoch: 30%
    _performDrip(0.3e18);

    // Alice: 200 * 0.7 = 140
    // Bob: still 0
    // Charlie: 400 * 0.7 = 280
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, alice), 140e18, 1e16);
    assertEq(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, bob), 0);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, charlie), 280e18, 1e16);

    // Charlie withdraws everything
    uint256 charlieBalance = rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, charlie);
    vm.prank(charlie);
    rewardsManager.withdrawRewardAssets(DEFAULT_REWARD_POOL_ID, charlieBalance, charlie);
    assertApproxEqAbs(rewardsManager.getWithdrawableBalance(DEFAULT_REWARD_POOL_ID, charlie), 0, 1e4);
    assertApproxEqAbs(rewardAsset.balanceOf(charlie), 280e18, 1e16);

    // Final state
    // Alice has 140e18 withdrawable + 200e18 already withdrawn = 340e18 total value extracted
    // Bob has 0 withdrawable (lost funds in epoch transition)
    // Charlie has 0 withdrawable + 280e18 withdrawn = 280e18 total value extracted

    RewardPool memory finalPool = _getRewardPool(DEFAULT_REWARD_POOL_ID);
    assertEq(finalPool.epoch, 1, "Should still be in epoch 1");
    assertGt(finalPool.logIndexSnapshot, 0, "Log index should have accumulated");
  }

  // Helper Functions

  function _depositRewardAssets(address depositor_, uint256 amount_) internal {
    // Mint and approve tokens
    rewardAsset.mint(depositor_, amount_);

    vm.prank(depositor_);
    rewardAsset.approve(address(rewardsManager), amount_);

    // Deposit
    vm.prank(depositor_);
    rewardsManager.depositRewardAssets(DEFAULT_REWARD_POOL_ID, amount_);
  }

  function _performDrip(uint256 dripFactor_) internal {
    // Set the drip factor for next drip
    flexibleDripModel.setNextDripFactor(dripFactor_);

    // Advance time to allow drip
    vm.warp(block.timestamp + 1);

    // Trigger drip
    rewardsManager.dripRewardPool(DEFAULT_REWARD_POOL_ID);
  }

  function _getRewardPool(uint16 poolId_) internal view returns (RewardPool memory) {
    (
      uint256 undrippedRewards,
      uint256 cumulativeDrippedRewards,
      uint128 lastDripTime,
      IERC20 asset,
      IDripModel dripModel,
      uint32 epoch,
      uint256 logIndexSnapshot
    ) = rewardsManager.rewardPools(poolId_);

    return RewardPool({
      undrippedRewards: undrippedRewards,
      cumulativeDrippedRewards: cumulativeDrippedRewards,
      lastDripTime: lastDripTime,
      asset: asset,
      dripModel: dripModel,
      epoch: epoch,
      logIndexSnapshot: logIndexSnapshot
    });
  }
}
