// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ReceiptToken} from "./ReceiptToken.sol";

contract StkToken is ReceiptToken {
  constructor() ReceiptToken() {}

  function transfer(address to_, uint256 amount_) public override returns (bool) {
    rewardsModule.updateUserRewardsForStkTokenTransfer(msg.sender, to_);
    return super.transfer(to_, amount_);
  }

  function transferFrom(address from_, address to_, uint256 amount_) public override returns (bool) {
    rewardsModule.updateUserRewardsForStkTokenTransfer(from_, to_);
    return super.transferFrom(from_, to_, amount_);
  }
}
