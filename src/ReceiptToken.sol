// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IRewardsModule} from "./interfaces/IRewardsModule.sol";
import {ERC20} from "./lib/ERC20.sol";

contract ReceiptToken is ERC20 {
  /// @notice Address of this token's reward module.
  IRewardsModule public rewardsModule;

  /// @dev Thrown if the minimal proxy contract is already initialized.
  error Initialized();

  /// @dev Thrown when an address is invalid.
  error InvalidAddress();

  /// @dev Thrown when the caller is not authorized to perform the action.
  error Unauthorized();

  /// @notice Replaces the constructor for minimal proxies.
  /// @param rewardsModule_ The rewards module for this ReceiptToken.
  /// @param name_ The name of the token.
  /// @param symbol_ The symbol of the token.
  /// @param decimals_ The decimal places of the token.
  function initialize(IRewardsModule rewardsModule_, string memory name_, string memory symbol_, uint8 decimals_)
    external
  {
    __initERC20(name_, symbol_, decimals_);
    rewardsModule = rewardsModule_;
  }

  /// @notice Mints `amount_` of tokens to `to_`.
  function mint(address to_, uint256 amount_) external onlyRewardsModule {
    _mint(to_, amount_);
  }

  function burn(address caller_, address owner_, uint256 amount_) external onlyRewardsModule {
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

  // -------- Modifiers --------

  /// @dev Checks that msg.sender is the set address.
  modifier onlyRewardsModule() {
    if (msg.sender != address(rewardsModule)) revert Unauthorized();
    _;
  }
}
