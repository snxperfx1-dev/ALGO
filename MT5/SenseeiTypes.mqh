//+------------------------------------------------------------------+
//|                                               SenseeiTypes.mqh    |
//|  Shared data structures for the Master Senseei engine port.      |
//|  Split out so the engine, EA, and dashboard share one vocabulary.|
//+------------------------------------------------------------------+
#ifndef __SENSEEI_TYPES_MQH__
#define __SENSEEI_TYPES_MQH__
#property strict

//==================================================================
// ENGINE CONFIGURATION (mirrors the Pine inputs that drive signal)
//==================================================================
struct SEngineConfig
{
   // f_se / f_phys
   int    pivotLen;        // Pivot Length            (Pine: 5)
   int    atrLen;          // ATR Length              (Pine: 14)
   int    effLen;          // Efficiency Lookback     (Pine: 10)
   int    structLen;       // Structure Pivot Length  (Pine: 10)
   double impulseAtrMult;  // Impulse ATR Multiple    (Pine: 1.5)
   double effThresh;       // Efficiency Threshold    (Pine: 0.65)
   double dispThresh;      // Displacement ATR Thresh (Pine: 1.5)
   double convMult;        // Convexity ATR Multiplier(Pine: 0.01)
   double chochBufferATR;  // CHoCH Buffer (ATR)      (Pine: 0.75)
   bool   useStrictStruct; // Use Strict Structure    (Pine: true)
   int    beliefSmooth;    // Belief EMA Smoothing    (Pine: 3)
   int    liqSweepLook;    // Sweep Lookback Bars     (Pine: 10)
   // node / FU engine
   double wickFrac;        // FU spike min wick/range (Pine: 0.30)
   int    fuLookback;      // FU structure lookback   (Pine: 3)
   int    authMin;         // Min node authority      (Pine: 45)
   int    nodeScanBars;    // bars scanned for FU nodes per TF
   // meta-intelligence
   int    minConf;         // Min confidence to ATTACK(Pine: 55)
   // engine window
   int    historyBars;     // bars to iterate per TF for state build
   int    curveCtx;        // 0 = chart wave, 1 = higher TF, 2 = highest TF
};

void EngineConfigDefaults(SEngineConfig &c)
{
   c.pivotLen       = 5;
   c.atrLen         = 14;
   c.effLen         = 10;
   c.structLen      = 10;
   c.impulseAtrMult = 1.5;
   c.effThresh      = 0.65;
   c.dispThresh     = 1.5;
   c.convMult       = 0.01;
   c.chochBufferATR = 0.75;
   c.useStrictStruct= true;
   c.beliefSmooth   = 3;
   c.liqSweepLook   = 10;
   c.wickFrac       = 0.30;
   c.fuLookback     = 3;
   c.authMin        = 45;
   c.nodeScanBars   = 400;
   c.minConf        = 55;
   c.historyBars    = 1500;
   c.curveCtx       = 0;
}

//==================================================================
// PER-TIMEFRAME WAVE STATE (output of f_se + f_phys)
//==================================================================
struct SWaveState
{
   bool   valid;
   int    dir;          // wave direction by origin (-1/0/1)
   int    phase;        // 1..14 phase code (0 = none)
   double atr;
   double vel, acc, conv, csm;
   double eff, disp;
   bool   bullImp, bearImp, bullDec, bearDec;
   bool   bullCH, bearCH;
   bool   vd70, vd50;
   double curSH, curSL, prSH, prSL;
   int    bos;          // -1/0/1
   int    ch;           // -1/0/1
   double p4h, p4l;
   double inv;          // invalidation (protective extreme = stop reference)
   double tgt;          // measured objective (target reference)
   double ft, fb;       // flip zone top / bottom (entry zone)
   double cycH, cycL;
   double waveProgress; // 0..100 (f_se internal _wp)
   double convScore, expScore, absScore, mf, comp;
   double sh, sl;       // confirmed swing high / low (curSH/curSL)
   double closePrice;   // close of the TF at evaluation
};

//==================================================================
// FU / NODE detection result (one timeframe / one event)
//==================================================================
struct SFuState
{
   bool   valid;
   int    dir;     // -1/0/1
   double score;   // authority score
   double tip;
};

//==================================================================
// CURVE NODE (F72 recursive curve tree)
//==================================================================
struct SCurveNode
{
   int    id;
   int    parent;
   int    dir;
   double origin;
   double extreme;
   double energy;
   bool   alive;
   int    depth;
   string state;     // emergent phase (Principle 1/14)
   int    bar;
   double comp;
   double mat;
   int    srcTf;     // 0=chart/se5, 5=H1/se60, 6=H4/se240
};

