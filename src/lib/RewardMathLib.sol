// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

// PRBMath typed fixed-point wrappers (v4+)
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/src/SD59x18.sol";

/// @notice Reward math helpers using PRBMath (WAD: 1e18).
library RewardMathLib {
  uint256 internal constant WAD = 1e18;

  /// @notice Computes -ln(x) for 0 < x <= 1 (WAD-scaled).
  /// @dev Returns WAD-scaled result in uint256.
  function negLn(uint256 x_) internal pure returns (uint256) {
    require(x_ > 0 && x_ <= WAD, "RewardMathLib: x out of (0,1]");

    // ln(x) for x in (0,1] is <= 0. We compute it in signed space,
    // then negate and cast back to uint256.
    if (x_ == WAD) return 0; // -ln(1) = 0

    // Convert raw WAD to PRB signed 59.18 and take ln.
    int256 lnRaw = sd(int256(x_)).ln().unwrap();
    return uint256(-lnRaw);
  }

  /// @notice Computes e^(-x) for x >= 0 (WAD-scaled).
  /// @dev Returns WAD-scaled result in uint256.
  function expNeg(uint256 x_) internal pure returns (uint256) {
    if (x_ == 0) return WAD;

    // For x > ~41.4465e18, e^(-x) < 1e-18 so it rounds to 0 in WAD.
    // Using 42e18 gives a cheap and safe early-out without calling exp.
    if (x_ >= 42e18) return 0;

    // Compute exp(-x) in signed space, unwrap (still WAD), cast to uint.
    SD59x18 y = sd(-int256(x_));
    return uint256(y.exp().unwrap());
  }
}
