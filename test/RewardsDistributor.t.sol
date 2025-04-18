// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {ICommonErrors} from "cozy-safety-module-libs/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-libs/interfaces/IReceiptToken.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-libs/lib/Ownable.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {RewardsDistributor} from "../src/lib/RewardsDistributor.sol";
import {RewardsManagerInspector} from "../src/lib/RewardsManagerInspector.sol";
import {RewardsManagerState} from "../src/lib/RewardsManagerStates.sol";
import {Staker} from "../src/lib/Staker.sol";
import {AssetPool, StakePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {
  UserRewardsData,
  PreviewClaimableRewardsData,
  PreviewClaimableRewards,
  ClaimableRewardsData
} from "../src/lib/structs/Rewards.sol";
import {IdLookup} from "../src/lib/structs/Pools.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {MockStkReceiptToken} from "./utils/MockStkReceiptToken.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract RewardsDistributorUnitTest is TestBase {
  using FixedPointMathLib for uint256;

  TestableRewardsDistributor component = new TestableRewardsDistributor();

  uint256 internal constant ONE_YEAR = 365.25 days;

  event ClaimedRewards(
    uint16 indexed stakePoolId_,
    uint16 indexed rewardPoolId_,
    IERC20 rewardAsset_,
    uint256 amount_,
    address indexed owner_,
    address receiver_
  );

  function _setUpRewardPools(uint256 numRewardAssets_) internal {
    for (uint256 i = 0; i < numRewardAssets_; i++) {
      MockERC20 mockRewardAsset_ = new MockERC20("Mock Reward Asset", "MockRewardAsset", 6);
      uint256 undrippedRewards_ = _randomUint64();

      RewardPool memory rewardPool_ = RewardPool({
        undrippedRewards: undrippedRewards_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp),
        asset: IERC20(address(mockRewardAsset_)),
        dripModel: IDripModel(address(new MockDripModel(0.1e18))) // Constant 10% drip rate
      });
      component.mockAddRewardPool(rewardPool_);

      // Mint rewards manager the undripped rewards and initialize the asset pool.
      mockRewardAsset_.mint(address(component), undrippedRewards_);
      component.mockAddAssetPool(IERC20(address(mockRewardAsset_)), AssetPool({amount: undrippedRewards_}));
    }
  }

  function _setUpStakePools(uint256 numStakePools_, bool zeroStakeAmount_) internal {
    for (uint16 i = 0; i < numStakePools_; i++) {
      MockERC20 mockStakeAsset_ = new MockERC20("Mock Stake Asset", "MockStakeAsset", 6);
      IReceiptToken stkReceiptToken_ = IReceiptToken(
        address(new MockStkReceiptToken(address(component), "Mock StkReceiptToken", "MockStkReceiptToken", 6))
      );
      uint256 stakeAmount_ = zeroStakeAmount_ ? 0 : _randomUint64();

      StakePool memory stakePool_ = StakePool({
        amount: stakeAmount_,
        asset: IERC20(address(mockStakeAsset_)),
        stkReceiptToken: stkReceiptToken_,
        rewardsWeight: uint16(MathConstants.ZOC / numStakePools_)
      });

      component.mockRegisterStkReceiptToken(i, stkReceiptToken_);
      component.mockAddStakePool(stakePool_);

      // Mint rewards manager the stake assets and initialize the asset pool.
      mockStakeAsset_.mint(address(component), stakeAmount_);
      component.mockAddAssetPool(IERC20(address(mockStakeAsset_)), AssetPool({amount: stakeAmount_}));

      stkReceiptToken_.mint(address(0), stakeAmount_);
    }
  }

  function _setUpClaimableRewards(uint256 numStakePools_, uint256 numRewardAssets_) internal {
    for (uint16 i = 0; i < numStakePools_; i++) {
      for (uint16 j = 0; j < numRewardAssets_; j++) {
        component.mockSetClaimableRewardsData(i, j, uint128(_randomUint64()), 0);
      }
    }
  }

  function _setUpDefault() internal {
    uint256 numStakePools_ = 2;
    uint256 numRewardAssets_ = 3;

    _setUpStakePools(numStakePools_, false);
    _setUpRewardPools(numRewardAssets_);
    _setUpClaimableRewards(numStakePools_, numRewardAssets_);
  }

  function _setUpConcrete() internal {
    // Set-up two stake pools.
    MockERC20 mockStakeAssetA_ = new MockERC20("Mock Stake Asset A", "MockStakeAssetA", 6);
    IReceiptToken stkReceiptTokenA_ = IReceiptToken(
      address(new MockStkReceiptToken(address(component), "Mock StkReceiptToken A", "MockStkReceiptTokenA", 6))
    );
    uint256 stakeAmountA_ = 100e6;
    StakePool memory stakePoolA_ = StakePool({
      amount: stakeAmountA_,
      asset: IERC20(address(mockStakeAssetA_)),
      stkReceiptToken: stkReceiptTokenA_,
      rewardsWeight: 0.1e4 // 10% weight
    });

    MockERC20 mockStakeAssetB_ = new MockERC20("Mock Stake Asset B", "MockStakeAssetB", 6);
    IReceiptToken stkReceiptTokenB_ = IReceiptToken(
      address(new MockStkReceiptToken(address(component), "Mock StkReceiptToken", "MockStkReceiptTokenB", 6))
    );
    uint256 stakeAmountB_ = 200e6;
    StakePool memory stakePoolB_ = StakePool({
      amount: stakeAmountB_,
      asset: IERC20(address(mockStakeAssetB_)),
      stkReceiptToken: stkReceiptTokenB_,
      rewardsWeight: 0.9e4 // 90% weight
    });

    component.mockRegisterStkReceiptToken(0, stkReceiptTokenA_);
    component.mockRegisterStkReceiptToken(1, stkReceiptTokenB_);

    component.mockAddStakePool(stakePoolA_);
    component.mockAddStakePool(stakePoolB_);

    mockStakeAssetA_.mint(address(component), stakeAmountA_);
    component.mockAddAssetPool(IERC20(address(mockStakeAssetA_)), AssetPool({amount: stakeAmountA_}));
    stkReceiptTokenA_.mint(address(0), stakeAmountA_);

    mockStakeAssetB_.mint(address(component), stakeAmountB_);
    component.mockAddAssetPool(IERC20(address(mockStakeAssetB_)), AssetPool({amount: stakeAmountB_}));
    stkReceiptTokenB_.mint(address(0), stakeAmountB_);

    // Set-up three reward pools.
    {
      MockERC20 mockRewardAssetA_ = new MockERC20("Mock Reward Asset A", "MockRewardAssetA", 6);
      uint256 undrippedRewardsA_ = 100_000;

      RewardPool memory rewardPoolA_ = RewardPool({
        undrippedRewards: undrippedRewardsA_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp),
        asset: IERC20(address(mockRewardAssetA_)),
        dripModel: IDripModel(address(new DripModelExponential(318_475_925))) // 1% drip rate
      });
      component.mockAddRewardPool(rewardPoolA_);

      mockRewardAssetA_.mint(address(component), undrippedRewardsA_);
      component.mockAddAssetPool(IERC20(address(mockRewardAssetA_)), AssetPool({amount: undrippedRewardsA_}));
    }

    {
      MockERC20 mockRewardAssetB_ = new MockERC20("Mock Reward Asset B", "MockRewardAssetB", 18);
      uint256 undrippedRewardsB_ = 1_000_000_000;

      RewardPool memory rewardPoolB_ = RewardPool({
        undrippedRewards: undrippedRewardsB_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp),
        asset: IERC20(address(mockRewardAssetB_)),
        dripModel: IDripModel(address(new DripModelExponential(9_116_094_774))) // 25% annual drip rate
      });
      component.mockAddRewardPool(rewardPoolB_);

      mockRewardAssetB_.mint(address(component), undrippedRewardsB_);
      component.mockAddAssetPool(IERC20(address(mockRewardAssetB_)), AssetPool({amount: undrippedRewardsB_}));
    }

    {
      MockERC20 mockRewardAssetC_ = new MockERC20("Mock Reward Asset C", "MockRewardAssetC", 18);
      uint256 undrippedRewardsC_ = 9999;

      RewardPool memory rewardPoolC_ = RewardPool({
        undrippedRewards: undrippedRewardsC_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp),
        asset: IERC20(address(mockRewardAssetC_)),
        dripModel: IDripModel(address(new DripModelExponential(145_929_026_605))) // 99% annual drip rate
      });
      component.mockAddRewardPool(rewardPoolC_);

      mockRewardAssetC_.mint(address(component), undrippedRewardsC_);
      component.mockAddAssetPool(IERC20(address(mockRewardAssetC_)), AssetPool({amount: undrippedRewardsC_}));
    }
  }

  function _stake(uint16 stakePoolId_, uint256 amount_, address user_) internal {
    StakePool memory stakePool_ = component.getStakePool(stakePoolId_);
    MockERC20 mockStakeAsset_ = MockERC20(address(stakePool_.asset));
    mockStakeAsset_.mint(user_, amount_);

    vm.startPrank(user_);
    mockStakeAsset_.approve(address(component), amount_);
    component.stake(stakePoolId_, amount_, user_);
    vm.stopPrank();
  }

  function _getUserClaimRewardsFixture() internal returns (address user_, uint16 stakePoolId_, address receiver_) {
    user_ = _randomAddress();
    receiver_ = _randomAddress();
    stakePoolId_ = _randomUint16() % uint16(component.getStakePools().length);
    uint256 stakeAmount_ = bound(_randomUint64(), 1, type(uint64).max);

    // Mint user stake assets.
    StakePool memory stakePool_ = component.getStakePool(stakePoolId_);
    MockERC20 mockStakeAsset_ = MockERC20(address(stakePool_.asset));
    mockStakeAsset_.mint(user_, stakeAmount_);

    vm.startPrank(user_);
    mockStakeAsset_.approve(address(component), type(uint256).max);
    component.stake(stakePoolId_, stakeAmount_, user_);
    vm.stopPrank();
  }

  function _calculateExpectedDripQuantity(uint256 poolAmount_, uint256 dripFactor_) internal pure returns (uint256) {
    return poolAmount_.mulWadDown(dripFactor_);
  }

  function _calculateExpectedUpdateToClaimableRewardsData(
    uint256 totalDrippedRewards_,
    uint256 rewardsPoolsWeight_,
    uint256 stkReciptTokenSupply_
  ) internal pure returns (uint256) {
    uint256 scaledDrippedRewards_ = totalDrippedRewards_.mulDivDown(rewardsPoolsWeight_, MathConstants.ZOC);
    return scaledDrippedRewards_.divWadDown(stkReciptTokenSupply_);
  }
}

