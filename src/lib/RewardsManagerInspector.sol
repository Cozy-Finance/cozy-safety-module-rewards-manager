// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsManagerCalculationsLib} from "./RewardsManagerCalculationsLib.sol";
import {StakePool} from "./structs/Pools.sol";

abstract contract RewardsManagerInspector is RewardsManagerCommon {
  uint256 internal constant POOL_AMOUNT_FLOOR = 1;

  /// @notice Converts a reward pool's reward asset amount to the corresponding reward deposit receipt token amount.
  function convertRewardAssetAmountToRewardDepositReceiptTokenAmount(uint256 rewardPoolId_, uint256 rewardAssetAmount_)
    external
    view
    returns (uint256 depositReceiptTokenAmount_)
  {
    depositReceiptTokenAmount_ = RewardsManagerCalculationsLib.convertToReceiptTokenAmount(
      rewardAssetAmount_,
      rewardPools[rewardPoolId_].depositReceiptToken.totalSupply(),
      /// We set a floor to avoid divide-by-zero errors that would occur when the supply of deposit receipt tokens >
      /// 0, but the `poolAmount` == 0, which can occur due to drip.
      _poolAmountWithFloor(rewardPools[rewardPoolId_].undrippedRewards)
    );
  }

  /// @notice Converts a reward pool's reward deposit receipt token amount to the corresponding reward asset amount.
  function convertRewardDepositReceiptTokenToRewardAssetAmount(
    uint256 rewardPoolId_,
    uint256 depositReceiptTokenAmount_
  ) external view returns (uint256 rewardAssetAmount_) {
    rewardAssetAmount_ = RewardsManagerCalculationsLib.convertToAssetAmount(
      depositReceiptTokenAmount_,
      rewardPools[rewardPoolId_].depositReceiptToken.totalSupply(),
      // We set a floor to avoid divide-by-zero errors that would occur when the supply of depositReceiptTokens >
      // 0, but the `poolAmount` == 0, which can occur due to drip.
      _poolAmountWithFloor(rewardPools[rewardPoolId_].undrippedRewards)
    );
  }

  /// @notice Converts a stake pool's stake asset amount to the corresponding stake receipt token amount.
  function convertStakeAssetAmountToStakeReceiptTokenAmount(uint256 stakePoolId_, uint256 stakeAssetAmount_)
    external
    view
    returns (uint256 stakeReceiptTokenAmount_)
  {
    StakePool memory stakePool_ = stakePools[stakePoolId_];
    stakeReceiptTokenAmount_ = RewardsManagerCalculationsLib.convertToReceiptTokenAmount(
      stakeAssetAmount_, stakePool_.stkReceiptToken.totalSupply(), stakePool_.amount
    );
  }

  /// @notice Converts a stake pool's stake receipt token amount to the corresponding stake asset amount.
  function convertStakeReceiptTokenToStakeAssetAmount(uint256 stakePoolId_, uint256 stakeReceiptTokenAmount_)
    external
    view
    returns (uint256 stakeAssetAmount_)
  {
    StakePool memory stakePool_ = stakePools[stakePoolId_];
    stakeAssetAmount_ = RewardsManagerCalculationsLib.convertToAssetAmount(
      stakeReceiptTokenAmount_, stakePool_.stkReceiptToken.totalSupply(), stakePool_.amount
    );
  }

  /// @notice The pool amount for the purposes of performing conversions. We set a floor once reward
  /// deposit receipt tokens have been initialized to avoid divide-by-zero errors that would occur when the supply
  /// of reward deposit receipt tokens > 0, but the `poolAmount` = 0, which can occur due to drip.
  function _poolAmountWithFloor(uint256 poolAmount_) internal pure override returns (uint256) {
    return poolAmount_ > POOL_AMOUNT_FLOOR ? poolAmount_ : POOL_AMOUNT_FLOOR;
  }
}
