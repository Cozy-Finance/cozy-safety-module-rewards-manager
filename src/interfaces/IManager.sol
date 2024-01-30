// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {ISafetyModule} from "./ISafetyModule.sol";

interface IManager {
  function isSafetyModule(ISafetyModule safetyModule_) external view returns (bool);

  /// @notice Number of reward pools allowed per safety module.
  function allowedRewardPools() external view returns (uint256);
}
