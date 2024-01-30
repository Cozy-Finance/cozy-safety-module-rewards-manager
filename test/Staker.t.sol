// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IDepositorErrors} from "../src/interfaces/IDepositorErrors.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {Staker} from "../src/lib/Staker.sol";
import {RewardsDistributor} from "../src/lib/RewardsDistributor.sol";
import {AssetPool, ReservePool} from "../src/lib/structs/Pools.sol";
import {RewardPool} from "../src/lib/structs/Pools.sol";
import {ClaimableRewardsData} from "../src/lib/structs/Rewards.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockSafetyModule} from "./utils/MockSafetyModule.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";
import "forge-std/console2.sol";

contract StakerUnitTest is TestBase {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);
  MockERC20 mockSafetyModuleReceiptToken = new MockERC20("Mock Asset", "MOCK", 6);
  MockERC20 mockStkToken = new MockERC20("Mock Cozy Stake Token", "cozyStk", 6);
  MockERC20 mockDepositToken = new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6);
  MockSafetyModule mockSafetyModule = new MockSafetyModule(SafetyModuleState.ACTIVE);
  TestableStaker component = new TestableStaker(mockSafetyModule);
  uint256 cumulativeDrippedRewards_ = 290e18;
  uint256 cumulativeClaimedRewards_ = 90e18;
  uint256 initialIndexSnapshot_ = 11;

  event Staked(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed stkToken_,
    uint256 amount_,
    uint256 stkTokenAmount_
  );

  /// @dev Emitted when a user unstakes.
  event Unstaked(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed stkReceiptToken_,
    uint256 stkReceiptTokenAmount_,
    uint256 safetyModuleReceiptTokenAmount_
  );

  event Transfer(address indexed from, address indexed to, uint256 amount);

  uint256 initialSafetyModuleBal = 150e18;
  uint256 initialStakeAmount = 100e18;

  function setUp() public {
    ReservePool memory initialReservePool_ = ReservePool({
      safetyModuleReceiptToken: IReceiptToken(address(mockSafetyModuleReceiptToken)),
      stkReceiptToken: IReceiptToken(address(mockStkToken)),
      amount: 100e18,
      rewardsWeight: 1e4
    });
    AssetPool memory initialAssetPool_ = AssetPool({amount: 150e18});
    component.mockAddReservePool(initialReservePool_);
    component.mockAddAssetPool(IERC20(address(mockSafetyModuleReceiptToken)), initialAssetPool_);

    component.mockAddRewardPool(IERC20(address(mockAsset)), cumulativeDrippedRewards_);
    AssetPool memory initialRewardsPool_ = AssetPool({amount: cumulativeDrippedRewards_});
    component.mockAddAssetPool(IERC20(address(mockAsset)), initialRewardsPool_);
    mockAsset.mint(address(component), cumulativeDrippedRewards_);
    component.mockSetClaimableRewardsData(0, 0, initialIndexSnapshot_, cumulativeClaimedRewards_);

    deal(address(mockSafetyModuleReceiptToken), address(component), initialSafetyModuleBal);
  }

  function test_stake_StkTokensAndStorageUpdates() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial safety module receipt token balance for rewards manager.
    mockSafetyModuleReceiptToken.mint(address(component), 150e18);
    // Mint initial safety module receipt token balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountToStake_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.approve(address(component), amountToStake_);

    // `stkToken.totalSupply() == 0`, so should be minted 1-1 with safety module receipt tokens staked.
    uint256 expectedStkTokenAmount_ = 20e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountToStake_, expectedStkTokenAmount_);

    vm.prank(staker_);
    uint256 stkTokenAmount_ = component.stake(0, amountToStake_, receiver_, staker_);

    assertEq(stkTokenAmount_, expectedStkTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockSafetyModuleReceiptToken)));
    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);

    // 100e18 + 20e18
    assertEq(finalReservePool_.amount, 120e18);
    // 150e18 + 20e18
    assertEq(finalAssetPool_.amount, 170e18);
    assertEq(mockSafetyModuleReceiptToken.balanceOf(address(component)), 170e18 + initialSafetyModuleBal);

    // Because `stkToken.totalSupply() == 0`, the index snapshot and cumulative claimed rewards should not have change.
    assertEq(finalClaimableRewardsData_.indexSnapshot, initialIndexSnapshot_);
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeClaimedRewards_);

    assertEq(mockSafetyModuleReceiptToken.balanceOf(staker_), 0);
    assertEq(mockStkToken.balanceOf(receiver_), expectedStkTokenAmount_);
  }

  function test_stake_StkTokensAndStorageUpdatesNonZeroSupply() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial safety module receipt token balance for rewards manager.
    mockSafetyModuleReceiptToken.mint(address(component), 150e18);
    // Mint initial safety module receipt token balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountToStake_);
    // Mint/burn some stkTokens.
    uint256 initialStkTokenSupply_ = 50e18;
    mockStkToken.mint(address(0), initialStkTokenSupply_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.approve(address(component), amountToStake_);

    // `stkToken.totalSupply() == 50e18`, so we have (20e18 / 100e18) * 50e18 = 10e18.
    uint256 expectedStkTokenAmount_ = 10e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountToStake_, expectedStkTokenAmount_);

    vm.prank(staker_);
    uint256 stkTokenAmount_ = component.stake(0, amountToStake_, receiver_, staker_);

    assertEq(stkTokenAmount_, expectedStkTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockSafetyModuleReceiptToken)));
    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);

    // 100e18 + 20e18
    assertEq(finalReservePool_.amount, 120e18);
    // 150e18 + 20e18
    assertEq(finalAssetPool_.amount, 170e18);
    assertEq(mockSafetyModuleReceiptToken.balanceOf(address(component)), 170e18 + initialSafetyModuleBal);

    // Because `stkToken.totalSupply() > 0`, the index snapshot and cumulative claimed rewards should change.
    // Since this updates before the user is minted stkTokens, the `stkToken.totalSupply() == initialStkTokenSupply_`.
    assertEq(
      finalClaimableRewardsData_.indexSnapshot,
      initialIndexSnapshot_
        + uint256(cumulativeDrippedRewards_ - cumulativeClaimedRewards_).divWadDown(initialStkTokenSupply_)
    );
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeDrippedRewards_);

    assertEq(mockSafetyModuleReceiptToken.balanceOf(staker_), 0);
    assertEq(mockStkToken.balanceOf(receiver_), expectedStkTokenAmount_);
  }

  function testFuzz_stake_RevertSafetyModulePaused(uint256 amountToStake_) external {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    // Mint initial safety module receipt token balance for rewards manager.
    mockSafetyModuleReceiptToken.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountToStake_);
    // Mint/burn some stkTokens.
    uint256 initialStkTokenSupply_ = 50e18;
    mockStkToken.mint(address(0), initialStkTokenSupply_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.approve(address(component), amountToStake_);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);
  }

  function test_stake_RevertOutOfBoundsReservePoolId() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    vm.prank(staker_);
    component.stake(1, 10e18, receiver_, staker_);
  }

  function testFuzz_stake_RevertInsufficientAssetsAvailable(uint256 amountToStake_) external {
    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint insufficient safety module receipt tokens for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountToStake_ - 1);
    // Approve rewards manager to spend safety module receipt tokens.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.approve(address(component), amountToStake_);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);
  }

  function test_stakeWithoutTransfer_StkTokensAndStorageUpdates() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial safety module receipt token balance for rewards manager.
    mockSafetyModuleReceiptToken.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountToStake_);
    // Transfer to rewards manager.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.transfer(address(component), amountToStake_);

    // `stkToken.totalSupply() == 0`, so should be minted 1-1 with safety module receipt tokens staked.
    uint256 expectedStkTokenAmount_ = 20e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountToStake_, expectedStkTokenAmount_);

    vm.prank(staker_);
    uint256 stkTokenAmount_ = component.stakeWithoutTransfer(0, amountToStake_, receiver_);

    assertEq(stkTokenAmount_, expectedStkTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockSafetyModuleReceiptToken)));
    // 100e18 + 20e18
    assertEq(finalReservePool_.amount, 120e18);
    // 150e18 + 20e18
    assertEq(finalAssetPool_.amount, 170e18);
    assertEq(mockSafetyModuleReceiptToken.balanceOf(address(component)), 170e18 + initialSafetyModuleBal);

    assertEq(mockSafetyModuleReceiptToken.balanceOf(staker_), 0);
    assertEq(mockStkToken.balanceOf(receiver_), expectedStkTokenAmount_);
  }

  function test_stakeWithoutTransfer_StkTokensAndStorageUpdatesNonZeroSupply() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial safety module receipt token balance for rewards manager.
    mockSafetyModuleReceiptToken.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountToStake_);
    // Mint/burn some stkTokens.
    uint256 initialStkTokenSupply_ = 50e18;
    mockStkToken.mint(address(0), initialStkTokenSupply_);
    // Transfer to rewards manager.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.transfer(address(component), amountToStake_);

    // `stkToken.totalSupply() == 50e18`, so we have (20e18 / 100e18) * 50e18 = 10e18.
    uint256 expectedStkTokenAmount_ = 10e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountToStake_, expectedStkTokenAmount_);

    vm.prank(staker_);
    uint256 stkTokenAmount_ = component.stakeWithoutTransfer(0, amountToStake_, receiver_);

    assertEq(stkTokenAmount_, expectedStkTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockSafetyModuleReceiptToken)));
    // 100e18 + 20e18
    assertEq(finalReservePool_.amount, 120e18);
    // 150e18 + 20e18
    assertEq(finalAssetPool_.amount, 170e18);
    assertEq(mockSafetyModuleReceiptToken.balanceOf(address(component)), 170e18 + initialSafetyModuleBal);

    assertEq(mockSafetyModuleReceiptToken.balanceOf(staker_), 0);
    assertEq(mockStkToken.balanceOf(receiver_), expectedStkTokenAmount_);
  }

  function test_stakeWithoutTransfer_RevertSafetyModulePaused() external {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);

    uint256 amountToStake_ = 150e18;

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint initial safety module receipt token balance for rewards manager.
    mockSafetyModuleReceiptToken.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountToStake_);
    // Mint/burn some stkTokens.
    uint256 initialStkTokenSupply_ = 50e18;
    mockStkToken.mint(address(0), initialStkTokenSupply_);
    // Transfer to rewards manager.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.transfer(address(component), amountToStake_);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);
  }

  function test_stakeWithoutTransfer_RevertOutOfBoundsReservePoolId() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    component.stakeWithoutTransfer(1, 10e18, receiver_);
  }

  function testFuzz_stakeWithoutTransfer_RevertInsufficientAssetsAvailable(uint256 amountToStake_) external {
    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Set initial safety module receipt token balance for rewards manager.
    deal(address(mockSafetyModuleReceiptToken), address(component), 150e18);
    // Mint safety module receipt tokens for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountToStake_);
    // Transfer insufficient safety module receipt tokens to safety module.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.transfer(address(component), amountToStake_ - 1);

    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    vm.prank(staker_);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);
  }

  function test_stake_RevertZeroShares() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToStake_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);
  }

  function test_stakeWithoutTransfer_RevertZeroShares() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToStake_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(staker_);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);
  }

  function _setupDefaultSingleUserFixture()
    internal
    returns (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmountReceived_)
  {
    staker_ = _randomAddress();
    receiver_ = _randomAddress();
    amountStaked_ = 20e18;

    // Mint initial safety module receipt token balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountStaked_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.approve(address(component), amountStaked_);

    // `stkToken.totalSupply() == 0`, so should be minted 1-1 with safety module receipt tokens staked.
    uint256 expectedStkTokenAmount_ = 20e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountStaked_, expectedStkTokenAmount_);

    vm.prank(staker_);
    stkTokenAmountReceived_ = component.stake(0, amountStaked_, receiver_, staker_);
    assertEq(amountStaked_, expectedStkTokenAmount_); // 1:1 exchange rate for initial stake.
  }

  function test_unstake_unstakeAll() public {
    (, address receiver_, uint256 amountStaked_, uint256 stkTokenAmountReceived_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    vm.prank(receiver_);
    mockStkToken.approve(address(component), stkTokenAmountReceived_);

    _expectEmit();
    emit Transfer(address(component), unstakeReceiver_, amountStaked_ + initialStakeAmount);
    _expectEmit();
    emit Unstaked(
      receiver_,
      unstakeReceiver_,
      receiver_,
      IReceiptToken(address(mockStkToken)),
      stkTokenAmountReceived_,
      amountStaked_ + initialStakeAmount
    );

    // receiver_ owns the entire supply of stake receipt tokens.
    uint256 stkTokenSupplyBeforeUnstake_ = component.getReservePool(0).stkReceiptToken.totalSupply();
    assertEq(stkTokenAmountReceived_, stkTokenSupplyBeforeUnstake_);

    vm.prank(receiver_);
    uint256 safetyModuleReceiptTokenAmount_ = component.unstake(0, stkTokenAmountReceived_, unstakeReceiver_, receiver_);

    assertEq(mockSafetyModuleReceiptToken.balanceOf(unstakeReceiver_), amountStaked_ + initialStakeAmount);
    assertEq(amountStaked_ + initialStakeAmount, safetyModuleReceiptTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockSafetyModuleReceiptToken)));
    // Entire supply of stake tokens was unstaked
    assertEq(finalReservePool_.amount, 0);
    // 150e18 + 20e18 - 120e18
    assertEq(finalAssetPool_.amount, initialSafetyModuleBal + stkTokenAmountReceived_ - safetyModuleReceiptTokenAmount_);
    assertEq(finalAssetPool_.amount, 50e18);
    assertEq(mockSafetyModuleReceiptToken.balanceOf(address(component)), finalAssetPool_.amount);

    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);

    // Because `stkToken.totalSupply() > 0` before unstaking, the index snapshot and cumulative claimed rewards should
    // change. Since this updates before the users stkTokens are burned, the calculation below uses
    // `stkToken.totalSupply() == stkTokenSupplyBeforeUnstake_`.
    assertEq(
      finalClaimableRewardsData_.indexSnapshot,
      initialIndexSnapshot_
        + uint256(cumulativeDrippedRewards_ - cumulativeClaimedRewards_).divWadDown(stkTokenSupplyBeforeUnstake_)
    );
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeDrippedRewards_);
    assertEq(finalClaimableRewardsData_.indexSnapshot, initialIndexSnapshot_ + 10e18);
  }

  function test_unstake_unstakePartial() public {
    (, address receiver_, uint256 amountStaked_, uint256 stkTokenAmountReceived_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    ReservePool memory initReservePool_ = component.getReservePool(0);
    AssetPool memory initAssetPool_ = component.getAssetPool(IERC20(address(mockSafetyModuleReceiptToken)));
    // 100e18 + 20e18
    assertEq(initReservePool_.amount, 120e18);
    // 150e18 + 20e18
    assertEq(initAssetPool_.amount, 170e18);
    assertEq(mockSafetyModuleReceiptToken.balanceOf(address(component)), initialSafetyModuleBal + 20e18);

    vm.prank(receiver_);
    mockStkToken.approve(address(component), stkTokenAmountReceived_);

    uint256 stkTokenSupplyBeforeUnstake_ = initReservePool_.stkReceiptToken.totalSupply();

    uint256 stkTokenAmountToUnstake_ = stkTokenAmountReceived_ / 2;
    uint256 safetyModuleReceiptTokenAmountToReceive_ =
      uint256(initReservePool_.amount).mulDivDown(stkTokenAmountToUnstake_, stkTokenSupplyBeforeUnstake_);

    _expectEmit();
    emit Transfer(address(component), unstakeReceiver_, safetyModuleReceiptTokenAmountToReceive_);
    _expectEmit();
    emit Unstaked(
      receiver_,
      unstakeReceiver_,
      receiver_,
      IReceiptToken(address(mockStkToken)),
      stkTokenAmountToUnstake_,
      safetyModuleReceiptTokenAmountToReceive_
    );

    vm.prank(receiver_);
    uint256 safetyModuleReceiptTokenAmountReceived_ =
      component.unstake(0, stkTokenAmountToUnstake_, unstakeReceiver_, receiver_);

    assertEq(mockSafetyModuleReceiptToken.balanceOf(unstakeReceiver_), (amountStaked_ + initialStakeAmount) / 2);
    assertEq(safetyModuleReceiptTokenAmountReceived_, safetyModuleReceiptTokenAmountToReceive_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockSafetyModuleReceiptToken)));
    // Half of supply was unstaked.
    assertEq(finalReservePool_.amount, (initialStakeAmount + amountStaked_) / 2);
    // 150e18 + 20e18 - 60e18
    assertEq(finalAssetPool_.amount, initialSafetyModuleBal + amountStaked_ - safetyModuleReceiptTokenAmountReceived_);
    assertEq(finalAssetPool_.amount, 110e18);

    ClaimableRewardsData memory finalClaimableRewardsData_ = component.getClaimableRewardsData(0, 0);
    // Because `stkToken.totalSupply() > 0` before unstaking, the index snapshot and cumulative claimed rewards should
    // change. Since this updates before the users stkTokens are burned, the calculation below uses
    // `stkToken.totalSupply() == stkTokenSupplyBeforeUnstake_`.
    assertEq(
      finalClaimableRewardsData_.indexSnapshot,
      initialIndexSnapshot_
        + uint256(cumulativeDrippedRewards_ - cumulativeClaimedRewards_).divWadDown(stkTokenSupplyBeforeUnstake_)
    );
    assertEq(finalClaimableRewardsData_.cumulativeClaimedRewards, cumulativeDrippedRewards_);
    assertEq(finalClaimableRewardsData_.indexSnapshot, initialIndexSnapshot_ + 10e18);
  }

  function test_unstake_canUnstakeTotalInMultipleUnstakes() external {
    (, address receiver_, uint256 amountStaked_, uint256 stkTokenAmountReceived_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    vm.prank(receiver_);
    mockStkToken.approve(address(component), stkTokenAmountReceived_);

    vm.prank(receiver_);
    uint256 safetyModuleReceiptTokenAmount_ =
      component.unstake(0, stkTokenAmountReceived_ / 2, unstakeReceiver_, receiver_);

    assertEq(mockSafetyModuleReceiptToken.balanceOf(unstakeReceiver_), (amountStaked_ + initialStakeAmount) / 2);
    assertEq(safetyModuleReceiptTokenAmount_, (amountStaked_ + initialStakeAmount) / 2);

    vm.prank(receiver_);
    safetyModuleReceiptTokenAmount_ = component.unstake(0, stkTokenAmountReceived_ / 2, unstakeReceiver_, receiver_);

    assertEq(mockSafetyModuleReceiptToken.balanceOf(unstakeReceiver_), amountStaked_ + initialStakeAmount);
    assertEq(safetyModuleReceiptTokenAmount_, (amountStaked_ + initialStakeAmount) / 2);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockSafetyModuleReceiptToken)));
    // Entire supply of stake tokens was unstaked
    assertEq(finalReservePool_.amount, 0);
    // 150e18 + 100e18
    assertEq(finalAssetPool_.amount, initialSafetyModuleBal - initialStakeAmount);
    assertEq(finalAssetPool_.amount, 50e18);
    assertEq(mockSafetyModuleReceiptToken.balanceOf(address(component)), finalAssetPool_.amount);
  }

  function test_unstake_cannotRedeemIfRoundsDownToZero() external {
    (, address receiver_,,) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(receiver_);
    component.unstake(0, 0, unstakeReceiver_, receiver_);

    component.mockSetStakeAmount(0);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(receiver_);
    component.unstake(0, 1, unstakeReceiver_, receiver_);
  }

  function test_unstake_canUnstakeThroughAllowance() external {
    (, address receiver_, uint256 amountStaked_, uint256 stkTokenAmountReceived_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();
    address spender_ = _randomAddress();

    vm.prank(receiver_);
    mockStkToken.approve(spender_, stkTokenAmountReceived_ + 1); // Allowance is 1 extra.

    vm.prank(spender_);
    uint256 safetyModuleReceiptTokenAmount_ = component.unstake(0, stkTokenAmountReceived_, unstakeReceiver_, receiver_);

    assertEq(mockStkToken.allowance(receiver_, spender_), 1, "depositToken allowance"); // Only 1 allowance left because
      // of subtraction.
    assertEq(mockSafetyModuleReceiptToken.balanceOf(unstakeReceiver_), amountStaked_ + initialStakeAmount);
    assertEq(safetyModuleReceiptTokenAmount_, amountStaked_ + initialStakeAmount);
  }

  function test_unstake_cannotUnstake_ThroughAllowance_WithInsufficientAllowance() external {
    (, address receiver_,, uint256 stkTokenAmountReceived_) = _setupDefaultSingleUserFixture();
    address unstakeReceiver_ = _randomAddress();
    address spender_ = _randomAddress();

    vm.prank(receiver_);
    mockStkToken.approve(spender_, stkTokenAmountReceived_ - 1); // Allowance is 1 less.

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(spender_);
    component.unstake(0, stkTokenAmountReceived_, unstakeReceiver_, receiver_);
  }

  function test_unstake_cannotUnstake_InsufficientTokenBalance() external {
    address staker_ = _randomAddress();
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(staker_);
    component.unstake(0, _randomUint128(), staker_, staker_);

    (, address receiver_,, uint256 stkTokenAmountReceived_) = _setupDefaultSingleUserFixture();

    vm.prank(receiver_);
    mockStkToken.approve(address(component), stkTokenAmountReceived_ + 1);

    vm.prank(receiver_);
    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    component.unstake(0, stkTokenAmountReceived_ + 1, receiver_, receiver_);
  }

  function test_unstake_invalidReservePoolId() external {
    address staker_ = _randomAddress();
    _expectPanic(PANIC_ARRAY_OUT_OF_BOUNDS);
    vm.prank(staker_);
    component.unstake(1, _randomUint128(), staker_, staker_);
  }

  function test_unstake_matchesPreviewUnstakeAll() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountStaked_ = 20e18;

    // Mint initial safety module receipt token balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountStaked_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.approve(address(component), amountStaked_);

    vm.prank(staker_);
    uint256 stkTokenAmountReceived_ = component.stake(0, amountStaked_, receiver_, staker_);

    uint256 unstakeAmountPreview_ = component.previewUnstake(0, stkTokenAmountReceived_);

    vm.prank(receiver_);
    mockStkToken.approve(address(component), stkTokenAmountReceived_);

    vm.prank(receiver_);
    uint256 safetyModuleReceiptTokenAmountReceived_ =
      component.unstake(0, stkTokenAmountReceived_, receiver_, receiver_);

    assertEq(unstakeAmountPreview_, safetyModuleReceiptTokenAmountReceived_);
  }

  function test_unstake_matchesPreviewUnstakePartial() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountStaked_ = 20e18;

    // Mint initial safety module receipt token balance for staker.
    mockSafetyModuleReceiptToken.mint(staker_, amountStaked_);
    // Approve rewards manager to spend safety module receipt token.
    vm.prank(staker_);
    mockSafetyModuleReceiptToken.approve(address(component), amountStaked_);

    vm.prank(staker_);
    uint256 stkTokenAmountReceived_ = component.stake(0, amountStaked_, receiver_, staker_);

    uint256 stkTokenAmountToUnstake_ = stkTokenAmountReceived_ / 2;

    uint256 unstakeAmountPreview_ = component.previewUnstake(0, stkTokenAmountToUnstake_);

    vm.prank(receiver_);
    mockStkToken.approve(address(component), stkTokenAmountToUnstake_);

    vm.prank(receiver_);
    uint256 safetyModuleReceiptTokenAmountReceived_ =
      component.unstake(0, stkTokenAmountToUnstake_, receiver_, receiver_);

    assertEq(unstakeAmountPreview_, safetyModuleReceiptTokenAmountReceived_);
  }

  function test_unstake_previewUnstakeRoundsDownToZero() external {
    (, address receiver_,,) = _setupDefaultSingleUserFixture();

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(receiver_);
    component.previewUnstake(0, 0);

    component.mockSetStakeAmount(0);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(receiver_);
    component.previewUnstake(0, 1);
  }
}

