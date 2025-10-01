// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-libs/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {RewardsManagerBaseStorage} from "./RewardsManagerBaseStorage.sol";
import {ClaimRewardsArgs, ClaimableRewardsData, UserRewardsData, DepositorRewardsData} from "./structs/Rewards.sol";
import {StakePool, RewardPool} from "./structs/Pools.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ICommonEvents} from "../interfaces/ICommonEvents.sol";
import {Governable} from "cozy-safety-module-libs/lib/Governable.sol";

abstract contract RewardsManagerCommon is RewardsManagerBaseStorage, ICommonErrors, ICommonEvents, Governable {
  /// @dev Thrown when a signature's deadline has passed.
  error SignatureExpired();

  /// @dev Thrown when a signature is invalid.
  error InvalidSignature();

  /// @notice Builds the EIP-712 domain separator.
  function _buildDomainSeparator() internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"), //EIP712 Domain typehash
        keccak256(bytes(eip712DomainName)), // name
        keccak256(bytes(Strings.toString(eip712DomainVersion))), // version
        block.chainid, // chainId
        address(this) // verifyingContract
      )
    );
  }

  /// @notice Set a new version; invalidates all outstanding signatures immediately.
  function incrementEIP712Version() external onlyOwner {
    eip712DomainVersion++;
    emit EIP712DomainVersionUpdated(eip712DomainVersion);
  }

  /// @notice Set a new name for the EIP-712 domain; invalidates all outstanding signatures immediately.
  /// @param name_ The new name.
  function setEIP712DomainName(string calldata name_) external onlyOwner {
    eip712DomainName = name_;
    emit EIP712DomainNameUpdated(eip712DomainName);
  }

  /// @dev Defined in RewardsDistributor.
  function _claimRewards(ClaimRewardsArgs memory args_) internal virtual;

  /// @dev Defined in RewardsDistributor.
  function dripRewards() public virtual;

  /// @notice The pool amount for the purposes of performing conversions. We set a floor once reward
  /// deposit receipt tokens have been initialized to avoid divide-by-zero errors that would occur when the supply
  /// of reward deposit receipt tokens > 0, but the `poolAmount` = 0, which can occur due to drip.
  /// @dev Defined in RewardsManagerInspector.
  function _poolAmountWithFloor(uint256 poolAmount_) internal pure virtual returns (uint256);

  /// @notice Helper to assert that the rewards manager has a balance of tokens that matches the required amount for a
  /// deposit/stake.
  /// @dev Defined in Depositor.
  function _assertValidDepositBalance(IERC20 token_, uint256 tokenPoolBalance_, uint256 depositAmount_)
    internal
    view
    virtual;

  /// @notice Returns the next amount of rewards/fees to be dripped given a base amount, drip model and last drip time.
  /// @dev Defined in RewardsDistributor.
  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    virtual
    returns (uint256);

  /// @dev Defined in RewardsDistributor.
  function _updateUserRewards(
    uint256 userStkReceiptTokenBalance_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_,
    UserRewardsData[] storage userRewards_
  ) internal virtual;

  /// @dev Defined in RewardsDistributor.
  function _dripRewardPool(RewardPool storage rewardPool_) internal virtual;

  /// @dev Defined in RewardsDistributor.
  function _dripAndApplyPendingDrippedRewards(
    StakePool storage stakePool_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_
  ) internal virtual;

  /// @dev Defined in RewardsDistributor.
  function _dripAndResetCumulativeRewardsValues(StakePool[] storage stakePools_, RewardPool[] storage rewardPools_)
    internal
    virtual;

  /// @dev Defined in Withdrawer.
  function _previewCurrentWithdrawableRewards(
    RewardPool storage rewardPool_,
    DepositorRewardsData storage depositorRewardsData_
  ) internal view virtual returns (uint256);
}
