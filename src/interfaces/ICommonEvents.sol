// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ICommonEvents {
  /// @notice Emitted when the EIP-712 version is updated.
  event EIP712DomainVersionUpdated(uint64 newVersion_);

  /// @notice Emitted when the EIP-712 domain name is updated.
  event EIP712DomainNameUpdated(string newName_);

  /// @notice Emitted when the EIP-712 nonce is updated.
  event EIP712DomainNonceUpdated(uint256 newNonce_);
}
