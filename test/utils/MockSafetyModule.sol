// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";

contract MockSafetyModule {
  SafetyModuleState public safetyModuleState;
  uint16 public numReservePools;
  mapping(uint256 => IReceiptToken) public reservePoolToReceiptToken;

  constructor(SafetyModuleState _safetyModuleState) {
    safetyModuleState = _safetyModuleState;
  }

  function setSafetyModuleState(SafetyModuleState _safetyModuleState) public {
    safetyModuleState = _safetyModuleState;
  }

  function setNumReservePools(uint16 _numReservePools) public {
    numReservePools = _numReservePools;
  }

  function setReservePoolReceiptToken(uint256 _reservePoolId, IReceiptToken _receiptToken) public {
    reservePoolToReceiptToken[_reservePoolId] = _receiptToken;
  }

  function reservePools(uint256 _id)
    external
    view
    returns (
      uint256 amount,
      uint256 pendingWithdrawalsAmount,
      uint256 feeAmount,
      uint256 maxSlashPercentage,
      IERC20 asset,
      IReceiptToken receiptToken,
      uint128 lastFeesDripTime
    )
  {
    return (0, 0, 0, 0, IERC20(address(0)), reservePoolToReceiptToken[_id], 0);
  }
}
