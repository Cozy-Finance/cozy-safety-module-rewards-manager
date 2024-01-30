// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {AssetPool} from "../lib/structs/Pools.sol";
import {ClaimableRewardsData, PreviewClaimableRewards} from "../lib/structs/Rewards.sol";
import {RewardPoolConfig} from "../lib/structs/Rewards.sol";
import {IDripModel} from "./IDripModel.sol";

interface IRewardsManager {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(
    address owner_,
    address pauser_,
    address safetyModuleAddress_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_
  ) external;

  function assetPools(IERC20 asset_) external view returns (AssetPool memory assetPool_);

  /// @notice Retrieve accounting and metadata about reserve pools.
  function reservePools(uint256 id_)
    external
    view
    returns (
      uint256 amount,
      IReceiptToken safetyModuleReceiptToken,
      IReceiptToken stkReceiptToken,
      /// @dev The weighting of each stkToken's claim to all reward pools in terms of a ZOC. Must sum to 1.
      /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
      /// wrt totalSupply.
      uint16 rewardsWeight
    );

  /// @notice Retrieve accounting and metadata about reward pools.
  /// @dev Claimable reward pool IDs are mapped 1:1 with reward pool IDs.
  function rewardPools(uint256 id_)
    external
    view
    returns (
      uint256 amount,
      uint256 cumulativeDrippedRewards,
      uint128 lastDripTime,
      IERC20 asset,
      IDripModel dripModel,
      IReceiptToken depositToken
    );

  /// @notice Updates the reward module's user rewards data prior to a stkToken transfer.
  function updateUserRewardsForStkTokenTransfer(address from_, address to_) external;

  function cozyManager() external view returns (address);

  function receiptTokenFactory() external view returns (address);

  function owner() external view returns (address);

  function pauser() external view returns (address);
}
