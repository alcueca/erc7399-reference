// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "./lib/ERC20.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IERC7399 } from "./interfaces/IERC7399.sol";

/**
 * @author Alberto Cuesta Cañada
 * @dev Extension of {ERC20} that allows flash minting.
 */
contract FlashMinter is ERC20, IERC7399 {
    uint256 public fee; //  1 == 0.01 %.

    /**
     * @param fee_ The percentage of the loan `amount` that needs to be repaid, in addition to `amount`.
     */
    constructor(string memory name, string memory symbol, uint256 fee_) ERC20(name, symbol) {
        fee = fee_;
    }

    /// @dev The fee to be charged for a given loan.
    /// @param asset The loan currency.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal. Returns
    /// type(uint256).max if the loan is not possible.
    function flashFee(IERC20 asset, uint256 amount) external view returns (uint256) {
        require(address(asset) == address(this), "FlashMinter: Unsupported currency");
        if (type(uint256).max - _totalSupply < amount) return type(uint256).max;
        return _flashFee(amount);
    }

    /// @dev Initiate a flash mint.
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
        require(address(asset) == address(this), "FlashMinter: Unsupported currency");
        uint256 _fee = _flashFee(amount);
        uint256 _before = _balanceOf[address(this)];

        _mint(address(loanReceiver), amount);
        bytes memory result = callback(msg.sender, address(this), asset, amount, _fee, data);
        _burn(address(this), amount);
        require(_balanceOf[address(this)] >= _before + _fee, "FlashLender: Repay failed");
        return result;
    }

    /// @dev The fee to be charged for a given loan. Assumes that the loan is possible.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal.
    function _flashFee(uint256 amount) internal view returns (uint256) {
        return amount * fee / 10_000;
    }
}
