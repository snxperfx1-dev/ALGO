# Master Senseei v57 — Autonomous MT5 Expert Advisor (FULL ENGINE)

A hedge-fund-grade MetaTrader 5 Expert Advisor that ports the **complete** F16 Raptor v57 / Master Senseei TradingView engine (`../v57.txt`, a Pine Script v6 *indicator*) into a fully autonomous trading system — and renders the entire brain as a **living on-chart dashboard**.

> The original `v57.txt` is a **display-only** TradingView indicator: it analyses the market and draws panels but cannot trade. This project reconstructs the **whole analytical brain** in MQL5 — not just a trade trigger — and wraps it in an institutional execution + risk layer so it trades by itself in MT5.

---

## The full brain (every layer of the indicator)

All of this now runs inside the EA, recomputed on every closed bar:

| Indicator layer | MQL5 location |
|---|---|
| `f_phys` physics (velocity / acceleration / convexity / efficiency / displacement, impulse & decay, vd70/vd50) | `SenseeiEngine.mqh` |
| `f_se` fixed-TF structure engine (pivots, BOS/CHoCH, impulse-leg spawn, flip zone, invalidation, target, 14-state phase machine) per ladder rung | `RunSE()` / `ComputeWave()` |
| Adaptive 6-TF climbing ladder + **MTF curve map** | `BuildLadder()` + rung arrays in `Evaluate()` |
| Canonical wave **observation layer** (Expansion / Decay / Curvature / Absorption / Liquidity) | `ComputeCanonical()` |
| **Belief engine** (Expansion / Convexity / Creation / Absorption / Retracement / Demand-Return), EMA-smoothed | `ComputeCanonical()` |
| **Convexity maturity** + **dual waveProgress** (geometric × physical, smoothed) | `ComputeCanonical()` |
| **EDE / RE / EAE** — Energy Dissipation, Resolution (residual + resolved/partial/unresolved), Emergent Attractor (price + score) | `ComputeCanonical()` |
| **liqg** liquidation-wave overlay (induction / liquidity-grab sub-phases + target) | `ComputeCanonical()` |
| **F72 recursive CURVE TREE** — origin→extreme curve nodes, recursion depth, emergent node phase, ownership, migration band (0.5 / 0.618), HTF threat/runway, and the **"is the trade alive" LIFE score** | `ComputeCanonical()` → `SCurveTree` |
| **Time Intelligence Engine** (MN/W/D/H4/H1 bias stack, alignment/conflict, H1 timing) | `ComputeTimeEngine()` |
| **Node / FU authority network** (netBias, pressure/pdir, eligible nodes, open vs consumed memory, FEZ band) | `ComputeNodeNetwork()` |
| **Fractal stack** alignment (`stackDir` / `stackPct`) | `Evaluate()` |
| **Participant fib interference** zones (0.618 / 0.705 / 0.786 + flip) | `Evaluate()` |
| **Senseei meta-intelligence** — master vote, alignment, conflict, threat, confidence, opportunity, **action verdict**, timing, **intent**, **story** | `Evaluate()` → `SSenseeiResult` |
| **Attack sequence** (entry, invalidation stop, T1 / T2 / T3 objectives) | `ComputeCanonical()` |

The verdict matches the indicator: **ATTACK** requires `opportunity ∈ {STRONG, EXCEPTIONAL}`, `confidence ≥ MinConfidence`, `threat < MaxThreat`, master agreement, and (optionally) fractal-stack agreement + a live curve tree.

---

## Hedge-fund-grade execution & risk

- **Fixed-fractional sizing** from the real stop distance.
- **Daily-loss limit**, **max-drawdown circuit breaker**, **exposure caps** (positions + simultaneous risk), **spread guard**, broker stop-level / ATR stop floor.
- **Staged scale-outs**: close part at **T1** (→ move to break-even), part at **T2** (→ lock stop at T1), the runner rides to **T3** with an **ATR trailing** stop. A per-ticket state registry tracks each trade.
- Resilient order sends (retries + filling-mode probe), session / day filters.

