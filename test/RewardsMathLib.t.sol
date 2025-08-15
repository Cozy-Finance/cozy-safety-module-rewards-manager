// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {RewardsMathLib} from "../src/lib/RewardsMathLib.sol";
import {TestBase} from "./utils/TestBase.sol";

contract RewardsMathLibTest is TestBase {
  uint256 constant WAD = 1e18;
  uint256 constant HALF_WAD = 0.5e18;

  function test_negLn_knownValues() public {
    // Test negLn(1) = 0
    assertEq(RewardsMathLib.negLn(WAD), 0, "negLn(1) should be 0");

    // Test negLn(0.5) ~= ln(2) ~= 0.693147...
    assertApproxEqRel(RewardsMathLib.negLn(HALF_WAD), 693_147_180_559_945_309, 1e15, "negLn(0.5) ~= ln(2)");

    // Test negLn(0.1) ~= ln(10) ~= 2.302585...
    assertApproxEqRel(RewardsMathLib.negLn(0.1e18), 2_302_585_092_994_045_674, 1e15, "negLn(0.1) ~= ln(10)");

    // Test negLn(0.9) ~= -ln(0.9) ~= 0.105360...
    assertApproxEqRel(RewardsMathLib.negLn(0.9e18), 105_360_515_657_826_292, 1e15, "negLn(0.9) ~= -ln(0.9)");
  }

  function test_negLn_edgeCases() public {
    // Test boundary: negLn(0) should revert
    vm.expectRevert("RewardsMathLib: x out of (0,1]");
    RewardsMathLib.negLn(0);

    // Test boundary: negLn(x > 1) should revert
    vm.expectRevert("RewardsMathLib: x out of (0,1]");
    RewardsMathLib.negLn(WAD + 1);

    // Test very small value
    assertGt(RewardsMathLib.negLn(1), 41e18, "negLn(1e-18) should be very large");
  }

  function testFuzz_negLn_validRange(uint256 x) public {
    // Test random values in valid range (0, 1]
    x = bound(x, 1, WAD);

    uint256 result_ = RewardsMathLib.negLn(x);

    // For x in (0,1], negLn(x) should be >= 0
    assertGe(result_, 0, "negLn result should be non-negative");

    // The closer x is to 0, the larger negLn(x) should be
    // For x very close to 1, negLn(x) approaches 0 and may round to 0
    if (x < WAD - 1e12) {
      // Only check if x is meaningfully less than 1
      assertGt(result_, 0, "negLn(x) should be positive for x < 1");
    }
  }

  function test_expNeg_knownValues() public {
    // Test expNeg(0) = 1
    assertEq(RewardsMathLib.expNeg(0), WAD, "expNeg(0) should be 1");

    // Test expNeg(1) ~= 1/e ~= 0.367879...
    assertApproxEqRel(RewardsMathLib.expNeg(WAD), 367_879_441_171_442_321, 1e15, "expNeg(1) ~= 1/e");

    // Test expNeg(2) ~= 1/e^2 ~= 0.135335...
    assertApproxEqRel(RewardsMathLib.expNeg(2e18), 135_335_283_236_612_691, 1e15, "expNeg(2) ~= 1/e^2");

    // Test expNeg(0.5) ~= 1/sqrt(e) ~= 0.606530...
    assertApproxEqRel(RewardsMathLib.expNeg(HALF_WAD), 606_530_659_712_633_424, 1e15, "expNeg(0.5) ~= 1/sqrt(e)");
  }

  function test_expNeg_edgeCases() public {
    // Test large value (should return 0)
    assertEq(RewardsMathLib.expNeg(42e18), 0, "expNeg(42) should be 0");
    assertEq(RewardsMathLib.expNeg(100e18), 0, "expNeg(100) should be 0");

    // Test boundary around 42
    assertGt(RewardsMathLib.expNeg(41e18), 0, "expNeg(41) should be > 0");
    assertEq(RewardsMathLib.expNeg(42e18), 0, "expNeg(42) should be 0");
  }

  function testFuzz_expNeg_validRange(uint256 x_) public {
    // Test random values
    x_ = bound(x_, 0, 100e18);

    uint256 result_ = RewardsMathLib.expNeg(x_);

    // expNeg(x) should be in [0, 1]
    assertLe(result_, WAD, "expNeg(x) should be <= 1");

    // For large x, result should be 0
    if (x_ >= 42e18) assertEq(result_, 0, "expNeg(x) should be 0 for x >= 42");
  }

  function test_roundTrip_fixedValues() public {
    // Test that expNeg(negLn(x)) ~= x for various values
    uint256[] memory testValues_ = new uint256[](5);
    testValues_[0] = 0.1e18;
    testValues_[1] = 0.25e18;
    testValues_[2] = 0.5e18;
    testValues_[3] = 0.75e18;
    testValues_[4] = 0.99e18;

    for (uint256 i = 0; i < testValues_.length; i++) {
      uint256 x_ = testValues_[i];
      uint256 expNegResult_ = RewardsMathLib.expNeg(RewardsMathLib.negLn(x_));
      assertApproxEqRel(expNegResult_, x_, 1e15, "expNeg(negLn(x)) should equal x");
    }
  }

  function testFuzz_roundTrip(uint256 x_) public {
    // Test round trip for random values in (0, 1]
    x_ = bound(x_, 1e6, WAD); // Using 1e6 as minimum to avoid precision issues

    uint256 negLnX_ = RewardsMathLib.negLn(x_);
    uint256 expNegResult_ = RewardsMathLib.expNeg(negLnX_);

    assertApproxEqRel(
      expNegResult_,
      x_,
      1e14, // about 0.01% relative error
      "Round trip should preserve value"
    );
  }

  function test_negLn_monotonicity() public {
    // negLn should be strictly decreasing for x in (0,1]
    uint256 x1_ = 0.1e18;
    uint256 x2_ = 0.5e18;
    uint256 x3_ = 0.9e18;

    uint256 negLnX1_ = RewardsMathLib.negLn(x1_);
    uint256 negLnX2_ = RewardsMathLib.negLn(x2_);
    uint256 negLnX3_ = RewardsMathLib.negLn(x3_);

    assertGt(negLnX1_, negLnX2_, "negLn(0.1) > negLn(0.5)");
    assertGt(negLnX2_, negLnX3_, "negLn(0.5) > negLn(0.9)");
  }

  function test_expNeg_monotonicity() public {
    // expNeg should be strictly decreasing for x >= 0
    uint256 x1_ = 0;
    uint256 x2_ = 1e18;
    uint256 x3_ = 2e18;

    uint256 expNegX1_ = RewardsMathLib.expNeg(x1_);
    uint256 expNegX2_ = RewardsMathLib.expNeg(x2_);
    uint256 expNegX3_ = RewardsMathLib.expNeg(x3_);

    assertGt(expNegX1_, expNegX2_, "expNeg(0) > expNeg(1)");
    assertGt(expNegX2_, expNegX3_, "expNeg(1) > expNeg(2)");
  }

  function test_compoundRetention() public {
    // Testing that multiple drips compound correctly
    // If we have retention factors r1, r2, r3, the compound retention is r1 * r2 * r3
    uint256 r1_ = 0.9e18; // 90% retention
    uint256 r2_ = 0.8e18; // 80% retention
    uint256 r3_ = 0.7e18; // 70% retention

    // Calculate compound retention using our functions
    uint256 negLnR1_ = RewardsMathLib.negLn(r1_);
    uint256 negLnR2_ = RewardsMathLib.negLn(r2_);
    uint256 negLnR3_ = RewardsMathLib.negLn(r3_);

    // exp(-sum) should equal the product
    uint256 compoundRetention_ = RewardsMathLib.expNeg(negLnR1_ + negLnR2_ + negLnR3_);

    // Direct calculation: 0.9 * 0.8 * 0.7 = 0.504
    uint256 expectedRetention_ = (r1_ * r2_ * r3_) / WAD / WAD;

    assertApproxEqRel(
      compoundRetention_, expectedRetention_, 1e15, "Compound retention should match direct calculation"
    );
  }
}
