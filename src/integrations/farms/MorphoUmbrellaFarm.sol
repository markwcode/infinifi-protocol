// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CoreRoles} from "@libraries/CoreRoles.sol";
import {MultiAssetFarmV2} from "@integrations/MultiAssetFarmV2.sol";
import {IMaturityFarm, IFarm} from "@interfaces/IMaturityFarm.sol";

/// @notice Specialised farm that aggregates Morpho ERC4626-like vaults where on-chain
///         totalAssets/convertToAssets reads are expensive. It keeps a cached
///         view of total assets that can be updated off-chain based on the
///         Morpho share price.
///         It can handle multiple Morpho vaults.
/// @dev    Note that due to rounding when pricing in MultiAssetFarmV2 the assets might be under-reported for a few wei
contract MorphoUmbrellaFarm is MultiAssetFarmV2, IMaturityFarm {
    using SafeERC20 for IERC20;

    /// @notice Emitted whenever the cached total assets value is updated
    event CachedTotalAssetsUpdated(uint256 indexed timestamp, uint256 newAssets);

    uint256 public immutable duration;

    /// @notice Cached total assets of underlying Morpho vaults
    uint256 public cachedTotalAssets;

    constructor(address _core, address _assetToken, address _accounting, uint256 _duration)
        MultiAssetFarmV2(_core, _assetToken, _accounting)
    {
        duration = _duration;
    }

    function maturity() public view returns (uint256) {
        return block.timestamp + duration;
    }

    /// @notice returns cached assets. Sync assets to get the latest value.
    function assets() public view override(IFarm, MultiAssetFarmV2) returns (uint256) {
        return IERC20(assetToken).balanceOf(address(this)) + cachedTotalAssets;
    }

    /// @notice returns asset token balance + actual balance of Morpho vaults
    function freshAssets() public view returns (uint256) {
        return super.assets();
    }

    /// @notice returns asset balance of a single Morpho vault
    function vaultBalance(address _vault) public view returns (uint256) {
        return ERC4626(_vault).convertToAssets(IERC20(_vault).balanceOf(address(this)));
    }

    /// @notice Deposits `_amount` of asset tokens to underlying Morpho `_vault`
    function vaultDeposit(address[] calldata _vaults, uint256[] calldata _amounts)
        external
        whenNotPaused
        checkSlippage
        onlyCoreRole(CoreRoles.FARM_SWAP_CALLER)
    {
        for (uint256 i = 0; i < _vaults.length; i++) {
            require(isAssetSupported(_vaults[i]), InvalidAsset(_vaults[i]));
            IERC20(assetToken).forceApprove(_vaults[i], _amounts[i]);
            ERC4626(_vaults[i]).deposit(_amounts[i], address(this));
        }
        syncAssets();
    }

    /// @notice Redeem `_amount` of morpho shares from underlying Morpho `_vault`
    function vaultRedeem(address[] calldata _vaults, uint256[] calldata _amounts)
        external
        whenNotPaused
        checkSlippage
        onlyCoreRole(CoreRoles.FARM_SWAP_CALLER)
    {
        for (uint256 i = 0; i < _vaults.length; i++) {
            require(isAssetSupported(_vaults[i]), InvalidAsset(_vaults[i]));
            ERC4626(_vaults[i]).redeem(_amounts[i], address(this), address(this));
        }
        syncAssets();
    }

    /// @notice Allows anyone to update the assets based on the underlying Morpho vaults
    function syncAssets() public whenNotPaused {
        cachedTotalAssets = super.assets() - IERC20(assetToken).balanceOf(address(this));
        emit CachedTotalAssetsUpdated(block.timestamp, cachedTotalAssets);
    }

    /// @notice Withdraws any supported secondary asset tokens from the farm
    /// @param _asset The address of the asset token to withdraw
    /// @param _amount The amount of the asset to withdraw
    /// @param _to The address to send the withdrawn tokens to
    function withdrawSecondaryAsset(address _asset, uint256 _amount, address _to)
        external
        override
        onlyCoreRole(CoreRoles.FARM_MANAGER)
        whenNotPaused
    {
        require(isAssetSupported(_asset) && _asset != assetToken, InvalidAsset(_asset));

        uint256 assetsBefore = assets();
        IERC20(_asset).safeTransfer(_to, _amount);
        uint256 assetsAfter = assets();

        syncAssets();
        emit AssetsUpdated(block.timestamp, assetsBefore, assetsAfter);
    }
}
