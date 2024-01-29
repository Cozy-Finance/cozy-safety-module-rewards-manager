// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {AssetPool} from "../lib/structs/Pools.sol";
import {ClaimableRewardsData, PreviewClaimableRewards} from "../lib/structs/Rewards.sol";
import {SafetyModuleState} from "../lib/SafetyModuleStates.sol";
import {IDripModel} from "./IDripModel.sol";
import {IReceiptToken} from "./IReceiptToken.sol";
import {IReceiptTokenFactory} from "./IReceiptTokenFactory.sol";

interface IRewardsModule {
  function assetPools(IERC20 asset_) external view returns (AssetPool memory assetPool_);

  /// @notice Retrieve accounting and metadata about reserve pools.
  function reservePools(uint256 id_)
    external
    view
    returns (
      uint256 stakeAmount,
      uint256 depositAmount,
      uint256 pendingUnstakesAmount,
      uint256 pendingWithdrawalsAmount,
      uint256 feeAmount,
      /// @dev The max percentage of the stake amount that can be slashed in a SINGLE slash as a WAD. If multiple
      /// slashes
      /// occur, they compound, and the final stake amount can be less than (1 - maxSlashPercentage)% following all the
      /// slashes. The max slash percentage is only a guarantee for stakers; depositors are always at risk to be fully
      /// slashed.
      uint256 maxSlashPercentage,
      IERC20 asset,
      IReceiptToken stkToken,
      IReceiptToken depositToken,
      /// @dev The weighting of each stkToken's claim to all reward pools in terms of a ZOC. Must sum to 1.
      /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
      /// wrt totalSupply.
      uint16 rewardsPoolsWeight,
      uint128 lastFeesDripTime
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

  /// @notice Updates the safety module's user rewards data prior to a stkToken transfer.
  function updateUserRewardsForStkTokenTransfer(address from_, address to_) external;
}
