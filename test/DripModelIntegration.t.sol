// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelConstant} from "cozy-safety-module-models/DripModelConstant.sol";
import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {StakePoolConfig, RewardPoolConfig} from "../src/lib/structs/Configs.sol";
import {RewardsManager} from "../src/RewardsManager.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {MockERC20} from "./utils/MockERC20.sol";

abstract contract DripModelIntegrationTestSetup is MockDeployProtocol {
  uint256 internal constant ONE_YEAR = 365.25 days;
  uint256 internal constant REWARD_POOL_AMOUNT = 1000;

  IERC20 stakeAsset = IERC20(address(new MockERC20("MockStakeAsset", "MOCK", 18)));
  IERC20 rewardAsset = IERC20(address(new MockERC20("MockRewardAsset", "MOCK", 18)));

  RewardsManager rewardsManager;
  address self = address(this);
  address alice = _randomAddress();

  function depositRewards(RewardsManager rewardsManager_, uint256 rewardAssetAmount_) internal {
    deal(
      address(rewardAsset),
      address(rewardsManager_),
      rewardAsset.balanceOf(address(rewardsManager_)) + rewardAssetAmount_
    );
    rewardsManager_.depositRewardAssetsWithoutTransfer(0, rewardAssetAmount_);
  }

  function stake(RewardsManager rewardsManager_, uint256 stakeAssetAmount_, address receiver_) internal {
    deal(
      address(stakeAsset), address(rewardsManager_), stakeAsset.balanceOf(address(rewardsManager_)) + stakeAssetAmount_
    );
    rewardsManager_.stakeWithoutTransfer(0, stakeAssetAmount_, receiver_);
  }

  function _assertRewardDripAmountAndReset(uint256 skipTime_, uint256 expectedClaimedRewards_) internal {
    skip(skipTime_);
    address receiver_ = _randomAddress();

    vm.prank(alice);
    rewardsManager.claimRewards(0, receiver_);

    assertEq(rewardAsset.balanceOf(receiver_), expectedClaimedRewards_);

    // Reset reward pool.
    (uint256 currentAmount_,,,,,,) = rewardsManager.rewardPools(0);
    if (REWARD_POOL_AMOUNT - currentAmount_ > 0) depositRewards(rewardsManager, REWARD_POOL_AMOUNT - currentAmount_);
  }
}

