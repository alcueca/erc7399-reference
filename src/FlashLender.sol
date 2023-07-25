// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "./interfaces/IERC20.sol";
import { IERC3156PPFlashLender } from "./interfaces/IERC3156PPFlashLender.sol";


/**
 * @author Alberto Cuesta Cañada
 * @dev Extension of {ERC20} that allows flash lending.
 */
contract FlashLender is IERC3156PPFlashLender {

    mapping(IERC20 => bool) public supportedAssets;
    uint256 public fee; //  1 == 0.01 %.

    /**
     * @param supportedAssets_ Asset contracts supported for flash lending.
     * @param fee_ The percentage of the loan `amount` that needs to be repaid, in addition to `amount`.
     */
    constructor(
        IERC20[] memory supportedAssets_,
        uint256 fee_
    ) {
        for (uint256 i = 0; i < supportedAssets_.length; i++) {
            supportedAssets[supportedAssets_[i]] = true;
        }
        fee = fee_;
    }

    /// @dev The fee to be charged for a given loan.
    /// @param asset The loan currency.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal. Returns type(uint256).max if the loan is not possible.
    function flashFee(
        IERC20 asset,
        uint256 amount
    ) external view returns (uint256) {
        require (supportedAssets[asset], "Unsupported currency");
        if (asset.balanceOf(address(this)) < amount) return type(uint256).max; 
        else return _flashFee(amount);
    }

    /// @dev Use the aggregator to serve an ERC3156++ flash loan.
    /// @dev Forward the callback to the callback receiver. The borrower only needs to trust the aggregator and its governance, instead of the underlying lenders.
    /// @param loanReceiver The address receiving the flash loan
    /// @param asset The asset to be loaned
    /// @param amount The amount to loaned
    /// @param data The ABI encoded user data
    /// @param callback The address and signature of the callback function
    /// @return result ABI encoded result of the callback
    function flashLoan(
        address loanReceiver,
        IERC20 asset,
        uint256 amount,
        bytes calldata data,
        /// @dev callback.
        /// This is a concatenation of (address, bytes4), where the address is the callback receiver, and the bytes4 is the signature of callback function.
        /// The arguments in the callback function are fixed.
        /// If the callback receiver needs to know the loan receiver, it should be encoded by the initiator in `data`.
        /// @param initiator The address that called this function
        /// @param paymentReceiver The address that needs to receive the amount plus fee at the end of the callback
        /// @param asset The asset to be loaned
        /// @param amount The amount to loaned
        /// @param fee The fee to be paid
        /// @param data The ABI encoded data to be passed to the callback
        /// @return result ABI encoded result of the callback
        function(address, address, IERC20, uint256, uint256, bytes memory) external returns (bytes memory) callback
    ) external returns (bytes memory) {
        require(
            supportedAssets[asset],
            "Unsupported currency"
        );
        uint256 _fee = _flashFee(amount);
        uint256 _before = asset.balanceOf(address(this));

        asset.transfer(loanReceiver, amount);
        bytes memory result = callback(msg.sender, address(this), asset, amount, _fee, data);
        require(
            asset.balanceOf(address(this)) >= _before + _fee,
            "Repay failed"
        );

        return result;
    }

    /// @dev The fee to be charged for a given loan. Assumes that the loan is possible.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal.
    function _flashFee(
        uint256 amount
    ) internal view returns (uint256) {
        return amount * fee / 10000;
    }
}