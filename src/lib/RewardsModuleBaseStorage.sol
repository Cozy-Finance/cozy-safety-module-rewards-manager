// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";
import {AssetPool, ReservePool, IdLookup, RewardPool} from "./structs/Pools.sol";
import {UserRewardsData, ClaimableRewardsData} from "./structs/Rewards.sol";

abstract contract RewardsModuleBaseStorage {
  /// @notice Address of the Cozy SafetyModule.
  ISafetyModule public safetyModule;

  /// @notice Address of the Cozy protocol ReceiptTokenFactory.
  IReceiptTokenFactory public immutable receiptTokenFactory;

  /// @dev Reserve pool index in this array is its ID
  ReservePool[] public reservePools;

  /// @dev Reward pool index in this array is its ID
  RewardPool[] public rewardPools;

  /// @dev Used for doing aggregate accounting of reserve assets.
  mapping(IERC20 reserveAsset_ => AssetPool assetPool_) public assetPools;

  /// @notice Maps a reserve pool id to an reward pool id to claimable reward index
  mapping(uint16 => mapping(uint16 => ClaimableRewardsData)) public claimableRewards;

  /// @notice Maps a reserve pool id to a user address to a user reward pool accounting struct.
  mapping(uint16 => mapping(address => UserRewardsData[])) public userRewards;

  /// @dev Used when claiming rewards
  mapping(IReceiptToken stkToken_ => IdLookup reservePoolId_) public stkTokenToReservePoolIds;
}
