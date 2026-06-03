// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

import {ICapToken} from "@interfaces/cap/ICapToken.sol";
import {Farm, CoreRoles} from "@integrations/Farm.sol";
import {IMultiAssetWithdrawable} from "@interfaces/IMultiAssetWithdrawable.sol";

interface ICapOracle {
    function getPrice(address _asset) external returns (uint256, uint256);
}

contract CapFarm is Farm, IMultiAssetWithdrawable {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    error NotWhitelisted();
    error OraclePrecisionTooLow();
    error InsufficientAssets(uint256 _amount, uint256 _maxAmount);

    address public constant CUSD = 0xcCcc62962d17b8914c62D74FfB843d73B2a3cccC;
    address public constant STCUSD = 0x88887bE419578051FF9F4eb6C858A951921D8888;
    address public constant CAP_ORACLE = 0xcD7f45566bc0E7303fB92A93969BB4D3f6e662bb;

    constructor(address _core, address _assetToken) Farm(_core, _assetToken) {
        maxSlippage = 0.999999999e18;
    }

    function assets() public view override returns (uint256) {
        uint256 stakedCapBalance = ERC4626(STCUSD).balanceOf(address(this));
        if (stakedCapBalance == 0) return 0;
        return _getBurnAmount(ERC4626(STCUSD).convertToAssets(stakedCapBalance));
    }

    /// Supports both cUSD and stcUSD in case of residual or accidental transfers to this farm.
    function isAssetSupported(address _asset) public pure returns (bool) {
        return _asset == CUSD || _asset == STCUSD;
    }

    function maxDeposit() public view override returns (uint256) {
        return ICapToken(CUSD).getRemainingMintCapacity(assetToken);
    }

    function liquidity() external view override returns (uint256) {
        uint256 maxWithdrawAmount = ERC4626(STCUSD).maxWithdraw(address(this));
        if (maxWithdrawAmount == 0) return 0;
        return _getBurnAmount(maxWithdrawAmount);
    }

    /// @notice Can be called by manual rebalancer to withdraw staked Cap tokens.
    function withdrawSecondaryAsset(address _asset, uint256 _amount, address _to)
        external
        whenNotPaused
        onlyCoreRole(CoreRoles.FARM_MANAGER)
    {
        uint256 assetsBefore = assets();
        IERC20(_asset).safeTransfer(_to, _amount);
        uint256 assetsAfter = assets();

        emit AssetsUpdated(block.timestamp, assetsBefore, assetsAfter);
    }

    function _deposit(uint256 _assetsToDeposit) internal override {
        require(ICapToken(CUSD).whitelisted(address(this)), NotWhitelisted());

        // Pick up any residual asset token balance (dust from prior withdrawals).
        uint256 assetTokenBalance = IERC20(assetToken).balanceOf(address(this));
        require(assetTokenBalance >= _assetsToDeposit, InsufficientAssets(assetTokenBalance, _assetsToDeposit));

        IERC20(assetToken).forceApprove(CUSD, assetTokenBalance);
        ICapToken(CUSD).mint(assetToken, assetTokenBalance, 0, address(this), block.timestamp);

        // Stake all CUSD, including any dust from prior operations.
        uint256 capAmount = IERC20(CUSD).balanceOf(address(this));
        IERC20(CUSD).forceApprove(STCUSD, capAmount);
        ERC4626(STCUSD).deposit(capAmount, address(this));
    }

    function _withdraw(uint256 _amount, address _to) internal virtual override {
        require(ICapToken(CUSD).whitelisted(address(this)), NotWhitelisted());

        // Make sure the oracle is reporting sufficient decimals.
        (uint256 assetPrice,) = ICapOracle(CAP_ORACLE).getPrice(assetToken);
        require(assetPrice >= 1e6, OraclePrecisionTooLow());

        uint256 capTokensToUnstake = ERC4626(STCUSD).maxWithdraw(address(this));
        uint256 maxAssetsOut = _getBurnAmount(capTokensToUnstake);

        require(_amount <= maxAssetsOut, InsufficientAssets(_amount, maxAssetsOut));

        if (_amount < maxAssetsOut) {
            // Target _amount + 1 so that Cap's two nested floor divisions are not causing problems.
            // Any excess assets sit in the farm as dust and are swept on the next deposit.
            capTokensToUnstake = capTokensToUnstake.mulDivUp(_amount + 1, maxAssetsOut);
        }

        // First unstake tokens from to get CAP.
        ERC4626(STCUSD).withdraw(capTokensToUnstake, address(this), address(this));
        // Take entire cap balance to pick up any residue.
        uint256 capBalance = IERC20(CUSD).balanceOf(address(this));
        // Burn CAP balance in exchange for USDC to this address.
        ICapToken(CUSD).burn(assetToken, capBalance, 0, address(this), block.timestamp);
        // Transfer the exact requested amount to the receiver.
        IERC20(assetToken).safeTransfer(_to, _amount);
    }

    function _getBurnAmount(uint256 _capTokens) internal view returns (uint256 amountOut) {
        (amountOut,) = ICapToken(CUSD).getBurnAmount(assetToken, _capTokens);
    }
}
