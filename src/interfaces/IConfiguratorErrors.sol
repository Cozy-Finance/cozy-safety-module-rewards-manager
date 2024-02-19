// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IConfiguratorErrors {
  /// @notice Thrown when an config update does not meet all requirements.
  error InvalidConfiguration();
}
