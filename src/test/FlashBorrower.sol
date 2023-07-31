// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC7399 } from "../interfaces/IERC7399.sol";

contract LoanReceiver {
    function retrieve(IERC20 asset) external {
        asset.transfer(msg.sender, asset.balanceOf(address(this)));
    }
}

contract FlashBorrower {
    IERC7399 lender;
    LoanReceiver loanReceiver;

    uint256 public flashBalance;
    address public flashInitiator;
    IERC20 public flashAsset;
    uint256 public flashAmount;
    uint256 public flashFee;

    constructor(IERC7399 lender_) {
        lender = lender_;
        loanReceiver = new LoanReceiver();
    }

    /// @dev ERC-3156++ Flash loan callback
    function onCallback(
        address initiator,
        address paymentReceiver,
        IERC20 asset,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    )
        external
        returns (bytes memory)
    {
        require(msg.sender == address(lender), "FlashBorrower: Untrusted lender");
        require(initiator == address(this), "FlashBorrower: External loan initiator");
        flashInitiator = initiator;
        flashAsset = asset;
        flashAmount = amount;
        flashFee = fee;
        loanReceiver.retrieve(asset);
        flashBalance = IERC20(asset).balanceOf(address(this));
        asset.transfer(paymentReceiver, amount + fee);

        return abi.encode(data, paymentReceiver, fee);
    }

    function onSteal(
        address initiator,
        address paymentReceiver,
        IERC20 asset,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    )
        external
        returns (bytes memory)
    {
        require(msg.sender == address(lender), "FlashBorrower: Untrusted lender");
        require(initiator == address(this), "FlashBorrower: External loan initiator");
        flashInitiator = initiator;
        flashAsset = asset;
        flashAmount = amount;
        flashFee = fee;

        // do nothing

        return abi.encode(data, paymentReceiver, fee);
    }

    function onReenter(
        address initiator,
        address paymentReceiver,
        IERC20 asset,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    )
        external
        returns (bytes memory)
    {
        require(msg.sender == address(lender), "FlashBorrower: Untrusted lender");
        require(initiator == address(this), "FlashBorrower: External loan initiator");
        flashInitiator = initiator;
        flashAsset = asset;
        loanReceiver.retrieve(asset);

        flashBorrow(asset, amount * 2);

        asset.transfer(paymentReceiver, amount + fee);

        // flashBorrow will have initialized these
        flashAmount += amount;
        flashFee += fee;

        return abi.encode(data, paymentReceiver, fee);
    }

    function flashBorrow(IERC20 asset, uint256 amount) public returns (bytes memory) {
        return lender.flash(address(loanReceiver), asset, amount, "", this.onCallback);
    }

    function flashBorrowAndSteal(IERC20 asset, uint256 amount) public returns (bytes memory) {
        return lender.flash(address(loanReceiver), asset, amount, "", this.onSteal);
    }

    function flashBorrowAndReenter(IERC20 asset, uint256 amount) public returns (bytes memory) {
        return lender.flash(address(loanReceiver), asset, amount, "", this.onReenter);
    }
}
