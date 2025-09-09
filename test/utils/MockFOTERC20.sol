// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "cozy-safety-module-libs/lib/ERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {ERC20} from "cozy-safety-module-libs/lib/ERC20.sol";

contract MockFOTERC20 is ERC20 {
  uint16 public feeBps; // e.g. 100 = 1%
  address public feeRecipient; // where fees are sent

  constructor(string memory _name, string memory _symbol, uint8 _decimals, uint16 _feeBps, address _feeRecipient) {
    __initERC20(_name, _symbol, _decimals);
    feeBps = _feeBps;
    feeRecipient = _feeRecipient == address(0) ? address(0xdead) : _feeRecipient;
  }

  function mint(address to, uint256 value) public virtual {
    _mint(to, value);
  }

  function burn(address from, uint256 value) public virtual {
    _burn(from, value);
  }

  function burn(address caller_, address owner_, uint256 amount_) external {
    if (caller_ != owner_) {
      uint256 allowed_ = allowance[owner_][caller_]; // Saves gas for limited approvals.
      if (allowed_ != type(uint256).max) _setAllowance(owner_, caller_, allowed_ - amount_);
    }
    _burn(owner_, amount_);
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    _transferWithFee(msg.sender, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
    uint256 allowed_ = allowance[from][msg.sender];
    if (allowed_ != type(uint256).max) {
      require(allowed_ >= amount, "insufficient allowance");
      _setAllowance(from, msg.sender, allowed_ - amount);
    }
    _transferWithFee(from, to, amount);
    return true;
  }

  function _transferWithFee(address from, address to, uint256 amount) internal {
    // Calculate fee and net received
    uint256 fee = (amount * feeBps) / MathConstants.ZOC; // floor
    uint256 received = amount - fee;

    // Move funds
    balanceOf[from] -= amount;
    balanceOf[to] += received;
    if (fee > 0) balanceOf[feeRecipient] += fee;

    // Emit transfers: one to fee recipient (if any), one to receiver
    if (fee > 0) emit Transfer(from, feeRecipient, fee);
    emit Transfer(from, to, received);
  }

  /// @notice Sets the allowance such that the `_spender` can spend `_amount` of `_owner`s tokens.
  function _setAllowance(address _owner, address _spender, uint256 _amount) internal {
    allowance[_owner][_spender] = _amount;
    emit Approval(_owner, _spender, _amount);
  }
}
