// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IDepositorErrors} from "../src/interfaces/IDepositorErrors.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {RewardsManagerInspector} from "../src/lib/RewardsManagerInspector.sol";
import {RewardsManagerState} from "../src/lib/RewardsManagerStates.sol";
import {AssetPool, StakePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {UserRewardsData, ClaimRewardsArgs, ClaimableRewardsData} from "../src/lib/structs/Rewards.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract DepositorUnitTest is TestBase {
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);
  TestableDepositor component = new TestableDepositor();

  /// @dev Emitted when a user deposits rewards.
  event Deposited(address indexed caller_, uint16 indexed rewardPoolId_, uint256 assetAmount_);

  event Transfer(address indexed from, address indexed to, uint256 amount);

  uint256 initialSafetyModuleBal = 50e18;
  uint256 initialUndrippedRewards = 50e18;

  function setUp() public {
    RewardPool memory initialRewardPool_ = RewardPool({
      asset: IERC20(address(mockAsset)),
      dripModel: IDripModel(address(0)),
      undrippedRewards: initialUndrippedRewards,
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });
    AssetPool memory initialAssetPool_ = AssetPool({amount: initialUndrippedRewards});
    component.mockAddRewardPool(initialRewardPool_);
    component.mockAddAssetPool(IERC20(address(mockAsset)), initialAssetPool_);
    deal(address(mockAsset), address(component), initialUndrippedRewards);
  }

  function _deposit(bool withoutTransfer_, uint16 poolId_, uint256 amountToDeposit_) internal {
    if (withoutTransfer_) component.depositRewardAssetsWithoutTransfer(poolId_, amountToDeposit_);
    else component.depositRewardAssets(poolId_, amountToDeposit_);
  }

  function test_depositReserve_DepositAndStorageUpdates() external {
    address depositor_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    _expectEmit();
    emit Deposited(depositor_, 0, amountToDeposit_);

    vm.prank(depositor_);
    _deposit(false, 0, amountToDeposit_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 10e18
    assertEq(finalRewardPool_.undrippedRewards, 60e18);
    // 50e18 + 10e18
    assertEq(finalAssetPool_.amount, 60e18);
    assertEq(mockAsset.balanceOf(address(component)), 60e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
  }

  function test_depositReward_DepositAndStorageUpdatesWithDrip() external {
    address depositor_ = _randomAddress();
    uint128 amountToDeposit_ = 20e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    component.mockSetNextRewardsDripAmount(45e18);

    vm.prank(depositor_);
    _expectEmit();
    emit Deposited(depositor_, 0, amountToDeposit_);
    _deposit(false, 0, amountToDeposit_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 45e18 of the assets are dripped: 50e18 - 45e18 + 20e18
    assertEq(finalRewardPool_.undrippedRewards, 25e18);

    // 50e18 + 20e18
    assertEq(finalAssetPool_.amount, 70e18);
    assertEq(mockAsset.balanceOf(address(component)), 70e18);
    assertEq(mockAsset.balanceOf(depositor_), 0);
  }

  function test_depositRewardAssets_RevertWhenPaused() external {
    address depositor_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);

    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(depositor_);
    _deposit(false, 0, amountToDeposit_);
  }

  function test_depositRewards_RevertOutOfBoundsRewardPoolId() external {
    address depositor_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    vm.prank(depositor_);
    _deposit(false, 1, 10e18);
  }

  function testFuzz_depositRewards_RevertInsufficientAssetsAvailable(uint256 amountToDeposit_) external {
    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint216).max);

    address depositor_ = _randomAddress();

    // Mint insufficient assets for depositor.
    mockAsset.mint(depositor_, amountToDeposit_ - 1);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(depositor_);
    _deposit(false, 0, amountToDeposit_);
  }

  function test_depositRewardAssetsWithoutTransfer_DepositAndStorageUpdates() external {
    address depositor_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Transfer to rewards manager.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    _expectEmit();
    emit Deposited(depositor_, 0, amountToDeposit_);

    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 10e18
    assertEq(finalRewardPool_.undrippedRewards, 60e18);
    // 50e18 + 10e18
    assertEq(finalAssetPool_.amount, 60e18);
    assertEq(mockAsset.balanceOf(address(component)), 60e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
  }

  function test_depositRewardAssetsWithoutTransfer_DepositAndStorageUpdatesNonZeroSupply() external {
    address depositor_ = _randomAddress();
    uint128 amountToDeposit_ = 20e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Transfer to rewards manager.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    _expectEmit();
    emit Deposited(depositor_, 0, amountToDeposit_);

    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 20e18
    assertEq(finalRewardPool_.undrippedRewards, 70e18);
    // 50e18 + 20e18
    assertEq(finalAssetPool_.amount, 70e18);
    assertEq(mockAsset.balanceOf(address(component)), 70e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
  }

  function test_depositRewardAssetsWithoutTransfer_RevertWhenPaused() external {
    address depositor_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Transfer to rewards manager.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_);
  }

  function test_depositRewardAssetsWithoutTransfer_RevertOutOfBoundsRewardPoolId() external {
    _expectPanic(INDEX_OUT_OF_BOUNDS);
    _deposit(true, 1, 10e18);
  }

  function testFuzz_depositRewardAssetsWithoutTransfer_RevertInsufficientAssetsAvailable(uint256 amountToDeposit_)
    external
  {
    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint128).max);
    address depositor_ = _randomAddress();

    // Mint insufficient assets for depositor.
    mockAsset.mint(depositor_, amountToDeposit_ - 1);
    // Transfer to rewards manager.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_ - 1);

    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_);
  }
}

