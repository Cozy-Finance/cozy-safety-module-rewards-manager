// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {AssetPool} from "../lib/structs/Pools.sol";
import {ClaimableRewardsData, PreviewClaimableRewards} from "../lib/structs/Rewards.sol";
import {SafetyModuleState} from "../lib/SafetyModuleStates.sol";
import {IDripModel} from "./IDripModel.sol";
import {IReceiptToken} from "./IReceiptToken.sol";
import {IReceiptTokenFactory} from "./IReceiptTokenFactory.sol";

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

  /// @notice The state of this SafetyModule.
  function safetyModuleState() external view returns (SafetyModuleState);
}
