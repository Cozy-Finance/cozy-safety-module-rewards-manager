// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {RewardPool, ReservePool} from "../../src/lib/structs/Pools.sol";
import {
  UserRewardsData,
  PreviewClaimableRewardsData,
  PreviewClaimableRewards,
  ClaimableRewardsData
} from "../../src/lib/structs/Rewards.sol";
import {Test} from "forge-std/Test.sol";

abstract contract TestAssertions is Test {
  function assertEq(uint256[][] memory actual_, uint256[][] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(ReservePool[] memory actual_, ReservePool[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(ReservePool memory actual_, ReservePool memory expected_) internal {
    assertEq(
      address(actual_.safetyModuleReceiptToken),
      address(expected_.safetyModuleReceiptToken),
      "ReservePool.safetyModuleReceiptToken"
    );
    assertEq(address(actual_.stkReceiptToken), address(expected_.stkReceiptToken), "ReservePool.stkReceiptToken");
    assertEq(actual_.amount, expected_.amount, "ReservePool.amount");
    assertEq(actual_.rewardsWeight, expected_.rewardsWeight, "ReservePool.rewardsWeight");
  }

  function assertEq(RewardPool[] memory actual_, RewardPool[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(RewardPool memory actual_, RewardPool memory expected_) internal {
    assertEq(address(actual_.asset), address(expected_.asset), "RewardPool.asset");
    assertEq(address(actual_.dripModel), address(expected_.dripModel), "RewardPool.dripModel");
    assertEq(address(actual_.depositToken), address(expected_.depositToken), "RewardPool.depositToken");
    assertEq(actual_.undrippedRewards, expected_.undrippedRewards, "RewardPool.undrippedRewards");
    assertEq(
      actual_.cumulativeDrippedRewards, expected_.cumulativeDrippedRewards, "RewardPool.cumulativeDrippedRewards"
    );
    assertEq(actual_.lastDripTime, expected_.lastDripTime, "RewardPool.lastDripTime");
  }

  function assertEq(UserRewardsData[] memory actual_, UserRewardsData[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(UserRewardsData memory actual_, UserRewardsData memory expected_) internal {
    assertEq(actual_.accruedRewards, expected_.accruedRewards, "RewardPool.accruedRewards");
    assertEq(actual_.indexSnapshot, expected_.indexSnapshot, "RewardPool.indexSnapshot");
  }

  function assertEq(SafetyModuleState actual_, SafetyModuleState expected_) internal {
    assertEq(uint256(actual_), uint256(expected_), "SafetyModuleState");
  }

  function assertEq(ClaimableRewardsData[][] memory actual_, ClaimableRewardsData[][] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(ClaimableRewardsData[] memory actual_, ClaimableRewardsData[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(ClaimableRewardsData memory actual_, ClaimableRewardsData memory expected_) internal {
    assertEq(
      actual_.cumulativeClaimedRewards,
      expected_.cumulativeClaimedRewards,
      "ClaimableRewardsData.cumulativeClaimedRewards"
    );
    assertEq(actual_.indexSnapshot, expected_.indexSnapshot, "ClaimableRewardsData.indexSnapshot");
  }

  function assertEq(PreviewClaimableRewards[] memory actual_, PreviewClaimableRewards[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(PreviewClaimableRewards memory actual_, PreviewClaimableRewards memory expected_) internal {
    assertEq(actual_.reservePoolId, expected_.reservePoolId, "PreviewClaimableRewards.reservePoolId");
    for (uint256 i = 0; i < actual_.claimableRewardsData.length; i++) {
      assertEq(actual_.claimableRewardsData[i], expected_.claimableRewardsData[i]);
    }
  }

  function assertEq(PreviewClaimableRewardsData[] memory actual_, PreviewClaimableRewardsData[] memory expected_)
    internal
  {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(PreviewClaimableRewardsData memory actual_, PreviewClaimableRewardsData memory expected_) internal {
    assertEq(address(actual_.asset), address(expected_.asset), "PreviewClaimableRewardsData.asset");
    assertEq(actual_.amount, expected_.amount, "PreviewClaimableRewardsData.amount");
    assertEq(actual_.rewardPoolId, expected_.rewardPoolId, "PreviewClaimableRewardsData.rewardPoolId");
  }
}
