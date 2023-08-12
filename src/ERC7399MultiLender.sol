// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "erc7399/IERC7399.sol";

import { IERC20 } from "./interfaces/IERC20.sol";
import { InsufficientBalance, OnlyOwner } from "./lib/Errors.sol";

/**
 * @author Alberto Cuesta Cañada
 * @dev Minimal {ERC7399} contract that allows flash lending of a multiple assets for a fixed fee.
 */
contract ERC7399MultiLender is IERC7399 {
    event Flash(IERC20 indexed asset, uint256 amount, uint256 fee);
    event Fund(IERC20 indexed asset, uint256 amount);
    event Defund(IERC20 indexed asset, uint256 amount);

    address public immutable owner;
    uint256 public immutable fee; //  1 == 0.01 %.
    mapping (IERC20 asset => uint256 balance) public reserves;

    /**
     * @param asset Asset supported for flash lending
     * @param fee_ Fee charged on flash loans
     */
    constructor(IERC20 asset, uint256 fee_) {
        owner = msg.sender;
        asset = asset;
        fee = fee_;
    }

    /// @dev Add assets to this contract. The assets must have been transferred previous to this call.
    /// @param asset The asset to add.
    /// @param amount The amount of asset to add.
    function fund(IERC20 asset, uint256 amount) external {
        _acceptTransfer(asset, amount);
        emit Fund(asset, amount);
    }

    /// @dev Remove assets from this contract
    /// @param asset The assets lent
    function defund(IERC20 asset) external {
        if (msg.sender != owner) {
            revert OnlyOwner(msg.sender, owner);
        }
        delete reserves[asset];

        uint256 amount = asset.balanceOf(address(this));
        asset.transfer(owner, amount);
        emit Defund(asset, amount);
    }

    /// @inheritdoc IERC7399
    function maxFlashLoan(address asset) external view returns (uint256) {
        return _maxFlashLoan(IERC20(asset));
    }

    /// @inheritdoc IERC7399
    function flashFee(address asset, uint256 amount) external view returns (uint256) {
        return amount <= _maxFlashLoan(IERC20(asset)) ? _flashFee(amount) : type(uint256).max;
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
        returns (bytes memory)
    {
        // Calculate the fee to charge for the loan
        uint256 fee_ = _flashFee(amount);

        // Transfer the loan to the loan receiver
        _serveLoan(loanReceiver, IERC20(asset), amount);

        // Call the callback on the callback receiver
        bytes memory result = callback(msg.sender, _repayTo(), asset, amount, fee_, data);

        // Verify and accept the repayment
        _acceptTransfer(IERC20(asset), fee_);

        emit Flash(IERC20(asset), amount, fee);

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
    /// @param asset The assets lent
    /// @return The maximum flash loan of `asset` that can be served.
    function _maxFlashLoan(IERC20 asset) internal view returns (uint256) {
        return reserves[asset];
    }

    /// @dev Transfer the loan to the loan receiver.
    /// @param loanReceiver The receiver of the loan assets.
    /// @param asset The assets lent
    /// @param amount The amount of assets lent.
    function _serveLoan(address loanReceiver, IERC20 asset, uint256 amount) internal {
        asset.transfer(loanReceiver, amount);
    }

    /// @dev Determine the repayment receiver.
    function _repayTo() internal view returns (address) {
        return address(this);
    }

    /// @dev Verify that the repayment happened. Make sure the repayment wasn't used for anything else.
    function _acceptTransfer(IERC20 asset, uint256 fee_) internal {
        uint256 expectedReserves = reserves[asset] + fee_;
        uint256 currentReserves = asset.balanceOf(address(this));
        
        // We do not accept donations for security reasons.
        // Excess assets can be removed by using `flash`.
        reserves[asset] = expectedReserves;

        if (currentReserves < expectedReserves) {
            revert InsufficientBalance({ expected: expectedReserves, balance: currentReserves });
        }
    }
}
