// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {RewardsManagerInspector} from "../src/lib/RewardsManagerInspector.sol";
import {RewardPool, StakePool} from "../src/lib/structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract RewardsManagerInspectorTest is TestBase {
  MockERC20 mockAsset = new MockERC20("Mock Asset Token", "cozyAsset", 18);
  MockERC20 mockRewardPoolReceiptToken = new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6);
  MockERC20 mockStakePoolReceiptToken = new MockERC20("Mock Cozy stake Token", "cozyStk", 6);

  TestableRewardsManagerInspector component = new TestableRewardsManagerInspector();

  function setUp() public {
    RewardPool memory initialRewardPool_ = RewardPool({
      asset: IERC20(address(mockAsset)),
      depositReceiptToken: IReceiptToken(address(mockRewardPoolReceiptToken)),
      dripModel: IDripModel(address(0)),
      undrippedRewards: 0,
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });
    component.mockAddRewardPool(initialRewardPool_);

    StakePool memory initialStakePool_ = StakePool({
      asset: IERC20(address(mockAsset)),
      stkReceiptToken: IReceiptToken(address(mockStakePoolReceiptToken)),
      amount: 0,
      rewardsWeight: 0
    });
    component.mockAddStakePool(initialStakePool_);
  }

  function test_convertRewardAssetToReceiptTokenAmount_zeroTotalSupply(uint256 rewardAssetAmount_) external {
    uint256 rewardDepositReceiptTokenAmount = component.convertRewardAssetToReceiptTokenAmount(0, rewardAssetAmount_);
    assertEq(rewardDepositReceiptTokenAmount, rewardAssetAmount_); // 1:1 exchange rate.
  }

  function test_convertRewardAssetToReceiptTokenAmount_totalSupplyGtZero() public {
    component.setRewardPoolUndrippedRewards(0, 100);
    mockRewardPoolReceiptToken.mint(address(0), 50);
    uint256 rewardAssetAmount_ = 100;
    uint256 rewardDepositReceiptTokenAmount = component.convertRewardAssetToReceiptTokenAmount(0, rewardAssetAmount_);
    assertEq(rewardDepositReceiptTokenAmount, 50); // 100 * 50 / 100

    mockRewardPoolReceiptToken.mint(address(0), 950);
    rewardDepositReceiptTokenAmount = component.convertRewardAssetToReceiptTokenAmount(0, rewardAssetAmount_);
    assertEq(rewardDepositReceiptTokenAmount, 1000); // 100 * 1000 / 100

    mockRewardPoolReceiptToken.burn(address(0), 999);
    rewardDepositReceiptTokenAmount = component.convertRewardAssetToReceiptTokenAmount(0, rewardAssetAmount_);
    assertEq(rewardDepositReceiptTokenAmount, 1); // 100 * 1 / 100
  }

  function test_convertRewardAssetToReceiptTokenAmount_zeroUndrippedRewards() public {
    component.setRewardPoolUndrippedRewards(0, 0);
    mockRewardPoolReceiptToken.mint(address(0), 50);
    uint256 rewardAssetAmount_ = 100;
    uint256 rewardDepositReceiptTokenAmount = component.convertRewardAssetToReceiptTokenAmount(0, rewardAssetAmount_);
    // The undripped rewards amount is floored to 1.
    assertEq(rewardDepositReceiptTokenAmount, 5000); // 100 * 50 / 1
  }

  function test_convertRewardAssetToReceiptTokenAmount_zeroRewardAssetAmount() public {
    component.setRewardPoolUndrippedRewards(0, 100);
    mockRewardPoolReceiptToken.mint(address(0), 50);
    uint256 rewardAssetAmount_ = 0;
    uint256 rewardDepositReceiptTokenAmount = component.convertRewardAssetToReceiptTokenAmount(0, rewardAssetAmount_);
    assertEq(rewardDepositReceiptTokenAmount, 0);

    // The undripped rewards amount is floored to 1, and the result is still 0.
    component.setRewardPoolUndrippedRewards(0, 0);
    rewardDepositReceiptTokenAmount = component.convertRewardAssetToReceiptTokenAmount(0, rewardAssetAmount_);
    assertEq(rewardDepositReceiptTokenAmount, 0);
  }

  function test_convertRewardReceiptTokenToAssetAmount_zeroTotalSupply(uint256 receiptTokenAmount_) public {
    uint256 rewardAssetAmount_ = component.convertRewardReceiptTokenToAssetAmount(0, receiptTokenAmount_);
    assertEq(rewardAssetAmount_, 0);
  }

  function test_convertRewardReceiptTokenToAssetAmount_totalSupplyGtZero() public {
    component.setRewardPoolUndrippedRewards(0, 100);
    mockRewardPoolReceiptToken.mint(address(0), 50);
    uint256 rewardAssetAmount_ = component.convertRewardReceiptTokenToAssetAmount(0, 50);
    assertEq(rewardAssetAmount_, 100); // 50 * 100 / 50

    mockRewardPoolReceiptToken.mint(address(0), 950);
    rewardAssetAmount_ = component.convertRewardReceiptTokenToAssetAmount(0, 3000);
    assertEq(rewardAssetAmount_, 300); // 3000 * 100 / 1000

    mockRewardPoolReceiptToken.burn(address(0), 999);
    rewardAssetAmount_ = component.convertRewardReceiptTokenToAssetAmount(0, 2);
    assertEq(rewardAssetAmount_, 200); // 2 * 100 / 1
  }

  function test_convertRewardReceiptTokenToAssetAmount_zeroUndrippedRewards() public {
    component.setRewardPoolUndrippedRewards(0, 0);
    mockRewardPoolReceiptToken.mint(address(0), 50);
    uint256 rewardAssetAmount_ = component.convertRewardReceiptTokenToAssetAmount(0, 50);
    // The undripped rewards amount is floored to 1.
    assertEq(rewardAssetAmount_, 1); // 50 * 1 / 50
  }

  function test_convertRewardReceiptTokenToAssetAmount_zeroReceiptTokenAmount() public {
    component.setRewardPoolUndrippedRewards(0, 100);
    mockRewardPoolReceiptToken.mint(address(0), 50);
    uint256 rewardAssetAmount_ = component.convertRewardReceiptTokenToAssetAmount(0, 0);
    assertEq(rewardAssetAmount_, 0);

    // The undripped rewards amount is floored to 1, and the result is still 0.
    component.setRewardPoolUndrippedRewards(0, 0);
    rewardAssetAmount_ = component.convertRewardReceiptTokenToAssetAmount(0, 0);
    assertEq(rewardAssetAmount_, 0);
  }

  function test_convertStakeAssetToReceiptTokenAmount_zeroTotalSupply(uint256 stakeAssetAmount_) public {
    uint256 stakeReceiptTokenAmount = component.convertStakeAssetToReceiptTokenAmount(0, stakeAssetAmount_);
    assertEq(stakeReceiptTokenAmount, stakeAssetAmount_); // 1:1 exchange rate.
  }

  function test_convertStakeAssetToReceiptTokenAmount_totalSupplyGtZero() public {
    mockStakePoolReceiptToken.mint(address(0), 50);
    component.setStakePoolAmount(0, 100);
    uint256 stakeAssetAmount_ = 100;
    uint256 stakeReceiptTokenAmount = component.convertStakeAssetToReceiptTokenAmount(0, stakeAssetAmount_);
    assertEq(stakeReceiptTokenAmount, 50); // 100 * 50 / 100

    mockStakePoolReceiptToken.mint(address(0), 950);
    stakeReceiptTokenAmount = component.convertStakeAssetToReceiptTokenAmount(0, 100);
    assertEq(stakeReceiptTokenAmount, 1000); // 100 * 1000 / 100

    mockStakePoolReceiptToken.burn(address(0), 999);
    stakeReceiptTokenAmount = component.convertStakeAssetToReceiptTokenAmount(0, 100);
    assertEq(stakeReceiptTokenAmount, 1); // 100 * 1 / 100
  }

  function test_convertStakeReceiptTokenToAssetAmount_zeroTotalSupply(uint256 stakeReceiptTokenAmount_) public {
    uint256 stakeAssetAmount_ = component.convertStakeReceiptTokenToAssetAmount(0, stakeReceiptTokenAmount_);
    assertEq(stakeAssetAmount_, 0);
  }

  function test_convertStakeReceiptTokenToAssetAmount_totalSupplyGtZero() public {
    component.setStakePoolAmount(0, 100);
    mockStakePoolReceiptToken.mint(address(0), 50);
    uint256 stakeAssetAmount_ = component.convertStakeReceiptTokenToAssetAmount(0, 50);
    assertEq(stakeAssetAmount_, 100); // 50 * 100 / 50

    mockStakePoolReceiptToken.mint(address(0), 950);
    stakeAssetAmount_ = component.convertStakeReceiptTokenToAssetAmount(0, 3000);
    assertEq(stakeAssetAmount_, 300); // 3000 * 100 / 1000

    mockStakePoolReceiptToken.burn(address(0), 999);
    stakeAssetAmount_ = component.convertStakeReceiptTokenToAssetAmount(0, 2);
    assertEq(stakeAssetAmount_, 200); // 2 * 100 / 1
  }

  function test_convertStakeReceiptTokenToAssetAmount_zeroReceiptTokenAmount() public {
    uint256 stakeAssetAmount_ = component.convertStakeReceiptTokenToAssetAmount(0, 0);
    assertEq(stakeAssetAmount_, 0);
  }
}

