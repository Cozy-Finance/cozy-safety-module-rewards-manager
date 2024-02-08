// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {IManager} from "../interfaces/IManager.sol";
import {AssetPool, StakePool, IdLookup, RewardPool} from "./structs/Pools.sol";
import {UserRewardsData, ClaimableRewardsData} from "./structs/Rewards.sol";

abstract contract RewardsManagerBaseStorage {
  /// @notice Address of the Cozy protocol manager.
  IManager public immutable cozyManager;

  /// @notice Address of the Cozy protocol ReceiptTokenFactory.
  IReceiptTokenFactory public immutable receiptTokenFactory;

  /// @dev Stake pool index in this array is its ID
  StakePool[] public stakePools;

  /// @dev Reward pool index in this array is its ID
  RewardPool[] public rewardPools;

  /// @dev Used for doing aggregate accounting of stake pool assets.
  mapping(IERC20 asset_ => AssetPool assetPool_) public assetPools;

  /// @notice Maps a stake pool id to an reward pool id to claimable reward index
  mapping(uint16 => mapping(uint16 => ClaimableRewardsData)) public claimableRewards;

  /// @notice Maps a stake pool id to a user address to a user reward pool accounting struct.
  mapping(uint16 => mapping(address => UserRewardsData[])) public userRewards;

  /// @dev Used when claiming rewards
  mapping(IReceiptToken stkReceiptToken_ => IdLookup stakePoolId_) public stkReceiptTokenToStakePoolIds;

  /// @dev The state of this rewards manager.
  RewardsManagerState public rewardsManagerState;

  /// @notice The max number of stake pools allowed per rewards manager.
  uint8 public immutable allowedStakePools;

  /// @notice The max number of reward pools allowed per rewards manager.
  uint8 public immutable allowedRewardPools;
}
