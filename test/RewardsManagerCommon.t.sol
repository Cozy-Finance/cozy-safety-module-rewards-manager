// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {RewardsManagerCommon} from "../src/lib/RewardsManagerCommon.sol";
import {ICommonEvents} from "../src/interfaces/ICommonEvents.sol";
import {Ownable} from "cozy-safety-module-libs/lib/Ownable.sol";
import {TestBase} from "./utils/TestBase.sol";
import {MockManager} from "./utils/MockManager.sol";
import {ICozyManager} from "../src/interfaces/ICozyManager.sol";
import {
  ClaimRewardsArgs, ClaimableRewardsData, UserRewardsData, DepositorRewardsData
} from "../src/lib/structs/Rewards.sol";
import {StakePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {IDripModel} from "cozy-safety-module-libs/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {ClaimRewardsPoolData} from "../src/lib/structs/Rewards.sol";

contract RewardsManagerCommonUnitTest is TestBase {
  MockManager cozyManager = new MockManager();
  TestableRewardsManagerCommon component = new TestableRewardsManagerCommon(cozyManager);

  function test_incrementEIP712Version_revertIfNotAuthorized() external {
    address unauthorizedCaller_ = _randomAddress();
    vm.prank(unauthorizedCaller_);

    vm.expectRevert(Ownable.Unauthorized.selector);
    component.incrementEIP712Version();
  }

  function test_incrementEIP712Version_updatesVersion() external {
    // Get the current version
    uint64 initialVersion_ = component.eip712DomainVersion();

    vm.expectEmit();
    emit ICommonEvents.EIP712DomainVersionUpdated(initialVersion_ + 1);

    // Call the function as the owner
    vm.prank(component.owner());
    component.incrementEIP712Version();

    // Check that the version has been incremented
    uint64 updatedVersion_ = component.eip712DomainVersion();
    assertEq(updatedVersion_, initialVersion_ + 1, "EIP-712 version should increment by 1");
  }

  function test_setEIP712DomainName_revertIfNotAuthorized() external {
    address unauthorizedCaller_ = _randomAddress();
    vm.prank(unauthorizedCaller_);

    // Expect revert due to lack of authorization
    vm.expectRevert(Ownable.Unauthorized.selector);
    component.setEIP712DomainName("NewDomainName");
  }

  function test_setEIP712DomainName_updatesDomainName() external {
    // Define the new domain name
    string memory newDomainName_ = "NewDomainName";

    vm.expectEmit();
    emit ICommonEvents.EIP712DomainNameUpdated(newDomainName_);
    // Call the function as the owner
    vm.prank(component.owner());
    component.setEIP712DomainName(newDomainName_);

    // Check that the domain name has been updated
    string memory updatedDomainName_ = component.eip712DomainName();
    assertEq(updatedDomainName_, newDomainName_, "EIP-712 domain name should be updated");
  }
}

contract TestableRewardsManagerCommon is RewardsManagerCommon {
  constructor(MockManager manager_) {
    cozyManager = ICozyManager(address(manager_));
  }

  function _claimRewards(ClaimRewardsArgs memory args_, ClaimRewardsPoolData[] memory claimRewardsPoolData_)
    internal
    override
  {}

  function dripRewards() public override {}

  function _poolAmountWithFloor(uint256 poolAmount_) internal pure returns (uint256) {
    return poolAmount_;
  }

  function _assertValidDepositBalance(IERC20, uint256, uint256) internal view override {}

  function _getNextDripAmount(uint256, IDripModel, uint256) internal pure override returns (uint256) {
    return 0;
  }

  function _getNextDripFactor(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    pure
    override
    returns (uint256)
  {}

  function _updateUserRewards(uint256, mapping(uint16 => ClaimableRewardsData) storage, UserRewardsData[] storage)
    internal
    override
  {}

  function _dripRewardPool(RewardPool storage) internal override {}

  function _dripAndApplyPendingDrippedRewards(StakePool storage, mapping(uint16 => ClaimableRewardsData) storage)
    internal
    override
  {}

  function _dripAndResetCumulativeRewardsValues(StakePool[] storage, RewardPool[] storage) internal override {}

  function _previewCurrentWithdrawableRewards(RewardPool storage, DepositorRewardsData storage)
    internal
    pure
    override
    returns (uint256)
  {
    return 0;
  }
}
