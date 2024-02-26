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
  MockERC20 mockRewardPoolDepositReceiptToken = new MockERC20("Mock Cozy Deposit Receipt Token", "cozyDep", 6);
  TestableDepositor component = new TestableDepositor();

  /// @dev Emitted when a user deposits rewards.
  event Deposited(
    address indexed caller_,
    address indexed receiver_,
    uint16 indexed rewardPoolId_,
    IReceiptToken depositReceiptToken_,
    uint256 assetAmount_,
    uint256 depositReceiptTokenAmount_
  );

  /// @dev Emitted when a user redeems rewards.
  event RedeemedUndrippedRewards(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint16 indexed rewardPoolId_,
    IReceiptToken depositReceiptToken_,
    uint256 depositReceiptTokenAmount_,
    uint256 rewardAssetAmount_
  );

  event Transfer(address indexed from, address indexed to, uint256 amount);

  uint256 initialSafetyModuleBal = 50e18;
  uint256 initialUndrippedRewards = 50e18;

  function setUp() public {
    RewardPool memory initialRewardPool_ = RewardPool({
      asset: IERC20(address(mockAsset)),
      depositReceiptToken: IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
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

  function _deposit(
    bool withoutTransfer_,
    uint16 poolId_,
    uint256 amountToDeposit_,
    address receiver_,
    address depositor_
  ) internal returns (uint256 depositReceiptTokenAmount_) {
    if (withoutTransfer_) {
      depositReceiptTokenAmount_ = component.depositRewardAssetsWithoutTransfer(poolId_, amountToDeposit_, receiver_);
    } else {
      depositReceiptTokenAmount_ = component.depositRewardAssets(poolId_, amountToDeposit_, receiver_, depositor_);
    }
  }

  function test_depositReserve_DepositReceiptTokensAndStorageUpdates() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    // `depositReceiptToken.totalSupply() == 0`, so should be minted 1-1 with stake assets deposited.
    uint256 expectedDepositReceiptTokenAmount_ = 10e18;
    _expectEmit();
    emit Deposited(
      depositor_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      amountToDeposit_,
      expectedDepositReceiptTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositReciptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    assertEq(depositReciptTokenAmount_, expectedDepositReceiptTokenAmount_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 10e18
    assertEq(finalRewardPool_.undrippedRewards, 60e18);
    // 50e18 + 10e18
    assertEq(finalAssetPool_.amount, 60e18);
    assertEq(mockAsset.balanceOf(address(component)), 60e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockRewardPoolDepositReceiptToken.balanceOf(receiver_), expectedDepositReceiptTokenAmount_);
  }

  function test_depositReserve_DepositReceiptTokensAndStorageUpdatesNonZeroSupply() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 20e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Mint/burn some depositReceiptTokens.
    uint256 initialDepositReceiptTokenSupply_ = 50e18;
    mockRewardPoolDepositReceiptToken.mint(address(0), initialDepositReceiptTokenSupply_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    // `depositReceiptToken.totalSupply() == 50e18`, so we have (20e18 / 50e18) * 50e18 = 20e18.
    uint256 expectedDepositReceiptTokenAmount_ = 20e18;
    _expectEmit();
    emit Deposited(
      depositor_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      amountToDeposit_,
      expectedDepositReceiptTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    assertEq(depositReceiptTokenAmount_, expectedDepositReceiptTokenAmount_);
    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 20e18
    assertEq(finalRewardPool_.undrippedRewards, 70e18);

    // 50e18 + 20e18
    assertEq(finalAssetPool_.amount, 70e18);
    assertEq(mockAsset.balanceOf(address(component)), 70e18);
    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockRewardPoolDepositReceiptToken.balanceOf(receiver_), expectedDepositReceiptTokenAmount_);
  }

  function test_depositReserveAssets_RevertWhenPaused() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);

    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(depositor_);
    _deposit(false, 0, amountToDeposit_, receiver_, depositor_);
  }

  function test_depositReserve_RevertOutOfBoundsRewardPoolId() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    vm.prank(depositor_);
    _deposit(false, 1, 10e18, receiver_, depositor_);
  }

  function testFuzz_depositReserve_RevertInsufficientAssetsAvailable(uint256 amountToDeposit_) external {
    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint216).max);

    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint insufficient assets for depositor.
    mockAsset.mint(depositor_, amountToDeposit_ - 1);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(depositor_);
    _deposit(false, 0, amountToDeposit_, receiver_, depositor_);
  }

  function test_depositReserveAssetsWithoutTransfer_DepositReceiptTokensAndStorageUpdates() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Transfer to rewards manager.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    // `depositReceiptToken.totalSupply() == 0`, so should be minted 1-1 with stake assets deposited.
    uint256 expectedDepositReceiptTokenAmount_ = 10e18;
    _expectEmit();
    emit Deposited(
      depositor_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      amountToDeposit_,
      expectedDepositReceiptTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(true, 0, amountToDeposit_, receiver_, receiver_);

    assertEq(depositReceiptTokenAmount_, expectedDepositReceiptTokenAmount_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 10e18
    assertEq(finalRewardPool_.undrippedRewards, 60e18);
    // 50e18 + 10e18
    assertEq(finalAssetPool_.amount, 60e18);
    assertEq(mockAsset.balanceOf(address(component)), 60e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockRewardPoolDepositReceiptToken.balanceOf(receiver_), expectedDepositReceiptTokenAmount_);
  }

  function test_depositReserveAssetsWithoutTransfer_DepositReceiptTokensAndStorageUpdatesNonZeroSupply() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 20e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Mint/burn some depositReceiptTokens.
    uint256 initialDepositReceiptTokenSupply_ = 50e18;
    mockRewardPoolDepositReceiptToken.mint(address(0), initialDepositReceiptTokenSupply_);
    // Transfer to rewards manager.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    // `depositReceiptToken.totalSupply() == 50e18`, so we have (20e18 / 50e18) * 50e18 = 20e18.
    uint256 expectedDepositReceiptTokenAmount_ = 20e18;
    _expectEmit();
    emit Deposited(
      depositor_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      amountToDeposit_,
      expectedDepositReceiptTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(true, 0, amountToDeposit_, receiver_, receiver_);

    assertEq(depositReceiptTokenAmount_, expectedDepositReceiptTokenAmount_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 20e18
    assertEq(finalRewardPool_.undrippedRewards, 70e18);
    // 50e18 + 20e18
    assertEq(finalAssetPool_.amount, 70e18);
    assertEq(mockAsset.balanceOf(address(component)), 70e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockRewardPoolDepositReceiptToken.balanceOf(receiver_), expectedDepositReceiptTokenAmount_);
  }

  function test_depositReserveAssetsWithoutTransfer_RevertWhenPaused() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Transfer to rewards manager.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_, receiver_, receiver_);
  }

  function test_depositReserveAssetsWithoutTransfer_RevertOutOfBoundsRewardPoolId() external {
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    _deposit(true, 1, 10e18, receiver_, receiver_);
  }

  function testFuzz_depositReserveAssetsWithoutTransfer_RevertInsufficientAssetsAvailable(uint256 amountToDeposit_)
    external
  {
    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint128).max);
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint insufficient assets for depositor.
    mockAsset.mint(depositor_, amountToDeposit_ - 1);
    // Transfer to rewards manager.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_ - 1);

    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_, receiver_, address(0));
  }

  function test_deposit_RevertZeroShares() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToDeposit_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_, receiver_, address(0));
  }

  function test_depositWithoutTransfer_RevertZeroShares() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToDeposit_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(depositor_);
    _deposit(false, 0, amountToDeposit_, receiver_, address(0));
  }

  function test_redeemUndrippedRewards_redeemAll() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial asset balance for rewards manager.
    mockAsset.mint(address(component), initialSafetyModuleBal);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    // Total supply of deposit receipt token is redeemed.
    assertEq(depositReceiptTokenAmount_, mockRewardPoolDepositReceiptToken.totalSupply());
    uint256 expectedRewardAssetAmount_ = initialUndrippedRewards + amountToDeposit_;

    vm.prank(receiver_);
    mockRewardPoolDepositReceiptToken.approve(address(component), depositReceiptTokenAmount_);

    _expectEmit();
    emit Transfer(receiver_, address(0), depositReceiptTokenAmount_);
    _expectEmit();
    emit RedeemedUndrippedRewards(
      receiver_,
      receiver_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      depositReceiptTokenAmount_,
      expectedRewardAssetAmount_
    );
    vm.prank(receiver_);
    uint256 rewardAssetAmount_ = component.redeemUndrippedRewards(0, depositReceiptTokenAmount_, receiver_, receiver_);

    // Receiver redeems their entire reward pool deposit receipt token balance, which is the entire supply.
    assertEq(rewardAssetAmount_, expectedRewardAssetAmount_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    // Entire pool is redeemed
    assertEq(finalRewardPool_.undrippedRewards, 0);

    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    assertEq(finalAssetPool_.amount, initialSafetyModuleBal - initialUndrippedRewards);
    assertEq(finalAssetPool_.amount, 0);
    // At the start of this test the component was minted additional unaccounted for assets.
    assertEq(finalAssetPool_.amount + initialSafetyModuleBal, mockAsset.balanceOf(address(component)));
  }

  function test_redeemUndrippedRewards_redeemPartial() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    // Half of total supply of deposit receipt token is redeemed.
    assertEq(depositReceiptTokenAmount_, mockRewardPoolDepositReceiptToken.totalSupply());
    uint256 depositReceiptTokenAmountToRedeem_ = depositReceiptTokenAmount_ / 2;
    uint256 expectedRewardAssetAmount_ = (initialUndrippedRewards + amountToDeposit_) / 2;

    vm.prank(receiver_);
    mockRewardPoolDepositReceiptToken.approve(address(component), depositReceiptTokenAmountToRedeem_);

    _expectEmit();
    emit Transfer(receiver_, address(0), depositReceiptTokenAmountToRedeem_);
    _expectEmit();
    emit RedeemedUndrippedRewards(
      receiver_,
      receiver_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      depositReceiptTokenAmountToRedeem_,
      expectedRewardAssetAmount_
    );
    vm.prank(receiver_);
    uint256 rewardAssetAmount_ =
      component.redeemUndrippedRewards(0, depositReceiptTokenAmountToRedeem_, receiver_, receiver_);

    // Receiver redeems half of their reward pool deposit receipt token balance.
    assertEq(rewardAssetAmount_, expectedRewardAssetAmount_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    // Half of pool is redeemed
    assertEq(finalRewardPool_.undrippedRewards, expectedRewardAssetAmount_);

    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    assertEq(finalAssetPool_.amount, (initialSafetyModuleBal + amountToDeposit_) - rewardAssetAmount_);
    assertEq(finalAssetPool_.amount, 30e18);
  }

  function test_redeemUndrippredRewards_withDrip() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    // Drip half of the assets in the reward pool.
    vm.warp(100);
    component.mockSetNextRewardsDripAmount((initialUndrippedRewards + amountToDeposit_) / 2);

    // Half of total supply of deposit receipt token is redeemed.
    assertEq(depositReceiptTokenAmount_, mockRewardPoolDepositReceiptToken.totalSupply());
    uint256 depositReceiptTokenAmountToRedeem_ = depositReceiptTokenAmount_ / 2;
    uint256 expectedRewardAssetAmount_ = (initialUndrippedRewards + amountToDeposit_) / 4;

    vm.prank(receiver_);
    mockRewardPoolDepositReceiptToken.approve(address(component), depositReceiptTokenAmountToRedeem_);

    _expectEmit();
    emit Transfer(receiver_, address(0), depositReceiptTokenAmountToRedeem_);
    _expectEmit();
    emit RedeemedUndrippedRewards(
      receiver_,
      receiver_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      depositReceiptTokenAmountToRedeem_,
      expectedRewardAssetAmount_
    );
    vm.prank(receiver_);
    uint256 rewardAssetAmount_ =
      component.redeemUndrippedRewards(0, depositReceiptTokenAmountToRedeem_, receiver_, receiver_);

    // Receiver redeems half of their reward pool deposit receipt token balance.
    assertEq(rewardAssetAmount_, expectedRewardAssetAmount_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    // Half of pool after drip is redeemed
    assertEq(finalRewardPool_.undrippedRewards, expectedRewardAssetAmount_);

    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // A quarter of the total assets before component.redeemUndrippedRewards were redeemed, since half dripped, and then
    // half of the remaining were redeemed.
    assertEq(finalAssetPool_.amount, (initialSafetyModuleBal + amountToDeposit_) / 4 * 3);
    assertEq(finalAssetPool_.amount, 45e18);
  }

  function test_redeemUndrippredRewards_noDripWhenPaused() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    // Mock the next drip to half of the assets in the reward pool.
    vm.warp(100);
    component.mockSetNextRewardsDripAmount((initialUndrippedRewards + amountToDeposit_) / 2);
    // But because the rewards manager is paused, the drip doesn't occur for this test.
    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    // Half of total supply of deposit receipt token is redeemed.
    assertEq(depositReceiptTokenAmount_, mockRewardPoolDepositReceiptToken.totalSupply());
    uint256 depositReceiptTokenAmountToRedeem_ = depositReceiptTokenAmount_ / 2;
    uint256 expectedRewardAssetAmount_ = (initialUndrippedRewards + amountToDeposit_) / 2;

    vm.prank(receiver_);
    mockRewardPoolDepositReceiptToken.approve(address(component), depositReceiptTokenAmountToRedeem_);

    _expectEmit();
    emit Transfer(receiver_, address(0), depositReceiptTokenAmountToRedeem_);
    _expectEmit();
    emit RedeemedUndrippedRewards(
      receiver_,
      receiver_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      depositReceiptTokenAmountToRedeem_,
      expectedRewardAssetAmount_
    );
    vm.prank(receiver_);
    uint256 rewardAssetAmount_ =
      component.redeemUndrippedRewards(0, depositReceiptTokenAmountToRedeem_, receiver_, receiver_);

    // Receiver redeems half of their reward pool deposit receipt token balance.
    assertEq(rewardAssetAmount_, expectedRewardAssetAmount_);

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    // Half of pool after drip is redeemed
    assertEq(finalRewardPool_.undrippedRewards, expectedRewardAssetAmount_);

    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // Half of the total assets before component.redeemUndrippedRewards were redeemed, since none dripped.
    assertEq(finalAssetPool_.amount, (initialSafetyModuleBal + amountToDeposit_) / 2);
    assertEq(finalAssetPool_.amount, 30e18);
  }

  function test_redeemUndrippedRewards_cannotRedeemIfRoundsDownToZeroAssets() external {
    // Init 0 assets.
    deal(address(mockAsset), address(component), 0);
    component.mockSetRewardsPoolUndrippedRewards(0, 0);
    component.mockSetAssetPoolAmount(IERC20(address(mockAsset)), 0);

    address owner_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 rewardAssetAmount_ = 1;
    uint256 depositReceiptTokenAmount_ = 3;

    // Mint initial balance for depositor.
    mockAsset.mint(owner_, rewardAssetAmount_);
    // Approve rewards manager to spend asset.
    vm.prank(owner_);
    mockAsset.approve(address(component), rewardAssetAmount_);
    // Deposit 1 asset.
    vm.prank(owner_);
    _deposit(false, 0, rewardAssetAmount_, owner_, owner_);

    // Mint an additional 2 receipt tokens to the owner, so now totalSupply == 3 and undrippedRewards == 1.
    mockRewardPoolDepositReceiptToken.mint(owner_, 2);
    assertEq(mockRewardPoolDepositReceiptToken.totalSupply(), depositReceiptTokenAmount_);
    assertEq(component.getRewardPool(0).undrippedRewards, rewardAssetAmount_);

    vm.prank(owner_);
    mockRewardPoolDepositReceiptToken.approve(address(component), depositReceiptTokenAmount_);

    // 1 * (2 / 3) rounds to zero
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(owner_);
    component.redeemUndrippedRewards(0, 2, receiver_, owner_);

    // Set undripped rewards to zero, as if all rewards have dripped.
    component.mockSetRewardsPoolUndrippedRewards(0, 0);
    // 0 * (3 / 3) rounds to zero.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(owner_);
    component.redeemUndrippedRewards(0, depositReceiptTokenAmount_, receiver_, owner_);
  }

  function test_redeemUndrippedRewards_canRedeemAllThroughAllowance() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    address spender_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, depositor_, depositor_);

    // Depositor approves spender to spend all of their deposit receipt tokens, + 1.
    vm.prank(depositor_);
    mockRewardPoolDepositReceiptToken.approve(spender_, depositReceiptTokenAmount_ + 1);

    // Total supply of deposit receipt token is redeemed by spender.
    vm.prank(spender_);
    component.redeemUndrippedRewards(0, depositReceiptTokenAmount_, receiver_, depositor_);
    assertEq(mockRewardPoolDepositReceiptToken.allowance(depositor_, spender_), 1, "depositReceiptToken allowance"); // Only
      // 1
      // allowance left because of
      // subtraction.

    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
    // Entire pool is redeemed
    assertEq(finalRewardPool_.undrippedRewards, 0);
  }

  function test_redeemUndrippedRewards_cannotRedeemThroughAllowanceWithInsufficientAllowance() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    address spender_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, depositor_, depositor_);

    // Depositor approves spender to spend all of their deposit receipt tokens, - 1.
    vm.prank(depositor_);
    mockRewardPoolDepositReceiptToken.approve(spender_, depositReceiptTokenAmount_ - 1);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(spender_);
    component.redeemUndrippedRewards(0, depositReceiptTokenAmount_, receiver_, depositor_);
  }

  function test_redeemUndrippedRewards_cannotRedeemInsufficientDepositReceiptTokenBalance() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToDeposit_ = _randomUint120();

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, depositor_, depositor_);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(depositor_);
    component.redeemUndrippedRewards(0, depositReceiptTokenAmount_ + 1, receiver_, depositor_);
  }

  function test_redeemUndrippedRewards_cannotRedeemInvalidRewardPoolId() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToDeposit_ = _randomUint120();
    uint16 redeemStakePoolId_ = uint16(bound(_randomUint16(), 1, type(uint16).max));

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, depositor_, depositor_);

    _expectPanic(PANIC_ARRAY_OUT_OF_BOUNDS);
    vm.prank(depositor_);
    component.redeemUndrippedRewards(redeemStakePoolId_, depositReceiptTokenAmount_, receiver_, depositor_);
  }

  function test_redeemUndrippedRewards_previewUndrippedRewardsRedemptionWithDrip() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    // Next drip (which occurs on redeem), drip half of the assets in the reward pool.
    vm.warp(100);
    component.mockSetNextRewardsDripAmount((initialUndrippedRewards + amountToDeposit_) / 2);

    // Half of total supply of deposit receipt token is redeemed.
    assertEq(depositReceiptTokenAmount_, mockRewardPoolDepositReceiptToken.totalSupply());
    uint256 depositReceiptTokenAmountToRedeem_ = depositReceiptTokenAmount_ / 2;
    uint256 expectedRewardAssetAmount_ = (initialUndrippedRewards + amountToDeposit_) / 4;

    uint256 previewRewardAssetAmount_ =
      component.previewUndrippedRewardsRedemption(0, depositReceiptTokenAmountToRedeem_);

    vm.prank(receiver_);
    mockRewardPoolDepositReceiptToken.approve(address(component), depositReceiptTokenAmountToRedeem_);

    _expectEmit();
    emit Transfer(receiver_, address(0), depositReceiptTokenAmountToRedeem_);
    _expectEmit();
    emit RedeemedUndrippedRewards(
      receiver_,
      receiver_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      depositReceiptTokenAmountToRedeem_,
      expectedRewardAssetAmount_
    );
    vm.prank(receiver_);
    uint256 rewardAssetAmount_ =
      component.redeemUndrippedRewards(0, depositReceiptTokenAmountToRedeem_, receiver_, receiver_);

    // Receiver redeems half of their reward pool deposit receipt token balance.
    assertEq(rewardAssetAmount_, expectedRewardAssetAmount_);
    assertEq(mockAsset.balanceOf(receiver_), rewardAssetAmount_);
    assertEq(rewardAssetAmount_, previewRewardAssetAmount_);
  }

  function test_redeemUndrippedRewards_previewRewardsRedemptionFullyDripped() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    // Next drip (which occurs on redeem), drip half of the assets in the reward pool.
    vm.warp(100);
    component.mockSetNextRewardsDripAmount(initialUndrippedRewards + amountToDeposit_);

    uint256 rewardAssetAmount_ = component.previewUndrippedRewardsRedemption(0, depositReceiptTokenAmount_);
    assertEq(rewardAssetAmount_, 0);

    vm.prank(receiver_);
    mockRewardPoolDepositReceiptToken.approve(address(component), depositReceiptTokenAmount_);
    vm.prank(receiver_);
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    component.redeemUndrippedRewards(0, depositReceiptTokenAmount_, receiver_, receiver_);
  }

  function test_redeemUndrippedRewards_noDripWhenPaused() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve rewards manager to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    // Mock next drip (which occurs on redeem), drip half of the assets in the reward pool.
    vm.warp(100);
    component.mockSetNextRewardsDripAmount((initialUndrippedRewards + amountToDeposit_) / 2);
    // But because the rewards manager is paused, the drip doesn't occur for this test.
    component.mockSetRewardsManagerState(RewardsManagerState.PAUSED);

    // Half of total supply of deposit receipt token is redeemed.
    assertEq(depositReceiptTokenAmount_, mockRewardPoolDepositReceiptToken.totalSupply());
    uint256 depositReceiptTokenAmountToRedeem_ = depositReceiptTokenAmount_ / 2;
    uint256 expectedRewardAssetAmount_ = (initialUndrippedRewards + amountToDeposit_) / 2;

    uint256 previewRewardAssetAmount_ =
      component.previewUndrippedRewardsRedemption(0, depositReceiptTokenAmountToRedeem_);

    vm.prank(receiver_);
    mockRewardPoolDepositReceiptToken.approve(address(component), depositReceiptTokenAmountToRedeem_);

    _expectEmit();
    emit Transfer(receiver_, address(0), depositReceiptTokenAmountToRedeem_);
    _expectEmit();
    emit RedeemedUndrippedRewards(
      receiver_,
      receiver_,
      receiver_,
      0,
      IReceiptToken(address(mockRewardPoolDepositReceiptToken)),
      depositReceiptTokenAmountToRedeem_,
      expectedRewardAssetAmount_
    );
    vm.prank(receiver_);
    uint256 rewardAssetAmount_ =
      component.redeemUndrippedRewards(0, depositReceiptTokenAmountToRedeem_, receiver_, receiver_);

    // Receiver redeems half of their reward pool deposit receipt token balance.
    assertEq(rewardAssetAmount_, expectedRewardAssetAmount_);
    assertEq(mockAsset.balanceOf(receiver_), rewardAssetAmount_);
    assertEq(rewardAssetAmount_, previewRewardAssetAmount_);
  }

  function test_redeemUndrippedRewards_previewRewardsRedemptionRoundsDownToZero() external {
    // Init 0 assets.
    deal(address(mockAsset), address(component), 0);
    component.mockSetRewardsPoolUndrippedRewards(0, 0);
    component.mockSetAssetPoolAmount(IERC20(address(mockAsset)), 0);

    address owner_ = _randomAddress();
    uint256 rewardAssetAmount_ = 1;
    uint256 depositReceiptTokenAmount_ = 3;

    // Mint initial balance for depositor.
    mockAsset.mint(owner_, rewardAssetAmount_);
    // Approve rewards manager to spend asset.
    vm.prank(owner_);
    mockAsset.approve(address(component), rewardAssetAmount_);
    // Deposit 1 asset.
    vm.prank(owner_);
    _deposit(false, 0, rewardAssetAmount_, owner_, owner_);

    // Mint an additional 2 receipt tokens to the owner, so now totalSupply == 3 and undrippedRewards == 1.
    mockRewardPoolDepositReceiptToken.mint(owner_, 2);
    assertEq(mockRewardPoolDepositReceiptToken.totalSupply(), depositReceiptTokenAmount_);
    assertEq(component.getRewardPool(0).undrippedRewards, rewardAssetAmount_);

    // 1 * (2 / 3) rounds to zero.
    uint256 previewedRewardAssetAmount_ = component.previewUndrippedRewardsRedemption(0, 2);
    assertEq(previewedRewardAssetAmount_, 0);

    // Set undripped rewards to zero, as if all rewards have dripped.
    component.mockSetRewardsPoolUndrippedRewards(0, 0);

    // 0 * (3 / 3) rounds to zero.
    previewedRewardAssetAmount_ = component.previewUndrippedRewardsRedemption(0, depositReceiptTokenAmount_);
    assertEq(previewedRewardAssetAmount_, 0);
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
