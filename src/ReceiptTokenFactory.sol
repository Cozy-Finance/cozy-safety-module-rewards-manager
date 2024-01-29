// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {IReceiptToken} from "./interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "./interfaces/IReceiptTokenFactory.sol";
import {IRewardsModule} from "./interfaces/IRewardsModule.sol";

// TODO: Move this to shared repo?
/**
 * @notice Deploys new deposit and stake receipt tokens, which implement the IReceiptToken interface.
 * @dev ReceiptTokens are compliant with ERC-20 and ERC-2612.
 */
contract ReceiptTokenFactory is IReceiptTokenFactory {
  using Clones for address;

  /// @notice Address of the DepositToken logic contract used to deploy new DepositToken.
  IReceiptToken public immutable depositTokenLogic;

  /// @notice Address of the stkToken logic contract used to deploy new stkToken.
  IReceiptToken public immutable stkTokenLogic;

  /// @dev Thrown if an address parameter is invalid.
  error InvalidAddress();

  /// @param depositTokenLogic_ Logic contract for deploying new DepositTokens.
  /// @param stkTokenLogic_ Logic contract for deploying new stkTokens.
  /// @dev stkTokens are only different from DepositTokens in that they have special logic when they are transferred.
  constructor(IReceiptToken depositTokenLogic_, IReceiptToken stkTokenLogic_) {
    _assertAddressNotZero(address(depositTokenLogic_));
    _assertAddressNotZero(address(stkTokenLogic_));
    depositTokenLogic = depositTokenLogic_;
    stkTokenLogic = stkTokenLogic_;
  }

  /// @notice Creates a new ReceiptToken contract with the given number of `decimals_`. The ReceiptToken's rewards
  /// module is identified by the caller address. The pool id of the ReceiptToken in the rewards module and its
  /// `PoolType` is used to generate a unique salt for deploy.
  function deployReceiptToken(uint16 poolId_, PoolType poolType_, uint8 decimals_)
    external
    returns (IReceiptToken receiptToken_)
  {
    // The caller is the rewards module.
    IRewardsModule rewardsModule_ = IRewardsModule(msg.sender);

    // TODO: Make this rewards module specific.
    address tokenLogicContract_ = poolType_ == PoolType.STAKE ? address(stkTokenLogic) : address(depositTokenLogic);
    string memory name_ = poolType_ == PoolType.STAKE
      ? "Cozy Stake Token"
      : (poolType_ == PoolType.RESERVE ? "Cozy Reserve Deposit Token" : "Cozy Reward Deposit Token");
    string memory symbol_ = poolType_ == PoolType.STAKE ? "cozyStk" : "cozyDep";

    // We generate the salt from the rewards module-pool id-pool type, which must be unique, and concatenate it with the
    // chain ID to prevent the same ReceiptToken address existing on multiple chains for different rewards modules or
    // pools.
    receiptToken_ =
      IReceiptToken(address(tokenLogicContract_).cloneDeterministic(salt(rewardsModule_, poolId_, poolType_)));
    receiptToken_.initialize(rewardsModule_, name_, symbol_, decimals_);
    emit ReceiptTokenDeployed(receiptToken_, rewardsModule_, poolId_, poolType_, decimals_);
  }

  /// @notice Given a `rewardsModule_`, its `poolId_`, and `poolType_`, compute and return the address of its
  /// ReceiptToken.
  function computeAddress(IRewardsModule rewardsModule_, uint16 poolId_, PoolType poolType_)
    external
    view
    returns (address)
  {
    address tokenLogicContract_ = poolType_ == PoolType.STAKE ? address(stkTokenLogic) : address(depositTokenLogic);
    return
      Clones.predictDeterministicAddress(tokenLogicContract_, salt(rewardsModule_, poolId_, poolType_), address(this));
  }

  /// @notice Given a `rewardsModule_`, its `poolId_`, and `poolType_`, return the salt used to compute the ReceiptToken
  /// address.
  function salt(IRewardsModule rewardsModule_, uint16 poolId_, PoolType poolType_) public view returns (bytes32) {
    return keccak256(abi.encode(rewardsModule_, poolId_, poolType_, block.chainid));
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
