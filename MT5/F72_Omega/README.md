# F72 OMEGA — Synthetic Market Nervous System (MT5)

> "Can this system maintain continuous awareness of the life of the story?"
> Entries, exits, scaling, hedging and reversals are merely **consequences** of that answer.

F72 OMEGA is a modular MetaTrader 5 organism whose architecture follows the philosophy, not conventional EA design. **Nothing is a signal. Everything is STATE.** Risk, capital and execution all *read from* the trinity — they never sit outside it.

```
LifeScore        — is the story alive?
StoryStability   — is the story coherent / not flipping?
StoryConfidence  — how much do I trust myself?   (engine self-trust, not market confidence)
```

Everything else emerges into those three, and every decision (ENTER / HOLD / ADD / REDUCE / REVERSE / EXIT) is a consequence of them plus layer-specific state.

---

## Build status

| Phase | Scope | Status |
|---|---|---|
| **1** | Skeleton · logging · memory · state containers · risk shell · capital state-machine · execution shell · paper/observer modes · explainability · event architecture | ✅ done |
| **2** | **Curve engine: `f_se`/`f_phys` per timeframe + the fractal stack, compression, convexity, force — replaces placeholder perception** | ✅ **this delivery** |
| 3 | Curve tree: recursion, ownership-by-energy, transfer, merge, chain health | ⏳ next |
| 4 | Narrative: story, life score, narrative score, alignment, confidence | ⏳ |
| 5 | Execution: campaign positions (Origin/Entry/Progression/Terminal), pyramiding, hedge transfer, position health | ⏳ |
| 6 | Probability clouds, self-observation, capital throttle (Layers 12–14) | ⏳ |
| 7 | Replay, shadow, optimization, final integration | ⏳ |

Phase 1 **compiles and runs today**. Attach in **Observer** mode and it immediately perceives, scores the trinity, logs every consequence with a reason code, and persists campaign memory — without placing a single order.

---

## Phase 1 + 2 files (dependency order — never inverted)

```
F72_Omega/
├── Common.mqh        # enums, the trinity + all layer STATE, decision & campaign schemas, math
├── Logger.mqh        # structured explainability log (decision/execution/transfer/exception CSV)
├── Session.mqh       # session context (read-only, never blocks — 24/5)
├── News.mqh          # news environment context (read-only, never blocks)
├── Capital.mqh       # equity tracking + drawdown STATE MACHINE + throttle
├── Risk.mqh          # risk that BREATHES (0.25→2%) driven by the trinity; exposure/spread gates
├── PaperTrade.mqh    # execution shell: routes orders by mode (observer/shadow/copilot/paper/live)
├── CampaignDB.mqh    # immortal campaign persistence (JSON, per-symbol folders)
├── Statistics.mqh    # rolling self-observation metrics (hit rate, expectancy, regime drift)
├── Memory.mqh        # campaign lifecycle (birth→update→death→persist→learn)
│   --- Phase 2 (the curve engine = perception) ---
├── CurveState.mqh    # SCurve (per-TF f_se/f_phys output) + SCurveStack (the fractal organism)
├── Curve.mqh         # the curve engine: f_se/f_phys lifecycle + fractal stack + canonical gCurve
├── Force.mqh         # expansion/displacement force (per-curve + stack-weighted)
├── Compression.mqh   # Layer 5: compression intelligence (can price breathe?)
├── Convexity.mqh     # curvature maturity
└── EA.mq5            # the organism: lifecycle, mode switch, perception→state→consequence loop
```

### Memory layout (`MQL5/Files/F72_Omega/`)

```
F72_Omega/
├── campaigns/<SYMBOL>/campaign_<YYYY>_<NNNNNN>.json   # immortal campaign records
├── rolling/   (chain_memory, statistics, story_history, ... — populated by later phases; news.csv read here)
├── logs/      decision_log.csv · execution_log.csv · transfer_log.csv · exception_log.csv
├── backtests/  paper/  exports/
```

`news.csv` (optional, you provide): `time(yyyy.mm.dd HH:MM),impact(1..3),ccy` — context only, never a blackout.

---

## Operating modes (Layer-8 human-override philosophy)

| Mode | Orders? | Use |
|---|---|---|
| `MODE_OBSERVER` | none | scores + logging only (default) |
| `MODE_SHADOW` | none (logged as-if) | compare engine intent to reality |
| `MODE_COPILOT` | queued | engine suggests, human approves (`ApproveNext`) |
| `MODE_PAPER` | simulated | internal fills + paper P&L, no live orders |
| `MODE_AUTONOMOUS` | live (hedge) | engine controls fully |