contract TestableRewardsManagerInspector is RewardsManagerInspector {
  // -------- Mock setters --------

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function mockAddStakePool(StakePool memory stakePool_) external {
    stakePools.push(stakePool_);
  }

  function setRewardPoolUndrippedRewards(uint256 rewardPoolId_, uint256 undrippedRewards_) external {
    rewardPools[rewardPoolId_].undrippedRewards = undrippedRewards_;
  }

  function setStakePoolAmount(uint256 stakePoolId_, uint256 amount_) external {
    stakePools[stakePoolId_].amount = amount_;
  }

  // -------- Overridden abstract function placeholders --------

  function _assertValidDepositBalance(IERC20, /*token_*/ uint256, /*tokenPoolBalance_*/ uint256 /*depositAmount_*/ )
    internal
    view
    override
  {
    __readStub__();
  }

  function _claimRewards(uint16, /* stakePoolId_ */ address, /* receiver_ */ address /* owner */ ) internal override {
    __writeStub__();
  }

  function dripRewards() public view override {
    __readStub__();
  }

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 /* lastDripTime_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
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
    uint256, /*userStkTokenBalance_*/
    mapping(uint16 => ClaimableRewardsData) storage, /*claimableRewards_*/
    UserRewardsData[] storage /*userRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _dripRewardPool(RewardPool storage /* rewardPool_ */ ) internal override {
    __writeStub__();
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
