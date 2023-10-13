// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "erc7399/IERC7399.sol";

import { IERC20 } from "src/interfaces/IERC20.sol";

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
    address public flashAsset;
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
        address asset,
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
        loanReceiver.retrieve(IERC20(asset));
        flashBalance = IERC20(asset).balanceOf(address(this));
        IERC20(asset).transfer(paymentReceiver, amount + fee);

        return abi.encode(data, paymentReceiver, fee);
    }

    function onSteal(
        address initiator,
        address paymentReceiver,
        address asset,
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
        address asset,
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
        loanReceiver.retrieve(IERC20(asset));

        flashBorrow(asset, amount * 2);

        IERC20(asset).transfer(paymentReceiver, amount + fee);

        // flashBorrow will have initialized these
        flashAmount += amount;
        flashFee += fee;

        return abi.encode(data, paymentReceiver, fee);
    }

    function flashBorrow(address asset, uint256 amount) public returns (bytes memory) {
        return lender.flash(address(loanReceiver), asset, amount, "", this.onCallback);
    }

    function flashBorrowAndSteal(address asset, uint256 amount) public returns (bytes memory) {
        return lender.flash(address(loanReceiver), asset, amount, "", this.onSteal);
    }

    function flashBorrowAndReenter(address asset, uint256 amount) public returns (bytes memory) {
        return lender.flash(address(loanReceiver), asset, amount, "", this.onReenter);
    }
}
