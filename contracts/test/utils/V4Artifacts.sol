// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// PoolManager pins `pragma solidity 0.8.26` while reactive-lib-omni needs ^0.8.29, so no single test file can
// import both. This file only forces the PoolManager artifact to be built; fixtures deploy it with deployCode.
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
