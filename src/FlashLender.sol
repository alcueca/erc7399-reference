// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "./interfaces/IERC20.sol";
import { IERC7399 } from "./interfaces/IERC7399.sol";

/**
 * @author Alberto Cuesta Cañada
 * @dev Extension of {ERC20} that allows flash lending.
 */
contract FlashLender is IERC7399 {
    struct AssetData {
        bool supported;
        uint16 fee; //  1 == 0.01 %.
            // 29 bytes free for other asset-specific data
    }

    struct AssetSetup {
        IERC20 asset;
        uint16 fee; //  1 == 0.01 %. Max of 655.36 %
    }

    mapping(IERC20 => AssetData) public assets;

    /**
     * @param assetSetup Asset contracts supported for flash lending, along with the fees charged.
     */
    constructor(AssetSetup[] memory assetSetup) {
        for (uint256 i = 0; i < assetSetup.length; i++) {
            assets[assetSetup[i].asset] = AssetData({ supported: true, fee: assetSetup[i].fee });
        }
    }

    /// @dev The fee to be charged for a given loan.
    /// @param asset The loan currency.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal. Returns
    /// type(uint256).max if the loan is not possible.
    function flashFee(IERC20 asset, uint256 amount) external view returns (uint256) {
        AssetData memory assetData = assets[asset];
        require(assetData.supported, "Unsupported currency");
        if (asset.balanceOf(address(this)) < amount) return type(uint256).max;
        else return _flashFee(assetData, amount);
    }

    /// @dev Initiate a flash loan.
    /// @param loanReceiver The address receiving the flash loan
    /// @param asset The asset to be loaned
    /// @param amount The amount to loaned
    /// @param data The ABI encoded user data
    /// @param callback The address and signature of the callback function
    /// @return result ABI encoded result of the callback
    function flash(
        address loanReceiver,
        IERC20 asset,
        uint256 amount,
        bytes calldata data,
        /// @dev callback. This is a combination of the callback receiver address, and the signature of callback
        /// function. It is encoded packed as 20 bytes + 4 bytes.
        /// @dev the return of the callback function is not encoded in the parameter, but must be `returns (bytes
        /// memory)` for compliance with the standard.
        /// @param initiator The address that called this function
        /// @param paymentReceiver The address that needs to receive the amount plus fee at the end of the callback
        /// @param asset The asset to be loaned
        /// @param amount The amount to loaned
        /// @param fee The fee to be paid
        /// @param data The ABI encoded data to be passed to the callback
        /// @return result ABI encoded result of the callback
        function(address, address, IERC20, uint256, uint256, bytes memory) external returns (bytes memory) callback
    )
        external
        returns (bytes memory)
    {
        AssetData memory assetData = assets[asset];
        require(assetData.supported, "Unsupported currency");
        uint256 _fee = _flashFee(assetData, amount);
        uint256 _before = asset.balanceOf(address(this));

        asset.transfer(loanReceiver, amount);
        bytes memory result = callback(msg.sender, address(this), asset, amount, _fee, data);
        require(asset.balanceOf(address(this)) >= _before + _fee, "Repay failed");

        return result;
    }

    /// @dev The fee to be charged for a given loan. Assumes that the loan is possible.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal.
    function _flashFee(AssetData memory assetData, uint256 amount) internal pure returns (uint256) {
        return amount * assetData.fee / 10_000;
    }
}
