// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";

contract MockDripModelFlexible is IDripModel {
  uint256 public nextDripFactor;

  function setNextDripFactor(uint256 dripFactor_) external {
    nextDripFactor = dripFactor_;
  }

  function dripFactor(uint256 lastDripTime_, uint256 /* initialAmount_ */ ) external view override returns (uint256) {
    if (block.timestamp <= lastDripTime_) return 0;
    return nextDripFactor;
  }
}
