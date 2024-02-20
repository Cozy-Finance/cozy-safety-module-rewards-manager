// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @notice Read-only rewards manager calculations.
 */
library RewardsManagerCalculationsLib {
  using FixedPointMathLib for uint256;

  /// @notice The `receiptTokenAmount_` of the receipt tokens that the rewards manager would exchange for `assetAmount_`
  /// of underlying asset provided.
  /// @dev See the ERC-4626 spec for more info.
  function convertToReceiptTokenAmount(uint256 assetAmount_, uint256 receiptTokenSupply_, uint256 poolAmount_)
    internal
    pure
    returns (uint256 receiptTokenAmount_)
  {
    receiptTokenAmount_ =
      receiptTokenSupply_ == 0 ? assetAmount_ : assetAmount_.mulDivDown(receiptTokenSupply_, poolAmount_);
  }

  /// @notice The `assetAmount_` of the underlying asset that the rewards manager would exchange for
  /// `receiptTokenAmount_` of the receipt token provided.
  /// @dev See the ERC-4626 spec for more info.
  function convertToAssetAmount(uint256 receiptTokenAmount_, uint256 receiptTokenSupply_, uint256 poolAmount_)
    internal
    pure
    returns (uint256 assetAmount_)
  {
    assetAmount_ = receiptTokenSupply_ == 0 ? 0 : receiptTokenAmount_.mulDivDown(poolAmount_, receiptTokenSupply_);
  }
}
