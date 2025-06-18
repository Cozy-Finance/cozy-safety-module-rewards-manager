// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@prb/math/contracts/PRBMathSD59x18.sol";
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

        uint256 lastAvailable_ = depositorState_.lastAvailableToWithdraw;
        int256 lastAvailableFixed_ = PRBMathSD59x18.fromUint(lastAvailable_);

        if (lastAvailable_ == 0) revert BalanceTooLow();

        int256 lnC_ = rewardPool_.lnCumulativeDripFactor;
        int256 lnL_ = depositorState_.lnLastDripFactor;
        int256 decayFactor_ = (lnC_ - lnL_).exp();
        uint256 updatedWithdrawable_ = lastAvailableFixed_.mul(decayFactor_).toUint();

        if (withdrawalAmount_ > updatedWithdrawable_) revert BalanceTooLow();

        depositorState_.lastAvailableToWithdraw = updatedWithdrawable_ - withdrawalAmount_;
        depositorState_.lnLastDripFactor = lnC_;
        
        rewardPool_.undrippedRewards -= withdrawalAmount_;
        assetPools[token_].amount -= withdrawalAmount_;
        token_.safeTransfer(to_, withdrawalAmount_);

        emit Withdrawn(msg.sender, rewardPoolId_, address(token_), to_, withdrawalAmount_);
    }

}
