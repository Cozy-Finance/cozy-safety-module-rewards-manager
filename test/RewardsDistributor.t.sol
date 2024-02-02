// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {RewardsDistributor} from "../src/lib/RewardsDistributor.sol";
import {Staker} from "../src/lib/Staker.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
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
import {MockStkToken} from "./utils/MockStkToken.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract RewardsDistributorUnitTest is TestBase {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  TestableRewardsDistributor component = new TestableRewardsDistributor();

  uint256 internal constant ONE_YEAR = 365.25 days;

  event ClaimedRewards(
    uint16 indexed reservePoolId,
    IERC20 indexed rewardAsset_,
    uint256 amount_,
    address indexed owner_,
    address receiver_
  );

  function _setUpRewardPools(uint256 numRewardAssets_) internal {
    for (uint256 i = 0; i < numRewardAssets_; i++) {
      MockERC20 mockRewardAsset_ = new MockERC20("Mock Reward Asset", "MockRewardAsset", 6);
      uint256 undrippedRewards_ = _randomUint128();

      RewardPool memory rewardPool_ = RewardPool({
        undrippedRewards: undrippedRewards_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp),
        asset: IERC20(address(mockRewardAsset_)),
        dripModel: IDripModel(address(new MockDripModel(0.1e18))), // Constant 10% drip rate
        depositReceiptToken: IReceiptToken(_randomAddress())
      });
      component.mockAddRewardPool(rewardPool_);

      // Mint rewards manager the undripped rewards and initialize the asset pool.
      mockRewardAsset_.mint(address(component), undrippedRewards_);
      component.mockAddAssetPool(IERC20(address(mockRewardAsset_)), AssetPool({amount: undrippedRewards_}));
    }
  }

  function _setUpStakePools(uint256 numStakePools_, bool nonZeroStkReceiptTokenSupply_) internal {
    for (uint16 i = 0; i < numStakePools_; i++) {
      MockERC20 mockStakeAsset_ = new MockERC20("Mock Stake Asset", "MockStakeAsset", 6);
      IReceiptToken stkReceiptToken_ =
        IReceiptToken(address(new MockStkToken(address(component), "Mock StkReceiptToken", "MockStkReceiptToken", 6)));
      uint256 stakeAmount_ = _randomUint128();

      StakePool memory stakePool_ = StakePool({
        amount: stakeAmount_,
        asset: IERC20(address(mockStakeAsset_)),
        stkReceiptToken: stkReceiptToken_,
        rewardsWeight: (MathConstants.ZOC / numStakePools_).safeCastTo16()
      });

      component.mockRegisterStkReceiptToken(i, stkReceiptToken_);
      component.mockAddStakePool(stakePool_);

      // Mint rewards manager the stake assets and initialize the asset pool.
      mockStakeAsset_.mint(address(component), stakeAmount_);
      component.mockAddAssetPool(IERC20(address(mockStakeAsset_)), AssetPool({amount: stakeAmount_}));

      if (nonZeroStkReceiptTokenSupply_) {
        // Mint stkReceiptTokens and send to zero address to floor supply at a non-zero value.
        stkReceiptToken_.mint(address(0), _randomUint64());
      }
    }
  }

  function _setUpClaimableRewards(uint256 numReservePools_, uint256 numRewardAssets_) internal {
    for (uint16 i = 0; i < numReservePools_; i++) {
      for (uint16 j = 0; j < numRewardAssets_; j++) {
        component.mockSetClaimableRewardsData(i, j, uint128(_randomUint64()), 0);
      }
    }
  }

  function _setUpDefault() internal {
    uint256 numStakePools_ = 2;
    uint256 numRewardAssets_ = 3;

    _setUpStakePools(numStakePools_, true);
    _setUpRewardPools(numRewardAssets_);
    _setUpClaimableRewards(numStakePools_, numRewardAssets_);
  }

  function _setUpConcrete() internal {
    // Set-up two reserve pools.
    MockERC20 mockStakeAssetA_ = new MockERC20("Mock Stake Asset A", "MockStakeAssetA", 6);
    IReceiptToken stkReceiptTokenA_ =
      IReceiptToken(address(new MockStkToken(address(component), "Mock StkReceiptToken A", "MockStkReceiptTokenA", 6)));
    uint256 stakeAmountA_ = 100e6;
    uint256 stkReceiptTokenSupplyA_ = 0.1e18;
    StakePool memory stakePoolA_ = StakePool({
      amount: stakeAmountA_,
      asset: IERC20(address(mockStakeAssetA_)),
      stkReceiptToken: stkReceiptTokenA_,
      rewardsWeight: 0.1e4 // 10% weight
    });

    MockERC20 mockStakeAssetB_ = new MockERC20("Mock Stake Asset B", "MockStakeAssetB", 6);
    IReceiptToken stkReceiptTokenB_ =
      IReceiptToken(address(new MockStkToken(address(component), "Mock StkReceiptToken", "MockStkReceiptTokenB", 6)));
    uint256 stakeAmountB_ = 200e6;
    uint256 stkReceiptTokenSupplyB_ = 10;
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
    stkReceiptTokenA_.mint(address(0), stkReceiptTokenSupplyA_);

    mockStakeAssetB_.mint(address(component), stakeAmountB_);
    component.mockAddAssetPool(IERC20(address(mockStakeAssetB_)), AssetPool({amount: stakeAmountB_}));
    stkReceiptTokenB_.mint(address(0), stkReceiptTokenSupplyB_);

    // Set-up three reserve pools.
    {
      MockERC20 mockRewardAssetA_ = new MockERC20("Mock Reward Asset A", "MockRewardAssetA", 6);
      uint256 undrippedRewardsA_ = 100_000;

      RewardPool memory rewardPoolA_ = RewardPool({
        undrippedRewards: undrippedRewardsA_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp),
        asset: IERC20(address(mockRewardAssetA_)),
        depositReceiptToken: IReceiptToken(_randomAddress()),
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
        depositReceiptToken: IReceiptToken(_randomAddress()),
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
        depositReceiptToken: IReceiptToken(_randomAddress()),
        dripModel: IDripModel(address(new DripModelExponential(145_929_026_605))) // 99% annual drip rate
      });
      component.mockAddRewardPool(rewardPoolC_);

      mockRewardAssetC_.mint(address(component), undrippedRewardsC_);
      component.mockAddAssetPool(IERC20(address(mockRewardAssetC_)), AssetPool({amount: undrippedRewardsC_}));
    }
  }

  function _getUserClaimRewardsFixture() internal returns (address user_, uint16 stakePoolId_, address receiver_) {
    user_ = _randomAddress();
    receiver_ = _randomAddress();
    stakePoolId_ = _randomUint16() % uint16(component.getStakePools().length);
    uint256 stakeAmount_ = _randomUint64();

    // Mint user stake assets.
    StakePool memory stakePool_ = component.getStakePool(stakePoolId_);
    MockERC20 mockStakeAsset_ = MockERC20(address(stakePool_.asset));
    mockStakeAsset_.mint(user_, stakeAmount_);

    vm.prank(user_);
    mockStakeAsset_.approve(address(component), type(uint256).max);
    component.stake(stakePoolId_, stakeAmount_, user_, user_);
    vm.stopPrank();
  }

  function _calculateExpectedDripQuantity(uint256 poolAmount_, uint256 dripFactor_) internal pure returns (uint256) {
    return poolAmount_.mulWadDown(dripFactor_);
  }

  function _calculateExpectedUpdateToClaimableRewardsData(
    uint256 totalDrippedRewards_,
    uint256 rewardsPoolsWeight_,
    uint256 stkTokenSupply_
  ) internal pure returns (uint256) {
    uint256 scaledDrippedRewards_ = totalDrippedRewards_.mulDivDown(rewardsPoolsWeight_, MathConstants.ZOC);
    return scaledDrippedRewards_.divWadDown(stkTokenSupply_);
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

contract TestableRewardsDistributor is RewardsDistributor, Staker, Depositor {
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
    uint128 cumulativeClaimedRewards_
  ) external {
    claimableRewards[stakePoolId_][rewardPoolId_] =
      ClaimableRewardsData({indexSnapshot: claimableRewardsIndex_, cumulativeClaimedRewards: cumulativeClaimedRewards_});
  }

  function mockRegisterStkReceiptToken(uint16 stakePoolId_, IReceiptToken stkReceiptToken_) external {
    stkReceiptTokenToStakePoolIds[stkReceiptToken_] = IdLookup({index: stakePoolId_, exists: true});
  }

  // -------- Mock getters --------
  function getStakePools() external view returns (StakePool[] memory) {
    return stakePools;
  }

  function getStakePool(uint16 stakePoolId_) external view returns (StakePool memory) {
    return stakePools[stakePoolId_];
  }

  function getRewardPools() external view returns (RewardPool[] memory) {
    return rewardPools;
  }

  function getRewardPool(uint16 rewardPoolid_) external view returns (RewardPool memory) {
    return rewardPools[rewardPoolid_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  function getClaimableRewards() external view returns (ClaimableRewardsData[][] memory) {
    uint256 numStakePools_ = stakePools.length;
    uint256 numRewardPools_ = rewardPools.length;
    ClaimableRewardsData[][] memory claimableRewards_ = new ClaimableRewardsData[][](numStakePools_);
    for (uint16 i = 0; i < numStakePools_; i++) {
      claimableRewards_[i] = new ClaimableRewardsData[](numRewardPools_);
      for (uint16 j = 0; j < numRewardPools_; j++) {
        claimableRewards_[i][j] = claimableRewards[i][j];
      }
    }
    return claimableRewards_;
  }

  function getClaimableRewards(uint16 stakePoolId_) external view returns (ClaimableRewardsData[] memory) {
    uint256 numRewardPools_ = rewardPools.length;
    ClaimableRewardsData[] memory claimableRewards_ = new ClaimableRewardsData[](numRewardPools_);
    for (uint16 j = 0; j < numRewardPools_; j++) {
      claimableRewards_[j] = claimableRewards[stakePoolId_][j];
    }
    return claimableRewards_;
  }

  function getClaimableRewardsData(uint16 stakePoolId_, uint16 rewardPoolid_)
    external
    view
    returns (ClaimableRewardsData memory)
  {
    return claimableRewards[stakePoolId_][rewardPoolid_];
  }

  function getUserRewards(uint16 stakePoolId_, address user) external view returns (UserRewardsData[] memory) {
    return userRewards[stakePoolId_][user];
  }

  // -------- Exposed internal functions --------
  function getUserAccruedRewards(uint256 stkTokenAmount_, uint128 newRewardPoolIndex, uint128 oldRewardPoolIndex)
    external
    pure
    returns (uint256)
  {
    return _getUserAccruedRewards(stkTokenAmount_, newRewardPoolIndex, oldRewardPoolIndex);
  }

  function dripAndResetCumulativeRewardsValues() external {
    _dripAndResetCumulativeRewardsValues(stakePools, rewardPools);
  }

  // -------- Overridden abstract function placeholders --------
}
