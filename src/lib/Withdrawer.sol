// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { PRBMathSD59x18 } from "@prb/math/contracts/PRBMathSD59x18.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {RewardPool} from "./structs/Pools.sol";
import {DepositorRewardState} from "./structs/Rewards.sol";
import {IWithdrawerErrors} from "../interfaces/IWithdrawerErrors.sol";
import {IWithdrawerEvents} from "../interfaces/IWithdrawerEvents.sol";

contract Withdrawer is RewardsManagerCommon, IWithdrawerErrors, IWithdrawerEvents {
    using PRBMathSD59x18 for int256;
    using SafeERC20 for IERC20;

    function _withdraw(uint16 rewardPoolId_, address to_, uint256 withdrawalAmount_) external {
        RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
        DepositorRewardState storage depositorState_ = rewardPoolDepositorStates[rewardPoolId_][msg.sender];
        IERC20 token_ = rewardPool_.asset;

        // Ensure reward pool drip is up-to-date before withdrawal
        _dripRewardPool(rewardPool_,rewardPoolId_);

        if (depositorState_.lastAvailableToWithdraw == 0) revert BalanceTooLow();

        uint256 updatedWithdrawable_ = PRBMathSD59x18.fromUint(depositorState_.lastAvailableToWithdraw).mul((rewardPool_.lnCumulativeDripFactor - depositorState_.lnLastDripFactor).exp()).toUint();

        if (withdrawalAmount_ > updatedWithdrawable_) revert BalanceTooLow();

        depositorState_.lastAvailableToWithdraw = updatedWithdrawable_ - withdrawalAmount_;
        depositorState_.lnLastDripFactor = rewardPool_.lnCumulativeDripFactor;
        
        rewardPool_.undrippedRewards -= withdrawalAmount_;
        assetPools[token_].amount -= withdrawalAmount_;
        token_.safeTransfer(to_, withdrawalAmount_);

        emit Withdrawn(msg.sender, rewardPoolId_, address(token_), to_, withdrawalAmount_);
    }

}
