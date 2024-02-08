// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {AssetPool} from "../lib/structs/Pools.sol";
import {ClaimableRewardsData, PreviewClaimableRewards} from "../lib/structs/Rewards.sol";
import {RewardPoolConfig, StakePoolConfig} from "../lib/structs/Configs.sol";
import {IDripModel} from "./IDripModel.sol";

interface IRewardsManager {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_
  ) external;

  function assetPools(IERC20 asset_) external view returns (AssetPool memory assetPool_);

  /// @notice Retrieve accounting and metadata about stake pools.
  function stakePools(uint256 id_)
    external
    view
    returns (
      uint256 amount,
      IERC20 asset,
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

  function receiptTokenFactory() external view returns (address);

  function owner() external view returns (address);

  function pauser() external view returns (address);

  function redeemUndrippedRewards(
    uint16 rewardPoolId_,
    uint256 depositReceiptTokenAmount_,
    address receiver_,
    address owner_
  ) external returns (uint256 rewardAssetAmount_);

  function unstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_)
    external
    returns (uint256 assetAmount_);

  function claimRewards(uint16 stakePoolId_, address receiver_) external;

  function previewClaimableRewards(uint16[] calldata stakePoolIds_, address owner_)
    external
    view
    returns (PreviewClaimableRewards[] memory previewClaimableRewards_);

  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  function stake(uint16 stakePoolId_, uint256 assetAmount_, address receiver_, address from_)
    external
    returns (uint256 stkReceiptTokenAmount_);

  function stakeWithoutTransfer(uint16 stakePoolId_, uint256 assetAmount_, address receiver_)
    external
    returns (uint256 stkReceiptTokenAmount_);
}
