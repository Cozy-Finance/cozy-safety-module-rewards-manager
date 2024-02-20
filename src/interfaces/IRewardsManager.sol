// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {StakePool, RewardPool, AssetPool} from "../lib/structs/Pools.sol";
import {ClaimableRewardsData, PreviewClaimableRewards, UserRewardsData} from "../lib/structs/Rewards.sol";
import {RewardsManagerState} from "../lib/RewardsManagerStates.sol";
import {ClaimableRewardsData, PreviewClaimableRewards} from "../lib/structs/Rewards.sol";
import {RewardPoolConfig, StakePoolConfig} from "../lib/structs/Configs.sol";
import {ICozyManager} from "./ICozyManager.sol";

interface IRewardsManager {
  function allowedRewardPools() external view returns (uint8);

  function allowedStakePools() external view returns (uint8);

  function assetPools(IERC20 asset_) external view returns (AssetPool memory);

  function claimableRewards(uint16 stakePoolId_, uint16 rewardPoolId_)
    external
    view
    returns (ClaimableRewardsData memory);

  function claimRewards(uint16 stakePoolId_, address receiver_) external;

  function convertRewardAssetToReceiptTokenAmount(uint256 rewardPoolId_, uint256 rewardAssetAmount_)
    external
    view
    returns (uint256 depositReceiptTokenAmount_);

  function cozyManager() external returns (ICozyManager);

  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  function dripRewardPool(uint16 rewardPoolId_) external;

  function dripRewards() external;

  function getClaimableRewards() external view returns (ClaimableRewardsData[][] memory);

  function getClaimableRewards(uint16 stakePoolId_) external view returns (ClaimableRewardsData[] memory);

  function getRewardPools() external view returns (RewardPool[] memory);

  function getStakePools() external view returns (StakePool[] memory);

  function getUserRewards(uint16 stakePoolId_, address user) external view returns (UserRewardsData[] memory);

  function initialize(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_
  ) external;

  function owner() external view returns (address);

  function pause() external;

  function pauser() external view returns (address);

  function previewClaimableRewards(uint16[] calldata stakePoolIds_, address owner_)
    external
    view
    returns (PreviewClaimableRewards[] memory);

  function previewUndrippedRewardsRedemption(uint16 rewardPoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 rewardAssetAmount_);

  function redeemUndrippedRewards(
    uint16 rewardPoolId_,
    uint256 depositReceiptTokenAmount_,
    address receiver_,
    address owner_
  ) external returns (uint256 rewardAssetAmount_);

  function receiptTokenFactory() external view returns (address);

  function rewardPools(uint256 id_) external view returns (RewardPool memory);

  function rewardsManagerState() external view returns (RewardsManagerState);

  function stake(uint16 stakePoolId_, uint256 assetAmount_, address receiver_, address from_) external;

  function stakePools(uint256 id_) external view returns (StakePool memory);

  function stakeWithoutTransfer(uint16 stakePoolId_, uint256 assetAmount_, address receiver_) external;

  function unpause() external;

  function updateConfigs(StakePoolConfig[] calldata stakePoolConfigs_, RewardPoolConfig[] calldata rewardPoolConfigs_)
    external;

  function unstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_) external;

  function updateUserRewardsForStkReceiptTokenTransfer(address from_, address to_) external;
}
