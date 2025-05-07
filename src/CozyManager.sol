// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-libs/lib/Governable.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {ICozyManager} from "./interfaces/ICozyManager.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {IRewardsManagerFactory} from "./interfaces/IRewardsManagerFactory.sol";
import {RewardPoolConfig, StakePoolConfig} from "./lib/structs/Configs.sol";

contract CozyManager is Governable, ICozyManager {
  struct FeeLookup {
    uint16 fee;
    bool exists;
  }

  /// @notice Cozy protocol RewardsManagerFactory.
  IRewardsManagerFactory public immutable rewardsManagerFactory;

  /// @notice The default claim fee used for RewardsManagers, represented as a ZOC (e.g. 500 = 5%).
  uint16 public claimFee;

  /// @notice The default deposit fee used for RewardsManagers, represented as a ZOC (e.g. 500 = 5%).
  uint16 public depositFee;

  /// @notice Override claim fees for specific RewardsManagers.
  mapping(IRewardsManager => FeeLookup) public overrideClaimFees;

  /// @notice Override deposit fees for specific RewardsManagers.
  mapping(IRewardsManager => FeeLookup) public overrideDepositFees;

  /// @param owner_ The Cozy protocol owner.
  /// @param pauser_ The Cozy protocol pauser.
  /// @param rewardsManagerFactory_ The Cozy protocol RewardsManagerFactory.
  /// @param claimFee_ The default claim fee used for RewardsManagers, represented as a ZOC (e.g. 500 = 5%).
  constructor(
    address owner_,
    address pauser_,
    IRewardsManagerFactory rewardsManagerFactory_,
    uint16 claimFee_,
    uint16 depositFee_
  ) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(address(rewardsManagerFactory_));
    __initGovernable(owner_, pauser_);

    rewardsManagerFactory = rewardsManagerFactory_;
    _updateClaimFee(claimFee_);
    _updateDepositFee(depositFee_);
  }

  // -------------------------------------------------
  // ------------------- Fee Management --------------
  // -------------------------------------------------

  /// @notice Update the default claim fee used for RewardsManagers.
  /// @param claimFee_ The new default claim fee.
  function updateClaimFee(uint16 claimFee_) external onlyOwner {
    _updateClaimFee(claimFee_);
  }

  /// @notice Update the default deposit fee used for RewardsManagers.
  /// @param depositFee_ The new default deposit fee.
  function updateDepositFee(uint16 depositFee_) external onlyOwner {
    _updateDepositFee(depositFee_);
  }

  /// @notice Update the claim fee for a specific RewardsManager.
  /// @param rewardsManager_ The RewardsManager to update the claim fee for.
  /// @param claimFee_ The new fee claim fee for the RewardsManager.
  function updateOverrideClaimFee(IRewardsManager rewardsManager_, uint16 claimFee_) external onlyOwner {
    if (claimFee_ > MathConstants.ZOC) revert InvalidClaimFee();
    overrideClaimFees[rewardsManager_] = FeeLookup({exists: true, fee: claimFee_});
    emit OverrideClaimFeeUpdated(rewardsManager_, claimFee_);
  }

  /// @notice Update the deposit fee for a specific RewardsManager.
  /// @param rewardsManager_ The RewardsManager to update the deposit fee for.
  /// @param depositFee_ The new fee deposit fee for the RewardsManager.
  function updateOverrideDepositFee(IRewardsManager rewardsManager_, uint16 depositFee_) external onlyOwner {
    if (depositFee_ > MathConstants.ZOC) revert InvalidDepositFee();
    overrideDepositFees[rewardsManager_] = FeeLookup({exists: true, fee: depositFee_});
    emit OverrideDepositFeeUpdated(rewardsManager_, depositFee_);
  }

  /// @notice Reset the override claim fee for the specified RewardsManager back to the default.
  /// @param rewardsManager_ The RewardsManager to update the claim fee for.
  function resetOverrideClaimFee(IRewardsManager rewardsManager_) external onlyOwner {
    delete overrideClaimFees[rewardsManager_];
    emit OverrideClaimFeeUpdated(rewardsManager_, claimFee);
  }

  /// @notice Reset the override deposit fee for the specified RewardsManager back to the default.
  /// @param rewardsManager_ The RewardsManager to update the deposit fee for.
  function resetOverrideDepositFee(IRewardsManager rewardsManager_) external onlyOwner {
    delete overrideDepositFees[rewardsManager_];
    emit OverrideDepositFeeUpdated(rewardsManager_, depositFee);
  }

  /// @notice For the specified RewardsManager, returns the claim fee.
  function getClaimFee(IRewardsManager rewardsManager_) public view returns (uint16) {
    FeeLookup memory overrideClaimFee_ = overrideClaimFees[rewardsManager_];
    if (overrideClaimFee_.exists) return overrideClaimFee_.fee;
    else return claimFee;
  }

  /// @notice For the specified RewardsManager, returns the deposit fee.
  function getDepositFee(IRewardsManager rewardsManager_) public view returns (uint16) {
    FeeLookup memory overrideDepositFee_ = overrideDepositFees[rewardsManager_];
    if (overrideDepositFee_.exists) return overrideDepositFee_.fee;
    else return depositFee;
  }

  /// @dev Executes the claim fee update.
  function _updateClaimFee(uint16 claimFee_) internal {
    if (claimFee_ > MathConstants.ZOC) revert InvalidClaimFee();
    claimFee = claimFee_;
    emit ClaimFeeUpdated(claimFee_);
  }

  /// @dev Executes the deposit fee update.
  function _updateDepositFee(uint16 depositFee_) internal {
    if (depositFee_ > MathConstants.ZOC) revert InvalidDepositFee();
    depositFee = depositFee_;
    emit DepositFeeUpdated(depositFee_);
  }

  // -------------------------------------------------
  // -------- Batched Rewards Manager Actions --------
  // -------------------------------------------------

  /// @notice Batch pauses rewardsManagers_. The manager's pauser or owner can perform this action.
  /// @param rewardsManagers_ The array of rewards managers to pause.
  function pause(IRewardsManager[] calldata rewardsManagers_) external {
    if (msg.sender != pauser && msg.sender != owner) revert Unauthorized();
    for (uint256 i = 0; i < rewardsManagers_.length; i++) {
      rewardsManagers_[i].pause();
    }
  }

  /// @notice Batch unpauses rewardsManagers_. The manager's owner can perform this action.
  /// @param rewardsManagers_ The array of rewards managers to unpause.
  function unpause(IRewardsManager[] calldata rewardsManagers_) external onlyOwner {
    for (uint256 i = 0; i < rewardsManagers_.length; i++) {
      rewardsManagers_[i].unpause();
    }
  }

  // ----------------------------------------
  // -------- Permissionless Actions --------
  // ----------------------------------------

  /// @notice Deploys a new Rewards Manager with the provided parameters.
  /// @param owner_ The owner of the rewards manager.
  /// @param pauser_ The pauser of the rewards manager.
  /// @param stakePoolConfigs_ The array of stake pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param rewardPoolConfigs_  The array of reward pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param salt_ Used to compute the resulting address of the rewards manager along with `msg.sender`.
  /// @return rewardsManager_ The newly created rewards manager.
  function createRewardsManager(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 salt_
  ) external returns (IRewardsManager rewardsManager_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(pauser_);

    bytes32 deploySalt_ = _computeDeploySalt(msg.sender, salt_);

    rewardsManager_ =
      rewardsManagerFactory.deployRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, deploySalt_);
  }

  /// @notice Given a `caller_` and `salt_`, compute and return the address of the RewardsManager deployed with
  /// `createRewardsManager`.
  /// @param caller_ The caller of the `createRewardsManager` function.
  /// @param salt_ Used to compute the resulting address of the rewards manager along with `caller_`.
  function computeRewardsManagerAddress(address caller_, bytes32 salt_) external view returns (address) {
    bytes32 deploySalt_ = _computeDeploySalt(caller_, salt_);
    return rewardsManagerFactory.computeAddress(deploySalt_);
  }

  /// @notice Given a `caller_` and `salt_`, return the salt used to compute the RewardsManager address deployed from
  /// the `rewardsManagerFactory`.
  /// @param caller_ The caller of the `createRewardsManager` function.
  /// @param salt_ Used to compute the resulting address of the rewards manager along with `caller_`.
  function _computeDeploySalt(address caller_, bytes32 salt_) internal pure returns (bytes32) {
    // To avoid front-running of RewardsManager deploys, msg.sender is used for the deploy salt.
    return keccak256(abi.encodePacked(salt_, caller_));
  }
}
