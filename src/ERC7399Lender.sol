// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "erc7399/IERC7399.sol";

import { IERC20 } from "./interfaces/IERC20.sol";
import { UnsupportedToken, InsufficientBalance, OnlyOwner } from "./lib/Errors.sol";

/**
 * @author Alberto Cuesta Cañada
 * @dev Minimal {ERC7399} contract that allows flash lending of a single asset for a fixed fee.
 */
contract ERC7399Lender is IERC7399 {
    event Flash(IERC20 indexed asset, uint256 amount, uint256 fee);
    event Fund(uint256 amount);
    event Defund(uint256 amount);

    address public immutable owner;
    IERC20 public immutable asset;
    uint256 public immutable fee; //  1 == 0.01 %.
    uint256 public reserves;

    /**
     * @param asset_ Asset supported for flash lending
     * @param fee_ Fee charged on flash loans
     */
    constructor(IERC20 asset_, uint256 fee_) {
        owner = msg.sender;
        asset = asset_;
        fee = fee_;
    }

    /// @dev Revert on unsuppoerted assets
    modifier isSupported(address asset_) {
        if (address(asset) != asset_) {
            revert UnsupportedToken(asset_);
        }
        _;
    }

    /// @dev Add funds to this contract. The assets must have been transferred previous to this call.
    /// @param amount The amount of asset to add.
    function fund(uint256 amount) external {
        _acceptTransfer(amount);
        emit Fund(amount);
    }

    /// @dev Remove all funds from this contract
    function defund() external {
        if (msg.sender != owner) {
            revert OnlyOwner(msg.sender, owner);
        }
        uint256 amount = asset.balanceOf(address(this));
        asset.transfer(owner, amount);
        emit Defund(amount);
    }

    /// @inheritdoc IERC7399
    function maxFlashLoan(address asset_) isSupported(asset_) external view returns (uint256) {
        return _maxFlashLoan();
    }

    /// @inheritdoc IERC7399
    function flashFee(address asset_, uint256 amount) isSupported(asset_) external view returns (uint256) {
        return amount <= reserves ? _flashFee(amount) : type(uint256).max;
    }

    /// @inheritdoc IERC7399
    function flash(
        address loanReceiver,
        address asset_,
        uint256 amount,
        bytes calldata data,
        function(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory) callback
    )
        isSupported(asset_) // Revert on unsupported assets
        external
        returns (bytes memory)
    {
        // Calculate the fee to charge for the loan
        uint256 fee_ = _flashFee(amount);
        
        // Transfer the loan to the loan receiver
        _serveLoan(loanReceiver, amount);

        // Call the callback on the callback receiver
        bytes memory result = callback(msg.sender, _repayTo(), asset_, amount, fee_, data);

        // Verify and accept the repayment
        _acceptTransfer(amount + fee);

        emit Flash(IERC20(asset_), amount, fee_);

        // Return the data from the callback
        return result;
    }

    /// @dev The fee to be charged for a given loan. Assumes that the loan is possible.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal.
    function _flashFee(uint256 amount) internal view returns (uint256) {
        return amount * fee / 10_000;
    }

    /// @dev The maximum flash loan of `asset` that can be served.
    /// @return The maximum flash loan of `asset` that can be served.
    function _maxFlashLoan() internal view returns (uint256) {
        return reserves;
    }

    /// @dev Transfer the loan to the loan receiver.
    /// @param loanReceiver The receiver of the loan assets.
    /// @param amount The amount of assets lent.
    function _serveLoan(address loanReceiver, uint256 amount) internal {
        reserves -= amount;
        asset.transfer(loanReceiver, amount);
    }

    /// @dev Determine the repayment receiver.
    function _repayTo() internal view returns (address) {
        return address(this);
    }

    /// @dev Verify that a transfer to this contract happened.
    function _acceptTransfer(uint256 amount) internal {
        uint256 expectedReserves = reserves + amount;
        uint256 currentReserves = asset.balanceOf(address(this));
        
        // We do not accept donations for security reasons.
        // Excess assets can be removed by using `flash`.
        reserves = expectedReserves;

        if (currentReserves < expectedReserves) {
            revert InsufficientBalance({ expected: expectedReserves, balance: currentReserves });
        }
    }
}