contract RewardsDepositorDripUnitTest is RewardsDistributorUnitTest {
  function test_noDripIfNoTimeElapsed() public {
    _setUpDefault();

    RewardPool[] memory initialRewardPools_ = component.getRewardPools();
    ClaimableRewardsData[][] memory initialClaimableRewards_ = component.getClaimableRewards();

    component.dripRewards();
    assertEq(component.getRewardPools(), initialRewardPools_);
    assertEq(component.getClaimableRewards(), initialClaimableRewards_);
  }

  function test_dripRewardsRevertsIfPaused() public {
    _setUpDefault();
    component.mockRewardsManagerState(RewardsManagerState.PAUSED);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    component.dripRewards();
    vm.expectRevert(ICommonErrors.InvalidState.selector);
    component.dripRewardPool(0);
  }

  function test_rewardsDripConcrete() public {
    _setUpConcrete();
    RewardPool[] memory expectedRewardPools_ = component.getRewardPools();

    // (1 - dripRate) * undrippedRewards = (1.0 - 0.01) * 100_000
    expectedRewardPools_[0].undrippedRewards = 99_000;
    // dripRate * undrippedRewards = 0.01 * 100_000
    expectedRewardPools_[0].cumulativeDrippedRewards = 1000;
    expectedRewardPools_[0].lastDripTime = uint128(block.timestamp + ONE_YEAR);

    // (1 - dripRate) * undrippedRewards = (1.0 - 0.25) * 1_000_000_000
    expectedRewardPools_[1].undrippedRewards = 750_000_000;
    // dripRate * undrippedRewards = 0.25 * 1_000_000_000
    expectedRewardPools_[1].cumulativeDrippedRewards = 250_000_000;
    expectedRewardPools_[1].lastDripTime = uint128(block.timestamp + ONE_YEAR);

    // (1 - dripRate) * undrippedRewards ~= 0.01 * 9999
    expectedRewardPools_[2].undrippedRewards = 100;
    // dripRate * undrippedRewards ~= 0.99 * 9999
    expectedRewardPools_[2].cumulativeDrippedRewards = 9899;
    expectedRewardPools_[2].lastDripTime = uint128(block.timestamp + ONE_YEAR);

    skip(ONE_YEAR);
    component.dripRewards();
    assertEq(component.getRewardPools(), expectedRewardPools_);
  }

  function testFuzz_rewardsDrip(uint64 timeElapsed_) public {
    _setUpDefault();

    timeElapsed_ = uint64(bound(timeElapsed_, 1, type(uint64).max));
    skip(timeElapsed_);

    RewardPool[] memory rewardPools_ = component.getRewardPools();
    uint256 numRewardAssets_ = rewardPools_.length;

    for (uint16 i = 0; i < numRewardAssets_; i++) {
      RewardPool memory setUpRewardPool_ = rewardPools_[i];
      // Set up drip rate.
      uint256 setUpDripRate_ = _randomUint256() % MathConstants.WAD;
      MockDripModel model_ = new MockDripModel(setUpDripRate_);
      setUpRewardPool_.dripModel = model_;
      // Update reward pool with model that has a new drip rate.
      component.mockSetRewardPool(i, setUpRewardPool_);

      // Define expected reward pool after drip.
      RewardPool memory expectedRewardPool_ = rewardPools_[i];
      expectedRewardPool_.dripModel = model_;
      uint256 totalDrippedAssets_ = _calculateExpectedDripQuantity(expectedRewardPool_.undrippedRewards, setUpDripRate_);
      expectedRewardPool_.undrippedRewards -= totalDrippedAssets_;
      expectedRewardPool_.cumulativeDrippedRewards += totalDrippedAssets_;
      expectedRewardPool_.lastDripTime = uint128(block.timestamp);

      rewardPools_[i] = expectedRewardPool_;
    }

    component.dripRewards();
    assertEq(component.getRewardPools(), rewardPools_);
  }

  function testFuzz_rewardsDripSinglePool(uint64 timeElapsed_) public {
    _setUpDefault();

    timeElapsed_ = uint64(bound(timeElapsed_, 1, type(uint64).max));
    skip(timeElapsed_);

    RewardPool[] memory rewardPools_ = component.getRewardPools();
    uint16 rewardPoolId_ = _randomUint16() % uint16(rewardPools_.length);

    RewardPool memory setUpRewardPool_ = rewardPools_[rewardPoolId_];
    // Set up drip rate.
    uint256 setUpDripRate_ = _randomUint256() % MathConstants.WAD;
    MockDripModel model_ = new MockDripModel(setUpDripRate_);
    setUpRewardPool_.dripModel = model_;
    // Update reward pool with model that has a new drip rate.
    component.mockSetRewardPool(rewardPoolId_, setUpRewardPool_);

    // Define expected reward pool after drip.
    RewardPool memory expectedRewardPool_ = rewardPools_[rewardPoolId_];
    expectedRewardPool_.dripModel = model_;
    uint256 totalDrippedAssets_ = _calculateExpectedDripQuantity(expectedRewardPool_.undrippedRewards, setUpDripRate_);
    expectedRewardPool_.undrippedRewards -= totalDrippedAssets_;
    expectedRewardPool_.cumulativeDrippedRewards += totalDrippedAssets_;
    expectedRewardPool_.lastDripTime = uint128(block.timestamp);
    rewardPools_[rewardPoolId_] = expectedRewardPool_;

    component.dripRewardPool(rewardPoolId_);
    // Only the reward pool with id `rewardPoolId_` should have been updated.
    assertEq(component.getRewardPools(), rewardPools_);
  }

  function test_revertOnInvalidDripFactor() public {
    _setUpDefault();

    skip(_randomUint64());

    // Update a random reward pool to an invalid drip model.
    uint256 dripRate_ = MathConstants.WAD + 1;
    MockDripModel model_ = new MockDripModel(dripRate_);
    uint16 rewardPoolId_ = _randomUint16() % uint16(component.getRewardPools().length);
    RewardPool memory rewardPool_ = component.getRewardPool(rewardPoolId_);
    rewardPool_.dripModel = model_;
    component.mockSetRewardPool(rewardPoolId_, rewardPool_);

    vm.expectRevert(ICommonErrors.InvalidDripFactor.selector);
    component.dripRewards();
  }
}

