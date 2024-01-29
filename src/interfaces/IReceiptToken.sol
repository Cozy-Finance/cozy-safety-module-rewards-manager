// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {IRewardsModule} from "./IRewardsModule.sol";

interface IReceiptToken is IERC20 {
  /// @notice Replaces the constructor for minimal proxies.
  /// @param rewardsModule_ The rewards module for this ReceiptToken.
  /// @param name_ The name of the token.
  /// @param symbol_ The symbol of the token.
  /// @param decimals_ The decimal places of the token.
  function initialize(IRewardsModule rewardsModule_, string memory name_, string memory symbol_, uint8 decimals_)
    external;

  /// @notice Mints `amount_` of tokens to `to_`.
  function mint(address to_, uint256 amount_) external;

  /// @notice Burns `amount_` of tokens from `from`_.
  function burn(address caller_, address from_, uint256 amount_) external;

  /// @notice Address of this token's rewards module.
  function rewardsModule() external view returns (IRewardsModule);
}
