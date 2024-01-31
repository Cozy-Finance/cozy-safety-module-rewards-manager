// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {RewardPoolConfig} from "../lib/structs/Rewards.sol";

interface IConfiguratorEvents {
  /// @notice Emitted when a reserve pool is created.
  event ReservePoolCreated(
    uint16 indexed reservePoolId, IReceiptToken stkReceiptToken, IReceiptToken safetyModuleReceiptToken
  );

  /// @notice Emitted when an reward pool is created.
  event RewardPoolCreated(uint16 indexed rewardPoolid, IERC20 rewardAsset, IReceiptToken depositReceiptToken);

  /// @dev Emitted when a rewards manager's configuration updates are applied.
  event ConfigUpdatesApplied(RewardPoolConfig[] rewardPoolConfigs, uint16[] rewardsWeights);
}