contract RewardsDistributorClaimUnitTest is RewardsDistributorUnitTest {
  using FixedPointMathLib for uint256;

  function test_claimRewardsConcrete() public {
    _setUpConcrete();

    RewardPool[] memory rewardPools_ = component.getRewardPools();
    uint256 numRewardAssets_ = rewardPools_.length;
    IERC20 rewardAssetA_ = rewardPools_[0].asset;
    IERC20 rewardAssetB_ = rewardPools_[1].asset;
    IERC20 rewardAssetC_ = rewardPools_[2].asset;

    // UserA stakes 100e6 in stakePoolA, increasing stkReceiptTokenSupply to 200e6.
    // UserA owns 50% of total stake, 200e6.
    address userA_ = _randomAddress();
    _stake(0, 100e6, userA_);

    // UserB stakes 800e6 in stakePoolB, increasing stkReceiptTokenSupply to 1000e6.
    // UserB owns 80% of total stake, 1000e6.
    address userB_ = _randomAddress();
    _stake(1, 800e6, userB_);

    skip(ONE_YEAR);

    // UserA claims rewards from stakePoolA and sends to a receiver.
    {
      address rewardsReceiver_ = _randomAddress();
      uint16 stakePoolId_ = 0;

      // Rewards received by userA are calculated as:
      //    drippedRewards * rewardsWeight * (userStkReceiptTokenBalance / totalStkReceiptTokenSupply)
      // rounded down.
      // drippedRewardsA_ = 0.01 * 100_000
      // drippedRewardsB_ = 0.25 * 1_000_000_000
      // drippedRewardsC_ = 0.99 * 9999
      uint256 rewardsReceivedPoolA_ = 50; // drippedRewardsA_ * 0.1 * 0.5
      uint256 rewardsReceivedPoolB_ = 12_500_000; // drippedRewardsB_ * 0.1 * 0.5
      uint256 rewardsReceivedPoolC_ = 494; // drippedRewardsC_ * 0.1 * 0.5

      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 0, rewardAssetA_, rewardsReceivedPoolA_, userA_, rewardsReceiver_);
      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 1, rewardAssetB_, rewardsReceivedPoolB_, userA_, rewardsReceiver_);
      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 2, rewardAssetC_, rewardsReceivedPoolC_, userA_, rewardsReceiver_);

      vm.prank(userA_);
      component.claimRewards(stakePoolId_, rewardsReceiver_);

      // Check that the rewards receiver received the assets.
      assertEq(rewardAssetA_.balanceOf(rewardsReceiver_), rewardsReceivedPoolA_);
      assertEq(rewardAssetB_.balanceOf(rewardsReceiver_), rewardsReceivedPoolB_);
      assertEq(rewardAssetC_.balanceOf(rewardsReceiver_), rewardsReceivedPoolC_);

      // Since user claimed rewards, accrued rewards should be 0 and index snapshot should be updated.
      UserRewardsData[] memory userRewardsData_ = component.getUserRewards(stakePoolId_, userA_);
      UserRewardsData[] memory expectedUserRewardsData_ = new UserRewardsData[](3);
      for (uint16 i = 0; i < numRewardAssets_; i++) {
        expectedUserRewardsData_[i] = UserRewardsData({
          accruedRewards: 0,
          indexSnapshot: component.getClaimableRewardsData(stakePoolId_, i).indexSnapshot
        });
      }
      assertEq(userRewardsData_, expectedUserRewardsData_);

      // Claimable reward indices should be updated as:
      //    oldIndex + [(drippedRewards * rewardsWeight) / stkReceiptTokenSupply] * WAD
      ClaimableRewardsData[] memory claimableRewards_ = component.getClaimableRewards(stakePoolId_);
      assertEq(claimableRewards_[0].indexSnapshot, 500_000_000_000 * MathConstants.WAD); // ~= 0 + [(drippedRewardsA_ *
        // 0.1) / 200e6] * WAD^2
      assertEq(claimableRewards_[1].indexSnapshot, 125_000_000_000_000_000 * MathConstants.WAD); // ~= 0 +
        // [(drippedRewardsB_ * 0.1) /
        // 200e6] * WAD^2
      assertEq(claimableRewards_[2].indexSnapshot, 4_945_000_000_000 * MathConstants.WAD); // ~= 0 + [(drippedRewardsC_
        // * 0.1) / 200e6] *
        // WAD^2
    }

    skip(ONE_YEAR);

    // UserB stakes 200e6 in stakePoolA, increasing stkReceiptTokenSupply to 0.4e18.
    // UserB owns 50% of total stake, 400e6.
    _stake(0, 200e6, userB_);

    // UserA claims rewards again from stakePoolA and sends to a receiver.
    {
      address rewardsReceiver_ = _randomAddress();
      uint16 stakePoolId_ = 0;

      // Rewards received by userA are calculated as:
      //    drippedRewards * rewardsWeight * (userStkReceiptTokenBalance / totalStkReceiptTokenSupply)
      // rounded down. Time skipped one year before userB's stake into stakePoolA, so for the entirety of the skip userA
      // still owned 50% of the stake.
      // drippedRewardsA_ = 0.01 * 99_000
      // drippedRewardsB_ = 0.25 * 750_000_000
      // drippedRewardsC_ = 0.99 * 100
      uint256 rewardsReceivedPoolA_ = 49; // drippedRewardsA_ * 0.1 * 0.5
      uint256 rewardsReceivedPoolB_ = 9_375_000; // drippedRewardsB_ * 0.1 * 0.5
      uint256 rewardsReceivedPoolC_ = 5; // drippedRewardsC_ * 0.1 * 0.5

      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 0, rewardAssetA_, rewardsReceivedPoolA_, userA_, rewardsReceiver_);
      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 1, rewardAssetB_, rewardsReceivedPoolB_, userA_, rewardsReceiver_);
      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 2, rewardAssetC_, rewardsReceivedPoolC_, userA_, rewardsReceiver_);

      vm.prank(userA_);
      component.claimRewards(stakePoolId_, rewardsReceiver_);

      // Check that the rewards receiver received the assets.
      assertEq(rewardAssetA_.balanceOf(rewardsReceiver_), rewardsReceivedPoolA_);
      assertEq(rewardAssetB_.balanceOf(rewardsReceiver_), rewardsReceivedPoolB_);
      assertEq(rewardAssetC_.balanceOf(rewardsReceiver_), rewardsReceivedPoolC_);

      // Since user claimed rewards, accrued rewards should be 0 and index snapshot should be updated.
      UserRewardsData[] memory userRewardsData_ = component.getUserRewards(stakePoolId_, userA_);
      UserRewardsData[] memory expectedUserRewardsData_ = new UserRewardsData[](3);
      for (uint16 i = 0; i < numRewardAssets_; i++) {
        expectedUserRewardsData_[i] = UserRewardsData({
          accruedRewards: 0,
          indexSnapshot: component.getClaimableRewardsData(stakePoolId_, i).indexSnapshot
        });
      }
      assertEq(userRewardsData_, expectedUserRewardsData_);

      // Claimable reward indices should be updated as:
      //    oldIndex + [(drippedRewards * rewardsWeight) / stkReceiptTokenSupply] * WAD
      ClaimableRewardsData[] memory claimableRewards_ = component.getClaimableRewards(stakePoolId_);
      assertEq(claimableRewards_[0].indexSnapshot, 995_000_000_000 * MathConstants.WAD); // ~= 500000000000 +
        // [(drippedRewardsA_ * 0.1)/200e6] * WAD^2
      assertEq(claimableRewards_[1].indexSnapshot, 218_750_000_000_000_000 * MathConstants.WAD); // ~=
        // 125000000000000000 + [(drippedRewardsB_ * 0.1) / 200e6] * WAD^2
      assertEq(claimableRewards_[2].indexSnapshot, 4_995_000_000_000 * MathConstants.WAD); // ~= 4945000000000 +
        // [(drippedRewardsC_ * 0.1) / 200e6] * WAD^2
    }

    skip(ONE_YEAR);

    // UserB claims rewards from both stakePoolA and stakePoolB.
    {
      address rewardsReceiver_ = _randomAddress();
      uint16 stakePoolId_ = 0;

      // Rewards received by userA are calculated as:
      //    drippedRewards * rewardsWeight * (userStkReceiptTokenBalance / totalStkReceiptTokenSupply)
      // rounded down. Time skipped one year before userB's stake into stakePoolA, so for the entirety of the skip userA
      // still owned 50% of the stake.
      // drippedRewardsA_ = 0.01 * 98_010
      // drippedRewardsB_ = 0.25 * 562_500_000
      // drippedRewardsC_ = 0.99 * 0
      uint256 rewardsReceivedPoolA_ = 49; // drippedRewardsA_ * 0.1 * 0.5
      uint256 rewardsReceivedPoolB_ = 7_031_250; // drippedRewardsB_ * 0.1 * 0.5

      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 0, rewardAssetA_, rewardsReceivedPoolA_, userB_, rewardsReceiver_);
      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 1, rewardAssetB_, rewardsReceivedPoolB_, userB_, rewardsReceiver_);
      // Event is not emitted from rewardPoolC because no rewards are transfered.

      vm.prank(userB_);
      component.claimRewards(stakePoolId_, rewardsReceiver_);

      // Check that the rewards receiver received the assets.
      assertEq(rewardAssetA_.balanceOf(rewardsReceiver_), rewardsReceivedPoolA_);
      assertEq(rewardAssetB_.balanceOf(rewardsReceiver_), rewardsReceivedPoolB_);

      stakePoolId_ = 1;
      rewardsReceiver_ = _randomAddress();

      // It has been 3 years since userA_ staked into stakePoolB, userA_ owns 80% of the stake, and the rewardsWeight is
      // 0.8.
      // Rewards received by userA are calculated as:
      // drippedRewardsA_ = 0.01 * (100_000 + (1-0.01)*100_000 + (1-0.01)^2*100_000) = 2970
      // drippedRewardsB_ = 0.25 * (1_000_000_000 + (1-0.25)*1_000_000_000 + (1-0.25)^2*1_000_000_000) = 578_125_000
      // drippedRewardsC_ = 0.99 * (9999 + (1-0.99)*9999 + (1-0.99)^2*9999) = 9999
      rewardsReceivedPoolA_ = 2138; // drippedRewardsA_ * 0.9 * 0.8
      rewardsReceivedPoolB_ = 416_250_000; // drippedRewardsB_ * 0.9 * 0.8
      uint256 rewardsReceivedPoolC_ = 7198; // drippedRewardsC_ * 0.9 * 0.8

      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 0, rewardAssetA_, rewardsReceivedPoolA_, userB_, rewardsReceiver_);
      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 1, rewardAssetB_, rewardsReceivedPoolB_, userB_, rewardsReceiver_);
      _expectEmit();
      emit ClaimedRewards(stakePoolId_, 2, rewardAssetC_, rewardsReceivedPoolC_, userB_, rewardsReceiver_);

      vm.prank(userB_);
      component.claimRewards(stakePoolId_, rewardsReceiver_);

      // Since user claimed rewards, accrued rewards should be 0 and index snapshot should be updated.
      for (uint16 sid_ = 0; sid_ < 2; sid_++) {
        UserRewardsData[] memory userRewardsData_ = component.getUserRewards(sid_, userB_);
        UserRewardsData[] memory expectedUserRewardsData_ = new UserRewardsData[](numRewardAssets_);
        for (uint16 i = 0; i < numRewardAssets_; i++) {
          expectedUserRewardsData_[i] = UserRewardsData({
            accruedRewards: 0,
            indexSnapshot: component.getClaimableRewardsData(sid_, i).indexSnapshot
          });
        }
        assertEq(userRewardsData_, expectedUserRewardsData_);
      }
    }
  }

  function testFuzz_previewClaimableRewards(uint64 timeElapsed_) public {
    _setUpDefault();
    (address user_, uint16 stakePoolId_, address receiver_) = _getUserClaimRewardsFixture();
    vm.assume(stakePoolId_ != 0);

    // Compute original number of reward pools.
    uint256 oldNumRewardPools_ = component.getRewardPools().length;
    // Add new reward asset pool.
    {
      MockERC20 mockRewardAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
      uint256 undrippedRewards_ = _randomUint256() % 500_000_000;
      RewardPool memory rewardPool_ = RewardPool({
        undrippedRewards: undrippedRewards_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp),
        asset: IERC20(address(mockRewardAsset_)),
        dripModel: IDripModel(address(new DripModelExponential(318_475_925))) // 1% drip rate
      });
      component.mockAddRewardPool(rewardPool_);
      mockRewardAsset_.mint(address(component), undrippedRewards_);
      component.mockAddAssetPool(IERC20(address(mockRewardAsset_)), AssetPool({amount: undrippedRewards_}));
    }

    skip(timeElapsed_);

    vm.startPrank(user_);
    // User previews two pools, stakePoolId_ (the pool they staked into) and 0 (the pool they did not stake into).
    uint16[] memory previewStakePoolIds_ = new uint16[](2);
    previewStakePoolIds_[0] = stakePoolId_;
    previewStakePoolIds_[1] = 0;
    PreviewClaimableRewards[] memory previewClaimableRewards_ =
      component.previewClaimableRewards(previewStakePoolIds_, user_);
    component.claimRewards(stakePoolId_, receiver_);
    vm.stopPrank();

    // Check preview claimable rewards.
    PreviewClaimableRewards[] memory expectedPreviewClaimableRewards_ = new PreviewClaimableRewards[](2);
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    PreviewClaimableRewardsData[] memory expectedPreviewClaimableRewardsData_ =
      new PreviewClaimableRewardsData[](rewardPools_.length);
    PreviewClaimableRewardsData[] memory expectedPreviewClaimableRewardsDataPool0_ =
      new PreviewClaimableRewardsData[](rewardPools_.length);
    for (uint16 i = 0; i < rewardPools_.length; i++) {
      IERC20 asset_ = rewardPools_[i].asset;
      expectedPreviewClaimableRewardsData_[i] =
        PreviewClaimableRewardsData({rewardPoolId: i, amount: asset_.balanceOf(receiver_), asset: asset_});
      expectedPreviewClaimableRewardsDataPool0_[i] =
        PreviewClaimableRewardsData({rewardPoolId: i, amount: 0, asset: asset_});
    }
    expectedPreviewClaimableRewards_[0] =
      PreviewClaimableRewards({stakePoolId: stakePoolId_, claimableRewardsData: expectedPreviewClaimableRewardsData_});
    expectedPreviewClaimableRewards_[1] =
      PreviewClaimableRewards({stakePoolId: 0, claimableRewardsData: expectedPreviewClaimableRewardsDataPool0_});

    assertEq(previewClaimableRewards_, expectedPreviewClaimableRewards_);
    assertEq(previewClaimableRewards_[0].claimableRewardsData.length, oldNumRewardPools_ + 1);
    assertEq(previewClaimableRewards_[1].claimableRewardsData.length, oldNumRewardPools_ + 1);
  }

  function test_previewClaimableRewardsWhenPaused() public {
    _setUpConcrete();
    address user_ = _randomAddress();
    uint16 stakePoolId_ = 1;
    uint256 timeElapsed_ = ONE_YEAR;

    uint256 stakeAmount_ = 100e6;

    // Mint user stake assets.
    StakePool memory stakePool_ = component.getStakePool(stakePoolId_);
    MockERC20 mockStakeAsset_ = MockERC20(address(stakePool_.asset));
    mockStakeAsset_.mint(user_, stakeAmount_);
    vm.startPrank(user_);
    mockStakeAsset_.approve(address(component), type(uint256).max);
    component.stake(stakePoolId_, stakeAmount_, user_);
    vm.stopPrank();

    skip(timeElapsed_);

    // User previews two pools, stakePoolId_ (the pool they staked into) and 0 (the pool they did not stake into).
    uint16[] memory previewStakePoolIds_ = new uint16[](1);
    previewStakePoolIds_[0] = stakePoolId_;
    PreviewClaimableRewards[] memory previewClaimableRewards_ =
      component.previewClaimableRewards(previewStakePoolIds_, user_);
    assertEq(previewClaimableRewards_[0].claimableRewardsData[0].amount, 300);
    assertEq(previewClaimableRewards_[0].claimableRewardsData[1].amount, 75_000_000);
    assertEq(previewClaimableRewards_[0].claimableRewardsData[2].amount, 2969);

    // Rewards Manager becomes paused.
    component.mockRewardsManagerState(RewardsManagerState.PAUSED);
    skip(timeElapsed_);

    // Since the rewards manager is paused, the claimable rewards for the user should be 0 now, since rewards do not
    // drip while paused.
    PreviewClaimableRewards[] memory previewClaimableRewardsAfterPause_ =
      component.previewClaimableRewards(previewStakePoolIds_, user_);
    assertEq(previewClaimableRewardsAfterPause_[0].claimableRewardsData[0].amount, 0);
    assertEq(previewClaimableRewardsAfterPause_[0].claimableRewardsData[1].amount, 0);
    assertEq(previewClaimableRewardsAfterPause_[0].claimableRewardsData[2].amount, 0);
  }

  function testFuzz_claimRewards(uint64 timeElapsed_) public {
    _setUpDefault();
    (address user_, uint16 stakePoolId_, address receiver_) = _getUserClaimRewardsFixture();

    timeElapsed_ = uint64(bound(timeElapsed_, 1, type(uint64).max));
    skip(timeElapsed_);

    IReceiptToken stkReceiptToken_ = component.getStakePool(stakePoolId_).stkReceiptToken;
    uint256 userStkReceiptTokenBalance_ = stkReceiptToken_.balanceOf(user_);

    RewardPool[] memory oldRewardPools_ = component.getRewardPools();
    ClaimableRewardsData[] memory oldClaimableRewards_ = component.getClaimableRewards(stakePoolId_);

    vm.prank(user_);
    component.claimRewards(stakePoolId_, receiver_);

    RewardPool[] memory newRewardPools_ = component.getRewardPools();
    ClaimableRewardsData[] memory newClaimableRewards_ = component.getClaimableRewards(stakePoolId_);
    UserRewardsData[] memory newUserRewards_ = component.getUserRewards(stakePoolId_, user_);

    uint256 numRewardAssets_ = newRewardPools_.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      IERC20 rewardAsset_ = newRewardPools_[i].asset;
      uint256 accruedRewards_ = component.getUserAccruedRewards(
        userStkReceiptTokenBalance_, newClaimableRewards_[i].indexSnapshot, oldClaimableRewards_[i].indexSnapshot
      );

      // Check that the reward pools are updated. All reward pools should have been dripped per the constant 10% rate.
      uint256 drippedRewards_ = oldRewardPools_[i].undrippedRewards.mulWadDown(0.1e18);
      assertEq(
        newRewardPools_[i].cumulativeDrippedRewards, oldRewardPools_[i].cumulativeDrippedRewards + drippedRewards_
      );
      assertEq(newRewardPools_[i].lastDripTime, uint128(block.timestamp));
      assertEq(newRewardPools_[i].undrippedRewards, oldRewardPools_[i].undrippedRewards - drippedRewards_);

      // Check that claimable rewards are updated.
      assertGt(newClaimableRewards_[i].indexSnapshot, oldClaimableRewards_[i].indexSnapshot);
      assertGt(newClaimableRewards_[i].cumulativeClaimableRewards, oldClaimableRewards_[i].cumulativeClaimableRewards);

      // Check that user rewards are updated and transferred to receiver.
      assertEq(rewardAsset_.balanceOf(receiver_), accruedRewards_);
      assertEq(newUserRewards_[i].indexSnapshot, newClaimableRewards_[i].indexSnapshot);
      assertEq(newUserRewards_[i].accruedRewards, 0);
    }
  }

  function test_claimRewardsWithNewRewardAssets() public {
    _test_claimRewardsWithNewRewardAssets(5);
  }

  function test_claimRewardsWithZeroInitialRewardAssets() public {
    _test_claimRewardsWithNewRewardAssets(0);
  }

  function _test_claimRewardsWithNewRewardAssets(uint256 numRewardsPools_) public {
    uint256 numStakePools_ = 2;
    _setUpStakePools(numStakePools_, false);
    _setUpRewardPools(numRewardsPools_);
    _setUpClaimableRewards(numStakePools_, numRewardsPools_);

    (address user_, uint16 stakePoolId_, address receiver_) = _getUserClaimRewardsFixture();

    // Add new reward asset pool.
    MockERC20 mockRewardAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
    {
      uint256 undrippedRewards_ = 90_000;
      RewardPool memory rewardPool_ = RewardPool({
        undrippedRewards: undrippedRewards_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp),
        asset: IERC20(address(mockRewardAsset_)),
        dripModel: IDripModel(address(new MockDripModel(0.01e18))) // 1% drip rate
      });
      component.mockAddRewardPool(rewardPool_);
      mockRewardAsset_.mint(address(component), undrippedRewards_);
      component.mockAddAssetPool(IERC20(address(mockRewardAsset_)), AssetPool({amount: undrippedRewards_}));
    }

    StakePool memory stakePool_ = component.getStakePool(stakePoolId_);
    uint256 userStkReceiptTokenBalance_ = stakePool_.stkReceiptToken.balanceOf(user_);
    uint256 totalStkReceiptTokenBalance_ = stakePool_.stkReceiptToken.totalSupply();

    skip(bound(_randomUint64(), 1, type(uint64).max));
    vm.prank(user_);
    component.claimRewards(stakePoolId_, receiver_);

    // Make sure receiver received rewards from new reward asset pool.
    {
      uint256 totalDrippedRewards_ = 900; // 90_000 * 0.01
      uint256 drippedRewards_ = totalDrippedRewards_.mulDivDown(stakePool_.rewardsWeight, MathConstants.ZOC);
      uint256 receivedRewards_ = mockRewardAsset_.balanceOf(receiver_);
      uint256 expectedRewards_ =
        drippedRewards_.mulWadDown(userStkReceiptTokenBalance_.divWadDown(totalStkReceiptTokenBalance_));
      assertGt(receivedRewards_, 0);
      assertLe(receivedRewards_, expectedRewards_);
    }

    // Make sure user rewards data reflects new reward asset pool.
    {
      UserRewardsData[] memory userRewardsData_ = component.getUserRewards(stakePoolId_, user_);
      assertEq(userRewardsData_[numRewardsPools_].accruedRewards, 0);
      assertEq(
        userRewardsData_[numRewardsPools_].indexSnapshot,
        component.getClaimableRewardsData(stakePoolId_, uint16(numRewardsPools_)).indexSnapshot
      );
    }
  }

  function test_claimRewardsTwice() public {
    _setUpDefault();
    (address user_, uint16 stakePoolId_, address receiver_) = _getUserClaimRewardsFixture();

    skip(bound(_randomUint64(), 1, type(uint64).max));

    vm.startPrank(user_);
    component.claimRewards(stakePoolId_, receiver_);
    UserRewardsData[] memory oldUserRewardsData_ = component.getUserRewards(stakePoolId_, user_);
    vm.stopPrank();

    // User claims rewards again.
    address newReceiver_ = _randomAddress();
    vm.startPrank(user_);
    component.claimRewards(stakePoolId_, newReceiver_);
    UserRewardsData[] memory newUserRewardsData_ = component.getUserRewards(stakePoolId_, user_);
    vm.stopPrank();

    // User rewards data is unchanged.
    assertEq(oldUserRewardsData_, newUserRewardsData_);
    // New receiver receives no reward assets.
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    for (uint16 i = 0; i < rewardPools_.length; i++) {
      assertEq(rewardPools_[i].asset.balanceOf(newReceiver_), 0);
    }
  }

  function test_claimRewardsAfterTwoIndependentStakes() public {
    _setUpConcrete();

    address user_ = _randomAddress();
    address receiver_ = _randomAddress();

    // User stakes 100e6, increasing stkReceiptTokenSupply to 0.2e18. User owns 50% of total stake, 200e6.
    _stake(0, 100e6, user_);

    // User transfers all stkReceiptTokens to receiver.
    IERC20 stkReceiptToken = component.getStakePool(0).stkReceiptToken;
    vm.prank(user_);
    stkReceiptToken.transfer(receiver_, 100e6);

    // User stakes again. Again, user owns 50% of the new total stake, 400e6.
    _stake(0, 200e6, user_);

    skip(ONE_YEAR);
    // Both user and receiver claim rewards.
    vm.prank(user_);
    component.claimRewards(0, user_);
    vm.prank(receiver_);
    component.claimRewards(0, receiver_);

    IERC20 rewardAssetA_ = component.getRewardPool(0).asset;
    IERC20 rewardAssetB_ = component.getRewardPool(1).asset;
    IERC20 rewardAssetC_ = component.getRewardPool(2).asset;
    // Rewards received are equal to the amount dripped from each reward pool * rewardsWeight *
    // (userStkReceiptTokenBalance / totalStkReceiptTokenSupply).
    assertApproxEqAbs(rewardAssetA_.balanceOf(user_), 50, 1); // ~= 1000 * 0.1 * 0.5
    assertApproxEqAbs(rewardAssetB_.balanceOf(user_), 12_500_000, 1); // ~= 250000000 * 0.1 * 0.5
    assertApproxEqAbs(rewardAssetC_.balanceOf(user_), 494, 1); // ~= 9899 * 0.1 * 0.5
    assertApproxEqAbs(rewardAssetA_.balanceOf(receiver_), 25, 1); // ~= 1000 * 0.1 * 0.25
    assertApproxEqAbs(rewardAssetB_.balanceOf(receiver_), 6_249_999, 1); // ~= 250000000 * 0.1 * 0.25
    assertApproxEqAbs(rewardAssetC_.balanceOf(receiver_), 247, 1); // ~= 9899 * 0.1 * 0.25
  }

  function test_claimRewardsConcreteBatch() public {
    _setUpConcrete();

    address user_ = _randomAddress();
    address receiver_ = _randomAddress();

    // User stakes 800e6, increasing stkReceiptTokenSupply to 1e18. User owns 80% of total stake, 1000e6.
    _stake(1, 800e6, user_);
    skip(2 * ONE_YEAR);
    // User stakes 100e6, increasing stkReceiptTokenSupply to 0.2e18. User owns 50% of total stake, 200e6.
    _stake(0, 100e6, user_);
    skip(ONE_YEAR);

    IERC20 rewardAssetA_ = component.getRewardPool(0).asset;
    IERC20 rewardAssetB_ = component.getRewardPool(1).asset;
    IERC20 rewardAssetC_ = component.getRewardPool(2).asset;

    // These values should match exactly the accounting in `test_claimRewardsConcrete`.
    uint256 rewardsReceivedPoolA_ = 49 + 2138;
    uint256 rewardsReceivedPoolB_ = 7_031_250 + 416_250_000;
    uint256 rewardsReceivedPoolC_ = 7198;

    _expectEmit();
    emit ClaimedRewards(0, 0, rewardAssetA_, 49, user_, receiver_);
    _expectEmit();
    emit ClaimedRewards(0, 1, rewardAssetB_, 7_031_250, user_, receiver_);
    _expectEmit();
    emit ClaimedRewards(1, 0, rewardAssetA_, 2138, user_, receiver_);
    _expectEmit();
    emit ClaimedRewards(1, 1, rewardAssetB_, 416_250_000, user_, receiver_);
    _expectEmit();
    emit ClaimedRewards(1, 2, rewardAssetC_, 7198, user_, receiver_);

    uint16[] memory stakePoolIds_ = new uint16[](2);
    stakePoolIds_[0] = 0;
    stakePoolIds_[1] = 1;
    vm.startPrank(user_);
    component.claimRewards(stakePoolIds_, receiver_);
    vm.stopPrank();

    // Check that the rewards receiver received the assets.
    assertEq(rewardAssetA_.balanceOf(receiver_), rewardsReceivedPoolA_);
    assertEq(rewardAssetB_.balanceOf(receiver_), rewardsReceivedPoolB_);
    assertEq(rewardAssetC_.balanceOf(receiver_), rewardsReceivedPoolC_);
  }
}

