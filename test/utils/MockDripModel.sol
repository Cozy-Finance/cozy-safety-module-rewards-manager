// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";

contract MockDripModel is IDripModel {
  uint256 public dripFactorConstant;
  bool public isValidDripModel = true;

  constructor(uint256 dripFactorConstant_) {
    dripFactorConstant = dripFactorConstant_;
  }

  function setIsValidDripModel(bool isValidDripModel_) external {
    isValidDripModel = isValidDripModel_;
  }

  function dripFactor(uint256 lastDripTime_, uint256 /* initialAmount_ */ ) external view override returns (uint256) {
    if (!isValidDripModel) revert("Invalid drip model");
    if (block.timestamp - lastDripTime_ == 0) return 0;
    return dripFactorConstant;
  }
}
