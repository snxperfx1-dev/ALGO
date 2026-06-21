//+------------------------------------------------------------------+
//|                                              MasterSenseei.mq5   |
//|        F16 RAPTOR v57 / MASTER SENSEEI — Autonomous MT5 EA        |
//|                                                                   |
//|  A hedge-fund-grade Expert Advisor that ports the F16 Raptor v57  |
//|  "Master Senseei" TradingView engine into a fully autonomous      |
//|  MetaTrader 5 trading system.                                     |
//|                                                                   |
//|  Signal core (SenseeiEngine.mqh): a faithful MQL5 reconstruction  |
//|  of the multi-timeframe wave-structure engine (f_phys + f_se),    |
//|  the fractal stack alignment, the node / FU bias network, and the |
//|  Senseei meta-intelligence that produces the ATTACK / WAIT verdict|
//|  together with the wave's invalidation (stop) and objective (TP). |
//|                                                                   |
//|  Risk core (RiskManager.mqh): fixed-fractional sizing, daily-loss |
//|  limit, max-drawdown circuit breaker, exposure caps, spread guard.|
//|                                                                   |
//|  Execution core (TradeManager.mqh): retried order sends, partial  |
//|  take-profit, break-even, ATR trailing, session/day filters.      |
//|                                                                   |
//|  The EA trades by itself: it evaluates on each new closed bar of  |
//|  the chart timeframe and manages open trades on every tick.       |
//+------------------------------------------------------------------+
#property copyright   "Master Senseei"
#property link        ""
#property version     "57.0"
#property description "Autonomous multi-timeframe wave / structure / meta-intelligence trading system."
#property strict

#include "SenseeiEngine.mqh"
#include "RiskManager.mqh"
#include "TradeManager.mqh"

//==================================================================
// INPUTS
//==================================================================
input group "===== Strategy / Signal ====="
input int    InpMinConfidence   = 55;     // Min confidence to ATTACK (0-100)
input double InpMaxThreat        = 45.0;   // Max threat to allow entry
input bool   InpRequireStackAgree= true;   // Require fractal stack to agree with master
input bool   InpManageExitOnResolve = true;// Close trades when wave RESOLVES (MANAGE/EXIT)
input bool   InpReverseOnFlip    = false;  // Close & reverse when master flips against position

input group "===== Engine (f_se / f_phys) ====="
input int    InpPivotLen         = 5;      // Pivot length
input int    InpAtrLen           = 14;     // ATR length
input int    InpEffLen           = 10;     // Efficiency lookback
input int    InpStructLen        = 10;     // Structure pivot length
input double InpImpulseAtrMult   = 1.5;    // Impulse ATR multiple
input double InpEffThresh        = 0.65;   // Efficiency threshold
input double InpDispThresh       = 1.5;    // Displacement ATR threshold
input double InpConvMult         = 0.01;   // Convexity ATR multiplier
input double InpChochBufferATR   = 0.75;   // CHoCH buffer (ATR)
input bool   InpUseStrictStruct  = true;   // Use strict structure
input double InpWickFrac         = 0.30;   // FU spike min wick/range
input int    InpFuLookback       = 3;      // FU structure lookback
input int    InpHistoryBars      = 1500;   // Bars per TF for state build

input group "===== Risk Management ====="
input double InpRiskPerTradePct  = 0.5;    // Risk per trade (% equity)
input double InpMaxDailyLossPct  = 3.0;    // Daily loss limit (% )
input double InpMaxDrawdownPct   = 15.0;   // Max drawdown breaker (%)
input double InpMaxTotalRiskPct  = 2.0;    // Max simultaneous open risk (%)
input int    InpMaxOpenPositions = 2;      // Max concurrent positions
input double InpMaxSpreadPoints  = 35.0;   // Max spread (points)
input double InpMinStopATRmult   = 0.6;    // Floor stop at N*ATR
input double InpStopATRpad       = 0.5;    // Extra ATR padding beyond invalidation
input double InpTargetRR         = 2.0;    // Fallback reward:risk if engine target missing
input double InpMaxLotCap        = 50.0;   // Absolute lot ceiling