contract RewardsDistributorStkReceiptTokenTransferUnitTest is RewardsDistributorUnitTest {
  function test_stkReceiptTokenTransferRewardsAccounting() public {
    _test_stkReceiptTokenTransferFuncRewardsAccounting(false);
  }

  function test_stkReceiptTokenTransferFromRewardsAccounting() public {
    _test_stkReceiptTokenTransferFuncRewardsAccounting(true);
  }

  function _test_stkReceiptTokenTransferFuncRewardsAccounting(bool useTransferFrom) internal {
    _setUpConcrete();
    address user_ = _randomAddress();
    address receiver_ = _randomAddress();

    // User stakes 100e6, increasing stkReceiptTokenSupply to 0.2e18. User owns 50% of total stake, 200e6.
    _stake(0, 100e6, user_);
    StakePool memory stakePool_ = component.getStakePool(0);

    // User transfers 25% the stkReceiptTokens.
    if (!useTransferFrom) {
      vm.prank(user_);
      stakePool_.stkReceiptToken.transfer(receiver_, 100e6 / 4);
    } else {
      address approvedAddress_ = _randomAddress();
      vm.prank(user_);
      stakePool_.stkReceiptToken.approve(approvedAddress_, type(uint256).max);

      vm.prank(approvedAddress_);
      stakePool_.stkReceiptToken.transferFrom(user_, receiver_, 100e6 / 4);
    }

    // Check stkReceiptToken balances.
    uint256 receiverStkReceiptTokenBalance_ = 100e6 / 4;
    assertEq(stakePool_.stkReceiptToken.balanceOf(user_), 100e6 - receiverStkReceiptTokenBalance_);
    assertEq(stakePool_.stkReceiptToken.balanceOf(receiver_), receiverStkReceiptTokenBalance_);

    skip(ONE_YEAR);

    // User claims rewards.
    vm.prank(user_);
    component.claimRewards(0, user_);

    // Check user rewards balances.
    RewardPool[] memory rewardPools_ = component.getRewardPools();

    IERC20 rewardAssetA_ = rewardPools_[0].asset;
    IERC20 rewardAssetB_ = rewardPools_[1].asset;
    IERC20 rewardAssetC_ = rewardPools_[2].asset;

    // Reward amounts received by `user_` are calculated as: rewardPool.amount * dripRate *
    // rewardsPoolWeight * (userstkReceiptTokenBalance / totalstkReceiptTokenSupply).
    assertApproxEqAbs(rewardAssetA_.balanceOf(user_), 37, 1); // 100_000 * 0.01 * 0.1 * (0.5 * 0.75)
    assertApproxEqAbs(rewardAssetB_.balanceOf(user_), 9_375_000, 1); // 1_000_000_000 * 0.25 * 0.1 *
      // (0.5 * 0.75)
    assertApproxEqAbs(rewardAssetC_.balanceOf(user_), 370, 1); // 9_999 * 0.99 * 0.1 * (0.5 * 0.75)

    UserRewardsData[] memory userRewardsData_ = component.getUserRewards(0, user_);
    UserRewardsData[] memory expectedUserRewardsData_ = new UserRewardsData[](3);
    for (uint16 i = 0; i < 3; i++) {
      expectedUserRewardsData_[i] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, i).indexSnapshot});
    }
    assertEq(userRewardsData_, expectedUserRewardsData_);

    skip(ONE_YEAR); // Will induce another drip of rewards
    vm.startPrank(receiver_);
    // Receiver claims rewards.
    component.claimRewards(0, receiver_);
    vm.stopPrank();

    assertApproxEqAbs(rewardAssetA_.balanceOf(receiver_), 24, 1); // (100_000 + 99_000) * 0.01 * 0.1 * (0.5 * 0.25)
    assertApproxEqAbs(rewardAssetB_.balanceOf(receiver_), 5_468_750, 1); // (1_000_000_000 + 750_000_000) * 0.25 * 0.1 *
      // (0.5 * 0.25)
    assertApproxEqAbs(rewardAssetC_.balanceOf(receiver_), 124, 1); // (9_999 + 0) * 1.0 * 0.1 * (0.5 * 0.25)

    UserRewardsData[] memory receiverRewardsData_ = component.getUserRewards(0, receiver_);
    UserRewardsData[] memory expectedReceiverRewardsData_ = new UserRewardsData[](3);
    for (uint16 i = 0; i < 3; i++) {
      expectedReceiverRewardsData_[i] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, i).indexSnapshot});
    }
    assertEq(receiverRewardsData_, expectedReceiverRewardsData_);
  }

  function test_multipleStkReceiptTokenTransfersRewardsAccounting() public {
    _setUpConcrete();
    address user_ = _randomAddress();
    address receiver_ = _randomAddress();

    // User stakes 100e6, increasing stkReceiptTokenSupply to 0.2e18. User owns 50% of total stake, 200e6.
    _stake(0, 100e6, user_);
    StakePool memory stakePool_ = component.getStakePool(0);

    // User transfers the stkReceiptTokens to receiver.
    vm.prank(user_);
    stakePool_.stkReceiptToken.transfer(receiver_, 100e6);

    // Time passes, but no rewards drip.
    skip(ONE_YEAR);

    // Receiver transfers the stkReceiptTokens back to user.
    vm.prank(receiver_);
    stakePool_.stkReceiptToken.transfer(user_, 100e6);

    vm.prank(user_);
    component.claimRewards(0, user_);

    vm.prank(receiver_);
    component.claimRewards(0, receiver_);

    // Reward amounts received by `user_` are calculated as: rewardPool.amount * dripRate *
    // rewardsPoolWeight * (userStkReceiptTokenBalance / totalStkReceiptTokenSupply).
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    IERC20 rewardAssetA_ = rewardPools_[0].asset;
    IERC20 rewardAssetB_ = rewardPools_[1].asset;
    IERC20 rewardAssetC_ = rewardPools_[2].asset;

    assertApproxEqAbs(rewardAssetA_.balanceOf(user_), 50, 1); // 100_000 * 0.01 * 0.1 * 0.5
    assertApproxEqAbs(rewardAssetB_.balanceOf(user_), 12_500_000, 1); // 1_000_000_000 * 0.25 * 0.1 * 0.5
    assertApproxEqAbs(rewardAssetC_.balanceOf(user_), 494, 1); // 9_999 * 0.99 * 0.1 * 0.5

    // Receiver should receive no rewards.
    assertEq(rewardAssetA_.balanceOf(receiver_), 0);
    assertEq(rewardAssetB_.balanceOf(receiver_), 0);
    assertEq(rewardAssetC_.balanceOf(receiver_), 0);
  }

  function test_revertsOnUnauthorizedUserRewardsUpdate() public {
    vm.startPrank(_randomAddress());
    vm.expectRevert(Ownable.Unauthorized.selector);
    component.updateUserRewardsForStkReceiptTokenTransfer(_randomAddress(), _randomAddress());
    vm.stopPrank();
  }
}

