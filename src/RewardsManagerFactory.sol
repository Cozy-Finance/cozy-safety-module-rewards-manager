// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {IManager} from "./interfaces/IManager.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {IRewardsManagerFactory} from "./interfaces/IRewardsManagerFactory.sol";
import {RewardPoolConfig} from "./lib/structs/Rewards.sol";

/**
 * @notice Deploys new Rewards Managers.
 */
contract RewardsManagerFactory is IRewardsManagerFactory {
  using Clones for address;

  /// @notice Address of the Cozy protocol manager.
  IManager public immutable cozyManager;

  /// @notice Address of the Rewards Manager logic contract used to deploy new Rewards Managers.
  IRewardsManager public immutable rewardsManagerLogic;

  /// @dev Thrown when the caller is not authorized to perform the action.
  error Unauthorized();

  /// @dev Thrown if an address parameter is invalid.
  error InvalidAddress();

  /// @param manager_ Cozy protocol Manager.
  /// @param rewardsManagerLogic_ Logic contract for deploying new Rewards Managers.
  constructor(IManager manager_, IRewardsManager rewardsManagerLogic_) {
    _assertAddressNotZero(address(manager_));
    _assertAddressNotZero(address(rewardsManagerLogic_));
    cozyManager = manager_;
    rewardsManagerLogic = rewardsManagerLogic_;
  }

  /// @notice Creates a new Rewards Manager contract with the specified configuration.
  /// @param owner_ The owner of the rewards manager.
  /// @param pauser_ The pauser of the rewards manager.
  /// @param baseSalt_ Used to compute the resulting address of the rewards manager.
  function deployRewardsManager(
    address owner_,
    address pauser_,
    address safetyModuleAddress_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_,
    bytes32 baseSalt_
  ) public returns (IRewardsManager rewardsManager_) {
    // It'd be harmless to let anyone deploy rewards managers, but to make it more clear where the proper entry
    // point for rewards manager creation is, we restrict this to being called by the Cozy manager.
    if (msg.sender != address(cozyManager)) revert Unauthorized();

    rewardsManager_ = IRewardsManager(address(rewardsManagerLogic).cloneDeterministic(salt(baseSalt_)));
    rewardsManager_.initialize(owner_, pauser_, safetyModuleAddress_, rewardPoolConfigs_, rewardsWeights_);
    emit RewardsManagerDeployed(rewardsManager_);
  }

  /// @notice Given the `baseSalt_` compute and return the address that Rewards Manager will be deployed to.
  /// @dev Rewards Manager addresses are uniquely determined by their salt because the deployer is always the factory,
  /// and the use of minimal proxies means they all have identical bytecode and therefore an identical bytecode hash.
  /// @dev The `baseSalt_` is the user-provided salt, not the final salt after hashing with the chain ID.
  function computeAddress(bytes32 baseSalt_) external view returns (address) {
    return Clones.predictDeterministicAddress(address(rewardsManagerLogic), salt(baseSalt_), address(this));
  }

  /// @notice Given the `baseSalt_`, return the salt that will be used for deployment.
  function salt(bytes32 baseSalt_) public view returns (bytes32) {
    // We take the user-provided salt and concatenate it with the chain ID before hashing. This is
    // required because CREATE2 with a user provided salt or CREATE both make it easy for an
    // attacker to create a malicious Rewards Manager on one chain and pass it off as a reputable Rewards Manager from
    // another chain since the two have the same address.
    return keccak256(abi.encode(baseSalt_, block.chainid));
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