contract TestableStaker is Staker, Depositor, RewardsDistributor {
  using SafeCastLib for uint256;

  constructor(MockSafetyModule safetyModule_) Staker() {
    safetyModule = ISafetyModule(address(safetyModule_));
  }

  // -------- Mock setters --------
  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    MockSafetyModule(address(safetyModule)).setSafetyModuleState(safetyModuleState_);
  }

  function mockAddReservePool(ReservePool memory reservePool_) external {
    reservePools.push(reservePool_);
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
        depositToken: IReceiptToken(address(new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6))),
        cumulativeDrippedRewards: cumulativeDrippedRewards_,
        lastDripTime: uint128(block.timestamp)
      })
    );
  }

  function mockSetClaimableRewardsData(
    uint16 reservePoolId_,
    uint16 rewardPoolid_,
    uint256 indexSnapshot_,
    uint256 cumulativeClaimedRewards_
  ) external {
    claimableRewards[reservePoolId_][rewardPoolid_] = ClaimableRewardsData({
      indexSnapshot: indexSnapshot_.safeCastTo128(),
      cumulativeClaimedRewards: cumulativeClaimedRewards_
    });
  }

  function mockSetStakeAmount(uint256 stakeAmount_) external {
    reservePools[0].amount = stakeAmount_;
  }

  // -------- Mock getters --------
  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  function getClaimableRewardsData(uint16 reservePoolId_, uint16 rewardPoolid_)
    external
    view
    returns (ClaimableRewardsData memory)
  {
    return claimableRewards[reservePoolId_][rewardPoolid_];
  }
}
