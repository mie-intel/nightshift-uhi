import { parseAbi } from "viem";

/** Minimal ABIs (only what the dashboard calls) — keeps the bundle small. */

export const hookAbi = parseAbi([
  "function poolState(bytes32) view returns (int24 anchorTick, uint40 anchorUpdatedAt, uint16 riskBps, uint16 dispersionTicks, uint8 regime, uint64 lastSeq, bool curatedOnly, bool initialized)",
  "function quoteFee((address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) key, bool zeroForOne) view returns (uint24 fee, bool away)",
  "event AnchorUpdated(bytes32 indexed id, int24 anchorTick, uint16 riskBps, uint16 dispersionTicks, uint64 seq)",
  "event SwapObserved(bytes32 indexed id, int24 tickBefore, int24 tickAfter, uint24 fee, bool away)",
]);

export const poolManagerAbi = parseAbi(["function extsload(bytes32 slot) view returns (bytes32)"]);

export const reactiveAbi = parseAbi([
  "event CallbackRequested(uint256 indexed destChainId, address indexed controller, uint64 seq, int24 anchorTick)",
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
