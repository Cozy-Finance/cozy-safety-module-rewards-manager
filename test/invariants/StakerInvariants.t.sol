// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, StakePool} from "../../src/lib/structs/Pools.sol";
import {RewardsManagerState} from "../../src/lib/RewardsManagerStates.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleStakePoolAndSingleRewardPool,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract StakerInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;
}

contract StakerInvariantsSingleReservePool is StakerInvariants, InvariantTestWithSingleStakePoolAndSingleRewardPool {}

contract StakerInvariantsMultipleReservePools is
  StakerInvariants,
  InvariantTestWithMultipleStakePoolsAndMultipleRewardPools
{}
