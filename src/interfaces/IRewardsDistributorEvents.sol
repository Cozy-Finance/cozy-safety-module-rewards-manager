// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IReceiptToken} from "cozy-safety-module-libs/interfaces/IReceiptToken.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";

interface IRewardsDistributorEvents {
  event ClaimedRewards(
    address indexed caller_,
    address indexed owner_,
    address indexed receiver_,
    uint16 stakePoolId_,
    uint16 rewardPoolId_,
    IERC20 rewardAsset_,
    uint256 amount_,
    uint256 claimFeeAmount_
  );
}