input group "===== Trade Management ====="
input long   InpMagic            = 570057; // Magic number
input int    InpSlippagePoints   = 20;     // Slippage (points)
input bool   InpUsePartialTP     = true;   // Scale out at first target
input double InpPartialTPpct     = 50.0;   // % closed at partial
input double InpPartialAtR       = 1.0;    // Partial at this R
input bool   InpUseBreakEven     = true;   // Move SL to BE
input double InpBreakEvenAtR     = 1.0;    // BE at this R
input double InpBreakEvenLockR   = 0.1;    // Lock this R at BE
input bool   InpUseTrailing      = true;   // ATR trailing
input double InpTrailATRmult     = 2.0;    // Trail distance (ATR)
input double InpTrailStartR      = 1.2;    // Start trailing at this R

input group "===== Sessions / Filters ====="
input bool   InpUseSession       = false;  // Restrict to session hours
input int    InpSessionStartHour = 7;      // Session start (server hour)
input int    InpSessionEndHour   = 21;     // Session end (server hour)
input bool   InpTradeMonday      = true;   // Trade Mondays
input bool   InpTradeFriday      = true;   // Trade Fridays
input int    InpFridayCutoffHour = 20;     // No new trades after (Fri server hour)

input group "===== Display ====="
input bool   InpShowDashboard    = true;   // On-chart status dashboard
input bool   InpVerboseLog       = false;  // Verbose journal logging

//==================================================================
// GLOBALS
//==================================================================
CSenseeiEngine g_engine;
CRiskManager   g_risk;
CTradeManager  g_trade;
SEngineConfig  g_ecfg;
SRiskConfig    g_rcfg;
STradeConfig   g_tcfg;

datetime       g_lastBarTime=0;
SSenseeiResult g_lastResult;
string         g_objName="MS_DASH";

//==================================================================
// INIT
//==================================================================
int OnInit()
{
   // engine config
   EngineConfigDefaults(g_ecfg);
   g_ecfg.pivotLen       = InpPivotLen;
   g_ecfg.atrLen         = InpAtrLen;
   g_ecfg.effLen         = InpEffLen;
   g_ecfg.structLen      = InpStructLen;
   g_ecfg.impulseAtrMult = InpImpulseAtrMult;
   g_ecfg.effThresh      = InpEffThresh;
   g_ecfg.dispThresh     = InpDispThresh;
   g_ecfg.convMult       = InpConvMult;
   g_ecfg.chochBufferATR = InpChochBufferATR;
   g_ecfg.useStrictStruct= InpUseStrictStruct;
   g_ecfg.wickFrac       = InpWickFrac;
   g_ecfg.fuLookback     = InpFuLookback;
   g_ecfg.minConf        = InpMinConfidence;
   g_ecfg.historyBars    = InpHistoryBars;
   g_engine.Init(_Symbol,(ENUM_TIMEFRAMES)_Period,g_ecfg);

   // risk config
   RiskConfigDefaults(g_rcfg);
   g_rcfg.riskPerTradePct  = InpRiskPerTradePct;
   g_rcfg.maxDailyLossPct  = InpMaxDailyLossPct;
   g_rcfg.maxDrawdownPct   = InpMaxDrawdownPct;
   g_rcfg.maxTotalRiskPct  = InpMaxTotalRiskPct;
   g_rcfg.maxOpenPositions = InpMaxOpenPositions;
   g_rcfg.maxSpreadPoints  = InpMaxSpreadPoints;
   g_rcfg.minStopATRmult   = InpMinStopATRmult;
   g_rcfg.maxLotCap        = InpMaxLotCap;
   g_rcfg.useEquityForSizing=true;
   g_risk.Init(_Symbol,InpMagic,g_rcfg);

   // trade config
   TradeConfigDefaults(g_tcfg);
   g_tcfg.magic           = InpMagic;
   g_tcfg.commentTag      = "MasterSenseei v57";
   g_tcfg.slippagePoints  = InpSlippagePoints;
   g_tcfg.usePartialTP    = InpUsePartialTP;
   g_tcfg.partialTPpct    = InpPartialTPpct;
   g_tcfg.partialAtR      = InpPartialAtR;
   g_tcfg.useBreakEven    = InpUseBreakEven;
   g_tcfg.breakEvenAtR    = InpBreakEvenAtR;
   g_tcfg.breakEvenLockR  = InpBreakEvenLockR;
   g_tcfg.useTrailing     = InpUseTrailing;
   g_tcfg.trailATRmult    = InpTrailATRmult;
   g_tcfg.trailStartR     = InpTrailStartR;
   g_tcfg.useSession      = InpUseSession;
   g_tcfg.sessionStartHour= InpSessionStartHour;
   g_tcfg.sessionEndHour  = InpSessionEndHour;
   g_tcfg.tradeMonday     = InpTradeMonday;
   g_tcfg.tradeFriday     = InpTradeFriday;
   g_tcfg.fridayCutoffHour= InpFridayCutoffHour;
   g_trade.Init(_Symbol,g_tcfg);

   g_engine.ZeroResult(g_lastResult);

   PrintFormat("[INIT] Master Senseei v57 EA started on %s %s. Magic=%I64d Risk/trade=%.2f%%",
               _Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),InpMagic,InpRiskPerTradePct);
   return(INIT_SUCCEEDED);
}

