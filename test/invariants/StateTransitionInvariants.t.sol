// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ICommonErrors} from "cozy-safety-module-libs/interfaces/ICommonErrors.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-libs/lib/Ownable.sol";
import {StakePool, RewardPool, AssetPool} from "../../src/lib/structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData, PreviewClaimableRewards} from "../../src/lib/structs/Rewards.sol";
import {RewardsManagerState} from "../../src/lib/RewardsManagerStates.sol";
import {
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract StateTransitionInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  using FixedPointMathLib for uint256;

  function invariant_pauseByAuthorizedCallerPossible() public syncCurrentTimestamp(rewardsManagerHandler) {
    address[3] memory authorizedCallers_ =
      [rewardsManager.owner(), rewardsManager.pauser(), address(rewardsManager.cozyManager())];
    address caller_ = authorizedCallers_[_randomUint16() % authorizedCallers_.length];

    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidStateTransition.selector);
    }

    vm.prank(caller_);
    rewardsManager.pause();
    require(
      rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED,
      "Invariant Violated: The rewards manager's state must be paused."
    );
  }

  function invariant_pauseByUnauthorizedCallerReverts() public syncCurrentTimestamp(rewardsManagerHandler) {
    address[3] memory authorizedCallers_ =
      [rewardsManager.owner(), rewardsManager.pauser(), address(rewardsManager.cozyManager())];
    address caller_ = _randomAddress();
    for (uint256 i = 0; i < authorizedCallers_.length; i++) {
      vm.assume(caller_ != authorizedCallers_[i]);
    }

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(caller_);
    rewardsManager.pause();
  }

  function invariant_unpauseTransitionsToExpectedRewardsManagerState()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    address[2] memory authorizedCallers_ = [rewardsManager.owner(), address(rewardsManager.cozyManager())];
    address caller_ = authorizedCallers_[_randomUint16() % authorizedCallers_.length];

    if (rewardsManager.rewardsManagerState() != RewardsManagerState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidStateTransition.selector);
    }

    vm.prank(caller_);
    rewardsManager.unpause();
    require(
      rewardsManager.rewardsManagerState() == RewardsManagerState.ACTIVE,
      "Invariant Violated: The rewards manager's state does not match expected state after unpause."
    );
  }

  function invariant_unpauseByUnauthorizedCallerReverts() public syncCurrentTimestamp(rewardsManagerHandler) {
    address[2] memory authorizedCallers_ = [rewardsManager.owner(), address(rewardsManager.cozyManager())];
    address[2] memory callers_ = [_randomAddress(), rewardsManager.pauser()];
    for (uint256 i = 0; i < authorizedCallers_.length; i++) {
      vm.assume(callers_[0] != authorizedCallers_[i]);
    }

    for (uint256 i = 0; i < callers_.length; i++) {
      vm.expectRevert(Ownable.Unauthorized.selector);
      vm.prank(callers_[i]);
      rewardsManager.unpause();
    }
  }

  function invariant_depositRewardAssetsWithoutTransferRevertsWhenPaused()
    public
    syncCurrentTimestamp(rewardsManagerHandler)
  {
    uint16 rewardPoolId_ = rewardsManagerHandler.pickValidRewardPoolId(_randomUint256());

    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(_randomAddress());
      rewardsManager.depositRewardAssetsWithoutTransfer(rewardPoolId_, _randomUint256());
    }
  }

  function invariant_depositRewardAssetsRevertsWhenPaused() public syncCurrentTimestamp(rewardsManagerHandler) {
    address actor_ = _randomAddress();
    uint16 rewardPoolId_ = rewardsManagerHandler.pickValidRewardPoolId(_randomUint256());
    IERC20 asset_ = rewardsManager.rewardPools(rewardPoolId_).asset;

    uint256 depositAmount_ = bound(_randomUint64(), 1, type(uint64).max);
    deal(address(asset_), actor_, depositAmount_, true);

    vm.prank(actor_);
    asset_.approve(address(rewardsManager), depositAmount_);

    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(actor_);
      rewardsManager.depositRewardAssets(rewardPoolId_, depositAmount_);
    }
  }

  function invariant_stakeWithoutTransferRevertsWhenPaused() public syncCurrentTimestamp(rewardsManagerHandler) {
    address actor_ = _randomAddress();
    uint16 stakePoolId_ = rewardsManagerHandler.pickValidStakePoolId(_randomUint256());
    IERC20 asset_ = rewardsManager.stakePools(stakePoolId_).asset;

    uint256 stakeAmount_ = bound(_randomUint64(), 1, type(uint64).max);
    deal(address(asset_), actor_, stakeAmount_, true);

    vm.prank(actor_);
    asset_.transfer(address(rewardsManager), stakeAmount_);

    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(actor_);
      rewardsManager.stakeWithoutTransfer(stakePoolId_, stakeAmount_, _randomAddress());
    }
  }

  function invariant_stakeRevertsWhenPaused() public syncCurrentTimestamp(rewardsManagerHandler) {
    address actor_ = _randomAddress();
    uint16 stakePoolId_ = rewardsManagerHandler.pickValidStakePoolId(_randomUint256());
    IERC20 asset_ = rewardsManager.stakePools(stakePoolId_).asset;

    uint256 stakeAmount_ = bound(_randomUint64(), 1, type(uint64).max);
    deal(address(asset_), actor_, stakeAmount_, true);

    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(actor_);
      rewardsManager.stake(stakePoolId_, stakeAmount_, _randomAddress());
    }
  }

  function invariant_dripRewardsRevertsWhenPaused() public syncCurrentTimestamp(rewardsManagerHandler) {
    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(_randomAddress());
      rewardsManager.dripRewards();
    }
  }

  function invariant_dripRewardPoolRevertsWhenPaused() public syncCurrentTimestamp(rewardsManagerHandler) {
    if (rewardsManager.rewardsManagerState() == RewardsManagerState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(_randomAddress());
      rewardsManager.dripRewardPool(rewardsManagerHandler.pickValidRewardPoolId(_randomUint256()));
    }
  }
}

contract StateTransitionInvariantsWithStateTransitionsSingleReservePool is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithSingleStakePoolAndSingleRewardPool
{}

contract StateTransitionInvariantsWithStateTransitionsMultipleReservePools is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
