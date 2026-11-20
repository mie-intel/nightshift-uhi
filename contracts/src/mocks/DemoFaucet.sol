// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DemoToken} from "./DemoToken.sol";

/// @title DemoFaucet
/// @notice Testnet-only: anyone can claim a fixed amount of demo dSTOCK + dUSD once per cooldown, so judges can try
///         swaps from the dashboard. Requires MINTER rights on both tokens. Demo tokens only (SPEC §4.4).
contract DemoFaucet {
    /// @notice Demo stock token.
    DemoToken public immutable stock;
    /// @notice Demo quote token.
    DemoToken public immutable usd;
    /// @notice dSTOCK per claim (raw units).
    uint256 public immutable stockAmount;
    /// @notice dUSD per claim (raw units).
    uint256 public immutable usdAmount;
    /// @notice Seconds between claims per address.
    uint256 public immutable cooldown;
    /// @notice Last claim time per address.
    mapping(address => uint256) public lastClaim;

    /// @notice Claimed again before the cooldown ended.
    error TooSoon(uint256 nextAt);

    /// @notice Tokens sent.
    event Claimed(address indexed to, uint256 stockAmount, uint256 usdAmount);

    constructor(DemoToken stock_, DemoToken usd_, uint256 stockAmount_, uint256 usdAmount_, uint256 cooldown_) {
        stock = stock_;
        usd = usd_;
        stockAmount = stockAmount_;
        usdAmount = usdAmount_;
        cooldown = cooldown_;
    }

    /// @notice Earliest time `who` can claim (0 = now).
    function nextClaimAt(address who) public view returns (uint256) {
        uint256 last = lastClaim[who];
        return last == 0 ? 0 : last + cooldown;
    }

    /// @notice Mint the demo amounts to the caller.
    function claim() external {
        uint256 next = nextClaimAt(msg.sender);
        if (block.timestamp < next) revert TooSoon(next);
        lastClaim[msg.sender] = block.timestamp;
        stock.mint(msg.sender, stockAmount);
        usd.mint(msg.sender, usdAmount);
        emit Claimed(msg.sender, stockAmount, usdAmount);
    }
}