contract RewardsDripModelExponentialIntegrationTest is DripModelIntegrationTestSetup {
  uint256 internal DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD

  function setUp() public virtual override {
    super.setUp();

    vm.prank(cozyManager.owner());
    cozyManager.updateDepositFee(0);

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](1);
    stakePoolConfigs_[0] = StakePoolConfig({asset: stakeAsset, rewardsWeight: uint16(MathConstants.ZOC)}); // 100% of
      // rewards for the only stake pool

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({
      asset: rewardAsset,
      dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
    });

    rewardsManager = RewardsManager(
      address(cozyManager.createRewardsManager(owner, pauser, stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32()))
    );

    depositRewards(rewardsManager, REWARD_POOL_AMOUNT);
    stake(rewardsManager, 99, alice);
  }

  function _setRewardsDripModel(uint256 rate_) internal {
    DripModelExponential rewardsDripModel_ = new DripModelExponential(rate_);
    (,,,, IDripModel currentRewardsDripModel_,,) = rewardsManager.rewardPools(0);
    vm.etch(address(currentRewardsDripModel_), address(rewardsDripModel_).code);
  }

  function _testSeveralRewardsDrips(uint256 rate_, uint256[] memory expectedClaimedRewards_) internal {
    _setRewardsDripModel(rate_);
    _assertRewardDripAmountAndReset(ONE_YEAR, expectedClaimedRewards_[0]);
    _assertRewardDripAmountAndReset(ONE_YEAR / 2, expectedClaimedRewards_[1]);
    _assertRewardDripAmountAndReset(ONE_YEAR / 4, expectedClaimedRewards_[2]);
    _assertRewardDripAmountAndReset(ONE_YEAR / 10, expectedClaimedRewards_[3]);
    _assertRewardDripAmountAndReset(ONE_YEAR / 20, expectedClaimedRewards_[4]);
    _assertRewardDripAmountAndReset(0, expectedClaimedRewards_[5]);
  }

  function test_RewardsDrip50Percent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 246; // 1000 * dripFactor(1 year) ~= 1000 * 0.25 ~= 249 (up to rounding down in favor
      // the protocol), taking a 1% fee, we get 249 * 0.99 = 246
    expectedClaimedRewards_[1] = 130; // 1000 * dripFactor(0.5 years) ~= 1000 * 0.13397459686 ~= 132, taking a 1% fee,
      // we get 132 * 0.99 = 130
    expectedClaimedRewards_[2] = 67; // 1000 * dripFactor(0.25 years) ~= 1000 * 0.06939514124 ~= 68, taking a 1% fee, we
      // get 68 * 0.99 = 67
    expectedClaimedRewards_[3] = 26; // 1000 * dripFactor(0.1 years) ~= 1000 * 0.02835834225 ~= 27, taking a 1% fee, we
      // get 27 * 0.99 = 26
    expectedClaimedRewards_[4] = 12; // 1000 * dripFactor(0.05 years) ~= 1000 * 0.0142811467 ~= 13, taking a 1% fee, we
      // get 13 * 0.99 = 13
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(DEFAULT_DRIP_RATE, expectedClaimedRewards_);
  }

  function test_RewardsDripZeroPercent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 0; // 1000 * dripFactor(1 year) = 1000 * 0 = 0
    expectedClaimedRewards_[1] = 0; // 1000 * dripFactor(0.5 years) = 1000 * 0 = 0
    expectedClaimedRewards_[2] = 0; // 1000 * dripFactor(0.25 years) = 1000 * 0 = 0
    expectedClaimedRewards_[3] = 0; // 1000 * dripFactor(0.1 years) = 1000 * 0 = 0
    expectedClaimedRewards_[4] = 0; // 1000 * dripFactor(0.05 years) = 1000 * 0 = 0
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(0, expectedClaimedRewards_);
  }

  function test_RewardsDrip100Percent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 989; // 1000 * dripFactor(1 year) = 1000 * 1 ~= 999 (up to rounding down in favor the
      // protocol), taking a 1% fee, we get 999 * 0.99 = 989
    expectedClaimedRewards_[1] = 989; // 1000 * dripFactor(0.5 years) = 1000 * 1 ~= 999, taking a 1% fee, we get 999 *
      // 0.99 = 989
    expectedClaimedRewards_[2] = 989; // 1000 * dripFactor(0.25 years) = 1000 * 1 ~= 999, taking a 1% fee, we get 999 *
      // 0.99 = 989
    expectedClaimedRewards_[3] = 989; // 1000 * dripFactor(0.1 years) = 1000 * 1 ~= 999, taking a 1% fee, we get 999 *
      // 0.99 = 989
    expectedClaimedRewards_[4] = 989; // 1000 * dripFactor(0.05 years) = 1000 * 1 ~= 999, taking a 1% fee, we get 999 *
      // 0.99 = 989
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(MathConstants.WAD, expectedClaimedRewards_);
  }
}

