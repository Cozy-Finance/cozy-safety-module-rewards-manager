// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

library RewardsMathLib {
  using FixedPointMathLib for int256;

  uint256 internal constant WAD = 1e18;

  /// @notice Computes -ln(x) for 0 < x <= 1 (WAD-scaled).
  /// @dev Returns WAD-scaled result as a uint256.
  function negLn(uint256 x_) internal pure returns (uint256) {
    require(x_ > 0 && x_ <= WAD, "RewardsMathLib: x out of (0,1]");
    if (x_ == WAD) return 0; // -ln(1) = 0

    // ln(x) for x in (0,1] is <= 0. We take the ln in signed space, negate and cast back to uint256.
    return uint256(-int256(x_).lnWad());
  }

  /// @notice Computes e^(-x) for x >= 0 (WAD-scaled).
  /// @dev Returns WAD-scaled result in uint256.
  function expNeg(uint256 x_) internal pure returns (uint256) {
    if (x_ == 0) return WAD;

    // For x > ~41.4465e18, e^(-x) < 1e-18 so it rounds to 0 in WAD.
    // Using 42e18 gives a cheap and safe early-out without calling exp.
    if (x_ >= 42e18) return 0;

    // Compute exp(-x) in signed space and cast back to unit256.
    return uint256((-int256(x_)).expWad());
  }
}
