// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {AssetPool} from "../lib/structs/Pools.sol";
import {ClaimableRewardsData, PreviewClaimableRewards} from "../lib/structs/Rewards.sol";
import {IDripModel} from "./IDripModel.sol";

interface ISafetyModule {
  struct Delays {
    // Duration between when safety module updates are queued and when they can be executed.
    uint64 configUpdateDelay;
    // Defines how long the owner has to execute a configuration change, once it can be executed.
    uint64 configUpdateGracePeriod;
    // Delay for two-step unstake process (for staked assets).
    uint64 unstakeDelay;
    // Delay for two-step withdraw process (for deposited assets).
    uint64 withdrawDelay;
  }

  function assetPools(IERC20 asset_) external view returns (AssetPool memory assetPool_);

  function delays() external view returns (Delays memory delays_);

  /// @dev Expects `from_` to have approved this SafetyModule for `reserveAssetAmount_` of
  /// `reservePools[reservePoolId_].asset` so it can `transferFrom`
  function depositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositTokenAmount_);

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositTokenAmount_);

  /// @notice Redeems by burning `depositTokenAmount_` of `reservePoolId_` reserve pool deposit tokens and sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeem(uint16 reservePoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_);

  /// @notice Redeem by burning `depositTokenAmount_` of `rewardPoolId_` reward pool deposit tokens and sending
  /// `rewardAssetAmount_` of `rewardPoolId_` reward pool assets to `receiver_`. Reward pool assets can only be redeemed
  /// if they have not been dripped yet.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeemUndrippedRewards(uint16 rewardPoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    external
    returns (uint256 rewardAssetAmount_);

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

  /// @notice The state of this SafetyModule.
  function safetyModuleState() external view returns (SafetyModuleState);

  function numReservePools() external view returns (uint16);
}
