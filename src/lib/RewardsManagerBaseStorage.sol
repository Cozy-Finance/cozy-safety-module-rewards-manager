// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {ICozyManager} from "../interfaces/ICozyManager.sol";
import {AssetPool, StakePool, IdLookup, RewardPool} from "./structs/Pools.sol";
import {UserRewardsData, ClaimableRewardsData} from "./structs/Rewards.sol";

abstract contract RewardsManagerBaseStorage {
  /// @notice Address of the Cozy protocol manager.
  ICozyManager public immutable cozyManager;

  /// @notice Address of the receipt token factory.
  IReceiptTokenFactory public immutable receiptTokenFactory;

  /// @notice The reward manager's stake pools.
  /// @dev Stake pool index in this array is its ID.
  StakePool[] public stakePools;

  /// @notice The reward manager's reward pools.
  /// @dev Reward pool index in this array is its ID.
  RewardPool[] public rewardPools;

  /// @notice Maps an asset to its asset pool.
  /// @dev Used for doing aggregate accounting of stake/reward assets.
  mapping(IERC20 asset_ => AssetPool assetPool_) public assetPools;

  /// @notice Maps a stake pool id to an reward pool id to claimable rewards data.
  mapping(uint16 => mapping(uint16 => ClaimableRewardsData)) public claimableRewards;

  /// @notice Maps a stake pool id to a user address to an array of user rewards data.
  mapping(uint16 => mapping(address => UserRewardsData[])) public userRewards;

  /// @notice Maps a stake receipt token to an index lookup for its stake pool id.
  /// @dev Used for authorization check when transferring stkReceiptTokens.
  mapping(IReceiptToken stkReceiptToken_ => IdLookup stakePoolId_) public stkReceiptTokenToStakePoolIds;

  /// @notice Maps an asset to an index lookup for its stake pool id.
  /// @dev Used for checking that new stake pools have unique underlying assets in config updates.
  mapping(IERC20 asset_ => IdLookup stakePoolId_) public assetToStakePoolIds;

  /// @dev True if the rewards manager has been initialized.
  bool public initialized;

  /// @notice The state of this rewards manager.
  RewardsManagerState public rewardsManagerState;

  /// @notice The max number of stake pools allowed per rewards manager.
  uint8 public immutable allowedStakePools;

  /// @notice The max number of reward pools allowed per rewards manager.
  uint8 public immutable allowedRewardPools;
}
