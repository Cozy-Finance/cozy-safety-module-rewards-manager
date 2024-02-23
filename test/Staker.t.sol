// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IDepositorErrors} from "../src/interfaces/IDepositorErrors.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {Staker} from "../src/lib/Staker.sol";
import {RewardsDistributor} from "../src/lib/RewardsDistributor.sol";
import {RewardsManagerInspector} from "../src/lib/RewardsManagerInspector.sol";
import {RewardsManagerState} from "../src/lib/RewardsManagerStates.sol";
import {AssetPool, StakePool} from "../src/lib/structs/Pools.sol";
import {RewardPool} from "../src/lib/structs/Pools.sol";
import {ClaimableRewardsData} from "../src/lib/structs/Rewards.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";
import "forge-std/console2.sol";

contract StakerUnitTest is TestBase {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);
  MockERC20 mockStakeAsset = new MockERC20("Mock Stake Asset", "MOCK Stake", 6);
  MockERC20 mockStkReceiptToken = new MockERC20("Mock Cozy Stake Receipt Token", "cozyStk", 6);
  MockERC20 mockDepositReceiptToken = new MockERC20("Mock Cozy Deposit Receipt Token", "cozyDep", 6);
  TestableStaker component = new TestableStaker();
  uint256 cumulativeDrippedRewards_ = 290e18;
  uint256 cumulativeClaimedRewards_ = 90e18;
  uint256 initialIndexSnapshot_ = 11;

  event Staked(
    address indexed caller_,
    address indexed receiver_,
    uint16 indexed stakePoolId_,
    IReceiptToken stkReceiptToken_,
    uint256 assetAmount_
  );

  event Unstaked(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint16 indexed stakePoolId_,
    IReceiptToken stkReceiptToken_,
    uint256 stkReceiptTokenAmount_
  );

  event Transfer(address indexed from, address indexed to, uint256 amount);

  uint256 initialStakeAmount = 100e18;

  function setUp() public {
    StakePool memory initialStakePool_ = StakePool({
      asset: IReceiptToken(address(mockStakeAsset)),
      stkReceiptToken: IReceiptToken(address(mockStkReceiptToken)),
      amount: initialStakeAmount,
      rewardsWeight: 1e4
    });
    AssetPool memory initialAssetPool_ = AssetPool({amount: initialStakeAmount});
    component.mockAddStakePool(initialStakePool_);
    component.mockAddAssetPool(IERC20(address(mockStakeAsset)), initialAssetPool_);

    component.mockAddRewardPool(IERC20(address(mockAsset)), cumulativeDrippedRewards_);
    AssetPool memory initialRewardsPool_ = AssetPool({amount: cumulativeDrippedRewards_});
    component.mockAddAssetPool(IERC20(address(mockAsset)), initialRewardsPool_);
    mockAsset.mint(address(component), cumulativeDrippedRewards_);
    component.mockSetClaimableRewardsData(0, 0, initialIndexSnapshot_, cumulativeClaimedRewards_);

    deal(address(mockStakeAsset), address(component), initialStakeAmount);
    mockStkReceiptToken.mint(address(0), initialStakeAmount);
  }

  function _overrideSetUpToZeroStkReceiptTokenSupply() internal {
    component.mockSetStakeAmount(0);
    component.mockSetAssetPoolAmount(0);
    deal(address(mockStakeAsset), address(component), 0);
    vm.mockCall(address(mockStkReceiptToken), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(0));
  }

  function test_stake_StkReceiptTokensAndStorageUpdates_NonZeroSupply() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial safety module receipt token balance for staker.
    mockStakeAsset.mint(staker_, amountToStake_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockStakeAsset.approve(address(component), amountToStake_);

    _expectEmit();
    emit Staked(staker_, receiver_, 0, IReceiptToken(address(mockStkReceiptToken)), amountToStake_);

    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);

    StakePool memory finalStakePool_ = component.getStakePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);

    // 100e18 + 20e18
    assertEq(finalStakePool_.amount, amountToStake_ + initialStakeAmount);
    assertEq(finalAssetPool_.amount, amountToStake_ + initialStakeAmount);
    assertEq(mockStakeAsset.balanceOf(address(component)), amountToStake_ + initialStakeAmount);

    // Because `stkReceiptToken.totalSupply() > 0`, the index snapshot and cumulative claimed rewards should change.
    // Since this updates before the user is minted stkReceiptTokens, the `stkReceiptToken.totalSupply() ==
    // initialStakeAmount`.
    assertEq(
      finalClaimableRewardsData_.indexSnapshot,
      initialIndexSnapshot_
        + uint256(cumulativeDrippedRewards_ - cumulativeClaimedRewards_).divWadDown(initialStakeAmount)
    );
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeDrippedRewards_);

    assertEq(mockStakeAsset.balanceOf(staker_), 0);
    assertEq(mockStkReceiptToken.balanceOf(receiver_), amountToStake_);
  }

  function test_stake_StkReceiptTokensAndStorageUpdates_ZeroSupply() external {
    _overrideSetUpToZeroStkReceiptTokenSupply();

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial safety module receipt token balance for staker.
    mockStakeAsset.mint(staker_, amountToStake_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockStakeAsset.approve(address(component), amountToStake_);

    _expectEmit();
    emit Staked(staker_, receiver_, 0, IReceiptToken(address(mockStkReceiptToken)), amountToStake_);

    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);

    StakePool memory finalStakePool_ = component.getStakePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);

    assertEq(finalStakePool_.amount, amountToStake_);
    assertEq(finalAssetPool_.amount, amountToStake_);
    assertEq(mockStakeAsset.balanceOf(address(component)), amountToStake_);

    // Because `stkReceiptToken.totalSupply() == 0` when the user stakes, the index snapshot and cumulative claimed
    // rewards
    // should not change.
    assertEq(finalClaimableRewardsData_.indexSnapshot, initialIndexSnapshot_);
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeClaimedRewards_);
    assertEq(mockStakeAsset.balanceOf(staker_), 0);
    assertEq(mockStkReceiptToken.balanceOf(receiver_), amountToStake_);
  }

  function test_stake_RevertWhenPaused() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    uint256 amountToStake_ = 20e18;
    // Mint initial safety module receipt token balance for staker.
    mockStakeAsset.mint(staker_, amountToStake_);

    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockStakeAsset.approve(address(component), amountToStake_);

    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);
  }

  function test_stake_RevertOutOfBoundsStakePoolId() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    vm.prank(staker_);
    component.stake(1, 10e18, receiver_, staker_);
  }

  function testFuzz_stake_RevertInsufficientAssetsAvailable(uint256 amountToStake_) external {
    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint insufficient safety module receipt tokens for staker.
    mockStakeAsset.mint(staker_, amountToStake_ - 1);
    // Approve rewards manager to spend safety module receipt tokens.
    vm.prank(staker_);
    mockStakeAsset.approve(address(component), amountToStake_);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);
  }

  function test_stakeWithoutTransfer_StkReceiptTokensAndStorageUpdates_NonZeroSupply() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial balance for staker.
    mockStakeAsset.mint(staker_, amountToStake_);
    // Transfer to rewards manager.
    vm.prank(staker_);
    mockStakeAsset.transfer(address(component), amountToStake_);

    _expectEmit();
    emit Staked(staker_, receiver_, 0, IReceiptToken(address(mockStkReceiptToken)), amountToStake_);

    vm.prank(staker_);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);

    StakePool memory finalStakePool_ = component.getStakePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    // 100e18 + 20e18
    assertEq(finalStakePool_.amount, amountToStake_ + initialStakeAmount);
    assertEq(finalAssetPool_.amount, amountToStake_ + initialStakeAmount);
    assertEq(mockStakeAsset.balanceOf(address(component)), amountToStake_ + initialStakeAmount);

    assertEq(mockStakeAsset.balanceOf(staker_), 0);
    assertEq(mockStkReceiptToken.balanceOf(receiver_), amountToStake_);
  }

  function test_stakeWithoutTransfer_StkReceiptTokensAndStorageUpdates_ZeroSupply() external {
    _overrideSetUpToZeroStkReceiptTokenSupply();

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial safety module receipt token balance for staker.
    mockStakeAsset.mint(staker_, amountToStake_);
    // Transfer to rewards manager.
    vm.prank(staker_);
    mockStakeAsset.transfer(address(component), amountToStake_);

    _expectEmit();
    emit Staked(staker_, receiver_, 0, IReceiptToken(address(mockStkReceiptToken)), amountToStake_);

    vm.prank(staker_);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);

    StakePool memory finalStakePool_ = component.getStakePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);

    assertEq(finalStakePool_.amount, amountToStake_);
    assertEq(finalAssetPool_.amount, amountToStake_);
    assertEq(mockStakeAsset.balanceOf(address(component)), amountToStake_);

    // Because `stkReceiptToken.totalSupply() == 0` when the user stakes, the index snapshot and cumulative claimed
    // rewards
    // should not change.
    assertEq(finalClaimableRewardsData_.indexSnapshot, initialIndexSnapshot_);
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeClaimedRewards_);
    assertEq(mockStakeAsset.balanceOf(staker_), 0);
    assertEq(mockStkReceiptToken.balanceOf(receiver_), amountToStake_);
  }

  function test_stakeWithoutTransfer_RevertWhenPaused() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint initial safety module receipt token balance for rewards manager.
    mockStakeAsset.mint(address(component), 150e18);

    uint256 amountToStake_ = 20e18;
    // Mint initial safety module receipt token balance for staker.
    mockStakeAsset.mint(staker_, amountToStake_);

    // Transfer to rewards manager.
    vm.prank(staker_);
    mockStakeAsset.transfer(address(component), amountToStake_);

    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(staker_);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);
  }

  function test_stakeWithoutTransfer_RevertOutOfBoundsStakePoolId() external {
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    component.stakeWithoutTransfer(1, 10e18, receiver_);
  }

  function testFuzz_stakeWithoutTransfer_RevertInsufficientAssetsAvailable(uint256 amountToStake_) external {
    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint safety module receipt tokens for staker.
    mockStakeAsset.mint(staker_, amountToStake_);
    // Transfer insufficient safety module receipt tokens to safety module.
    vm.prank(staker_);
    mockStakeAsset.transfer(address(component), amountToStake_ - 1);

    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    vm.prank(staker_);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);
  }

  function test_stake_RevertZeroShares() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToStake_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.AmountIsZero.selector);
    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);
  }

  function test_stakeWithoutTransfer_RevertZeroShares() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToStake_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.AmountIsZero.selector);
    vm.prank(staker_);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);
  }

  function _setupDefaultSingleUserFixture()
    internal
    returns (address staker_, address receiver_, uint256 amountStaked_)
  {
    staker_ = _randomAddress();
    receiver_ = _randomAddress();
    amountStaked_ = 20e18;

    // Mint initial safety module receipt token balance for staker.
    mockStakeAsset.mint(staker_, amountStaked_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockStakeAsset.approve(address(component), amountStaked_);

    _expectEmit();
    emit Staked(staker_, receiver_, 0, IReceiptToken(address(mockStkReceiptToken)), amountStaked_);

    vm.prank(staker_);
    component.stake(0, amountStaked_, receiver_, staker_);
  }

  function test_unstake_unstakeAll() public {
    (, address receiver_, uint256 amountStaked_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    vm.prank(receiver_);
    mockStkReceiptToken.approve(address(component), amountStaked_);

    _expectEmit();
    emit Transfer(address(component), unstakeReceiver_, amountStaked_);
    _expectEmit();
    emit Unstaked(receiver_, unstakeReceiver_, receiver_, 0, IReceiptToken(address(mockStkReceiptToken)), amountStaked_);

    vm.prank(receiver_);
    component.unstake(0, amountStaked_, unstakeReceiver_, receiver_);

    assertEq(mockStakeAsset.balanceOf(unstakeReceiver_), amountStaked_);

    StakePool memory finalStakePool_ = component.getStakePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    // Entire supply of stkReceiptTokens was unstaked
    assertEq(finalStakePool_.amount, initialStakeAmount);
    assertEq(finalAssetPool_.amount, initialStakeAmount);
    assertEq(mockStakeAsset.balanceOf(address(component)), finalAssetPool_.amount);

    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);

    // Because `stkReceiptToken.totalSupply() > 0` before unstaking, the index snapshot and cumulative claimed rewards
    // should
    // change. Since this updates when the user stakes, `stkReceiptToken.totalSupply() == initialStakeAmount`.
    assertEq(
      finalClaimableRewardsData_.indexSnapshot,
      initialIndexSnapshot_
        + uint256(cumulativeDrippedRewards_ - cumulativeClaimedRewards_).divWadDown(initialStakeAmount)
    );
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeDrippedRewards_);
  }

  function test_unstake_unstakePartial() public {
    (, address receiver_, uint256 amountStaked_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    StakePool memory initStakePool_ = component.getStakePool(0);
    AssetPool memory initAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    // 100e18 + 20e18
    assertEq(initStakePool_.amount, amountStaked_ + initialStakeAmount);
    assertEq(initAssetPool_.amount, amountStaked_ + initialStakeAmount);
    assertEq(mockStakeAsset.balanceOf(address(component)), amountStaked_ + initialStakeAmount);

    vm.prank(receiver_);
    mockStkReceiptToken.approve(address(component), amountStaked_);

    uint256 stkReceiptTokenAmountToUnstake_ = amountStaked_ / 2;
    _expectEmit();
    emit Transfer(address(component), unstakeReceiver_, stkReceiptTokenAmountToUnstake_);
    _expectEmit();
    emit Unstaked(
      receiver_,
      unstakeReceiver_,
      receiver_,
      0,
      IReceiptToken(address(mockStkReceiptToken)),
      stkReceiptTokenAmountToUnstake_
    );

    vm.prank(receiver_);
    component.unstake(0, stkReceiptTokenAmountToUnstake_, unstakeReceiver_, receiver_);

    assertEq(mockStakeAsset.balanceOf(unstakeReceiver_), amountStaked_ / 2);

    StakePool memory finalStakePool_ = component.getStakePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    // Half of supply was unstaked.
    assertEq(finalStakePool_.amount, initialStakeAmount + (amountStaked_ / 2));
    assertEq(finalAssetPool_.amount, initialStakeAmount + (amountStaked_ / 2));

    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);
    // Because `stkReceiptToken.totalSupply() > 0` before unstaking, the index snapshot and cumulative claimed rewards
    // should
    // change. Since this updates when the user stakes, `stkReceiptToken.totalSupply() == initialStakeAmount`.
    assertEq(
      finalClaimableRewardsData_.indexSnapshot,
      initialIndexSnapshot_
        + uint256(cumulativeDrippedRewards_ - cumulativeClaimedRewards_).divWadDown(initialStakeAmount)
    );
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeDrippedRewards_);
  }

  function test_unstake_canUnstakeTotalInMultipleUnstakes() external {
    (, address receiver_, uint256 amountStaked_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    vm.prank(receiver_);
    mockStkReceiptToken.approve(address(component), amountStaked_);

    vm.prank(receiver_);
    component.unstake(0, amountStaked_ / 2, unstakeReceiver_, receiver_);

    assertEq(mockStakeAsset.balanceOf(unstakeReceiver_), amountStaked_ / 2);

    vm.prank(receiver_);
    component.unstake(0, amountStaked_ / 2, unstakeReceiver_, receiver_);

    assertEq(mockStakeAsset.balanceOf(unstakeReceiver_), amountStaked_);

    StakePool memory finalStakePool_ = component.getStakePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    // Initial stake amount remains in the stake pool.
    assertEq(finalStakePool_.amount, initialStakeAmount);
    assertEq(finalAssetPool_.amount, initialStakeAmount);
    assertEq(mockStakeAsset.balanceOf(address(component)), finalAssetPool_.amount);
  }

  function test_unstake_whenPaused() public {
    (, address receiver_, uint256 amountStaked_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    vm.prank(receiver_);
    mockStkReceiptToken.approve(address(component), amountStaked_);

    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    // If the rewards manager is paused, no drip should occur, so the user should not receive any rewards.
    // As such, in the assertions below we do not add any of the undripped rewards.
    // Note: The drip model from setUp is a mock drip model with 100% drip per second.
    component.mockSetRewardPoolUndrippedRewards(0, 100e6);
    skip(1);

    _expectEmit();
    emit Transfer(address(component), unstakeReceiver_, amountStaked_);
    _expectEmit();
    emit Unstaked(receiver_, unstakeReceiver_, receiver_, 0, IReceiptToken(address(mockStkReceiptToken)), amountStaked_);
    vm.prank(receiver_);
    component.unstake(0, amountStaked_, unstakeReceiver_, receiver_);

    assertEq(mockStakeAsset.balanceOf(unstakeReceiver_), amountStaked_);

    StakePool memory finalStakePool_ = component.getStakePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockStakeAsset)));
    // Entire supply of stkReceiptTokens was unstaked
    assertEq(finalStakePool_.amount, initialStakeAmount);
    assertEq(finalAssetPool_.amount, initialStakeAmount);
    assertEq(mockStakeAsset.balanceOf(address(component)), finalAssetPool_.amount);

    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);

    // Because `stkReceiptToken.totalSupply() > 0` before unstaking, the index snapshot and cumulative claimed rewards
    // should
    // change. Since this updates when the user stakes, `stkReceiptToken.totalSupply() == initialStakeAmount`.
    assertEq(
      finalClaimableRewardsData_.indexSnapshot,
      initialIndexSnapshot_
        + uint256(cumulativeDrippedRewards_ - cumulativeClaimedRewards_).divWadDown(initialStakeAmount)
    );
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeDrippedRewards_);
  }

  function test_unstake_cannotUnstakeIfAmountIsZero() external {
    (, address receiver_,) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    vm.expectRevert(ICommonErrors.AmountIsZero.selector);
    vm.prank(receiver_);
    component.unstake(0, 0, unstakeReceiver_, receiver_);
  }

  function test_unstake_canUnstakeThroughAllowance() external {
    (, address receiver_, uint256 amountStaked_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();
    address spender_ = _randomAddress();

    vm.prank(receiver_);
    mockStkReceiptToken.approve(spender_, amountStaked_ + 1); // Allowance is 1 extra.

    vm.prank(spender_);
    component.unstake(0, amountStaked_, unstakeReceiver_, receiver_);

    assertEq(mockStkReceiptToken.allowance(receiver_, spender_), 1, "depositReceiptToken allowance"); // Only 1
      // allowance left
      // because
      // of subtraction.
    assertEq(mockStakeAsset.balanceOf(unstakeReceiver_), amountStaked_);
  }

  function test_unstake_cannotUnstake_ThroughAllowance_WithInsufficientAllowance() external {
    (, address receiver_, uint256 amountStaked_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();
    address spender_ = _randomAddress();

    vm.prank(receiver_);
    mockStkReceiptToken.approve(spender_, amountStaked_ - 1); // Allowance is 1 less.

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(spender_);
    component.unstake(0, amountStaked_, unstakeReceiver_, receiver_);
  }

  function test_unstake_cannotUnstake_InsufficientTokenBalance() external {
    address staker_ = _randomAddress();
    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(staker_);
    component.unstake(0, _randomUint128(), staker_, staker_);

    (, address receiver_, uint256 amountStaked_) = _setupDefaultSingleUserFixture();
    vm.prank(receiver_);
    mockStkReceiptToken.approve(address(component), amountStaked_ + 1);

    vm.prank(receiver_);
    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    component.unstake(0, amountStaked_ + 1, receiver_, receiver_);
  }

  function test_unstake_invalidStakePoolId() external {
    address staker_ = _randomAddress();
    _expectPanic(PANIC_ARRAY_OUT_OF_BOUNDS);
    vm.prank(staker_);
    component.unstake(1, _randomUint128(), staker_, staker_);
  }
}

contract TestableStaker is Staker, Depositor, RewardsDistributor, RewardsManagerInspector {
  using SafeCastLib for uint256;

  // -------- Mock setters --------

  function mockAddStakePool(StakePool memory stakePool_) external {
    stakePools.push(stakePool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockAddRewardPool(IERC20 rewardAsset_, uint256 cumulativeDrippedRewards_) external {
    rewardPools.push(
      RewardPool({
        asset: rewardAsset_,
        dripModel: IDripModel(address(new MockDripModel(1e18))),
        undrippedRewards: 0,
        depositReceiptToken: IReceiptToken(address(new MockERC20("Mock Cozy Deposit Receipt Token", "cozyDep", 6))),
        cumulativeDrippedRewards: cumulativeDrippedRewards_,
        lastDripTime: uint128(block.timestamp)
      })
    );
  }

  function mockSetClaimableRewardsData(
    uint16 stakePoolId_,
    uint16 rewardPoolid_,
    uint256 indexSnapshot_,
    uint256 cumulativeClaimedRewards_
  ) external {
    claimableRewards[stakePoolId_][rewardPoolid_] = ClaimableRewardsData({
      indexSnapshot: indexSnapshot_.safeCastTo128(),
      cumulativeClaimedRewards: cumulativeClaimedRewards_
    });
  }

  function mockSetStakeAmount(uint256 stakeAmount_) external {
    stakePools[0].amount = stakeAmount_;
  }

  function mockSetAssetPoolAmount(uint256 amount_) external {
    StakePool memory stakePool_ = stakePools[0];
    assetPools[stakePool_.asset].amount = amount_;
  }

  function mockSetRewardsManagerState(RewardsManagerState state_) external {
    rewardsManagerState = state_;
  }

  function mockSetRewardPoolUndrippedRewards(uint16 rewardPoolId_, uint256 undrippedRewards_) external {
    rewardPools[rewardPoolId_].undrippedRewards = undrippedRewards_;
  }

  // -------- Mock getters --------
  function getStakePool(uint16 stakePoolId_) external view returns (StakePool memory) {
    return stakePools[stakePoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  function getClaimableRewardsData(uint16 stakePoolId_, uint16 rewardPoolid_)
    external
    view
    returns (ClaimableRewardsData memory)
  {
    return claimableRewards[stakePoolId_][rewardPoolid_];
  }
}
