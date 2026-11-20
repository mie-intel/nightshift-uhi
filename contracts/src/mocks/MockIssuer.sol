// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DemoToken} from "./DemoToken.sol";

/// @title MockIssuer
/// @notice Testnet stand-in for an issuer's 24/7 mint/redeem desk (SPEC §13.3, ADR-011). Mints/redeems `share`
///         against `quote` at an owner-set price. Its `Minted`/`Redeemed` events are the strongest witness (weight 5).
/// @dev Requires MINTER rights on `share`. Holds quote received from mints to pay redemptions.
contract MockIssuer is Ownable {
    /// @notice Share token (e.g. dSTOCK).
    DemoToken public immutable share;
    /// @notice Quote token (e.g. dUSD).
    DemoToken public immutable quote;
    /// @notice Raw quote units per 1e18 raw share units (e.g. 100e6 = 100 dUSD per dSTOCK).
    uint256 public price;
    /// @notice Corporate-action multiplier, 1e18 = 1×.
    uint256 public multiplier = 1e18;

    /// @notice Zero amount or price.
    error ZeroAmount();
    /// @notice ERC-20 transfer failed.
    error TransferFailed();

    /// @notice Shares minted against quote (issuer witness).
    event Minted(address indexed to, uint256 shares, uint256 quoteAmount);
    /// @notice Shares redeemed for quote (issuer witness).
    event Redeemed(address indexed from, uint256 shares, uint256 quoteAmount);
    /// @notice Corporate-action multiplier change (SPEC §12).
    event MultiplierUpdated(uint256 oldM, uint256 newM, uint256 effectiveAt);
    /// @notice Issuer price changed (not a witness — only executions are).
    event PriceSet(uint256 price);

    constructor(DemoToken share_, DemoToken quote_, uint256 price_) Ownable(msg.sender) {
        if (price_ == 0) revert ZeroAmount();
        share = share_;
        quote = quote_;
        price = price_;
        emit PriceSet(price_);
    }

    /// @notice Set the issuer price (raw quote per 1e18 raw shares).
    function setPrice(uint256 price_) external onlyOwner {
        if (price_ == 0) revert ZeroAmount();
        price = price_;
        emit PriceSet(price_);
    }

    /// @notice Set the corporate-action multiplier.
    function setMultiplier(uint256 newM) external onlyOwner {
        if (newM == 0) revert ZeroAmount();
        emit MultiplierUpdated(multiplier, newM, block.timestamp);
        multiplier = newM;
    }

    /// @notice Quote cost of `shares` at the current price (rounded up).
    function quoteFor(uint256 shares) public view returns (uint256) {
        return Math.mulDiv(shares, price, 1e18, Math.Rounding.Ceil);
    }

    /// @notice Pay quote, receive freshly minted shares.
    function mint(uint256 shares) external returns (uint256 quoteAmount) {
        if (shares == 0) revert ZeroAmount();
        quoteAmount = quoteFor(shares);
        if (!quote.transferFrom(msg.sender, address(this), quoteAmount)) revert TransferFailed();
        share.mint(msg.sender, shares);
        emit Minted(msg.sender, shares, quoteAmount);
    }

    /// @notice Burn shares, receive quote at the current price (rounded down).
    function redeem(uint256 shares) external returns (uint256 quoteAmount) {
        if (shares == 0) revert ZeroAmount();
        quoteAmount = Math.mulDiv(shares, price, 1e18);
        share.burn(msg.sender, shares);
        if (!quote.transfer(msg.sender, quoteAmount)) revert TransferFailed();
        emit Redeemed(msg.sender, shares, quoteAmount);
    }
}