contract RewardsDripModelConstantIntegrationTest is DripModelIntegrationTestSetup {
  uint256 internal DEFAULT_DRIP_RATE = 10; // 10 per second.
  uint256 internal constant DEFAULT_DRIP_RATE_INTERVAL = 100 seconds;
  address dripModelOwner = address(0xBEEF);

  function setUp() public virtual override {
    super.setUp();

    vm.prank(cozyManager.owner());
    cozyManager.updateDepositFee(0);

    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](1);
    stakePoolConfigs_[0] = StakePoolConfig({asset: stakeAsset, rewardsWeight: uint16(MathConstants.ZOC)}); // 100% of
      // rewards for the only stake pool

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({
      asset: rewardAsset,
      dripModel: IDripModel(address(new DripModelConstant(dripModelOwner, DEFAULT_DRIP_RATE)))
    });

    rewardsManager = RewardsManager(
      address(cozyManager.createRewardsManager(owner, pauser, stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32()))
    );

    depositRewards(rewardsManager, REWARD_POOL_AMOUNT);
    stake(rewardsManager, 99, alice);
  }

  function _setRewardsDripModel(uint256 rate_) internal {
    (,,,, IDripModel currentRewardsDripModel_,,) = rewardsManager.rewardPools(0);
    vm.prank(dripModelOwner);
    DripModelConstant(address(currentRewardsDripModel_)).updateAmountPerSecond(rate_);
  }

  function _testSeveralRewardsDrips(uint256 rate_, uint256[] memory expectedClaimedRewards_) internal {
    _setRewardsDripModel(rate_);
    _assertRewardDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL, expectedClaimedRewards_[0]);
    _assertRewardDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL / 2, expectedClaimedRewards_[1]);
    _assertRewardDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL / 4, expectedClaimedRewards_[2]);
    _assertRewardDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL / 10, expectedClaimedRewards_[3]);
    _assertRewardDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL / 20, expectedClaimedRewards_[4]);
    _assertRewardDripAmountAndReset(0, expectedClaimedRewards_[5]);
  }

  function test_FeesDripOnePercent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 989; // 1000 * dripFactor(100 seconds) ~= 1000 * 1 ~= 999 (up to rounding down in favor
      // the protocol), taking a 1% fee, we get 999 * 0.99 = 989
    expectedClaimedRewards_[1] = 494; // 1000 * dripFactor(50 seconds) ~= 1000 * 0.5 ~= 499, taking a 1% fee, we get
      // 499 * 0.99 = 499
    expectedClaimedRewards_[2] = 246; // 1000 * dripFactor(25 seconds) ~= 1000 * 0.25 ~= 249, taking a 1% fee, we get
      // 249 * 0.99 = 249
    expectedClaimedRewards_[3] = 98; // 1000 * dripFactor(10 seconds) ~= 1000 * 0.1 ~= 99, taking a 1% fee, we get 99 *
      // 0.99 = 99
    expectedClaimedRewards_[4] = 48; // 1000 * dripFactor(5 seconds) ~= 1000 * 0.05 ~= 49, taking a 1% fee, we get 49 *
      // 0.99 = 49
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(10, expectedClaimedRewards_);
  }

  function test_FeesDripZeroPercent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 0; // 1000 * dripFactor(100 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[1] = 0; // 1000 * dripFactor(50 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[2] = 0; // 1000 * dripFactor(25 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[3] = 0; // 1000 * dripFactor(10 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[4] = 0; // 1000 * dripFactor(5 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(0, expectedClaimedRewards_);
  }

  function test_FeesDrip100Percent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 989; // 1000 * dripFactor(100 seconds) ~= 1000 * 1 = 999 (up to rounding down in favor
      // the protocol), taking a 1% fee, we get 999 * 0.99 = 989
    expectedClaimedRewards_[1] = 989; // 1000 * dripFactor(50 seconds) ~= 1000 * 1 = 999, taking a 1% fee, we get 999 *
      // 0.99 = 989
    expectedClaimedRewards_[2] = 989; // 1000 * dripFactor(25 seconds) ~= 1000 * 1 = 999, taking a 1% fee, we get 999 *
      // 0.99 = 989
    expectedClaimedRewards_[3] = 989; // 1000 * dripFactor(10 seconds) ~= 1000 * 1 = 999, taking a 1% fee, we get 999 *
      // 0.99 = 989
    expectedClaimedRewards_[4] = 989; // 1000 * dripFactor(5 seconds) ~= 1000 * 1 = 999, taking a 1% fee, we get 999 *
      // 0.99 = 989
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) = 1000 * 0 = 0
    _testSeveralRewardsDrips(REWARD_POOL_AMOUNT, expectedClaimedRewards_);
  }
}
