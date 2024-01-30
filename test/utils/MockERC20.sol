// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "cozy-safety-module-shared/lib/ERC20.sol";

/// @author Solmate
/// https://github.com/transmissions11/solmate/blob/d155ee8d58f96426f57c015b34dee8a410c1eacc/src/test/utils/mocks/MockERC20.sol
/// @dev Note that this version of MockERC20 uses our own version of ERC20 instead of solmate's.
contract MockERC20 is ERC20 {
  constructor(string memory _name, string memory _symbol, uint8 _decimals) {
    __initERC20(_name, _symbol, _decimals);
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

  /// @notice Sets the allowance such that the `_spender` can spend `_amount` of `_owner`s tokens.
  function _setAllowance(address _owner, address _spender, uint256 _amount) internal {
    allowance[_owner][_spender] = _amount;
  }
}