//==================================================================
// CANONICAL WAVE STATE — the full chart-TF lifecycle (Letra layer)
//==================================================================
struct SCanonState
{
   bool   valid;
   int    dir;                 // displayWaveDir_M5 / l0_dir
   int    structBias;
   int    phaseCode;
   string phaseStr;            // ie1a_currentPhase (canonical)
   double atr;

   // physics / observation
   double velocity, acceleration, convexity, convSmooth, efficiency, displacement;
   bool   bullImpulse, bearImpulse, bullMomDecay, bearMomDecay, bullConvShift, bearConvShift;
   double obs_Expansion, obs_Decay, obs_Curvature, obs_Absorption, obs_Liquidity;

   // energy framework
   int    ede_state;
   double ede_expansionEnergy, ede_dissipatedEnergy, ede_dissipationProgress;
   int    resCode;             // 0 unresolved, 1 partial, 2 resolved
   double residual;            // re_residualEnergyScore
   double attractor;           // eae_primaryAttractorScore
   double attractorPrice;
   string attractorLabel;

   // liquidation wave overlay
   bool   liqg_active;
   int    liqg_dir;
   double liqg_target;
   double liqg_distPct;
   string liqg_subPhase;
   string liqg_title;

   // beliefs (smoothed)
   double expansionBelief, convexityBelief, creationBelief, absorptionBelief, retracementBelief, demandReturnBelief;

   // progress / fit
   double convexityMaturity;
   double waveProgress;
   double waveModelFit;
   double phaseConfidence;
   double phaseIntegrity;

   // geometry
   double inv, tgt, ft, fb, p4h, p4l, cycH, cycL, sh, sl;

   // attack sequence levels
   double atkEntry, atkStop, atkT1, atkT2, atkT3;
};

//==================================================================
// CURVE TREE RESULT (F72)
//==================================================================
struct SCurveTree
{
   int    alive;
   int    depth;
   int    ownerDir;
   int    ownerDepth;
   double ownerEnergy;
   string ownerState;          // emergent node phase
   double ownerOrigin, ownerExtreme;
   double life;                // "is the trade alive" 0..100
   string aliveTx;
   string cpState;
   double cpForce;
   string cpTrend;
   double mig50, mig618;       // migrated ownership band
   string htfThreat;
   double htfRoomAtr;
   int    budgetDepth;
   bool   recursionComplete;
};

//==================================================================
// TIME INTELLIGENCE ENGINE RESULT
//==================================================================
struct STimeState
{
   int    dir;
   double align;
   double conflict;
   string stack;       // MN/W/D/H4/H1 tags
   string seq;         // sequence narrative
   string h1Timing;
   double h1LowProb;
};

//==================================================================
// NODE NETWORK RESULT
//==================================================================
struct SNetState
{
   int    netBias;
   int    eligN;
   int    openMem;
   int    consumed;
   double bullAuth, bearAuth;
   double pressure;
   int    pdir;
   double fezHi, fezLo;
};

//==================================================================
// FINAL SENSEEI META-INTELLIGENCE RESULT (the whole brain)
//==================================================================
struct SSenseeiResult
{
   bool   ready;
   datetime barTime;

   // votes
   int    waveDir;
   int    stackDir;
   double stackPct;
   int    netBias;
   int    pdir;
   int    master;

   // scores
   double alignment;
   double conflict;
   double threat;
   double confidence;
   double oppScore;
   double timeAlign;
   double timeConflict;
   double residual;
   double attractor;
   int    resCode;

   // verdict
   string opportunity;
   string action;
   string timing;
   string intent;
   string story;

   // trade geometry
   double entryRef;
   double stopRef;
   double targetRef;
   double t2Ref;
   double t3Ref;
   double flipTop;
   double flipBot;
   double atr;
   int    phase;
   string phaseStr;

   // rich sub-states for the "living" dashboard
   SCanonState canon;
   SCurveTree  tree;
   STimeState  time;
   SNetState   net;

   // per-rung MTF map (6 rungs)
   int    rungDir[6];
   int    rungPhase[6];
   double rungProg[6];
   string rungTf[6];

   // participant fib zones (of the canonical leg)
   double fib618, fib705, fib786, fibFlip;
};
//+------------------------------------------------------------------+

#endif // __SENSEEI_TYPES_MQH__