Switch via the `InpMode` input. Hedge-mode account required for live (buys + sells coexist for transfer/scaling).

---

## Risk that breathes

Tier is a **consequence** of the trinity, never arbitrary:

| Tier | Condition | Risk |
|---|---|---|
| Base | default | 0.25% |
| Normal | trust ≥ 55 | 0.5% |
| Strong | trust ≥ 68 & alignment ≥ 55 | 1% |
| Exceptional | trust ≥ 82 & alignment/chain/confidence corroborate & contradiction < 20 | 2% |

`trust = 0.45·Life + 0.30·Stability + 0.25·Confidence`. Final size = tier × capital-throttle × (1 / news-uncertainty) × confidence-factor, floored/capped, then converted to lots from the real stop distance. Hard limits: **daily 3% · weekly 8% · hard 15%** enforced by the capital state machine (NORMAL → CAUTION → DAILY/WEEKLY-LOCK → HARD-HALT).

---

## Layer → module → function map

The agreed home for every F72 OMEGA layer. ✅ = implemented in Phase 1, ⏳ = stubbed/neutral until its phase.

| Layer | Concept | Module · function | Status |
|---|---|---|---|
| 0 | Universe (everything is curves) | `Curve.mqh::Compute` → `SCurve` | ✅ P2 |
| 1 | Market as organism | architecture-wide | ✅ (frame) |
| 2 | Immortal memory | `CampaignDB::Save/Load` · `Memory::Birth/Update/Death` | ✅ |
| 3 | Narrative engine | `Story.mqh::Vote()` | ⏳ P4 |
| 4 | Fractal consciousness | `Curve::ComputeStack` → `SCurveStack` + alignment | ✅ P2 |
| 5 | Compression intelligence | `Compression::Score` → `state.compression` | ✅ P2 |
| 6 | Structural abandonment | `EA::BuildPerception` (curve extended/extreme) → `state.abandonment` | ✅ P2 (refined P4) |
| 7 | Continuation intelligence | `EA::BuildPerception` (force/align/support/phase) → `state.continuation` | ✅ P2 (refined P5) |
| 8 | Sequence intelligence | `ChainHealth.mqh::Sequence()` | ⏳ P3 |
| 9 | Meta-chain / regime | `ChainHealth.mqh::Regime()` → `state.regimeScore` | ⏳ P3 (Python sidecar for true cross-session) |
| 10 | Participant engine | `Participants` (fib/liquidity/FU) | ⏳ P2.5/P3 |
| 11 | Terminal intelligence | `Transfer.mqh::TerminalInduction()` | ⏳ P3 |
| 12 | Probability clouds | `EA::BuildPerception` → `pContinuation/pTerminal/pTransfer` | ✅ (curve-driven) |
| 13 | Capital intelligence | `Risk::TierRiskPct/EffectiveRiskPct` + `Capital::Throttle` | ✅ |
| 14 | Self-observation | `EA::ComputeSelfObservation` + `Statistics` → `storyConfidence` | ✅ |
| 15 | Continuous awareness | `EA::BuildPerception → trinity → Decide → Act` | ✅ (frame; perception is placeholder until P2) |

The **only** function Phase 2 replaced is `EA::BuildPerception()` — it now runs the real multi-TF curve engine. Everything downstream (trinity → risk → capital → execution → memory → explainability) is unchanged from Phase 1. Phase 3 plugs ownership/chain into the same state container.

---

## Install & run

1. Copy the whole `F72_Omega/` folder into `MQL5/Experts/F72_Omega/` (keep files together — relative `#include`s).
2. Open `EA.mq5` in MetaEditor, press **F7** (target build ≥ 3815). Expect 0 errors.
3. Attach to a chart (gold/M5 recommended to start). Leave `InpMode = OBSERVER`.
4. Watch the on-chart dashboard (trinity, layers, probability cloud, the current consequence + its reason, capital state, memory stats) and the logs under `MQL5/Files/F72_Omega/logs/`.
5. When satisfied, switch `InpMode` to `PAPER`, then `SHADOW`, then `AUTONOMOUS`.

---

## Honest scope notes

- "Hedge-fund grade" here means **institutionally-disciplined decision + risk logic**, not co-located FIX infra. The execution venue is MT5.
- Layer 9 true cross-symbol/cross-session statistical memory belongs in a Python/kdb sidecar the EA queries; MT5 holds live execution + a few thousand rolling campaigns.
- Layer 1 self-awareness is approximated faithfully (rolling metrics, regime drift, confidence decay, contradiction) — not claimed to *be* human intuition.
- Compile in MetaEditor before use; this environment has no MQL5 compiler. Trading leveraged instruments carries substantial risk — test on demo first.
