// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {console2} from "forge-std/console2.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {RewardsManager} from "../../../src/RewardsManager.sol";
import {StakePool, RewardPool} from "../../../src/lib/structs/Pools.sol";
import {PreviewClaimableRewards, PreviewClaimableRewardsData} from "../../../src/lib/structs/Rewards.sol";
import {RewardsManagerState} from "../../../src/lib/RewardsManagerStates.sol";
import {IRewardsManager} from "../../../src/interfaces/IRewardsManager.sol";
import {TestBase} from "../../utils/TestBase.sol";

contract RewardsManagerHandler is TestBase {
  using FixedPointMathLib for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  uint64 constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;
  address public constant DEFAULT_ADDRESS = address(0xc0ffee);

  address pauser;
  address owner;

  IRewardsManager public rewardsManager;

  uint256 numStakePools;
  uint256 numRewardPools;

  mapping(string => uint256) public calls;
  mapping(string => uint256) public invalidCalls;

  address public currentActor;

  EnumerableSet.AddressSet internal actors;

  EnumerableSet.AddressSet internal actorsWithRewardDeposits;

  EnumerableSet.AddressSet internal actorsWithStakes;

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
    uint256 unstakeAssetAmount;
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
    _depositRewardAssets(assetAmount_);

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
    _depositRewardAssets(assetAmount_);

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
    _depositRewardAssetsWithoutTransfer(assetAmount_);

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
    _depositRewardAssetsWithoutTransfer(assetAmount_);

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
    _stake(assetAmount_);

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
    _stake(assetAmount_);

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
    _stakeWithoutTransfer(assetAmount_);

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
    _stakeWithoutTransfer(assetAmount_);

    return currentActor;
  }

  function redeemUndrippedRewards(uint256 depositReceiptTokenRedeemAmount_, address receiver_, uint256 seed_)
    public
    virtual
    useActorWithRewardDeposits(seed_)
    countCall("redeemUndrippedRewards")
    advanceTime(seed_)
  {
    IERC20 depositReceiptToken_ = getRewardPool(rewardsManager, currentRewardPoolId).depositReceiptToken;
    uint256 actorDepositReceiptTokenBalance_ = depositReceiptToken_.balanceOf(currentActor);
    if (actorDepositReceiptTokenBalance_ == 0) {
      invalidCalls["redeemUndrippedRewards"] += 1;
      return;
    }

    depositReceiptTokenRedeemAmount_ = bound(depositReceiptTokenRedeemAmount_, 1, actorDepositReceiptTokenBalance_);
    vm.startPrank(currentActor);
    depositReceiptToken_.approve(address(rewardsManager), depositReceiptTokenRedeemAmount_);
    uint256 assetAmount_ = rewardsManager.redeemUndrippedRewards(
      currentRewardPoolId, depositReceiptTokenRedeemAmount_, receiver_, currentActor
    );
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].redeemAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].redeemSharesAmount += depositReceiptTokenRedeemAmount_;

    if (depositReceiptTokenRedeemAmount_ == actorDepositReceiptTokenBalance_) {
      actorsWithRewardDeposits.remove(currentActor);
    }
  }

  function unstake(address receiver_, uint256 seed_)
    public
    virtual
    useActorWithStakes(seed_)
    countCall("unstake")
    advanceTime(seed_)
    returns (uint256 stkReceiptTokenUnstakeAmount_)
  {
    IERC20 stkReceiptToken_ = getStakePool(rewardsManager, currentStakePoolId).stkReceiptToken;
    uint256 actorStkReceiptTokenBalance_ = stkReceiptToken_.balanceOf(currentActor);
    if (actorStkReceiptTokenBalance_ == 0) {
      invalidCalls["unstake"] += 1;
      return 0;
    }

    _incrementGhostRewardsToBeClaimed(currentStakePoolId, currentActor);

    stkReceiptTokenUnstakeAmount_ = bound(_randomUint256(), 1, actorStkReceiptTokenBalance_);
    vm.startPrank(currentActor);
    stkReceiptToken_.approve(address(rewardsManager), stkReceiptTokenUnstakeAmount_);
    rewardsManager.unstake(currentStakePoolId, stkReceiptTokenUnstakeAmount_, receiver_, currentActor);
    vm.stopPrank();

    if (stkReceiptTokenUnstakeAmount_ == actorStkReceiptTokenBalance_) actorsWithStakes.remove(currentActor);
    ghost_stakePoolCumulative[currentStakePoolId].unstakeAssetAmount += stkReceiptTokenUnstakeAmount_;
  }

  function dripRewards(uint256 seed_) public virtual countCall("dripRewards") advanceTime(seed_) {
    rewardsManager.dripRewards();
  }

  function dripRewardPool(uint256 seed_)
    public
    virtual
    countCall("dripRewardPool")
    useValidRewardPoolId(seed_)
    advanceTime(seed_)
  {
    rewardsManager.dripRewardPool(currentRewardPoolId);
  }

  function stkReceiptTokenTransfer(uint64 stkReceiptTokenTransferAmount_, address to_, uint256 seed_)
    public
    virtual
    useActorWithStakes(seed_)
    countCall("stkReceiptTokenTransfer")
    advanceTime(seed_)
    returns (address actor_, uint256 amount_)
  {
    IERC20 stkReceiptToken_ = getStakePool(rewardsManager, currentStakePoolId).stkReceiptToken;
    uint256 actorStkReceiptTokenBalance_ = stkReceiptToken_.balanceOf(currentActor);
    if (actorStkReceiptTokenBalance_ == 0) {
      invalidCalls["stkReceiptTokenTransfer"] += 1;
      return (currentActor, 0);
    }

    uint256 boundedStkReceiptTokenTransferAmount_ =
      bound(uint256(stkReceiptTokenTransferAmount_), 0, actorStkReceiptTokenBalance_);

    vm.startPrank(currentActor);
    // This will call `updateUserRewardsForStkReceiptTokenTransfer` in the RewardsManager.
    stkReceiptToken_.transfer(to_, boundedStkReceiptTokenTransferAmount_);
    vm.stopPrank();

    if (boundedStkReceiptTokenTransferAmount_ == actorStkReceiptTokenBalance_) actorsWithStakes.remove(currentActor);

    return (currentActor, boundedStkReceiptTokenTransferAmount_);
  }

  function updateUserRewardsForStkReceiptTokenTransfer(address from_, address to_, uint256 seed_)
    public
    virtual
    useValidStakePoolId(seed_)
    countCall("updateUserRewardsForStkReceiptTokenTransfer")
    advanceTime(seed_)
  {
    IERC20 stkReceiptToken_ = getStakePool(rewardsManager, currentStakePoolId).stkReceiptToken;

    vm.prank(address(stkReceiptToken_));
    rewardsManager.updateUserRewardsForStkReceiptTokenTransfer(from_, to_);
  }

  function claimRewards(address receiver_, uint256 seed_)
    public
    useActorWithStakes(seed_)
    countCall("claimRewards")
    advanceTime(seed_)
    returns (address actor_)
  {
    IERC20 stkReceiptToken_ = getStakePool(rewardsManager, currentStakePoolId).stkReceiptToken;
    uint256 actorStkReceiptTokenBalance_ = stkReceiptToken_.balanceOf(currentActor);
    if (actorStkReceiptTokenBalance_ == 0) {
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

  function pause(uint256 seed_) public virtual countCall("pause") advanceTime(seed_) {
    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) {
      invalidCalls["pause"] += 1;
      return;
    }
    vm.prank(pauser);
    rewardsManager.pause();
  }

  function unpause(uint256 seed_) public virtual countCall("unpause") advanceTime(seed_) {
    if (rewardsManager.rewardsManagerState() != RewardsManagerState.ACTIVE) {
      invalidCalls["unpause"] += 1;
      return;
    }
    vm.prank(owner);
    rewardsManager.unpause();
  }

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
    console2.log("unstake", calls["unstake"]);
    console2.log("dripRewards", calls["dripRewards"]);
    console2.log("dripRewardPool", calls["dripRewardPool"]);
    console2.log("claimRewards", calls["claimRewards"]);
    console2.log("stkReceiptTokenTransfer", calls["stkReceiptTokenTransfer"]);
    console2.log("updateUserRewardsForStkReceiptTokenTransfer", calls["updateUserRewardsForStkReceiptTokenTransfer"]);
    console2.log("redeemUndrippedRewards", calls["redeemUndrippedRewards"]);
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
    console2.log("unstake", invalidCalls["unstake"]);
    console2.log("dripRewards", invalidCalls["dripRewards"]);
    console2.log("dripRewardPool", invalidCalls["dripRewardPool"]);
    console2.log("claimRewards", invalidCalls["claimRewards"]);
    console2.log("stkReceiptTokenTransfer", invalidCalls["stkReceiptTokenTransfer"]);
    console2.log(
      "updateUserRewardsForStkReceiptTokenTransfer", invalidCalls["updateUserRewardsForStkReceiptTokenTransfer"]
    );
    console2.log("redeemUndrippedRewards", invalidCalls["redeemUndrippedRewards"]);
    console2.log("pause", invalidCalls["pause"]);
    console2.log("unpause", invalidCalls["unpause"]);
  }

  function stakeWithoutTransferWithExistingActorWithoutCountingCall(uint256 assets_) external returns (address) {
    uint256 invalidCallsBefore_ = invalidCalls["stakeWithExistingActor"];

    address actor_ = stakeWithExistingActor(assets_, _randomUint256());

    calls["stakeWithExistingActor"] -= 1; // stakeWithExistingActor increments by 1.
    if (invalidCallsBefore_ < invalidCalls["stakeWithExistingActor"]) invalidCalls["stakeWithExistingActor"] -= 1;

    return actor_;
  }

  function depositRewardAssetsWithExistingActorWithoutCountingCall(uint256 assets_) external returns (address) {
    uint256 invalidCallsBefore_ = invalidCalls["depositRewardAssetsWithExistingActor"];

    address actor_ = depositRewardAssetsWithExistingActor(assets_, _randomUint256());

    calls["depositRewardAssetsWithExistingActor"] -= 1; // depositWithExistingActor increments by 1.
    if (invalidCallsBefore_ < invalidCalls["depositRewardAssetsWithExistingActor"]) {
      invalidCalls["depositRewardAssetsWithExistingActor"] -= 1;
    }

    return actor_;
  }

  function depositRewardAssetsWithExistingActorWithoutCountingCall(uint8 rewardPoolId_, uint256 assets_, address actor_)
    external
    returns (address)
  {
    uint256 invalidCallsBefore_ = invalidCalls["depositRewardAssetsWithExistingActor"];

    currentRewardPoolId = rewardPoolId_;
    currentActor = actor_;

    _depositRewardAssets(assets_);

    // _depositReserveAssets increments invalidCalls by 1 if the rewards manager is paused.
    if (invalidCallsBefore_ < invalidCalls["depositRewardAssetsWithExistingActor"]) {
      invalidCalls["depositRewardAssetsWithExistingActor"] -= 1;
    }

    return currentActor;
  }

  function boundDepositAssetAmount(uint256 assetAmount_) public pure returns (uint256) {
    return bound(assetAmount_, 0.0001e6, type(uint72).max);
  }

  function pickValidRewardPoolId(uint256 seed_) public view returns (uint8) {
    return uint8(seed_ % numRewardPools);
  }

  function pickValidStakePoolId(uint256 seed_) public view returns (uint8) {
    return uint8(seed_ % numStakePools);
  }

  function pickActor(uint256 seed_) public view returns (address) {
    uint256 numActors_ = actors.length();
    return numActors_ == 0 ? DEFAULT_ADDRESS : actors.at(seed_ % numActors_);
  }

  function _depositRewardAssets(uint256 assetAmount_) internal {
    assetAmount_ = boundDepositAssetAmount(assetAmount_);
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

  function _depositRewardAssetsWithoutTransfer(uint256 assetAmount_) internal {
    assetAmount_ = boundDepositAssetAmount(assetAmount_);
    IERC20 asset_ = getRewardPool(rewardsManager, currentRewardPoolId).asset;
    _simulateTransferToRewardsManager(asset_, assetAmount_);

    vm.startPrank(currentActor);
    uint256 shares_ = rewardsManager.depositRewardAssetsWithoutTransfer(currentRewardPoolId, assetAmount_, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;
  }

  function _stake(uint256 assetAmount_) internal {
    assetAmount_ = boundDepositAssetAmount(assetAmount_);
    IERC20 asset_ = getStakePool(rewardsManager, currentStakePoolId).asset;
    deal(address(asset_), currentActor, asset_.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset_.approve(address(rewardsManager), assetAmount_);
    rewardsManager.stake(currentStakePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_stakePoolCumulative[currentStakePoolId].stakeAssetAmount += assetAmount_;
    ghost_stakePoolCumulative[currentStakePoolId].totalAssetAmount += assetAmount_;

    ghost_actorStakeCount[currentActor][currentStakePoolId] += 1;
  }

  function _stakeWithoutTransfer(uint256 assetAmount_) internal {
    assetAmount_ = boundDepositAssetAmount(assetAmount_);
    IERC20 asset_ = getStakePool(rewardsManager, currentStakePoolId).asset;
    _simulateTransferToRewardsManager(asset_, assetAmount_);

    vm.startPrank(currentActor);
    rewardsManager.stakeWithoutTransfer(currentStakePoolId, assetAmount_, currentActor);
    vm.stopPrank();

    ghost_stakePoolCumulative[currentStakePoolId].stakeAssetAmount += assetAmount_;
    ghost_stakePoolCumulative[currentStakePoolId].totalAssetAmount += assetAmount_;

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
    currentStakePoolId = pickValidStakePoolId(seed_);
    _;
  }

  modifier useValidRewardPoolId(uint256 seed_) {
    currentRewardPoolId = pickValidRewardPoolId(seed_);
    _;
  }

  modifier useActor(uint256 actorIndexSeed_) {
    currentActor = getActor(actorIndexSeed_);
    _;
  }

  modifier useActorWithRewardDeposits(uint256 seed_) {
    currentActor = getActorWithRewardDeposits(seed_);
    currentRewardPoolId = getRewardPoolIdForActorWithRewardDeposits(seed_, currentActor);
    _;
  }

  modifier useActorWithStakes(uint256 seed_) {
    currentActor = getActorWithStake(seed_);
    currentStakePoolId = getStakePoolIdForActorWithStake(seed_, currentActor);
    _;
  }

  modifier warpToCurrentTimestamp() {
    vm.warp(currentTimestamp);
    _;
  }

  // ----------------------------------
  // ------- AddressSet helpers -------
  // ----------------------------------
  function getActor(uint256 actorIndexSeed_) public view returns (address) {
    uint256 numActors_ = actors.length();
    return numActors_ == 0 ? DEFAULT_ADDRESS : actors.at(actorIndexSeed_ % numActors_);
  }

  function getActorWithRewardDeposits(uint256 actorIndexSeed_) public view returns (address) {
    uint256 numActorsWithRewardDeposits_ = actorsWithRewardDeposits.length();
    return numActorsWithRewardDeposits_ == 0
      ? DEFAULT_ADDRESS
      : actorsWithRewardDeposits.at(actorIndexSeed_ % numActorsWithRewardDeposits_);
  }

  function getActorWithStake(uint256 actorIndexSeed_) public view returns (address) {
    uint256 numActorsWithStakes_ = actorsWithStakes.length();
    return numActorsWithStakes_ == 0 ? DEFAULT_ADDRESS : actorsWithStakes.at(actorIndexSeed_ % numActorsWithStakes_);
  }

  function getActorsWithStakes() external view returns (address[] memory) {
    return actorsWithStakes.values();
  }

  function getActorsWithRewardDeposits() external view returns (address[] memory) {
    return actorsWithRewardDeposits.values();
  }

  function getStakePoolIdForActorWithStake(uint256 seed_, address actor_) public view returns (uint16) {
    uint16 initIndex_ = uint16(_randomUint256FromSeed(seed_) % numStakePools);
    uint16 indicesVisited_ = 0;

    // Iterate through stake pools to find the first pool with a stake deposit count for the current actor.
    for (uint16 i = initIndex_; indicesVisited_ < numStakePools; i = uint16((i + 1) % numStakePools)) {
      if (ghost_actorStakeCount[actor_][i] > 0) return i;
      indicesVisited_++;
    }

    // If no stake pool with a stake deposit count was found, return the random initial index.
    return initIndex_;
  }

  function getRewardPoolIdForActorWithRewardDeposits(uint256 seed_, address actor_) public view returns (uint16) {
    uint16 initIndex_ = uint16(_randomUint256FromSeed(seed_) % numRewardPools);
    uint16 indicesVisited_ = 0;

    // Iterate through reward pools to find the first pool with a positive reward deposit count for the current actor
    for (uint16 i = initIndex_; indicesVisited_ < numRewardPools; i = uint16((i + 1) % numRewardPools)) {
      if (ghost_actorRewardDepositCount[actor_][i] > 0) return i;
      indicesVisited_++;
    }

    // If no reward pool with a reward deposit count was found, return the random initial index.
    return initIndex_;
  }

  function previewClaimableRewardsForActor(uint16 stakePoolId_, address actor_)
    public
    view
    returns (PreviewClaimableRewards[] memory reservePoolClaimableRewards_)
  {
    uint16[] memory stakePoolIds_ = new uint16[](1);
    stakePoolIds_[0] = stakePoolId_;
    reservePoolClaimableRewards_ = rewardsManager.previewClaimableRewards(stakePoolIds_, actor_);
  }
}