//==================================================================
// DEINIT
//==================================================================
void OnDeinit(const int reason)
{
   ObjectDelete(0,g_objName);
   Comment("");
}

//==================================================================
// NEW BAR DETECTION (chart timeframe)
//==================================================================
bool IsNewBar()
{
   datetime t=iTime(_Symbol,_Period,0);
   if(t!=g_lastBarTime){ g_lastBarTime=t; return(true); }
   return(false);
}

//==================================================================
// TICK
//==================================================================
void OnTick()
{
   // 1) keep risk breakers & equity tracking current
   g_risk.Update();

   // 2) manage open trades on every tick (BE, trailing, partial)
   double atrNow=(g_lastResult.ready && g_lastResult.atr>0)?g_lastResult.atr:RoughATR();
   g_trade.ManageOpen(atrNow);

   // 3) decision-making only on a freshly closed bar
   if(!IsNewBar())
   {
      if(InpShowDashboard) DrawDashboard();
      return;
   }

   // run the full Senseei engine on the closed bar
   SSenseeiResult r=g_engine.Evaluate();
   g_lastResult=r;
   if(!r.ready)
   {
      if(InpShowDashboard) DrawDashboard();
      return;
   }

   if(InpVerboseLog)
      PrintFormat("[EVAL] action=%s master=%d conf=%.0f threat=%.0f opp=%s stack=%d(%.0f%%) net=%d pdir=%d phase=%d",
                  r.action,r.master,r.confidence,r.threat,r.opportunity,r.stackDir,r.stackPct,r.netBias,r.pdir,r.phase);

   // 4) MANAGE / EXIT — wave resolved: stand down (let trailing finish or close)
   if(InpManageExitOnResolve && r.action=="MANAGE / EXIT")
   {
      // resolved structure: tighten by closing positions counter to fresh master, keep none open if no edge
      // conservative: close everything to lock the resolved move
      g_trade.CloseAll(InpMagic);
      if(InpShowDashboard) DrawDashboard();
      return;
   }

   // 5) reverse handling
   if(InpReverseOnFlip && r.master!=0)
   {
      int opp=-r.master;
      if(g_trade.HasPositionDir(InpMagic,opp))
      {
         g_trade.CloseAllDir(InpMagic,opp);
         if(InpVerboseLog) Print("[MANAGE] Closed positions against flipped master direction.");
      }
   }

   // 6) ATTACK — attempt a new entry
   if(r.action=="ATTACK")
      TryEnter(r);

   if(InpShowDashboard) DrawDashboard();
}

