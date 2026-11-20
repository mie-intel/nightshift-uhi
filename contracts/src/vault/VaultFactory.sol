// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {NightShiftVault} from "./NightShiftVault.sol";
import {Mandate} from "../libraries/Types.sol";

/// @notice Controller registry surface used by the factory.
interface IVaultRegistry {
    function addVault(bytes32 poolId, address vault) external;
}

/// @title VaultFactory
/// @notice Anyone can become a curator: deploy a vault for the NightShift pool with a mandate; the vault is registered
///         with the Controller so Reactive callbacks drive it (SPEC §10.4, ADR-018).
contract VaultFactory {
    /// @notice v4 PoolManager.
    IPoolManager public immutable poolManager;
    /// @notice Controller (registry + caller of vault rebalance/snapshot/reconcile).
    address public immutable controller;
    PoolKey internal _key;

    /// @notice All vaults created.
    address[] public vaults;

    /// @notice New curator vault.
    event VaultCreated(address indexed vault, address indexed curator, string name, uint16 perfFeeBps);

    constructor(IPoolManager poolManager_, PoolKey memory key_, address controller_) {
        poolManager = poolManager_;
        _key = key_;
        controller = controller_;
    }

    /// @notice Deploy a vault where msg.sender is the curator.
    function create(Mandate calldata mandate_, string calldata name_, string calldata symbol_)
        external
        returns (address vault)
    {
        vault = address(new NightShiftVault(poolManager, _key, controller, msg.sender, mandate_, name_, symbol_));
        vaults.push(vault);
        IVaultRegistry(controller).addVault(PoolId.unwrap(_key.toId()), vault);
        emit VaultCreated(vault, msg.sender, name_, mandate_.perfFeeBps);
    }

    /// @notice Number of vaults created.
    function vaultCount() external view returns (uint256) {
        return vaults.length;
    }
}
