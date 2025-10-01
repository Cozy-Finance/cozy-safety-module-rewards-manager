// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract MockERC1271Signer is IERC1271 {
  bytes4 internal constant _MAGICVALUE = 0x1626ba7e;
  bytes4 internal constant _FAILVALUE = 0xffffffff;

  address public labeledOwner;

  /// @dev digest => keccak256(signature) that this mock will accept
  mapping(bytes32 => bytes32) public expectedSigHash;

  constructor(address owner_) {
    labeledOwner = owner_;
  }

  function signMessage(bytes32 digest_) external returns (bytes memory signature) {
    // Any deterministic scheme works as long as isValidSignature agrees.
    signature = abi.encodePacked(digest_, labeledOwner);
    expectedSigHash[digest_] = keccak256(signature);
  }

  function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
    return expectedSigHash[hash] == keccak256(signature) ? _MAGICVALUE : _FAILVALUE;
  }
}
