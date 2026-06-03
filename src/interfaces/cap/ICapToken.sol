// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Partial interface of the cap token
interface ICapToken {
    /// @notice Mint the cap token using an asset
    /// @dev This contract must have approval to move asset from msg.sender
    /// @dev The amount in is capped by the deposit cap of the asset
    /// @param _asset Whitelisted asset to deposit
    /// @param _amountIn Amount of asset to use in the minting
    /// @param _minAmountOut Minimum amount to mint
    /// @param _receiver Receiver of the minting
    /// @param _deadline Deadline of the tx
    function mint(address _asset, uint256 _amountIn, uint256 _minAmountOut, address _receiver, uint256 _deadline)
        external
        returns (uint256 amountOut);

    /// @notice Burn the cap token for an asset
    /// @dev Asset is withdrawn from the reserve or divested from the underlying vault
    /// @param _asset Asset to withdraw
    /// @param _amountIn Amount of cap token to burn
    /// @param _minAmountOut Minimum amount out to receive
    /// @param _receiver Receiver of the withdrawal
    /// @param _deadline Deadline of the tx
    function burn(address _asset, uint256 _amountIn, uint256 _minAmountOut, address _receiver, uint256 _deadline)
        external
        returns (uint256 amountOut);

    /// @notice Get the burn amount for a given asset
    /// @param _asset Asset address to withdraw
    /// @param _amountIn Amount of cap token to burn
    /// @return amountOut Amount of the asset withdrawn
    /// @return fee Fee applied
    function getBurnAmount(address _asset, uint256 _amountIn) external view returns (uint256 amountOut, uint256 fee);

    /// @notice Get the mint amount for a given asset
    /// @param _asset Asset address
    /// @param _amountIn Amount of asset to use
    /// @return amountOut Amount minted
    /// @return fee Fee applied
    function getMintAmount(address _asset, uint256 _amountIn) external view returns (uint256 amountOut, uint256 fee);

    /// @notice Check if the address is whitelisted
    function whitelisted(address _owner) external view returns (bool _whitelisted);

    /// @notice Check for remaining mint capacity.
    function getRemainingMintCapacity(address _asset) external view returns (uint256);
}
