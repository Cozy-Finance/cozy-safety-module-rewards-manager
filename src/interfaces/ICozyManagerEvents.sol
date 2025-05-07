// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRewardsManager} from "./IRewardsManager.sol";

interface ICozyManagerEvents {
  /// @dev Emitted when the default claim fee is updated by the Cozy Rewards Manager protocol owner.
  event ClaimFeeUpdated(uint16 claimFee_);

  /// @dev Emitted when the default deposit fee is updated by the Cozy Rewards Manager protocol owner.
  event DepositFeeUpdated(uint16 depositFee_);

  /// @dev Emitted when an override claim fee is updated by the Cozy Rewards Manager protocol owner.
  event OverrideClaimFeeUpdated(IRewardsManager indexed rewardsManager_, uint16 claimFee_);

  /// @dev Emitted when an override deposit fee is updated by the Cozy Rewards Manager protocol owner.
  event OverrideDepositFeeUpdated(IRewardsManager indexed rewardsManager_, uint16 depositFee_);

  /// @dev Emitted when an invalid claim fee is provided.
  error InvalidClaimFee();

  /// @dev Emitted when an invalid deposit fee is provided.
  error InvalidDepositFee();
}
