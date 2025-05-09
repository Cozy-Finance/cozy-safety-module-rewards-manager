// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-libs/interfaces/IReceiptToken.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {AssetPool, StakePool} from "./structs/Pools.sol";
import {ClaimRewardsArgs, ClaimableRewardsData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";

abstract contract Staker is RewardsManagerCommon {
  using SafeERC20 for IERC20;

  /// @notice Emitted when a user stakes.
  /// @param caller_ The address that called the stake function.
  /// @param receiver_ The address that received the stkReceiptTokens.
  /// @param stakePoolId_ The stake pool ID that the user staked in.
  /// @param stkReceiptToken_ The stkReceiptToken that was minted.
  /// @param assetAmount_ The amount of the underlying asset staked.
  event Staked(
    address indexed caller_,
    address indexed receiver_,
    uint16 indexed stakePoolId_,
    IReceiptToken stkReceiptToken_,
    uint256 assetAmount_
  );

  /// @notice Emitted when a user unstakes.
  /// @param caller_ The address that called the unstake function.
  /// @param receiver_ The address that received the unstaked assets.
  /// @param owner_ The owner of the stkReceiptTokens being unstaked.
  /// @param stakePoolId_ The stake pool ID that the user unstaked from.
  /// @param stkReceiptToken_ The stkReceiptToken that was burned.
  /// @param stkReceiptTokenAmount_ The amount of stkReceiptTokens burned.
  event Unstaked(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint16 indexed stakePoolId_,
    IReceiptToken stkReceiptToken_,
    uint256 stkReceiptTokenAmount_
  );

  /// @notice Stake by minting `assetAmount_` stkReceiptTokens to `receiver_` after depositing exactly `assetAmount_` of
  /// `stakePoolId_` stake pool asset.
  /// @dev Assumes that `msg.sender` has already approved this contract to transfer `assetAmount_` of the `stakePoolId_`
  /// stake pool asset.
  /// @param stakePoolId_ The ID of the stake pool to stake in.
  /// @param assetAmount_ The amount of the underlying asset to stake.
  /// @param receiver_ The address that will receive the stkReceiptTokens.
  function stake(uint16 stakePoolId_, uint256 assetAmount_, address receiver_) external {
    if (assetAmount_ == 0) revert AmountIsZero();

    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IERC20 asset_ = stakePool_.asset;
    AssetPool storage assetPool_ = assetPools[asset_];

    // Pull in stake assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    asset_.safeTransferFrom(msg.sender, address(this), assetAmount_);
    _assertValidDepositBalance(asset_, assetPool_.amount, assetAmount_);

    _executeStake(stakePoolId_, assetAmount_, receiver_, assetPool_, stakePool_);
  }

  /// @notice Stake by minting `assetAmount_` stkReceiptTokens to `receiver_`.
  /// @dev Assumes that `assetAmount_` of `stakePoolId_` stake pool asset has already been transferred to this rewards
  /// manager contract.
  /// @param stakePoolId_ The ID of the stake pool to stake in.
  /// @param assetAmount_ The amount of the underlying asset to stake.
  /// @param receiver_ The address that will receive the stkReceiptTokens.
  function stakeWithoutTransfer(uint16 stakePoolId_, uint256 assetAmount_, address receiver_) external {
    if (assetAmount_ == 0) revert AmountIsZero();

    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IERC20 asset_ = stakePool_.asset;
    AssetPool storage assetPool_ = assetPools[asset_];

    _assertValidDepositBalance(asset_, assetPool_.amount, assetAmount_);

    _executeStake(stakePoolId_, assetAmount_, receiver_, assetPool_, stakePool_);
  }

  /// @notice Unstakes by burning `stkReceiptTokenAmount_` of `stakePoolId_` stake pool stake receipt tokens and
  /// sending `stkReceiptTokenAmount_` of `stakePoolId_` stake pool asset to `receiver_`. Also, claims ALL outstanding
  /// user rewards and sends them to `owner_`.
  /// @dev Assumes that user has approved this rewards manager to spend its stkReceiptTokens.
  /// @dev The `owner_` is transferred ALL claimable rewards of the `owner_`, not just those associated with the
  /// input amount, `stkReceiptTokenAmount_`.
  /// @param stakePoolId_ The ID of the stake pool to unstake from.
  /// @param stkReceiptTokenAmount_ The amount of stkReceiptTokens to unstake.
  /// @param receiver_ The address that will receive the unstaked assets.
  /// @param owner_ The owner of the stkReceiptTokens being unstaked.
  function unstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_) external {
    if (stkReceiptTokenAmount_ == 0) revert AmountIsZero();

    _claimRewards(ClaimRewardsArgs(stakePoolId_, owner_, owner_));

    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IReceiptToken stkReceiptToken_ = stakePool_.stkReceiptToken;
    IERC20 asset_ = stakePool_.asset;

    // Given the 1:1 conversion rate between the underlying asset and stkReceiptTokens, we always have `assetAmount_ ==
    // stkReceiptTokenAmount_`.
    stakePool_.amount -= stkReceiptTokenAmount_;
    assetPools[asset_].amount -= stkReceiptTokenAmount_;
    // Burn also ensures that the sender has sufficient allowance if they're not the owner.
    stkReceiptToken_.burn(msg.sender, owner_, stkReceiptTokenAmount_);

    asset_.safeTransfer(receiver_, stkReceiptTokenAmount_);

    emit Unstaked(msg.sender, receiver_, owner_, stakePoolId_, stkReceiptToken_, stkReceiptTokenAmount_);
  }

  function _executeStake(
    uint16 stakePoolId_,
    uint256 assetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    StakePool storage stakePool_
  ) internal {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();

    // Given the 1:1 conversion rate between the underlying asset and stkReceiptTokens, we always have `assetAmount_ ==
    // stkReceiptTokenAmount_`.
    stakePool_.amount += assetAmount_;
    assetPool_.amount += assetAmount_;

    // Update user rewards before minting any new stkReceiptTokens.
    IReceiptToken stkReceiptToken_ = stakePool_.stkReceiptToken;
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[stakePoolId_];
    _dripAndApplyPendingDrippedRewards(stakePool_, claimableRewards_);
    _updateUserRewards(stkReceiptToken_.balanceOf(receiver_), claimableRewards_, userRewards[stakePoolId_][receiver_]);

    stkReceiptToken_.mint(receiver_, assetAmount_);
    emit Staked(msg.sender, receiver_, stakePoolId_, stkReceiptToken_, assetAmount_);
  }
}