contract TestableDepositor is Depositor, RewardsManagerInspector {
  uint256 internal mockNextRewardsDripAmount;

  // -------- Mock setters --------

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockSetNextRewardsDripAmount(uint256 nextDripAmount_) external {
    mockNextRewardsDripAmount = nextDripAmount_;
  }

  function mockSetRewardsPoolUndrippedRewards(uint16 rewardsPool_, uint256 amount_) external {
    rewardPools[rewardsPool_].undrippedRewards = amount_;
  }

  function mockSetAssetPoolAmount(IERC20 asset_, uint256 amount_) external {
    assetPools[asset_].amount = amount_;
  }

  function mockSetRewardsManagerState(RewardsManagerState state_) external {
    rewardsManagerState = state_;
  }

  // -------- Mock getters --------
  function getStakePool(uint16 stakePoolId_) external view returns (StakePool memory) {
    return stakePools[stakePoolId_];
  }

  function getRewardPool(uint16 rewardPoolid_) external view returns (RewardPool memory) {
    return rewardPools[rewardPoolid_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  // -------- Overridden abstract function placeholders --------

  function _claimRewards(ClaimRewardsArgs memory /* args_ */ ) internal override {
    __writeStub__();
  }

  function dripRewards() public view override {
    __readStub__();
  }

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 lastDripTime_)
    internal
    view
    override
    returns (uint256)
  {
    return block.timestamp - lastDripTime_ == 0 || rewardsManagerState == RewardsManagerState.PAUSED
      ? 0
      : mockNextRewardsDripAmount;
  }

  function _computeNextDripAmount(uint256, /* totalBaseAmount_ */ uint256 /* dripFactor_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _updateUserRewards(
    uint256, /*userStkReceiptTokenBalance_*/
    mapping(uint16 => ClaimableRewardsData) storage, /*claimableRewards_*/
    UserRewardsData[] storage /*userRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _dripRewardPool(RewardPool storage rewardPool_) internal override {
    uint256 totalDrippedRewards_ = mockNextRewardsDripAmount;
    if (totalDrippedRewards_ > 0) rewardPool_.undrippedRewards -= totalDrippedRewards_;
    rewardPool_.lastDripTime = uint128(block.timestamp);
  }

  function _dripAndApplyPendingDrippedRewards(
    StakePool storage, /*stakePool_*/
    mapping(uint16 => ClaimableRewardsData) storage /*claimableRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _dripAndResetCumulativeRewardsValues(
    StakePool[] storage, /*stakePools_*/
    RewardPool[] storage /*rewardPools_*/
  ) internal view override {
    __readStub__();
  }
}
