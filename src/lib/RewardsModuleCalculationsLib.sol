// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @notice Read-only safety module calculations.
 */
library RewardsModuleCalculationsLib {
  using FixedPointMathLib for uint256;

  uint256 internal constant POOL_AMOUNT_FLOOR = 1;

  /// @notice The `tokenAmount_` that the safety module would exchange for `assetAmount_` of receipt token provided.
  /// @dev See the ERC-4626 spec for more info.
  function convertToReceiptTokenAmount(uint256 assetAmount_, uint256 receiptTokenSupply_, uint256 poolAmount_)
    internal
    pure
    returns (uint256 receiptTokenAmount_)
  {
    receiptTokenAmount_ =
      receiptTokenSupply_ == 0 ? assetAmount_ : assetAmount_.mulDivDown(receiptTokenSupply_, poolAmount_);
  }

  /// @notice The `assetAmount_` that the safety module would exchange for `receiptTokenAmount_` of the receipt
  /// token.
  /// @dev See the ERC-4626 spec for more info.
  function convertToAssetAmount(uint256 receiptTokenAmount_, uint256 receiptTokenSupply_, uint256 poolAmount_)
    internal
    pure
    returns (uint256 assetAmount_)
  {
    assetAmount_ = receiptTokenSupply_ == 0 ? 0 : receiptTokenAmount_.mulDivDown(poolAmount_, receiptTokenSupply_);
  }
}
