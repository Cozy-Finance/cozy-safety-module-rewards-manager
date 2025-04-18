// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-libs/lib/Governable.sol";

contract MockManager is Governable {
  uint256 public allowedReservePools;
  uint256 public allowedRewardPools;

  function initGovernable(address owner_, address pauser_) external {
    __initGovernable(owner_, pauser_);
  }

  function setOwner(address owner_) external {
    owner = owner_;
  }

  function setAllowedReservePools(uint256 allowedReservePools_) external {
    allowedReservePools = allowedReservePools_;
  }

  function setAllowedRewardPools(uint256 allowedRewardPools_) external {
    allowedRewardPools = allowedRewardPools_;
  }
}
