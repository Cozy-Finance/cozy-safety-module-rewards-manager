// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RewardPool} from "./structs/Pools.sol";
import {DepositorRewardsData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsMathLib} from "./RewardsMathLib.sol";
import {IWithdrawerErrors} from "../interfaces/IWithdrawerErrors.sol";
import {IWithdrawerEvents} from "../interfaces/IWithdrawerEvents.sol";

abstract contract Withdrawer is RewardsManagerCommon, IWithdrawerErrors, IWithdrawerEvents {
  using SafeERC20 for IERC20;
  using FixedPointMathLib for uint256;

  /// @dev Typehash for EIP-712 withdrawRewardAssetsBySig so we dont recompute on each withdrawRewardAssetsBySig call.
  bytes32 public constant WITHDRAW_REWARD_ASSETS_BY_SIG_TYPEHASH = keccak256(
    "WithdrawRewardAssetsBySig(address owner,uint16 rewardPoolId,uint256 rewardAssetAmount,address caller,address receiver,uint256 deadline)"
  );

  /// @notice Withdraw undripped reward assets.
  /// @param rewardPoolId_ The ID of the reward pool to withdraw from.
  /// @param rewardAssetAmount_ The amount of reward assets to withdraw.
  /// @param receiver_ The address that will receive the withdrawn assets.
  function withdrawRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) external {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    _withdrawRewardAssetsInternal(rewardPool_, rewardPoolId_, msg.sender, receiver_, rewardAssetAmount_);
  }

  /// @notice Withdraw undripped reward assets on behalf of the owner via permit-style authorization.
  /// @dev Signature binds to (owner, rewardPoolId, rewardAssetAmount, caller=msg.sender, receiver, deadline).
  /// @param rewardPoolId_ The ID of the reward pool to withdraw from.
  /// @param rewardAssetAmount_ The amount of reward assets to withdraw.
  /// @param owner_ The owner of the reward assets.
  /// @param receiver_ The address that will receive the withdrawn assets.
  /// @param deadline_ The time at which the signature expires.
  /// @param signature_ The owner's signature over the EIP-712 structured data.
  function withdrawRewardAssetsBySig(
    uint16 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address owner_,
    address receiver_,
    uint256 deadline_,
    bytes calldata signature_
  ) external {
    if (block.timestamp > deadline_) revert SignatureExpired();

    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];

    bytes32 digest_ = keccak256(
      abi.encodePacked(
        "\x19\x01",
        _buildDomainSeparator(),
        keccak256(
          abi.encode(
            WITHDRAW_REWARD_ASSETS_BY_SIG_TYPEHASH,
            owner_,
            rewardPoolId_,
            rewardAssetAmount_,
            msg.sender,
            receiver_,
            deadline_
          )
        )
      )
    );

    if (!SignatureChecker.isValidSignatureNow(owner_, digest_, signature_)) revert InvalidSignature();

    _useEIP712DomainNonce();
    _withdrawRewardAssetsInternal(rewardPool_, rewardPoolId_, owner_, receiver_, rewardAssetAmount_);
  }

  function _withdrawRewardAssetsInternal(
    RewardPool storage rewardPool_,
    uint16 rewardPoolId_,
    address owner_,
    address receiver_,
    uint256 rewardAssetAmount_
  ) internal {
    uint256 currentWithdrawableRewards_ =
      _previewCurrentWithdrawableRewards(rewardPool_, depositorRewards[rewardPoolId_][owner_]);
    if (rewardAssetAmount_ > currentWithdrawableRewards_) revert InvalidWithdraw();

    depositorRewards[rewardPoolId_][owner_] = DepositorRewardsData({
      withdrawableRewards: currentWithdrawableRewards_ - rewardAssetAmount_,
      logIndexSnapshot: rewardPool_.logIndexSnapshot,
      epoch: rewardPool_.epoch
    });
    rewardPool_.undrippedRewards -= rewardAssetAmount_;
    assetPools[rewardPool_.asset].amount -= rewardAssetAmount_;

    rewardPool_.asset.safeTransfer(receiver_, rewardAssetAmount_);

    emit Withdrawn(owner_, rewardPoolId_, rewardAssetAmount_, receiver_);
  }

  /// @notice Preview the current withdrawable rewards for the depositor.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param depositor_ The address of the depositor.
  /// @return The depositor's current withdrawable rewards.
  function previewCurrentWithdrawableRewards(uint16 rewardPoolId_, address depositor_) external view returns (uint256) {
    return _previewCurrentWithdrawableRewards(rewardPools[rewardPoolId_], depositorRewards[rewardPoolId_][depositor_]);
  }

  function _previewCurrentWithdrawableRewards(
    RewardPool storage rewardPool_,
    DepositorRewardsData storage depositorRewardsData_
  ) internal view override returns (uint256) {
    if (depositorRewardsData_.epoch < rewardPool_.epoch || depositorRewardsData_.withdrawableRewards == 0) {
      // Rewards have fully dripped or the depositor previously had no withdrawable rewards, so the depositor has no
      // withdrawable rewards.
      return 0;
    } else if (depositorRewardsData_.logIndexSnapshot == rewardPool_.logIndexSnapshot) {
      // Rewards have not dripped since the last update, so no update to the depositor's withdrawable rewards.
      return depositorRewardsData_.withdrawableRewards;
    } else {
      // Rewards have dripped since the last update, so scale down the depositor's withdrawable rewards by the amount of
      // drip.
      return depositorRewardsData_.withdrawableRewards.mulWadDown(
        RewardsMathLib.expNeg(rewardPool_.logIndexSnapshot - depositorRewardsData_.logIndexSnapshot)
      );
    }
  }
}