contract RewardsDistributorDripAndResetCumulativeValuesUnitTest is RewardsDistributorUnitTest {
  function _expectedClaimableRewardsData(uint256 indexSnapshot) internal pure returns (ClaimableRewardsData memory) {
    return ClaimableRewardsData({indexSnapshot: indexSnapshot, cumulativeClaimableRewards: 0});
  }

  function test_dripAndResetCumulativeRewardsValues_ZeroStkReceiptTokenSupply() public {
    _setUpStakePools(1, true);
    _setUpRewardPools(1);
    _setUpClaimableRewards(1, 1);
    skip(_randomUint64());

    ClaimableRewardsData[][] memory initialClaimableRewards_ = component.getClaimableRewards();
    RewardPool[] memory expectedRewardPools_ = component.getRewardPools();

    component.dripAndResetCumulativeRewardsValues();

    ClaimableRewardsData[][] memory claimableRewards_ = component.getClaimableRewards();
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    expectedRewardPools_[0].lastDripTime = uint128(block.timestamp);
    expectedRewardPools_[0].undrippedRewards -=
      _calculateExpectedDripQuantity(expectedRewardPools_[0].undrippedRewards, 0.1e18);

    assertEq(claimableRewards_[0][0], _expectedClaimableRewardsData(initialClaimableRewards_[0][0].indexSnapshot));
    assertEq(expectedRewardPools_, rewardPools_);
  }

  function test_dripAndResetCumulativeRewardsValuesConcrete() public {
    _setUpConcrete();
    skip(ONE_YEAR);
    component.dripAndResetCumulativeRewardsValues();

    ClaimableRewardsData[] memory claimableRewardsPoolA_ = component.getClaimableRewards(0);
    // Claimable reward indices should be updated as [(drippedRewards * rewardsPoolWeight) / stkReceiptTokenSupply] *
    // WAD^2.
    // Cumulative claimed rewards should be the drippedRewards. Cumulative claimed rewards should be reset to 0.
    assertEq(claimableRewardsPoolA_[0], _expectedClaimableRewardsData(1_000_000_000_000 * MathConstants.WAD)); // [(100_000
      // * 0.01 * 0.1) / 100e6] * WAD^2
    assertEq(claimableRewardsPoolA_[1], _expectedClaimableRewardsData(250_000_000_000_000_000 * MathConstants.WAD)); // [(1_000_000_000
      // * 0.25 * 0.1) / 100e6] * WAD^2
    assertEq(claimableRewardsPoolA_[2], _expectedClaimableRewardsData(9_890_000_000_000 * MathConstants.WAD)); // [(9999
      // * 0.99 * 0.1) / 100e6] * WAD^2

    ClaimableRewardsData[] memory claimableRewardsPoolB_ = component.getClaimableRewards(1);
    assertEq(claimableRewardsPoolB_[0], _expectedClaimableRewardsData(4_500_000_000_000 * MathConstants.WAD)); // [(100_000
      // * 0.01 * 0.9) / 200e6] * WAD^2
    assertEq(claimableRewardsPoolB_[1], _expectedClaimableRewardsData(1_125_000_000_000_000_000 * MathConstants.WAD)); // [(1_000_000_000
      // * 0.25 *  0.9) / 200e6] * WAD^2
    assertEq(claimableRewardsPoolB_[2], _expectedClaimableRewardsData(44_545_000_000_000 * MathConstants.WAD)); // [(9999
      // * 0.99 * 0.9) / 200e6] * WAD^2

    RewardPool[] memory rewardPools_ = component.getRewardPools();
    for (uint16 i = 0; i < rewardPools_.length; i++) {
      assertEq(rewardPools_[i].cumulativeDrippedRewards, 0);
    }
  }

  function testFuzz_dripAndResetCumulativeValues() public {
    _setUpDefault();
    component.dripAndResetCumulativeRewardsValues();

    ClaimableRewardsData[][] memory claimableRewards_ = component.getClaimableRewards();
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    StakePool[] memory stakePools_ = component.getStakePools();

    // Check that cumulative claimed rewards here match the sum of the cumulative claimed rewards.
    uint256 numRewardPools_ = rewardPools_.length;
    uint256 numStakePools_ = stakePools_.length;

    for (uint16 i = 0; i < numRewardPools_; i++) {
      assertEq(rewardPools_[i].cumulativeDrippedRewards, 0);
      for (uint16 j = 0; j < numStakePools_; j++) {
        assertEq(claimableRewards_[j][i].cumulativeClaimableRewards, 0);
      }
    }
  }

  function test_dripAndResetCumulativeRewardsValuesWhenPaused() public {
    _setUpConcrete();

    component.mockRewardsManagerState(RewardsManagerState.PAUSED);

    skip(ONE_YEAR);

    component.dripAndResetCumulativeRewardsValues();

    ClaimableRewardsData[] memory claimableRewardsPoolA_ = component.getClaimableRewards(0);
    // Claimable reward indices should not be updated since the rewards manager is paused.
    // Cumulative claimed rewards should be reset to 0.
    assertEq(claimableRewardsPoolA_[0], _expectedClaimableRewardsData(0));
    assertEq(claimableRewardsPoolA_[1], _expectedClaimableRewardsData(0));
    assertEq(claimableRewardsPoolA_[2], _expectedClaimableRewardsData(0));

    ClaimableRewardsData[] memory claimableRewardsPoolB_ = component.getClaimableRewards(1);
    assertEq(claimableRewardsPoolB_[0], _expectedClaimableRewardsData(0));
    assertEq(claimableRewardsPoolB_[1], _expectedClaimableRewardsData(0));
    assertEq(claimableRewardsPoolB_[2], _expectedClaimableRewardsData(0));

    RewardPool[] memory rewardPools_ = component.getRewardPools();
    for (uint16 i = 0; i < rewardPools_.length; i++) {
      assertEq(rewardPools_[i].cumulativeDrippedRewards, 0);
    }
  }
}

