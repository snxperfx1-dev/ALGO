# Master Senseei v57 — Autonomous MT5 Expert Advisor

A hedge-fund-grade MetaTrader 5 Expert Advisor (EA) that ports the **F16 Raptor v57 / Master Senseei** TradingView engine (`../v57.txt`, a Pine Script v6 *indicator*) into a fully autonomous trading system that places, manages, and protects its own trades.

> The original `v57.txt` is a **display-only** TradingView indicator — it analyses the market and draws panels but cannot trade. This project reconstructs its tradeable core in MQL5 and wraps it in an institutional-grade execution and risk layer so it can trade by itself in MT5.

---

## What was ported

| Pine concept (`v57.txt`) | MQL5 implementation |
|---|---|
| `f_phys` physics (velocity / acceleration / convexity / efficiency / displacement, impulse & decay) | `SenseeiEngine.mqh` → iterative per-bar physics inside `ComputeWave()` |
| `f_se` fixed-TF structure engine (pivots, BOS/CHoCH, impulse-leg spawn, flip zone, invalidation, target, 14-state phase machine, wave progress) | `ComputeWave()` — bar-by-bar stateful reconstruction |
| Adaptive 6-TF ladder (M1·M3·chart·M15·H1·H4, climbs above H1) | `BuildLadder()` |
| Fractal stack alignment (`fractalStackDir` / `stackPct`) | `Evaluate()` |
| Node / FU bias network (`netBias`, `pressure`/`pdir`) | `ComputeFU()` + `Evaluate()` |
| Energy framework (resolution / residual / attractor) | `ComputeEnergy()` |
| Senseei meta-intelligence (`master`, `alignment`, `conflict`, `threat`, `confidence`, `oppScore`, `opportunity`, `action`) | `Evaluate()` → `SSenseeiResult` |
| Trade geometry: stop = wave **invalidation**, target = wave **objective**, entry zone = **flip zone** | consumed by `MasterSenseei.mq5` |

The verdict logic matches the indicator: an **ATTACK** requires `opportunity ∈ {STRONG, EXCEPTIONAL}`, `confidence ≥ MinConfidence`, and `threat < MaxThreat`, with `master` direction agreement.

---

## Hedge-fund-grade additions (not in the indicator)

These are the components that make it *tradeable by itself*, safely:

- **Fixed-fractional position sizing** from the actual stop distance (`RiskManager.mqh`).
- **Daily loss limit** — halts new trades for the rest of the day after a configurable drawdown.
- **Max-drawdown circuit breaker** — halts the EA on equity-peak drawdown.
- **Exposure caps** — max concurrent positions and max simultaneous open risk (%).
- **Spread guard** + broker **stop-level / ATR floor** on stops.
- **Execution resilience** — order sends retried with automatic filling-mode probing (`TradeManager.mqh`).
- **In-trade management** — partial take-profit scale-out, break-even move, ATR trailing stop.
- **Session / day filters** — optional trading-hours window, Friday cut-off, weekend safety.
- **Live on-chart dashboard** of the full Senseei read.

---

## Files

```
MT5/
├── MasterSenseei.mq5     # main Expert Advisor (attach this to a chart)
├── SenseeiEngine.mqh     # signal engine (f_phys + f_se + stack + FU + meta-intelligence)
├── RiskManager.mqh       # capital protection & position sizing
├── TradeManager.mqh      # order execution & trade management
└── README.md
```

---

## Installation

1. Open **MetaEditor** (MetaTrader 5 → Tools → MetaQuotes Language Editor).
2. Copy all four files into your terminal's data folder, keeping them **together**:
   - `MQL5/Experts/MasterSenseei/MasterSenseei.mq5`
   - `MQL5/Experts/MasterSenseei/SenseeiEngine.mqh`
   - `MQL5/Experts/MasterSenseei/RiskManager.mqh`
   - `MQL5/Experts/MasterSenseei/TradeManager.mqh`
   
   (The `.mqh` includes use relative `#include "..."`, so they must sit in the same folder as the `.mq5`.)
3. In MetaEditor, open `MasterSenseei.mq5` and press **F7** to compile. It should compile with 0 errors.
4. In MT5, enable **Algo Trading** (the toolbar button) and drag the EA onto a chart. Tick *Allow Algo Trading* in the dialog.

---

## Recommended usage

- **Timeframe:** attach to **M5** or **M15** (the canonical wave rung is the chart timeframe). M1 is supported but noisier.
- **Symbols:** designed for FX majors, indices, and metals. Always verify tick value / contract size per symbol.
- **Always backtest and forward-test on a demo account first.** Start with the default `RiskPerTradePct = 0.5%`.

### Key inputs

| Input | Default | Purpose |
|---|---|---|
| `InpMinConfidence` | 55 | Confidence threshold to ATTACK (mirrors Pine `minConf`) |
| `InpMaxThreat` | 45 | Max threat to allow an entry |
| `InpRequireStackAgree` | true | Require fractal stack to agree with master direction |
| `InpRiskPerTradePct` | 0.5 | Equity % risked per trade |
| `InpMaxDailyLossPct` | 3.0 | Daily loss halt |
| `InpMaxDrawdownPct` | 15.0 | Equity-peak drawdown breaker |
| `InpMaxOpenPositions` | 2 | Concurrent position cap |
| `InpStopATRpad` | 0.5 | Extra ATR padding beyond the wave invalidation |
| `InpTargetRR` | 2.0 | Fallback reward:risk if the engine target is unavailable |
| `InpUsePartialTP` / `InpUseBreakEven` / `InpUseTrailing` | true | Trade-management modules |

---

## How it decides (per closed bar)

1. Build the 6-timeframe wave stack and the node/FU bias.
2. Compute master direction (vote of wave dir + stack dir + net bias + pressure).
3. Score alignment, conflict, threat, confidence, opportunity (the Senseei meta-intelligence).
4. If the verdict is **ATTACK** and all risk gates pass → open a trade sized to risk, with:
   - **Stop** = wave invalidation (padded by ATR, floored to broker/ATR minimums).
   - **Target** = wave objective (or `TargetRR` fallback).
5. On **MANAGE / EXIT** (wave resolved) → close to lock the move.
6. Every tick → maintain break-even, partial TP, and ATR trailing on open trades.

---

## Important notes & limitations

- This is a faithful **reconstruction** of the indicator's tradeable logic, not a byte-for-byte port — the original is 2,654 lines of mostly display code. The signal *decision layer* matches; the energy `residual`/`attractor` terms are reconstructed as faithful proxies from the canonical wave phase and geometry.
- MQL5 cannot be compiled in this environment; **compile in MetaEditor** before use.
- Past performance does not guarantee future results. Trading leveraged instruments carries substantial risk. Use sensible risk settings and test thoroughly on demo before any live deployment.
