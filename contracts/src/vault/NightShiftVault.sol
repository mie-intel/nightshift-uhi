// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import {INightShiftVault} from "../interfaces/INightShiftVault.sol";
import {Mandate, Regime, RegimeMandate} from "../libraries/Types.sol";

/// @title NightShiftVault
/// @notice One curator, one pool. Depositors follow the curator; the Controller (fed by Reactive) moves the
///         liquidity onto the witnessed fair price — between trades — per the curator's per-regime mandate
///         (SPEC §10). At the reopen the epoch is scored vs HODL at the witnessed open tick; the curator earns a
///         performance fee only on alpha above the high-water mark (SPEC §11).
/// @dev MVP (ADR-018): a single concentrated position + idle balances. Flows are in-kind and pro-rata, so no price
///      is needed to deposit/withdraw (no stale-NAV games). The vault never swaps. The curator cannot move funds,
///      pick ticks or change the mandate after deployment. Values are in currency1 units.
contract NightShiftVault is ERC20, ReentrancyGuard, IUnlockCallback, INightShiftVault {
    using SafeERC20 for IERC20;
    using CurrencySettler for Currency;
    using StateLibrary for IPoolManager;
    using SafeCast for uint256;

    /// @notice Hard cap on the performance fee (20%).
    uint16 public constant MAX_PERF_FEE = 2000;
    uint256 private constant WAD = 1e18;

    /// @notice v4 PoolManager.
    IPoolManager public immutable poolManager;
    /// @notice Only caller of rebalance/snapshot/reconcile.
    address public immutable controller;
    /// @notice Curator (receives performance-fee shares; no other powers).
    address public immutable curator;
    /// @notice Pool id.
    PoolId public immutable poolId;

    PoolKey internal _key;
    Mandate internal _mandate;

    /// @notice Current position range and liquidity (0 = parked in idle).
    int24 public lower;
    int24 public upper;
    uint128 public liquidity;

    /// @notice Per-share composition snapshot at close (WAD-scaled raw token amounts per share).
    uint64 public snapshotEpoch;
    uint256 public snap0PerShare;
    uint256 public snap1PerShare;
    bool public snapshotOpen;

    /// @notice Cumulative alpha per share vs HODL (currency1 units, WAD-scaled) and its high-water mark.
    int256 public cumAlpha;
    int256 public hwm;
    /// @notice Epochs scored.
    uint64 public epochsPlayed;
    /// @notice Last epoch's alpha per share (currency1, WAD).
    int256 public lastAlpha;

    /// @notice Caller is not the Controller.
    error NotController();
    /// @notice Not the PoolManager.
    error NotPoolManager();
    /// @notice Perf fee above MAX_PERF_FEE.
    error PerfFeeTooHigh();
    /// @notice Slippage / zero-amount guard.
    error InsufficientOutput();
    /// @notice First deposit must include both tokens.
    error ZeroAmount();

    event Deposited(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);
    event Withdrawn(address indexed owner, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);
    event Rebalanced(int24 lower, int24 upper, uint128 liquidity, int24 anchorTick, uint16 riskBps, Regime regime);
    event RebalanceSkipped(int24 center, uint16 riskBps);
    event Exited(uint16 riskBps);
    event SnapshotTaken(uint64 indexed epochId, uint256 amount0PerShare, uint256 amount1PerShare);
    event EpochReconciled(
        uint64 indexed epochId,
        int24 openTick,
        int256 navPerShare,
        int256 hodlPerShare,
        int256 alphaPerShare,
        int256 cumAlpha,
        uint256 perfFeeShares,
        bool degraded
    );

    constructor(
        IPoolManager poolManager_,
        PoolKey memory key_,
        address controller_,
        address curator_,
        Mandate memory mandate_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        if (mandate_.perfFeeBps > MAX_PERF_FEE) revert PerfFeeTooHigh();
        poolManager = poolManager_;
        _key = key_;
        poolId = key_.toId();
        controller = controller_;
        curator = curator_;
        _mandate = mandate_;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert NotController();
        _;
    }

    // ---------------------------------------------------------------- views

    /// @notice Pool key.
    function key() external view returns (PoolKey memory) {
        return _key;
    }

    /// @notice Curator mandate (fixed at deployment in this build).
    function mandate() external view returns (Mandate memory) {
        return _mandate;
    }

    /// @notice Total token amounts held (position valued at the current pool price + idle).
    function totals() public view returns (uint256 t0, uint256 t1) {
        (uint160 sqrtP,,,) = poolManager.getSlot0(poolId);
        (t0, t1) = _positionAmounts(sqrtP);
        t0 += _balance0();
        t1 += _balance1();
    }

    /// @notice Net asset value of the whole vault at `tick`, in currency1 raw units.
    function navAt(int24 tick) public view returns (uint256) {
        uint160 s = TickMath.getSqrtPriceAtTick(tick);
        (uint256 p0, uint256 p1) = _positionAmounts(s);
        return _value(p0 + _balance0(), p1 + _balance1(), s);
    }

    // ---------------------------------------------------------------- depositor flows (in-kind, pro-rata)

    /// @notice Deposit up to `amount0Max`/`amount1Max` at the vault's current composition; excess is not taken.
    function deposit(uint256 amount0Max, uint256 amount1Max, uint256 minShares, address to)
        external
        nonReentrant
        returns (uint256 shares, uint256 amount0, uint256 amount1)
    {
        uint256 supply = totalSupply();
        if (supply == 0) {
            if (amount0Max == 0 || amount1Max == 0) revert ZeroAmount();
            (amount0, amount1) = (amount0Max, amount1Max);
            shares = Math.sqrt(amount0 * amount1);
        } else {
            (uint256 t0, uint256 t1) = totals();
            uint256 s0 = t0 == 0 ? type(uint256).max : FullMath.mulDiv(amount0Max, supply, t0);
            uint256 s1 = t1 == 0 ? type(uint256).max : FullMath.mulDiv(amount1Max, supply, t1);
            shares = s0 < s1 ? s0 : s1;
            amount0 = t0 == 0 ? 0 : FullMath.mulDivRoundingUp(shares, t0, supply);
            amount1 = t1 == 0 ? 0 : FullMath.mulDivRoundingUp(shares, t1, supply);
        }
        if (shares == 0 || shares < minShares) revert InsufficientOutput();
        if (amount0 > 0) IERC20(Currency.unwrap(_key.currency0)).safeTransferFrom(msg.sender, address(this), amount0);
        if (amount1 > 0) IERC20(Currency.unwrap(_key.currency1)).safeTransferFrom(msg.sender, address(this), amount1);
        _mint(to, shares);
        emit Deposited(msg.sender, to, shares, amount0, amount1);
    }

    /// @notice Burn `shares` for the pro-rata share of the position (incl. collected fees) and idle balances.
    function withdraw(uint256 shares, uint256 amount0Min, uint256 amount1Min, address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 supply = totalSupply();
        if (shares == 0 || shares > supply) revert InsufficientOutput();
        uint256 b0 = _balance0();
        uint256 b1 = _balance1();
        if (liquidity > 0) {
            uint128 cut = uint256(FullMath.mulDiv(liquidity, shares, supply)).toUint128();
            if (cut > 0) {
                _modify(lower, upper, -int256(uint256(cut)));
                liquidity -= cut;
            }
        }
        amount0 = FullMath.mulDiv(b0, shares, supply) + (_balance0() - b0);
        amount1 = FullMath.mulDiv(b1, shares, supply) + (_balance1() - b1);
        if (amount0 < amount0Min || amount1 < amount1Min) revert InsufficientOutput();
        _burn(msg.sender, shares);
        if (amount0 > 0) IERC20(Currency.unwrap(_key.currency0)).safeTransfer(to, amount0);
        if (amount1 > 0) IERC20(Currency.unwrap(_key.currency1)).safeTransfer(to, amount1);
        emit Withdrawn(msg.sender, to, shares, amount0, amount1);
    }

    // ---------------------------------------------------------------- controller (Reactive-fed)

    /// @inheritdoc INightShiftVault
    function rebalance(int24 anchorTick, uint16 riskBps, Regime regime) external onlyController nonReentrant {
        RegimeMandate memory m = _mandateFor(regime);
        if (riskBps >= m.exitRiskBps) {
            _removeAll();
            emit Exited(riskBps);
            return;
        }
        (, int24 tick,,) = poolManager.getSlot0(poolId);
        int24 center = int24(int256(tick) + (int256(anchorTick) - tick) * int256(uint256(m.followBps)) / 10_000);
        uint256 half = uint256(m.coreHalfWidth) * (1e8 + uint256(m.riskWidenBps) * riskBps) / 1e8;
        (int24 lo, int24 hi) = _range(center, half);
        if (liquidity > 0) {
            int24 cur = int24((int256(lower) + upper) / 2);
            uint256 moved = center >= cur ? uint256(int256(center) - cur) : uint256(int256(cur) - center);
            // rounding to tickSpacing can shift the width by one spacing as the center moves; ignore that
            int256 dw = int256(hi - lo) - int256(upper - lower);
            bool sameWidth = (dw >= 0 ? dw : -dw) <= _key.tickSpacing;
            if (moved < m.recenterThreshold && sameWidth) {
                emit RebalanceSkipped(center, riskBps);
                return;
            }
        }
        _removeAll();
        (uint160 sqrtP,,,) = poolManager.getSlot0(poolId);
        uint128 l = LiquidityAmounts.getLiquidityForAmounts(
            sqrtP, TickMath.getSqrtPriceAtTick(lo), TickMath.getSqrtPriceAtTick(hi), _balance0(), _balance1()
        );
        if (l > 0) {
            // leave 1 wei of dust headroom for rounding in the PoolManager
            l = l > 1 ? l - 1 : l;
            _modify(lo, hi, int256(uint256(l)));
        }
        (lower, upper, liquidity) = (lo, hi, l);
        emit Rebalanced(lo, hi, l, anchorTick, riskBps, regime);
    }

    /// @inheritdoc INightShiftVault
    function snapshotClose(uint64 epochId) external onlyController nonReentrant {
        uint256 supply = totalSupply();
        if (supply == 0) return;
        _collect();
        (uint256 t0, uint256 t1) = totals();
        snap0PerShare = FullMath.mulDiv(t0, WAD, supply);
        snap1PerShare = FullMath.mulDiv(t1, WAD, supply);
        snapshotEpoch = epochId;
        snapshotOpen = true;
        emit SnapshotTaken(epochId, snap0PerShare, snap1PerShare);
    }

    /// @inheritdoc INightShiftVault
    function reconcile(uint64 epochId, int24 openTick, bool degraded) external onlyController nonReentrant {
        uint256 supply = totalSupply();
        if (!snapshotOpen || supply == 0) return;
        snapshotOpen = false;
        _collect();
        uint160 s = TickMath.getSqrtPriceAtTick(openTick);
        int256 nav = int256(FullMath.mulDiv(navAt(openTick), WAD, supply));
        int256 hodl = int256(_value(snap0PerShare, snap1PerShare, s));
        int256 alpha = nav - hodl;
        lastAlpha = alpha;
        cumAlpha += alpha;
        ++epochsPlayed;
        uint256 feeShares;
        if (cumAlpha > hwm) {
            // curator earns perfFeeBps of the new alpha, paid by minting shares at the open NAV
            uint256 feePerShare = uint256(cumAlpha - hwm) * _mandate.perfFeeBps / 10_000;
            if (feePerShare > 0 && uint256(nav) > feePerShare) {
                feeShares = FullMath.mulDiv(supply, feePerShare, uint256(nav) - feePerShare);
                _mint(curator, feeShares);
            }
            hwm = cumAlpha;
        }
        emit EpochReconciled(epochId, openTick, nav, hodl, alpha, cumAlpha, feeShares, degraded);
    }

    // ---------------------------------------------------------------- PoolManager

    /// @notice Settle a modifyLiquidity inside the PoolManager lock. Only the PoolManager.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (int24 lo, int24 hi, int256 delta) = abi.decode(data, (int24, int24, int256));
        (BalanceDelta callerDelta,) =
            poolManager.modifyLiquidity(_key, ModifyLiquidityParams(lo, hi, delta, bytes32(0)), "");
        _settle(_key.currency0, callerDelta.amount0());
        _settle(_key.currency1, callerDelta.amount1());
        return "";
    }

    // ---------------------------------------------------------------- internals

    function _settle(Currency c, int128 amount) internal {
        if (amount < 0) c.settle(poolManager, address(this), uint256(uint128(-amount)), false);
        else if (amount > 0) c.take(poolManager, address(this), uint256(uint128(amount)), false);
    }

    function _modify(int24 lo, int24 hi, int256 delta) internal {
        poolManager.unlock(abi.encode(lo, hi, delta));
    }

    function _removeAll() internal {
        if (liquidity == 0) return;
        _modify(lower, upper, -int256(uint256(liquidity)));
        liquidity = 0;
    }

    /// @dev Zero-delta modify collects accrued fees into the vault.
    function _collect() internal {
        if (liquidity > 0) _modify(lower, upper, 0);
    }

    function _mandateFor(Regime r) internal view returns (RegimeMandate memory) {
        if (r == Regime.OPEN) return _mandate.open;
        if (r == Regime.REOPEN_PENDING) return _mandate.reopen;
        return _mandate.closed;
    }

    function _range(int24 center, uint256 half) internal view returns (int24 lo, int24 hi) {
        int24 sp = _key.tickSpacing;
        int256 l = int256(center) - int256(half);
        int256 h = int256(center) + int256(half);
        int256 minT = TickMath.minUsableTick(sp);
        int256 maxT = TickMath.maxUsableTick(sp);
        l = l < minT ? minT : l;
        h = h > maxT ? maxT : h;
        int256 q = l / sp;
        if (l < 0 && l % sp != 0) --q;
        lo = int24(q * sp);
        int256 r = h / sp;
        if (h < 0 && h % sp != 0) --r;
        hi = int24((r + 1) * sp);
        if (hi > maxT) hi = int24(maxT);
        if (hi <= lo) hi = lo + sp;
    }

    function _positionAmounts(uint160 sqrtP) internal view returns (uint256 a0, uint256 a1) {
        if (liquidity == 0) return (0, 0);
        uint160 sa = TickMath.getSqrtPriceAtTick(lower);
        uint160 sb = TickMath.getSqrtPriceAtTick(upper);
        if (sqrtP <= sa) {
            a0 = SqrtPriceMath.getAmount0Delta(sa, sb, liquidity, false);
        } else if (sqrtP < sb) {
            a0 = SqrtPriceMath.getAmount0Delta(sqrtP, sb, liquidity, false);
            a1 = SqrtPriceMath.getAmount1Delta(sa, sqrtP, liquidity, false);
        } else {
            a1 = SqrtPriceMath.getAmount1Delta(sa, sb, liquidity, false);
        }
    }

    /// @dev a0·P + a1 with P = (sqrtP/2^96)^2, in currency1 units.
    function _value(uint256 a0, uint256 a1, uint160 sqrtP) internal pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(a0, sqrtP, 1 << 96), sqrtP, 1 << 96) + a1;
    }

    function _balance0() internal view returns (uint256) {
        return IERC20(Currency.unwrap(_key.currency0)).balanceOf(address(this));
    }

    function _balance1() internal view returns (uint256) {
        return IERC20(Currency.unwrap(_key.currency1)).balanceOf(address(this));
    }
}
