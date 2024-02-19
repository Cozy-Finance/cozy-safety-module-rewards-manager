// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "./MockERC20.sol";
import "../../src/interfaces/IRewardsManager.sol";

contract MockStkReceiptToken is MockERC20 {
  address public module;

  constructor(address _module, string memory _name, string memory _symbol, uint8 _decimals)
    MockERC20(_name, _symbol, _decimals)
  {
    module = _module;
  }

  function transfer(address to_, uint256 amount_) public override returns (bool) {
    IRewardsManager(module).updateUserRewardsForStkReceiptTokenTransfer(msg.sender, to_);
    return super.transfer(to_, amount_);
  }

  function transferFrom(address from_, address to_, uint256 amount_) public override returns (bool) {
    IRewardsManager(module).updateUserRewardsForStkReceiptTokenTransfer(from_, to_);
    return super.transferFrom(from_, to_, amount_);
  }
}
