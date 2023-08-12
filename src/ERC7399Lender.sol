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

        // Fund the contract with all the `asset` from the deployer;
        asset_.transferFrom(msg.sender, address(this), asset_.balanceOf(msg.sender));
    }

    /// @dev Revert on unsuppoerted assets
    modifier supportedAsset(address asset_) {
        if (address(asset) != asset_) {
            revert UnsupportedToken(asset_);
        }
        _;
    }

    /// @dev Shutdown the lender and remove all assets
    function end() external {
        if (msg.sender != owner) {
            revert OnlyOwner(msg.sender, owner);
        }
        asset.transfer(owner, asset.balanceOf(address(this)));
    }

    /// @inheritdoc IERC7399
    function maxFlashLoan(address asset_) supportedAsset(asset_) external view returns (uint256) {
        return _maxFlashLoan();
    }

    /// @inheritdoc IERC7399
    function flashFee(address asset_, uint256 amount) supportedAsset(asset_) external view returns (uint256) {
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
        supportedAsset(asset_) // Revert on unsupported assets
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
        _acceptRepayment(fee_);

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
        asset.transfer(loanReceiver, amount);
    }

    /// @dev Determine the repayment receiver.
    function _repayTo() internal view returns (address) {
        return address(this);
    }

    /// @dev Verify that the repayment happened. Make sure the repayment wasn't used for anything else.
    function _acceptRepayment(uint256 fee_) internal {
        uint256 expectedReserves = reserves + fee_;
        uint256 currentReserves = asset.balanceOf(address(this));
        reserves = expectedReserves; // We do not accept donations for security reasons. Excess assets can be removed by using `flash`.

        if (currentReserves < expectedReserves) {
            revert InsufficientBalance({ expected: expectedReserves, balance: currentReserves });
        }
    }
}
