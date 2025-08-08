// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @notice Library for reward withdrawal mathematical operations.
/// @dev All functions operate in WAD (1e18) precision.
library RewardMathLib {
  using FixedPointMathLib for uint256;

  /// @notice Computes -ln(x) where x is in WAD precision.
  /// @param x_ The input value in WAD precision (must be > 0 and <= WAD).
  /// @return The negative natural logarithm of x in WAD precision.
  function negLn(uint256 x_) internal pure returns (uint256) {
    require(x_ > 0 && x_ <= MathConstants.WAD, "RewardMathLib: Invalid input for ln");

    // lnWad returns ln(x) in WAD precision
    // Since x <= 1, ln(x) <= 0, so we need to handle the sign
    if (x_ == MathConstants.WAD) return 0; // -ln(1) = 0

    // For x < 1, ln(x) is negative, but lnWad returns the absolute value
    // with the understanding that the result represents a negative number.
    // We need -ln(x), which is positive for x < 1.
    // Since lnWad effectively returns |ln(x)| for x < 1, and ln(x) < 0 for x < 1,
    // -ln(x) = |ln(x)| which is what lnWad gives us.
    return MathConstants.WAD.lnWad() - x_.lnWad();
  }

  /// @notice Computes e^(-x) where x is in WAD precision.
  /// @param x_ The input value in WAD precision (non-negative).
  /// @return The value e^(-x) in WAD precision.
  function expNeg(uint256 x_) internal pure returns (uint256) {
    if (x_ == 0) return MathConstants.WAD; // e^0 = 1

    // For very large x, e^(-x) approaches 0
    // expWad has a minimum input of -42139678854452767551 (approximately -42.14 in WAD)
    // Below this, it returns 0
    if (x_ > 42_139_678_854_452_767_551) return 0;

    // expWad expects a signed int256 for negative exponents
    // We need e^(-x), so we negate x
    // Safe to cast since we've bounded x above
    return FixedPointMathLib.expWad(-int256(x_));
  }
}