---

## Files

```
MT5/
├── MasterSenseei.mq5     # main EA: trading loop + living dashboard (attach this)
├── SenseeiTypes.mqh      # shared data structures (the engine's vocabulary)
├── SenseeiEngine.mqh     # the full analytical brain (all layers above)
├── RiskManager.mqh       # capital protection & position sizing
├── TradeManager.mqh      # staged execution & trade management
└── README.md
```

All `.mqh` files must sit in the **same folder** as the `.mq5` (the includes use relative paths).

---

## The living dashboard

When attached, the EA prints a continuously-updating panel (and draws price levels) showing the whole brain in real time:

- **Verdict** — action, master direction, intent, one-line story, confidence/threat bars, opportunity, timing, alignment/conflict.
- **Wave lifecycle** — phase, wave progress, model fit, EDE energy state, resolution (residual/attractor), the six beliefs, the liqg overlay.
- **Curve tree** — alive nodes, depth/budget, owner direction + emergent phase + energy/trend, the **LIFE** score, the migration ownership band, and the HTF runway/threat.
- **MTF map** — direction of all six fractal rungs + stack score.
- **Time engine + node network** — HTF bias stack, H1 timing, netBias/pressure, open vs consumed nodes, eligible authority.
- **Participants** — 0.618 / 0.705 / 0.786 interference levels.
- **Plan + book + account** — entry/SL/T1/T2/T3, open positions, open risk, equity, day P&L, drawdown.

Chart lines (prefix `MS57_`): invalidation stop, T1/T2/T3, flip-zone, fib zones, curve-ownership band, attractor.

---

## Installation

1. Open **MetaEditor** (MT5 → Tools → MetaQuotes Language Editor).
2. Copy all five files into `MQL5/Experts/MasterSenseei/` (keep them together).
3. Open `MasterSenseei.mq5`, press **F7** to compile (expect 0 errors).
4. In MT5, enable **Algo Trading**, drag the EA onto a chart, and tick *Allow Algo Trading*.

**Recommended:** attach to **M5** or **M15**. Start with the default `RiskPerTradePct = 0.5%`. Always backtest and demo-forward-test first.

### Key inputs

| Input | Default | Purpose |
|---|---|---|
| `InpMinConfidence` | 55 | Confidence threshold to ATTACK |
| `InpMaxThreat` | 45 | Max threat to allow entry |
| `InpRequireStackAgree` | true | Require fractal stack to agree with master |
| `InpRequireTreeAlive` / `InpMinTreeLife` | true / 45 | Require a living curve tree to ATTACK |
| `InpManageExitOnResolve` | true | Close trades when the wave RESOLVES |
| `InpRiskPerTradePct` | 0.5 | Equity % risked per trade |
| `InpUseStagedTP` / `InpT1ClosePct` / `InpT2ClosePct` | true / 40 / 35 | Staged scale-out fractions |
| `InpMaxDailyLossPct` / `InpMaxDrawdownPct` | 3 / 15 | Capital circuit breakers |
| `InpDrawLevels` | true | Draw the curve-tree / fib / target lines |

---

## Important notes & limitations

- **Compile in MetaEditor (F7)** — MQL5 has no compiler in this environment, so the code is delivered ready-to-compile and was reviewed manually for correctness (array bounds, series indexing, complex-struct usage, CTrade API, new-bar gating on the last *closed* bar).
- The canonical lifecycle is computed on the **chart timeframe** (which is the indicator's canonical wave rung), iterating bar-by-bar over history to rebuild the EMA-smoothed beliefs, convexity maturity, dual wave progress, and the recursive curve tree — so the read is equivalent to the indicator's persisted state.
- This faithfully reconstructs the indicator's **tradeable + analytical logic**; the EA omits only the purely cosmetic Pine drawing primitives (boxes/labels/web edges), replacing them with an equivalent MT5 dashboard + chart lines.
- Trading leveraged instruments carries substantial risk. Test thoroughly on demo before any live deployment.
