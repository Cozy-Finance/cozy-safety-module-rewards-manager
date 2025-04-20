// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {ReceiptToken} from "cozy-safety-module-libs/ReceiptToken.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";

contract StkReceiptToken is ReceiptToken {
  constructor() ReceiptToken() {}

  /// @dev Updates the user's rewards before transferring the stkReceiptTokens by calling into the rewards manager.
  function transfer(address to_, uint256 amount_) public override returns (bool) {
    IRewardsManager(module).updateUserRewardsForStkReceiptTokenTransfer(msg.sender, to_);
    return super.transfer(to_, amount_);
  }

  /// @dev Updates the user's rewards before transferring the stkReceiptTokens by calling into the rewards manager.
  function transferFrom(address from_, address to_, uint256 amount_) public override returns (bool) {
    IRewardsManager(module).updateUserRewardsForStkReceiptTokenTransfer(from_, to_);
    return super.transferFrom(from_, to_, amount_);
  }
}
