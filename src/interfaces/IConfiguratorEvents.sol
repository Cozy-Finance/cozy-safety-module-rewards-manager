// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {RewardPoolConfig} from "../lib/structs/Configs.sol";

interface IConfiguratorEvents {
  /// @notice Emitted when a stake pool is created.
  event StakePoolCreated(uint16 indexed stakePoolId, IReceiptToken stkReceiptToken, IERC20 asset);

  /// @notice Emitted when an reward pool is created.
  event RewardPoolCreated(uint16 indexed rewardPoolid, IERC20 rewardAsset, IReceiptToken depositReceiptToken);

  /// @dev Emitted when a rewards manager's configuration updates are applied.
  event ConfigUpdatesApplied(RewardPoolConfig[] rewardPoolConfigs, uint16[] rewardsWeights);
}
