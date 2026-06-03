// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Interface required by rebalancer for fund movements
interface IMultiAssetWithdrawable {
    function isAssetSupported(address _asset) external view returns (bool);

    function withdrawSecondaryAsset(address _asset, uint256 _amount, address _to) external;
}
