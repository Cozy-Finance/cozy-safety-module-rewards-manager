// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {console2} from "forge-std/console2.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {RewardsManager} from "../../../src/RewardsManager.sol";
import {StakePool, RewardPool} from "../../../src/lib/structs/Pools.sol";
import {PreviewClaimableRewards, PreviewClaimableRewardsData} from "../../../src/lib/structs/Rewards.sol";
import {IRewardsManager} from "../../../src/interfaces/IRewardsManager.sol";
import {AddressSet, AddressSetLib} from "../utils/AddressSet.sol";
import {TestBase} from "../../utils/TestBase.sol";

contract RewardsManagerHandler is TestBase {
  using FixedPointMathLib for uint256;
  using AddressSetLib for AddressSet;

  uint64 constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;

  address pauser;
  address owner;

  IRewardsManager public rewardsManager;

  uint256 numStakePools;
  uint256 numRewardPools;

  mapping(string => uint256) public calls;
  mapping(string => uint256) public invalidCalls;

  address internal currentActor;

  AddressSet internal actors;

  AddressSet internal actorsWithRewardDeposits;

  AddressSet internal actorsWithStakes;

  uint16 public currentStakePoolId;

  uint16 public currentRewardPoolId;

  uint256 public currentTimestamp;

  uint256 totalTimeAdvanced;

  uint256 public totalCalls;

  // -------- Ghost Variables --------

  mapping(uint16 stakePoolId_ => GhostStakePool stakePool_) public ghost_stakePoolCumulative;
  mapping(uint16 rewardPoolId_ => GhostRewardPool rewardPool_) public ghost_rewardPoolCumulative;

  mapping(address actor_ => mapping(uint16 stakePoolId_ => uint256 actorStakeCount_)) public ghost_actorStakeCount;
  mapping(address actor_ => mapping(uint16 rewardPoolId_ => uint256 actorRewardDepositCount_)) public
    ghost_actorRewardDepositCount;

  mapping(IERC20 asset_ => uint256 amount_) public ghost_rewardsClaimed;

  // -------- Structs --------

  struct GhostStakePool {
    uint256 totalAssetAmount;
    uint256 stakeAssetAmount;
    uint256 stakeSharesAmount;
    uint256 unstakeAssetAmount;
    uint256 unstakeSharesAmount;
  }

  struct GhostRewardPool {
    uint256 totalAssetAmount;
    uint256 depositSharesAmount;
    uint256 redeemSharesAmount;
    uint256 redeemAssetAmount;
  }

  // -------- Constructor --------

  constructor(
    IRewardsManager rewardsManager_,
    uint256 numStakePools_,
    uint256 numRewardPools_,
    uint256 currentTimestamp_
  ) {
    rewardsManager = rewardsManager_;
    numStakePools = numStakePools_;
    numRewardPools = numRewardPools_;
    // TODO: pauser = rewardsManager_.pauser();
    owner = rewardsManager_.owner();
    currentTimestamp = currentTimestamp_;

    vm.label(address(rewardsManager), "rewardsManager");
  }

  // --------------------------------------
  // -------- Functions under test --------
  // --------------------------------------
  function depositRewardAssets(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithRewardDeposits
    useValidRewardPoolId(seed_)
    countCall("depositRewardAssets")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositRewardAssets(assetAmount_, "depositRewardAssets");

    return currentActor;
  }

  function depositRewardAssetsWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidRewardPoolId(seed_)
    countCall("depositRewardAssetsWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositRewardAssets(assetAmount_, "depositRewardAssetsWithExistingActor");

    return currentActor;
  }

  function depositRewardAssetsWithoutTransfer(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithRewardDeposits
    useValidRewardPoolId(seed_)
    countCall("depositRewardAssetsWithoutTransfer")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositRewardAssetsWithoutTransfer(assetAmount_, "depositRewardAssetsWithoutTransfer");

    return currentActor;
  }

  function depositRewardAssetsWithoutTransferWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidRewardPoolId(seed_)
    countCall("depositRewardAssetsWithoutTransferWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositRewardAssetsWithoutTransfer(assetAmount_, "depositRewardAssetsWithoutTransferWithExistingActor");

    return currentActor;
  }

  function stake(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithStakes
    useValidStakePoolId(seed_)
    countCall("stake")
    advanceTime(seed_)
    returns (address actor_)
  {
    _stake(assetAmount_, "stake");

    return currentActor;
  }

  function stakeWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidStakePoolId(seed_)
    countCall("stakeWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _stake(assetAmount_, "stakeWithExistingActor");

    return currentActor;
  }

  function stakeWithoutTransfer(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithStakes
    useValidStakePoolId(seed_)
    countCall("stakeWithoutTransfer")
    advanceTime(seed_)
    returns (address actor_)
  {
    _stakeWithoutTransfer(assetAmount_, "stakeWithoutTransfer");

    return currentActor;
  }

  function stakeWithoutTransferWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidStakePoolId(seed_)
    countCall("stakeWithoutTransferWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _stakeWithoutTransfer(assetAmount_, "stakeWithoutTransferWithExistingActor");

    return currentActor;
  }

  function redeemUndrippedRewards(uint256 depositTokenRedeemAmount_, address receiver_, uint256 seed_)
    public
    virtual
    useActorWithRewardDeposits(seed_)
    countCall("redeemUndrippedRewards")
    advanceTime(seed_)
  {
    IERC20 depositToken_ = getRewardPool(rewardsManager, currentRewardPoolId).depositReceiptToken;
    uint256 actorDepositTokenBalance_ = depositToken_.balanceOf(currentActor);
    if (actorDepositTokenBalance_ == 0) {
      invalidCalls["redeemUndrippedRewards"] += 1;
      return;
    }

    depositTokenRedeemAmount_ = bound(depositTokenRedeemAmount_, 1, actorDepositTokenBalance_);
    vm.startPrank(currentActor);
    depositToken_.approve(address(rewardsManager), depositTokenRedeemAmount_);
    uint256 assetAmount_ =
      rewardsManager.redeemUndrippedRewards(currentRewardPoolId, depositTokenRedeemAmount_, receiver_, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].redeemAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].redeemSharesAmount += depositTokenRedeemAmount_;
  }

  function unstake(uint256 stkTokenUnstakeAmount_, address receiver_, uint256 seed_)
    public
    virtual
    useActorWithStakes(seed_)
    countCall("unstake")
    advanceTime(seed_)
  {
    IERC20 stkToken_ = getStakePool(rewardsManager, currentStakePoolId).stkReceiptToken;
    uint256 actorStkTokenBalance_ = stkToken_.balanceOf(currentActor);
    if (actorStkTokenBalance_ == 0) {
      invalidCalls["unstake"] += 1;
      return;
    }

    _incrementGhostRewardsToBeClaimed(currentStakePoolId, currentActor);

    stkTokenUnstakeAmount_ = bound(stkTokenUnstakeAmount_, 1, actorStkTokenBalance_);
    vm.startPrank(currentActor);
    stkToken_.approve(address(rewardsManager), stkTokenUnstakeAmount_);
    uint256 assetAmount_ = rewardsManager.unstake(currentStakePoolId, stkTokenUnstakeAmount_, receiver_, currentActor);
    vm.stopPrank();

    ghost_stakePoolCumulative[currentStakePoolId].unstakeAssetAmount += assetAmount_;
    ghost_stakePoolCumulative[currentStakePoolId].unstakeSharesAmount += stkTokenUnstakeAmount_;
  }

  function claimRewards(address receiver_, uint256 seed_)
    public
    useActorWithStakes(seed_)
    countCall("claimRewards")
    advanceTime(seed_)
    returns (address actor_)
  {
    IERC20 stkToken_ = getStakePool(rewardsManager, currentStakePoolId).stkReceiptToken;
    uint256 actorStkTokenBalance_ = stkToken_.balanceOf(currentActor);
    if (actorStkTokenBalance_ == 0) {
      invalidCalls["claimRewards"] += 1;
      return currentActor;
    }

    _incrementGhostRewardsToBeClaimed(currentStakePoolId, currentActor);

    vm.startPrank(currentActor);
    rewardsManager.claimRewards(currentStakePoolId, receiver_);
    vm.stopPrank();

    return currentActor;
  }

  function _incrementGhostRewardsToBeClaimed(uint16 currentStakePool_, address currentActor_) public {
    uint16[] memory stakePoolIds_ = new uint16[](1);
    stakePoolIds_[0] = currentStakePool_;
    PreviewClaimableRewards[] memory reservePoolClaimableRewards_ =
      rewardsManager.previewClaimableRewards(stakePoolIds_, currentActor_);

    for (uint16 j = 0; j < numRewardPools; j++) {
      PreviewClaimableRewardsData memory rewardPoolClaimableRewards_ =
        reservePoolClaimableRewards_[0].claimableRewardsData[j];
      ghost_rewardsClaimed[rewardPoolClaimableRewards_.asset] += rewardPoolClaimableRewards_.amount;
    }
  }

  /*
  TODO: 
  function pause(uint256 seed_) public virtual countCall("pause") advanceTime(seed_) {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["pause"] += 1;
      return;
    }
    vm.prank(pauser);
    safetyModule.pause();
  }

  function unpause(uint256 seed_) public virtual countCall("unpause") advanceTime(seed_) {
    if (safetyModule.safetyModuleState() != SafetyModuleState.PAUSED) {
      invalidCalls["unpause"] += 1;
      return;
    }
    vm.prank(owner);
    safetyModule.unpause();
  }
  */

  // ----------------------------------
  // -------- Helper functions --------
  // ----------------------------------

  function callSummary() public view virtual {
    console2.log("Call summary:");
    console2.log("----------------------------------------------------------------------------");
    console2.log("Total Calls: ", totalCalls);
    console2.log("Total Time Advanced: ", totalTimeAdvanced);
    console2.log("----------------------------------------------------------------------------");
    console2.log("Calls:");
    console2.log("");
    console2.log("depositRewardAssets", calls["depositRewardAssets"]);
    console2.log("depositRewardAssetsWithExistingActor", calls["depositRewardAssetsWithExistingActor"]);
    console2.log("depositRewardAssetsWithoutTransfer", calls["depositRewardAssetsWithoutTransfer"]);
    console2.log(
      "depositRewardAssetsWithoutTransferWithExistingActor",
      calls["depositRewardAssetsWithoutTransferWithExistingActor"]
    );
    console2.log("stake", calls["stake"]);
    console2.log("stakeWithExistingActor", calls["stakeWithExistingActor"]);
    console2.log("stakeWithoutTransfer", calls["stakeWithoutTransfer"]);
    console2.log("stakeWithoutTransferWithExistingActor", calls["stakeWithoutTransferWithExistingActor"]);
    console2.log("redeemUndrippedRewards", calls["redeemUndrippedRewards"]);
    console2.log("unstake", calls["unstake"]);
    console2.log("claimRewards", calls["claimRewards"]);
    console2.log("pause", calls["pause"]);
    console2.log("unpause", calls["unpause"]);
    console2.log("----------------------------------------------------------------------------");
    console2.log("Invalid calls:");
    console2.log("");
    console2.log("depositRewardAssets", invalidCalls["depositRewardAssets"]);
    console2.log("depositRewardAssetsWithExistingActor", invalidCalls["depositRewardAssetsWithExistingActor"]);
    console2.log("depositRewardAssetsWithoutTransfer", invalidCalls["depositRewardAssetsWithoutTransfer"]);
    console2.log(
      "depositRewardAssetsWithoutTransferWithExistingActor",
      invalidCalls["depositRewardAssetsWithoutTransferWithExistingActor"]
    );
    console2.log("stake", invalidCalls["stake"]);
    console2.log("stakeWithExistingActor", invalidCalls["stakeWithExistingActor"]);
    console2.log("stakeWithoutTransfer", invalidCalls["stakeWithoutTransfer"]);
    console2.log("stakeWithoutTransferWithExistingActor", invalidCalls["stakeWithoutTransferWithExistingActor"]);
    console2.log("redeemUndrippedRewards", invalidCalls["redeemUndrippedRewards"]);
    console2.log("unstake", invalidCalls["unstake"]);
    console2.log("claimRewards", invalidCalls["claimRewards"]);
    console2.log("pause", invalidCalls["pause"]);
    console2.log("unpause", invalidCalls["unpause"]);
  }

  function _depositRewardAssets(uint256 assetAmount_, string memory callName_) internal {
    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint64).max));
    IERC20 asset_ = getRewardPool(rewardsManager, currentRewardPoolId).asset;
    deal(address(asset_), currentActor, asset_.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset_.approve(address(rewardsManager), assetAmount_);
    uint256 shares_ = rewardsManager.depositRewardAssets(currentRewardPoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;
  }

  function _depositRewardAssetsWithoutTransfer(uint256 assetAmount_, string memory callName_) internal {
    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint64).max));
    IERC20 asset_ = getRewardPool(rewardsManager, currentRewardPoolId).asset;
    _simulateTransferToRewardsManager(asset_, assetAmount_);

    vm.startPrank(currentActor);
    uint256 shares_ = rewardsManager.depositRewardAssetsWithoutTransfer(currentRewardPoolId, assetAmount_, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;
  }

  function _stake(uint256 assetAmount_, string memory callName_) internal {
    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint64).max));
    IERC20 asset_ = getStakePool(rewardsManager, currentStakePoolId).asset;
    deal(address(asset_), currentActor, asset_.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset_.approve(address(rewardsManager), assetAmount_);
    uint256 shares_ = rewardsManager.stake(currentStakePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_stakePoolCumulative[currentStakePoolId].stakeAssetAmount += assetAmount_;
    ghost_stakePoolCumulative[currentStakePoolId].totalAssetAmount += assetAmount_;
    ghost_stakePoolCumulative[currentStakePoolId].stakeSharesAmount += shares_;

    ghost_actorStakeCount[currentActor][currentStakePoolId] += 1;
  }

  function _stakeWithoutTransfer(uint256 assetAmount_, string memory callName_) internal {
    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint64).max));
    IERC20 asset_ = getStakePool(rewardsManager, currentStakePoolId).asset;
    _simulateTransferToRewardsManager(asset_, assetAmount_);

    vm.startPrank(currentActor);
    uint256 shares_ = rewardsManager.stakeWithoutTransfer(currentStakePoolId, assetAmount_, currentActor);
    vm.stopPrank();

    ghost_stakePoolCumulative[currentStakePoolId].stakeAssetAmount += assetAmount_;
    ghost_stakePoolCumulative[currentStakePoolId].totalAssetAmount += assetAmount_;
    ghost_stakePoolCumulative[currentStakePoolId].stakeSharesAmount += shares_;

    ghost_actorStakeCount[currentActor][currentStakePoolId] += 1;
  }

  function _simulateTransferToRewardsManager(IERC20 asset_, uint256 assets_) internal {
    // Simulate transfer of assets to the rewards manager.
    deal(address(asset_), address(rewardsManager), asset_.balanceOf(address(rewardsManager)) + assets_, true);
  }

  function _createValidRandomAddress(address addr_) internal view returns (address) {
    if (addr_ == address(rewardsManager)) return _randomAddress();
    for (uint256 i = 0; i < numStakePools; i++) {
      for (uint256 j = 0; j < numRewardPools; j++) {
        if (addr_ == address(getStakePool(IRewardsManager(address(rewardsManager)), i).stkReceiptToken)) {
          return _randomAddress();
        }
        if (addr_ == address(getRewardPool(IRewardsManager(address(rewardsManager)), j).depositReceiptToken)) {
          return _randomAddress();
        }
      }
    }
    return addr_;
  }

  // ----------------------------------
  // -------- Helper modifiers --------
  // ----------------------------------

  modifier advanceTime(uint256 byAmount_) {
    vm.warp(currentTimestamp);
    byAmount_ = uint64(bound(byAmount_, 1, SECONDS_IN_A_YEAR));
    skip(byAmount_);
    currentTimestamp += byAmount_;
    totalTimeAdvanced += byAmount_;
    _;
  }

  modifier createActor() {
    address actor_ = _createValidRandomAddress(msg.sender);
    currentActor = actor_;
    actors.add(currentActor);
    _;
  }

  modifier createActorWithRewardDeposits() {
    actorsWithRewardDeposits.add(currentActor);
    _;
  }

  modifier createActorWithStakes() {
    actorsWithStakes.add(currentActor);
    _;
  }

  modifier countCall(string memory key_) {
    totalCalls++;
    calls[key_]++;
    _;
  }

  modifier useValidStakePoolId(uint256 seed_) {
    currentStakePoolId = uint16(bound(seed_, 0, numStakePools - 1));
    _;
  }

  modifier useValidRewardPoolId(uint256 seed_) {
    currentRewardPoolId = uint16(bound(seed_, 0, numRewardPools - 1));
    _;
  }

  modifier useActor(uint256 actorIndexSeed_) {
    currentActor = actors.rand(actorIndexSeed_);
    _;
  }

  modifier useActorWithRewardDeposits(uint256 seed_) {
    currentActor = actorsWithRewardDeposits.rand(seed_);

    uint16 initIndex_ = uint16(bound(seed_, 0, numRewardPools));
    uint16 indicesVisited_ = 0;

    // Iterate through reserve pools to find the first pool with a positive reserve deposit count for the current actor
    for (uint16 i = initIndex_; indicesVisited_ < numRewardPools; i = uint16((i + 1) % numRewardPools)) {
      if (ghost_actorRewardDepositCount[currentActor][i] > 0) {
        currentRewardPoolId = i;
        break;
      }
      indicesVisited_++;
    }
    _;
  }

  modifier useActorWithStakes(uint256 seed_) {
    currentActor = actorsWithStakes.rand(seed_);

    uint16 initIndex_ = uint16(bound(seed_, 0, numStakePools));
    uint16 indicesVisited_ = 0;

    // Iterate through reserve pools to find the first pool with a positive reserve deposit count for the current actor
    for (uint16 i = initIndex_; indicesVisited_ < numStakePools; i = uint16((i + 1) % numStakePools)) {
      if (ghost_actorStakeCount[currentActor][i] > 0) {
        currentStakePoolId = i;
        break;
      }
      indicesVisited_++;
    }
    _;
  }

  modifier warpToCurrentTimestamp() {
    vm.warp(currentTimestamp);
    _;
  }
}
