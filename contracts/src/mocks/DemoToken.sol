// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title DemoToken
/// @notice Testnet-only ERC-20 (`dSTOCK` 18 dec, `dUSD` 6 dec) with owner-managed minters (SPEC §13.3).
///         Demo tokens only — never a real security (SPEC §4.4).
contract DemoToken is ERC20, Ownable {
    uint8 private immutable _DECIMALS;

    /// @notice Addresses allowed to mint/burn (owner + e.g. MockIssuer).
    mapping(address => bool) public isMinter;

    /// @notice Caller is neither owner nor minter.
    error NotMinter();

    /// @notice Minter permission changed.
    event MinterSet(address indexed minter, bool allowed);

    /// @param name_ token name
    /// @param symbol_ token symbol
    /// @param decimals_ token decimals
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _DECIMALS = decimals_;
    }

    /// @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    /// @notice Grant or revoke minting rights.
    function setMinter(address minter, bool allowed) external onlyOwner {
        isMinter[minter] = allowed;
        emit MinterSet(minter, allowed);
    }

    /// @notice Mint `amount` to `to` (owner or minter).
    function mint(address to, uint256 amount) external {
        if (msg.sender != owner() && !isMinter[msg.sender]) revert NotMinter();
        _mint(to, amount);
    }

    /// @notice Burn `amount` from `from` (owner or minter).
    function burn(address from, uint256 amount) external {
        if (msg.sender != owner() && !isMinter[msg.sender]) revert NotMinter();
        _burn(from, amount);
    }
}
