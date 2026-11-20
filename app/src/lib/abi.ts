import { parseAbi } from "viem";

/** Minimal ABIs (only what the dashboard calls) — keeps the bundle small. */

export const hookAbi = parseAbi([
  "function poolState(bytes32) view returns (int24 anchorTick, uint40 anchorUpdatedAt, uint16 riskBps, uint16 dispersionTicks, uint8 regime, uint64 lastSeq, bool curatedOnly, bool initialized, uint64 lastRegimeSeq)",
  "function quoteFee((address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) key, bool zeroForOne) view returns (uint24 fee, bool away)",
  "event AnchorUpdated(bytes32 indexed id, int24 anchorTick, uint16 riskBps, uint16 dispersionTicks, uint64 seq)",
  "event RegimeSet(bytes32 indexed id, uint8 regime, uint64 seq)",
  "event SwapObserved(bytes32 indexed id, int24 tickBefore, int24 tickAfter, uint24 fee, bool away)",
]);

export const poolManagerAbi = parseAbi(["function extsload(bytes32 slot) view returns (bytes32)"]);

export const reactiveAbi = parseAbi([
  "event CallbackRequested(uint8 indexed kind, uint64 seq, int24 anchorTick, uint16 riskBps, uint8 regime)",
  "struct WitnessSource { uint256 chainId; address emitter; uint256 topic0; uint256 topic1; uint8 kind; bool invert; int24 offsetTicks; uint16 weight; uint128 minNotional; uint32 maxAgeOpen; uint32 maxAgeClosed; bool enabled; }",
  "struct SourceState { int24 ewma; int24 lastRaw; uint40 lastSeen; }",
  "function sourceCount() view returns (uint256)",
  "function sourceAt(uint256 i) view returns (WitnessSource, SourceState)",
  "function quorum() view returns (bool)",
  "function anchor() view returns (int24)",
  "function riskBps() view returns (uint16)",
  "function regime() view returns (uint8)",
]);

export const issuerAbi = parseAbi([
  "function owner() view returns (address)",
  "function price() view returns (uint256)",
  "function setPrice(uint256 price_)",
  "function mint(uint256 shares) returns (uint256)",
  "event Minted(address indexed to, uint256 shares, uint256 quoteAmount)",
]);

export const erc20Abi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
]);

export const faucetAbi = parseAbi([
  "function claim()",
  "function nextClaimAt(address) view returns (uint256)",
  "function stockAmount() view returns (uint256)",
  "function usdAmount() view returns (uint256)",
]);

export const swapRouterAbi = parseAbi([
  "function swap((address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) key, (bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96) params, (bool takeClaims, bool settleUsingBurn) testSettings, bytes hookData) payable returns (int256)",
]);
