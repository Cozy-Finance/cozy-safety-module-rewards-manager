// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {StakePool, AssetPool} from "./structs/Pools.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {
  UserRewardsData,
  PreviewClaimableRewardsData,
  PreviewClaimableRewards,
  ClaimableRewardsData
} from "./structs/Rewards.sol";
import {RewardPool, IdLookup} from "./structs/Pools.sol";

abstract contract RewardsDistributor is RewardsManagerCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;

  event ClaimedRewards(
    uint16 indexed stakePoolId_, IERC20 indexed rewardAsset_, uint256 amount_, address indexed owner_, address receiver_
  );

  struct RewardDrip {
    IERC20 rewardAsset;
    uint256 amount;
  }

  struct ClaimRewardsData {
    uint256 userStkReceiptTokenBalance;
    uint256 stkReceiptTokenSupply;
    uint256 rewardsWeight;
    uint256 numRewardAssets;
    uint256 numUserRewardAssets;
  }

  /// @notice Drip rewards for all reward pools.
  function dripRewards() public override {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();
    uint256 numRewardAssets_ = rewardPools.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      _dripRewardPool(rewardPools[i]);
    }
  }

  /// @notice Drip rewards for a specific reward pool.
  /// @param rewardPoolId_ The ID of the reward pool to drip rewards for.
  function dripRewardPool(uint16 rewardPoolId_) external {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();
    _dripRewardPool(rewardPools[rewardPoolId_]);
  }

  /// @notice Claim rewards for a specific stake pool and transfer rewards to `receiver_`.
  /// @param stakePoolId_ The ID of the stake pool to claim rewards for.
  /// @param receiver_ The address to transfer the claimed rewards to.
  function claimRewards(uint16 stakePoolId_, address receiver_) external {
    _claimRewards(stakePoolId_, receiver_, msg.sender);
  }

  /// @notice Preview the claimable rewards for a given set of stake pools.
  /// @param stakePoolIds_ The IDs of the stake pools to preview claimable rewards for.
  /// @param owner_ The address of the user to preview claimable rewards for.
  function previewClaimableRewards(uint16[] calldata stakePoolIds_, address owner_)
    external
    view
    returns (PreviewClaimableRewards[] memory previewClaimableRewards_)
  {
    uint256 numRewardAssets_ = rewardPools.length;

    RewardDrip[] memory nextRewardDrips_ = new RewardDrip[](numRewardAssets_);
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      nextRewardDrips_[i] = _previewNextRewardDrip(rewardPools[i]);
    }

    previewClaimableRewards_ = new PreviewClaimableRewards[](stakePoolIds_.length);
    for (uint256 i = 0; i < stakePoolIds_.length; i++) {
      previewClaimableRewards_[i] = _previewClaimableRewards(stakePoolIds_[i], owner_, nextRewardDrips_);
    }
  }

  /// @notice Update the user rewards data to prepare for a transfer of stkReceiptTokens.
  /// @dev stkReceiptTokens are expected to call this before the actual underlying ERC-20 transfer (e.g.
  /// `super.transfer(address to_, uint256 amount_)`). Otherwise, the `from_` user will have accrued less historical
  /// rewards they are entitled to as their new balance is smaller after the transfer. Also, the `to_` user will accure
  /// more historical rewards than they are entitled to as their new balance is larger after the transfer.
  /// @param from_ The address of the user transferring stkReceiptTokens.
  /// @param to_ The address of the user receiving stkReceiptTokens.
  function updateUserRewardsForStkReceiptTokenTransfer(address from_, address to_) external {
    // Check that only a registered stkReceiptToken can call this function.
    IdLookup memory idLookup_ = stkReceiptTokenToStakePoolIds[IReceiptToken(msg.sender)];
    if (!idLookup_.exists) revert Ownable.Unauthorized();

    uint16 stakePoolId_ = idLookup_.index;
    IReceiptToken stkReceiptToken_ = stakePools[stakePoolId_].stkReceiptToken;
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[stakePoolId_];

    // Fully accure historical rewards for both users given their current stkReceiptToken balances. Moving forward all
    // rewards
    // will accrue based on: (1) the stkReceiptToken balances of the `from_` and `to_` address after the transfer, (2)
    // the
    // current claimable reward index snapshots.
    _updateUserRewards(stkReceiptToken_.balanceOf(from_), claimableRewards_, userRewards[stakePoolId_][from_]);
    _updateUserRewards(stkReceiptToken_.balanceOf(to_), claimableRewards_, userRewards[stakePoolId_][to_]);
  }

  function _dripRewardPool(RewardPool storage rewardPool_) internal override {
    RewardDrip memory rewardDrip_ = _previewNextRewardDrip(rewardPool_);
    if (rewardDrip_.amount > 0) {
      rewardPool_.undrippedRewards -= rewardDrip_.amount;
      rewardPool_.cumulativeDrippedRewards += rewardDrip_.amount;
    }
    rewardPool_.lastDripTime = uint128(block.timestamp);
  }

  function _claimRewards(uint16 stakePoolId_, address receiver_, address owner_) internal override {
    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IReceiptToken stkReceiptToken_ = stakePool_.stkReceiptToken;
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[stakePoolId_];
    UserRewardsData[] storage userRewards_ = userRewards[stakePoolId_][owner_];

    ClaimRewardsData memory claimRewardsData_ = ClaimRewardsData({
      userStkReceiptTokenBalance: stkReceiptToken_.balanceOf(owner_),
      stkReceiptTokenSupply: stkReceiptToken_.totalSupply(),
      rewardsWeight: stakePool_.rewardsWeight,
      numRewardAssets: rewardPools.length,
      numUserRewardAssets: userRewards_.length
    });

    // When claiming rewards from a given reward pool, we take four steps:
    // (1) Drip from the reward pool since time may have passed since the last drip.
    // (2) Compute and update the next claimable rewards data for the (stake pool, reward pool) pair.
    // (3) Update the user's accrued rewards data for the (stake pool, reward pool) pair.
    // (4) Transfer the user's accrued rewards from the reward pool to the receiver.
    for (uint16 i = 0; i < claimRewardsData_.numRewardAssets; i++) {
      // Step (1)
      RewardPool storage rewardPool_ = rewardPools[i];
      if (rewardsManagerState == RewardsManagerState.ACTIVE) _dripRewardPool(rewardPool_);

      {
        // Step (2)
        ClaimableRewardsData memory newClaimableRewardsData_ = _previewNextClaimableRewardsData(
          claimableRewards_[i],
          rewardPool_.cumulativeDrippedRewards,
          claimRewardsData_.stkReceiptTokenSupply,
          claimRewardsData_.rewardsWeight
        );
        claimableRewards_[i] = newClaimableRewardsData_;

        // Step (3)
        UserRewardsData memory newUserRewardsData_ =
          UserRewardsData({accruedRewards: 0, indexSnapshot: newClaimableRewardsData_.indexSnapshot});
        // A new UserRewardsData struct is pushed to the array in the case a new reward pool was added since rewards
        // were last claimed for this user.
        uint256 oldIndexSnapshot_ = 0;
        uint256 oldAccruedRewards_ = 0;
        if (i < claimRewardsData_.numUserRewardAssets) {
          oldIndexSnapshot_ = userRewards_[i].indexSnapshot;
          oldAccruedRewards_ = userRewards_[i].accruedRewards;
          userRewards_[i] = newUserRewardsData_;
        } else {
          userRewards_.push(newUserRewardsData_);
        }

        // Step (4)
        _transferClaimedRewards(
          stakePoolId_,
          rewardPool_.asset,
          receiver_,
          oldAccruedRewards_
            + _getUserAccruedRewards(
              claimRewardsData_.userStkReceiptTokenBalance, newClaimableRewardsData_.indexSnapshot, oldIndexSnapshot_
            )
        );
      }
    }
  }

  function _previewNextClaimableRewardsData(
    ClaimableRewardsData memory claimableRewardsData_,
    uint256 cumulativeDrippedRewards_,
    uint256 stkReceiptTokenSupply_,
    uint256 rewardsWeight_
  ) internal pure returns (ClaimableRewardsData memory nextClaimableRewardsData_) {
    nextClaimableRewardsData_.cumulativeClaimedRewards = claimableRewardsData_.cumulativeClaimedRewards;
    nextClaimableRewardsData_.indexSnapshot = claimableRewardsData_.indexSnapshot;
    // If `stkReceiptTokenSupply_ == 0`, then we get a divide by zero error if we try to update the index snapshot. To
    // avoid this, we wait until the `stkReceiptTokenSupply_ > 0`, to apply all accumulated unclaimed dripped rewards to
    // the claimable rewards data. We have to update the index snapshot and cumulative claimed rewards at the same time
    // to keep accounting correct.
    if (stkReceiptTokenSupply_ > 0) {
      // Round down, in favor of leaving assets in the pool.
      uint256 unclaimedDrippedRewards_ = cumulativeDrippedRewards_.mulDivDown(rewardsWeight_, MathConstants.ZOC)
        - claimableRewardsData_.cumulativeClaimedRewards;

      nextClaimableRewardsData_.cumulativeClaimedRewards += unclaimedDrippedRewards_;
      // Round down, in favor of leaving assets in the claimable reward pool.
      nextClaimableRewardsData_.indexSnapshot += unclaimedDrippedRewards_.divWadDown(stkReceiptTokenSupply_);
    }
  }

  function _transferClaimedRewards(uint16 stakePoolId_, IERC20 rewardAsset_, address receiver_, uint256 amount_)
    internal
  {
    if (amount_ == 0) return;
    assetPools[rewardAsset_].amount -= amount_;
    rewardAsset_.safeTransfer(receiver_, amount_);
    emit ClaimedRewards(stakePoolId_, rewardAsset_, amount_, msg.sender, receiver_);
  }

  function _previewNextRewardDrip(RewardPool storage rewardPool_) internal view returns (RewardDrip memory) {
    return RewardDrip({
      rewardAsset: rewardPool_.asset,
      amount: _getNextDripAmount(rewardPool_.undrippedRewards, rewardPool_.dripModel, rewardPool_.lastDripTime)
    });
  }

  function _previewClaimableRewards(uint16 stakePoolId_, address owner_, RewardDrip[] memory nextRewardDrips_)
    internal
    view
    returns (PreviewClaimableRewards memory)
  {
    StakePool storage stakePool_ = stakePools[stakePoolId_];
    IReceiptToken stkReceiptToken_ = stakePool_.stkReceiptToken;
    uint256 stkReceiptTokenSupply_ = stkReceiptToken_.totalSupply();
    uint256 ownerStkReceiptTokenBalance_ = stkReceiptToken_.balanceOf(owner_);
    uint256 rewardsWeight_ = stakePool_.rewardsWeight;

    // Compute preview user accrued rewards accounting for any pending rewards drips.
    PreviewClaimableRewardsData[] memory claimableRewardsData_ =
      new PreviewClaimableRewardsData[](nextRewardDrips_.length);
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[stakePoolId_];
    UserRewardsData[] storage userRewards_ = userRewards[stakePoolId_][owner_];
    uint256 numUserRewardAssets_ = userRewards[stakePoolId_][owner_].length;

    for (uint16 i = 0; i < nextRewardDrips_.length; i++) {
      RewardPool storage rewardPool_ = rewardPools[i];
      ClaimableRewardsData memory previewNextClaimableRewardsData_ = _previewNextClaimableRewardsData(
        claimableRewards_[i],
        rewardPool_.cumulativeDrippedRewards + nextRewardDrips_[i].amount,
        stkReceiptTokenSupply_,
        rewardsWeight_
      );
      claimableRewardsData_[i] = PreviewClaimableRewardsData({
        rewardPoolId: i,
        asset: nextRewardDrips_[i].rewardAsset,
        amount: i < numUserRewardAssets_
          ? _previewUpdateUserRewardsData(
            ownerStkReceiptTokenBalance_, previewNextClaimableRewardsData_.indexSnapshot, userRewards_[i]
          ).accruedRewards
          : _previewAddUserRewardsData(ownerStkReceiptTokenBalance_, previewNextClaimableRewardsData_.indexSnapshot)
            .accruedRewards
      });
    }

    return PreviewClaimableRewards({stakePoolId: stakePoolId_, claimableRewardsData: claimableRewardsData_});
  }

  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    override
    returns (uint256)
  {
    if (rewardsManagerState == RewardsManagerState.PAUSED) return 0;
    uint256 dripFactor_ = dripModel_.dripFactor(lastDripTime_);
    if (dripFactor_ > MathConstants.WAD) revert InvalidDripFactor();

    return _computeNextDripAmount(totalBaseAmount_, dripFactor_);
  }

  function _computeNextDripAmount(uint256 totalBaseAmount_, uint256 dripFactor_)
    internal
    pure
    override
    returns (uint256)
  {
    return totalBaseAmount_.mulWadDown(dripFactor_);
  }

  function _dripAndApplyPendingDrippedRewards(
    StakePool storage stakePool_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_
  ) internal override {
    uint256 numRewardAssets_ = rewardPools.length;
    uint256 stkReceiptTokenSupply_ = stakePool_.stkReceiptToken.totalSupply();
    uint256 rewardsWeight_ = stakePool_.rewardsWeight;

    for (uint16 i = 0; i < numRewardAssets_; i++) {
      RewardPool storage rewardPool_ = rewardPools[i];
      _dripRewardPool(rewardPool_);
      ClaimableRewardsData storage claimableRewardsData_ = claimableRewards_[i];

      claimableRewards_[i] = _previewNextClaimableRewardsData(
        claimableRewardsData_, rewardPool_.cumulativeDrippedRewards, stkReceiptTokenSupply_, rewardsWeight_
      );
    }
  }

  /// @dev Drips rewards for all reward pools and resets the cumulative rewards values to 0. This function is only
  /// called on config updates (`Configurator.updateConfigs`), because config updates may change the rewards weights,
  /// which breaks the invariants that used to do claimable rewards accounting.
  function _dripAndResetCumulativeRewardsValues(StakePool[] storage stakePools_, RewardPool[] storage rewardPools_)
    internal
    override
  {
    uint256 numRewardAssets_ = rewardPools_.length;
    uint256 numStakePools_ = stakePools_.length;

    for (uint16 i = 0; i < numRewardAssets_; i++) {
      RewardPool storage rewardPool_ = rewardPools_[i];
      if (rewardsManagerState == RewardsManagerState.ACTIVE) _dripRewardPool(rewardPool_);
      uint256 oldCumulativeDrippedRewards_ = rewardPool_.cumulativeDrippedRewards;
      rewardPool_.cumulativeDrippedRewards = 0;

      for (uint16 j = 0; j < numStakePools_; j++) {
        StakePool storage stakePool_ = stakePools_[j];
        ClaimableRewardsData memory claimableRewardsData_ = _previewNextClaimableRewardsData(
          claimableRewards[j][i],
          oldCumulativeDrippedRewards_,
          stakePool_.stkReceiptToken.totalSupply(),
          stakePool_.rewardsWeight
        );
        claimableRewards[j][i] =
          ClaimableRewardsData({cumulativeClaimedRewards: 0, indexSnapshot: claimableRewardsData_.indexSnapshot});
      }
    }
  }

  function _updateUserRewards(
    uint256 userStkReceiptTokenBalance_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_,
    UserRewardsData[] storage userRewards_
  ) internal override {
    uint256 numRewardAssets_ = rewardPools.length;
    uint256 numUserRewardAssets_ = userRewards_.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      if (i < numUserRewardAssets_) {
        userRewards_[i] = _previewUpdateUserRewardsData(
          userStkReceiptTokenBalance_, claimableRewards_[i].indexSnapshot, userRewards_[i]
        );
      } else {
        userRewards_.push(_previewAddUserRewardsData(userStkReceiptTokenBalance_, claimableRewards_[i].indexSnapshot));
      }
    }
  }

  function _previewUpdateUserRewardsData(
    uint256 userStkReceiptTokenBalance_,
    uint256 newIndexSnapshot_,
    UserRewardsData storage userRewardsData_
  ) internal view returns (UserRewardsData memory newUserRewardsData_) {
    newUserRewardsData_.accruedRewards = userRewardsData_.accruedRewards
      + _getUserAccruedRewards(userStkReceiptTokenBalance_, newIndexSnapshot_, userRewardsData_.indexSnapshot);
    newUserRewardsData_.indexSnapshot = newIndexSnapshot_;
  }

  function _previewAddUserRewardsData(uint256 userStkReceiptTokenBalance_, uint256 newIndexSnapshot_)
    internal
    pure
    returns (UserRewardsData memory newUserRewardsData_)
  {
    newUserRewardsData_.accruedRewards = _getUserAccruedRewards(userStkReceiptTokenBalance_, newIndexSnapshot_, 0);
    newUserRewardsData_.indexSnapshot = newIndexSnapshot_;
  }

  function _getUserAccruedRewards(
    uint256 stkReceiptTokenAmount_,
    uint256 newRewardPoolIndex,
    uint256 oldRewardPoolIndex
  ) internal pure returns (uint256) {
    // Round down, in favor of leaving assets in the rewards pool.
    return stkReceiptTokenAmount_.mulWadDown(newRewardPoolIndex - oldRewardPoolIndex);
  }
}
