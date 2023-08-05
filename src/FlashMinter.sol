// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "erc7399/IERC7399.sol";

import { ERC20 } from "./lib/ERC20.sol";
import { UnsupportedToken, InsufficientBalance } from "./lib/Errors.sol";

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

    modifier supportedToken(address token) {
        if (token != address(this)) {
            revert UnsupportedToken(token);
        }
        _;
    }

    /// @inheritdoc IERC7399
    function maxFlashLoan(address token) external view supportedToken(token) returns (uint256) {
        return type(uint256).max - _totalSupply;
    }

    /// @inheritdoc IERC7399
    function flashFee(address token, uint256 amount) external view supportedToken(token) returns (uint256) {
        return _flashFee(amount);
    }

    /// @inheritdoc IERC7399
    function flash(
        address loanReceiver,
        address asset,
        uint256 amount,
        bytes calldata data,
        function(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory) callback
    )
        external
        supportedToken(asset)
        returns (bytes memory)
    {
        uint256 _fee = _flashFee(amount);
        uint256 _before = _balanceOf[address(this)];

        _mint(address(loanReceiver), amount);
        bytes memory result = callback(msg.sender, address(this), asset, amount, _fee, data);
        _burn(address(this), amount);

        if (_balanceOf[address(this)] < _before + _fee) {
            revert InsufficientBalance({ expected: _before + _fee, balance: _balanceOf[address(this)] });
        }

        return result;
    }

    /// @dev The fee to be charged for a given loan. Assumes that the loan is possible.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal.
    function _flashFee(uint256 amount) internal view returns (uint256) {
        return amount * fee / 10_000;
    }
}
