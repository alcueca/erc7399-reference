// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "erc7399/IERC7399.sol";

import { IERC20 } from "./interfaces/IERC20.sol";
import { UnsupportedToken, InsufficientBalance } from "./lib/Errors.sol";

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

    /// @inheritdoc IERC7399
    function maxFlashLoan(address token) external view returns (uint256) {
        _supportedToken(token);
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IERC7399
    function flashFee(address token, uint256 amount) external view returns (uint256) {
        return _flashFee(_supportedToken(token), amount);
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
        AssetData memory assetData = _supportedToken(asset);
        uint256 _fee = _flashFee(assetData, amount);
        uint256 _before = IERC20(asset).balanceOf(address(this));

        IERC20(asset).transfer(loanReceiver, amount);
        bytes memory result = callback(msg.sender, address(this), asset, amount, _fee, data);

        if (IERC20(asset).balanceOf(address(this)) < _before + _fee) {
            revert InsufficientBalance({ expected: _before + _fee, balance: IERC20(asset).balanceOf(address(this)) });
        }

        return result;
    }

    /// @dev The fee to be charged for a given loan. Assumes that the loan is possible.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal.
    function _flashFee(AssetData memory assetData, uint256 amount) internal pure returns (uint256) {
        return amount * assetData.fee / 10_000;
    }

    function _supportedToken(address token) internal view returns (AssetData memory assetData) {
        assetData = assets[IERC20(token)];
        if (!assets[IERC20(token)].supported) {
            revert UnsupportedToken(token);
        }
    }
}
