// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {RewardsManager} from "../../src/RewardsManager.sol";
import {RewardPoolConfig, StakePoolConfig} from "../../src/lib/structs/Configs.sol";
import {StakePool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {MockDeployProtocol} from "../utils/MockDeployProtocol.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {IDripModel} from "../../src/interfaces/IDripModel.sol";
import {IRewardsManager} from "../../src/interfaces/IRewardsManager.sol";
import {console2} from "forge-std/console2.sol";

abstract contract BenchmarkMaxPools is MockDeployProtocol {
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD
  uint256 internal constant DEFAULT_SKIP_DAYS = 10;

  RewardsManager rewardsManager;
  uint16 numRewardAssets;
  uint16 numStakePools;
  address self = address(this);

  function setUp() public virtual override {
    super.setUp();

    _createRewardsManager(_createStakePools(numStakePools), _createRewardPools(numRewardAssets));

    _initializeRewardPools();
    _initializeStakePools();

    skip(DEFAULT_SKIP_DAYS);
  }

  function _createRewardsManager(
    StakePoolConfig[] memory stakePoolConfigs_,
    RewardPoolConfig[] memory rewardPoolConfigs_
  ) internal {
    rewardsManager = RewardsManager(
      address(rewardsManagerFactory.deployRewardsManager(self, stakePoolConfigs_, rewardPoolConfigs_, _randomBytes32()))
    );
  }

  function _createStakePools(uint16 numPools) internal returns (StakePoolConfig[] memory) {
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numPools);
    uint16 weightSum_ = 0;
    for (uint256 i = 0; i < numPools; i++) {
      stakePoolConfigs_[i] = StakePoolConfig({
        asset: IERC20(address(new MockERC20("Mock Stake Asset", "cozyStk", 18))),
        rewardsWeight: i == numPools - 1 ? uint16(MathConstants.ZOC - weightSum_) : uint16(MathConstants.ZOC / numPools)
      });
      weightSum_ += stakePoolConfigs_[i].rewardsWeight;
    }
    return stakePoolConfigs_;
  }

  function _createRewardPools(uint16 numPools) internal returns (RewardPoolConfig[] memory) {
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](numPools);
    for (uint256 i = 0; i < numPools; i++) {
      rewardPoolConfigs_[i] = RewardPoolConfig({
        asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyRew", 18))),
        dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
      });
    }
    return rewardPoolConfigs_;
  }

  function _initializeRewardPools() internal {
    for (uint16 i = 0; i < numRewardAssets; i++) {
      (, uint256 rewardAssetAmount_, address receiver_) = _randomSingleActionFixture(false);
      _depositRewardAssets(i, rewardAssetAmount_, receiver_);
    }
  }

  function _initializeStakePools() internal {
    for (uint16 i = 0; i < numStakePools; i++) {
      (, uint256 stakeAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
      _stake(i, stakeAssetAmount_, receiver_);
    }
  }

  function _randomSingleActionFixture(bool isStakeAction_) internal view returns (uint16, uint256, address) {
    return (
      isStakeAction_ ? (_randomUint16() % numStakePools) : (_randomUint16() % numRewardAssets),
      _randomUint256() % 999_999_999_999_999,
      _randomAddress()
    );
  }

  function _setUpDepositRewardAssets(uint16 rewardPoolId_) internal {
    RewardPool memory rewardPool_ = getRewardPool(IRewardsManager(address(rewardsManager)), rewardPoolId_);
    deal(address(rewardPool_.asset), address(rewardsManager), type(uint256).max);
  }

  function _depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) internal {
    _setUpDepositRewardAssets(rewardPoolId_);
    rewardsManager.depositRewardAssetsWithoutTransfer(rewardPoolId_, rewardAssetAmount_, receiver_);
  }

  function _setUpStake(uint16 stakePoolId_) internal {
    StakePool memory stakePool_ = getStakePool(IRewardsManager(address(rewardsManager)), stakePoolId_);
    deal(address(stakePool_.asset), address(rewardsManager), type(uint256).max);
  }

  function _stake(uint16 stakePoolId_, uint256 stakeAssetAmount_, address receiver_) internal {
    _setUpStake(stakePoolId_);
    rewardsManager.stakeWithoutTransfer(stakePoolId_, stakeAssetAmount_, receiver_);
  }

  function _setUpUnstake(uint16 stakePoolId_, uint256 stakeAssetAmount_, address receiver_)
    internal
    returns (uint256 stkReceiptTokenAmount_)
  {
    _stake(stakePoolId_, stakeAssetAmount_, receiver_);

    // TODO: stkReceiptTokenAmount_ = rewardsManager.convertToStakeTokenAmount(stakePoolId_, stakeAssetAmount_);
    vm.startPrank(receiver_);
    getStakePool(IRewardsManager(address(rewardsManager)), stakePoolId_).stkReceiptToken.approve(
      address(rewardsManager), stkReceiptTokenAmount_
    );
    vm.stopPrank();
  }

  function _setUpRedeemRewards(uint16 rewardPoolId_, address receiver_)
    internal
    returns (uint256 depositReceiptTokenAmount_)
  {
    RewardPool memory rewardPool_ = getRewardPool(IRewardsManager(address(rewardsManager)), rewardPoolId_);
    _depositRewardAssets(rewardPoolId_, rewardPool_.undrippedRewards, receiver_);

    depositReceiptTokenAmount_ = rewardPool_.depositReceiptToken.balanceOf(receiver_);
    vm.startPrank(receiver_);
    rewardPool_.depositReceiptToken.approve(address(rewardsManager), depositReceiptTokenAmount_);
    vm.stopPrank();
  }

  function _setUpConfigUpdate() internal returns (StakePoolConfig[] memory, RewardPoolConfig[] memory) {
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](numStakePools + 1);
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](numRewardAssets + 1);

    uint16 weightSum_ = 0;
    for (uint256 i = 0; i < numStakePools + 1; i++) {
      IERC20 asset_ = i < numStakePools
        ? getStakePool(IRewardsManager(address(rewardsManager)), i).asset
        : IERC20(address(new MockERC20("Mock Stake Asset", "cozyStk", 18)));
      stakePoolConfigs_[i] = StakePoolConfig({
        asset: asset_,
        rewardsWeight: i == numStakePools
          ? uint16(MathConstants.ZOC - weightSum_)
          : uint16(MathConstants.ZOC / (numStakePools + 1))
      });
      weightSum_ += stakePoolConfigs_[i].rewardsWeight;
    }

    for (uint256 i = 0; i < numRewardAssets + 1; i++) {
      if (i < numRewardAssets) {
        RewardPool memory rewardPool_ = getRewardPool(IRewardsManager(address(rewardsManager)), i);
        rewardPoolConfigs_[i] = RewardPoolConfig({asset: rewardPool_.asset, dripModel: rewardPool_.dripModel});
      } else {
        rewardPoolConfigs_[i] = RewardPoolConfig({
          asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyRew", 18))),
          dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
        });
      }
    }

    return (stakePoolConfigs_, rewardPoolConfigs_);
  }

  function test_createRewardsManager() public {
    StakePoolConfig[] memory stakePoolConfigs_ = _createStakePools(numStakePools);
    RewardPoolConfig[] memory rewardPoolConfigs_ = _createRewardPools(numRewardAssets);

    uint256 gasInitial_ = gasleft();
    _createRewardsManager(stakePoolConfigs_, rewardPoolConfigs_);
    console2.log("Gas used for createRewardsManager: %s", gasInitial_ - gasleft());
  }

  function test_depositRewardAssets() public {
    (uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) = _randomSingleActionFixture(false);
    _setUpDepositRewardAssets(rewardPoolId_);

    uint256 gasInitial_ = gasleft();
    rewardsManager.depositRewardAssetsWithoutTransfer(rewardPoolId_, rewardAssetAmount_, receiver_);
    console2.log("Gas used for depositRewardAssetsWithoutTransfer: %s", gasInitial_ - gasleft());
  }

  function test_stake() public {
    (uint16 stakePoolId_, uint256 stakeAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _setUpStake(stakePoolId_);

    uint256 gasInitial_ = gasleft();
    rewardsManager.stakeWithoutTransfer(stakePoolId_, stakeAssetAmount_, receiver_);
    console2.log("Gas used for stakeWithoutTransfer: %s", gasInitial_ - gasleft());
  }

  function test_redeemRewards() public {
    (uint16 rewardPoolId_,, address receiver_) = _randomSingleActionFixture(false);
    uint256 depositReceiptTokenAmount_ = _setUpRedeemRewards(rewardPoolId_, receiver_);

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    rewardsManager.redeemUndrippedRewards(rewardPoolId_, depositReceiptTokenAmount_, receiver_, receiver_);
    console2.log("Gas used for redeemRewards: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_unstake() public {
    (uint16 stakePoolId_, uint256 stakeAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    uint256 stkReceiptTokenAmount_ = _setUpUnstake(stakePoolId_, stakeAssetAmount_, receiver_);

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    rewardsManager.unstake(stakePoolId_, stkReceiptTokenAmount_, receiver_, receiver_);
    console2.log("Gas used for unstake: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_dripRewards() public {
    skip(_randomUint64());

    uint256 gasInitial_ = gasleft();
    rewardsManager.dripRewards();
    console2.log("Gas used for dripRewards: %s", gasInitial_ - gasleft());
  }

  function test_claimRewards() public {
    (uint16 stakePoolId_, uint256 stakeAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _stake(stakePoolId_, stakeAssetAmount_, receiver_);

    skip(_randomUint64());

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    rewardsManager.claimRewards(stakePoolId_, receiver_);
    console2.log("Gas used for claimRewards: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_stkTokenTransfer() public {
    (uint16 stakePoolId_,, address receiver_) = _randomSingleActionFixture(true);

    StakePool memory stakePool_ = getStakePool(IRewardsManager(address(rewardsManager)), stakePoolId_);
    IERC20 stkReceiptToken_ = stakePool_.stkReceiptToken;
    _stake(stakePoolId_, stakePool_.amount, receiver_);

    skip(_randomUint64());

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    stkReceiptToken_.transfer(_randomAddress(), stkReceiptToken_.balanceOf(receiver_));
    console2.log("Gas used for stkToken_.transfer: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_updateConfigs() public {
    (StakePoolConfig[] memory stakePoolConfigs_, RewardPoolConfig[] memory rewardPoolConfigs_) = _setUpConfigUpdate();

    vm.startPrank(owner);
    uint256 gasInitial_ = gasleft();
    rewardsManager.updateConfigs(stakePoolConfigs_, rewardPoolConfigs_);
    console2.log("Gas used for updateConfigs: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }
}

contract BenchmarkMaxPools_30Stake_25Reward is BenchmarkMaxPools {
  function setUp() public override {
    numStakePools = 25;
    numRewardAssets = 30;
    super.setUp();
  }
}
