// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IRewardsModule} from "./IRewardsModule.sol";
import {IReceiptToken} from "./IReceiptToken.sol";

interface IReceiptTokenFactory {
  enum PoolType {
    RESERVE,
    STAKE,
    REWARD
  }

  /// @dev Emitted when a new ReceiptToken is deployed.
  event ReceiptTokenDeployed(
    IReceiptToken receiptToken,
    IRewardsModule indexed safetyModule,
    uint16 indexed reservePoolId,
    PoolType indexed poolType,
    uint8 decimals_
  );

  /// @notice Creates a new ReceiptToken contract with the given number of `decimals_`. The ReceiptToken's reward module
  /// is identified by the caller address. The pool id of the ReceiptToken in the reward module and its `PoolType` is
  /// used to generate a unique salt for deploy.
  function deployReceiptToken(uint16 poolId_, PoolType poolType_, uint8 decimals_)
    external
    returns (IReceiptToken receiptToken_);

  /// @notice Given a `rewardsModule_`, its `poolId_`, and `poolType_`, compute and return the address of its
  /// ReceiptToken.
  function computeAddress(IRewardsModule rewardsModule_, uint16 poolId_, PoolType poolType_)
    external
    view
    returns (address);
}