//==================================================================
// ENTRY
//==================================================================
void TryEnter(const SSenseeiResult &r)
{
   int dir=r.master;
   if(dir==0) return;

   // gating
   if(r.confidence<InpMinConfidence) return;
   if(r.threat>=InpMaxThreat) return;
   if(InpRequireStackAgree && r.stackDir!=0 && r.stackDir!=dir) return;
   if(!g_trade.TimeWindowOK()) { if(InpVerboseLog) Print("[ENTRY] Skipped: outside time window."); return; }

   string why;
   if(!g_risk.CanOpen(why)){ if(InpVerboseLog) PrintFormat("[ENTRY] Skipped: risk gate %s",why); return; }

   // avoid stacking same-direction duplicates beyond cap (handled by risk too)
   if(g_trade.HasPositionDir(InpMagic,dir) && InpMaxOpenPositions<=1) return;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double entry=(dir==1?ask:bid);
   double atr=(r.atr>0?r.atr:RoughATR());

   // STOP: engine invalidation, padded; fall back to ATR stop
   double stop;
   if(r.stopRef>0.0)
      stop=(dir==1?r.stopRef-atr*InpStopATRpad:r.stopRef+atr*InpStopATRpad);
   else
      stop=(dir==1?entry-atr*2.0:entry+atr*2.0);

   double rawDist=MathAbs(entry-stop);
   double dist=g_risk.ValidateStopDistance(rawDist,atr);
   stop=(dir==1?entry-dist:entry+dist);

   // TARGET: engine objective if valid & on the right side; else RR multiple
   double tp;
   bool engineTgtOK=(r.targetRef>0.0) && ((dir==1 && r.targetRef>entry) || (dir==-1 && r.targetRef<entry));
   if(engineTgtOK)
      tp=r.targetRef;
   else
      tp=(dir==1?entry+dist*InpTargetRR:entry-dist*InpTargetRR);

   // ensure TP respects a minimum RR of ~1 to be worth the risk
   double tpDist=MathAbs(tp-entry);
   if(tpDist<dist*0.9)
      tp=(dir==1?entry+dist*InpTargetRR:entry-dist*InpTargetRR);

   double lot=g_risk.CalcLot(dist);
   if(lot<=0){ if(InpVerboseLog) Print("[ENTRY] Skipped: computed lot <= 0"); return; }

   if(g_trade.Open(dir,lot,stop,tp))
      PrintFormat("[ENTRY] %s %.2f lots | entry=%.5f SL=%.5f TP=%.5f | conf=%.0f opp=%s phase=%d",
                  dir==1?"BUY":"SELL",lot,entry,stop,tp,r.confidence,r.opportunity,r.phase);
}

//==================================================================
// Fallback ATR (chart TF) when engine not yet ready
//==================================================================
double RoughATR()
{
   MqlRates rt[];
   ArraySetAsSeries(rt,true);
   int len=InpAtrLen;
   if(CopyRates(_Symbol,_Period,0,len+2,rt)<len+1)
      return(SymbolInfoDouble(_Symbol,SYMBOL_POINT)*100);
   double sum=0;
   for(int k=1;k<=len;k++)
      sum+=MathMax(rt[k].high-rt[k].low,MathMax(MathAbs(rt[k].high-rt[k+1].close),MathAbs(rt[k].low-rt[k+1].close)));
   return(sum/len);
}

//==================================================================
// DASHBOARD
//==================================================================
void DrawDashboard()
{
   SSenseeiResult r=g_lastResult;
   string dir=(r.master==1?"BULLISH":r.master==-1?"BEARISH":"NEUTRAL");
   string halt=g_risk.IsHalted()?("  [HALTED:"+g_risk.HaltReason()+"]"):"";
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct=(g_risk.EquityPeak()>0)?(g_risk.EquityPeak()-eq)/g_risk.EquityPeak()*100.0:0.0;
   double dayPnL=eq-g_risk.DayStartEquity();

   string txt="";
   txt+="==== MASTER SENSEEI v57 ===="+halt+"\n";
   txt+=StringFormat("Verdict   : %s  (%s)\n",r.action,dir);
   txt+=StringFormat("Confidence: %.0f%%   Threat: %.0f%%\n",r.confidence,r.threat);
   txt+=StringFormat("Opportunity: %s   Timing: %s\n",r.opportunity,r.timing);
   txt+=StringFormat("Alignment : %.0f%%   Conflict: %.0f%%\n",r.alignment,r.conflict);
   txt+=StringFormat("Stack     : %d (%.0f%%)  Net: %d  Pressure: %d\n",r.stackDir,r.stackPct,r.netBias,r.pdir);
   txt+=StringFormat("Resolution: %s   Residual: %.0f  Attractor: %.0f\n",
                     r.resCode==2?"RESOLVED":r.resCode==1?"PARTIAL":"UNRESOLVED",r.residual,r.attractor);
   txt+=StringFormat("Wave phase: %d   ATR: %.5f\n",r.phase,r.atr);
   txt+=StringFormat("Stop ref  : %.5f   Target ref: %.5f\n",r.stopRef,r.targetRef);
   txt+="----------------------------\n";
   txt+=StringFormat("Positions : %d   OpenRisk: %.2f%%\n",g_risk.CountPositions(),g_risk.CurrentOpenRiskPct());
   txt+=StringFormat("Equity    : %.2f   DayPnL: %.2f   DD: %.2f%%\n",eq,dayPnL,ddPct);
   Comment(txt);
}
//+------------------------------------------------------------------+
