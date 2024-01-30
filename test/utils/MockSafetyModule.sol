// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";

contract MockSafetyModule {
  SafetyModuleState public safetyModuleState;
  uint16 public numReservePools;
  mapping(uint256 => IReceiptToken) public reservePoolToStkReceiptToken;

  constructor(SafetyModuleState _safetyModuleState) {
    safetyModuleState = _safetyModuleState;
  }

  function setSafetyModuleState(SafetyModuleState _safetyModuleState) public {
    safetyModuleState = _safetyModuleState;
  }

  function setNumReservePools(uint16 _numReservePools) public {
    numReservePools = _numReservePools;
  }

  function setReservePoolStkReceiptToken(uint256 _reservePoolId, IReceiptToken _stkReceiptToken) public {
    reservePoolToStkReceiptToken[_reservePoolId] = _stkReceiptToken;
  }

  function reservePools(uint256 _id)
    external
    view
    returns (
      uint256 stakeAmount,
      uint256 depositAmount,
      uint256 pendingUnstakesAmount,
      uint256 pendingWithdrawalsAmount,
      uint256 feeAmount,
      uint256 maxSlashPercentage,
      IERC20 asset,
      IReceiptToken stkToken,
      IReceiptToken depositToken,
      uint16 rewardsPoolsWeight,
      uint128 lastFeesDripTime
    )
  {
    return (0, 0, 0, 0, 0, 0, IERC20(address(0)), IReceiptToken(address(0)), reservePoolToStkReceiptToken[_id], 0, 0);
  }
}