contract TestableRewardsDistributor is RewardsDistributor, Staker, Depositor, RewardsManagerInspector {
  // -------- Mock setters --------
  function mockAddStakePool(StakePool memory stakePool_) external {
    stakePools.push(stakePool_);
  }

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function mockSetRewardPool(uint16 i, RewardPool memory rewardPool_) external {
    rewardPools[i] = rewardPool_;
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockSetClaimableRewardsData(
    uint16 stakePoolId_,
    uint16 rewardPoolId_,
    uint128 claimableRewardsIndex_,
    uint128 cumulativeClaimableRewards_
  ) external {
    claimableRewards[stakePoolId_][rewardPoolId_] = ClaimableRewardsData({
      indexSnapshot: claimableRewardsIndex_,
      cumulativeClaimableRewards: cumulativeClaimableRewards_
    });
  }

  function mockRegisterStkReceiptToken(uint16 stakePoolId_, IReceiptToken stkReceiptToken_) external {
    stkReceiptTokenToStakePoolIds[stkReceiptToken_] = IdLookup({index: stakePoolId_, exists: true});
  }

  function mockRewardsManagerState(RewardsManagerState rewardsManagerState_) external {
    rewardsManagerState = rewardsManagerState_;
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

  function getClaimableRewardsData(uint16 stakePoolId_, uint16 rewardPoolid_)
    external
    view
    returns (ClaimableRewardsData memory)
  {
    return claimableRewards[stakePoolId_][rewardPoolid_];
  }

  // -------- Exposed internal functions --------
  function getUserAccruedRewards(uint256 stkReceiptTokenAmount_, uint256 newRewardPoolIndex, uint256 oldRewardPoolIndex)
    external
    pure
    returns (uint256)
  {
    return _getUserAccruedRewards(stkReceiptTokenAmount_, newRewardPoolIndex, oldRewardPoolIndex);
  }

  function dripAndResetCumulativeRewardsValues() external {
    _dripAndResetCumulativeRewardsValues(stakePools, rewardPools);
  }
}
