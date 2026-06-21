//+------------------------------------------------------------------+
//|                                              MasterSenseei.mq5   |
//|        F16 RAPTOR v57 / MASTER SENSEEI — Autonomous MT5 EA        |
//|                                                                   |
//|  A hedge-fund-grade Expert Advisor that ports the FULL F16 Raptor |
//|  v57 "Master Senseei" TradingView engine into a self-trading MT5  |
//|  system and renders the entire brain as a living dashboard.       |
//|                                                                   |
//|  Brain  (SenseeiEngine.mqh): f_phys + f_se multi-TF structure,    |
//|     the canonical wave LIFECYCLE (observation, EDE/RE/EAE energy  |
//|     framework, belief engine, convexity maturity, dual wave       |
//|     progress, liqg liquidation overlay), the F72 recursive CURVE  |
//|     TREE (ownership, life, migration, emergent node phase), the   |
//|     Time Intelligence Engine, the node/FU authority network, the  |
//|     fractal stack + MTF curve map, participant fib zones, and the |
//|     Senseei meta-intelligence verdict + intent + story.           |
//|  Risk   (RiskManager.mqh): fixed-fractional sizing, daily-loss    |
//|     limit, drawdown breaker, exposure caps, spread guard.         |
//|  Trade  (TradeManager.mqh): staged T1/T2/T3 scale-outs, BE,       |
//|     ATR trailing, retried sends, session/day filters.            |
//+------------------------------------------------------------------+
#property copyright   "Master Senseei"
#property version     "57.1"
#property description "Autonomous multi-timeframe wave / structure / curve-tree / meta-intelligence trading system."
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
input bool   InpRequireTreeAlive = true;   // Require curve-tree life >= MinTreeLife
input double InpMinTreeLife      = 45.0;   // Min curve-tree life to ATTACK
input bool   InpManageExitOnResolve = true;// Close trades when wave RESOLVES
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
input int    InpBeliefSmooth     = 3;      // Belief / progress EMA smoothing
input int    InpLiqSweepLook     = 10;     // Liquidity sweep lookback
input double InpWickFrac         = 0.30;   // FU spike min wick/range
input int    InpFuLookback       = 3;      // FU structure lookback
input int    InpAuthMin          = 45;     // Min node authority
input int    InpNodeScanBars     = 400;    // Bars scanned for FU nodes/TF
input int    InpHistoryBars      = 1500;   // Bars per TF for state build

input group "===== Risk Management ====="
input double InpRiskPerTradePct  = 0.5;    // Risk per trade (% equity)
input double InpMaxDailyLossPct  = 3.0;    // Daily loss limit (%)
input double InpMaxDrawdownPct   = 15.0;   // Max drawdown breaker (%)
input double InpMaxTotalRiskPct  = 2.0;    // Max simultaneous open risk (%)
input int    InpMaxOpenPositions = 2;      // Max concurrent positions
input double InpMaxSpreadPoints  = 35.0;   // Max spread (points)
input double InpMinStopATRmult   = 0.6;    // Floor stop at N*ATR
input double InpStopATRpad       = 0.5;    // Extra ATR padding beyond invalidation
input double InpMaxLotCap        = 50.0;   // Absolute lot ceiling

input group "===== Trade Management ====="
input long   InpMagic            = 570057; // Magic number
input int    InpSlippagePoints   = 20;     // Slippage (points)
input bool   InpUseStagedTP      = true;   // Staged T1/T2/T3 scale-outs
input double InpT1ClosePct       = 40.0;   // % closed at T1
input double InpT2ClosePct       = 35.0;   // % closed at T2
input double InpBreakEvenLockR   = 0.1;    // Lock this R at break-even
input bool   InpUseTrailing      = true;   // ATR trailing on the runner
input double InpTrailATRmult     = 2.0;    // Trail distance (ATR)
input double InpTrailStartR      = 1.2;    // Start trailing at this R (legacy)

input group "===== Sessions / Filters ====="
input bool   InpUseSession       = false;  // Restrict to session hours
input int    InpSessionStartHour = 7;      // Session start (server hour)
input int    InpSessionEndHour   = 21;     // Session end (server hour)
input bool   InpTradeMonday      = true;   // Trade Mondays
input bool   InpTradeFriday      = true;   // Trade Fridays
input int    InpFridayCutoffHour = 20;     // No new trades after (Fri server hour)

input group "===== Display ====="
input bool   InpShowDashboard    = true;   // On-chart text dashboard
input bool   InpDrawLevels       = true;   // Draw curve-tree / fib / target lines
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
SSenseeiResult g_R;
bool           g_have=false;
string         g_pfx="MS57_";

//==================================================================
// INIT
//==================================================================
int OnInit()
{
   EngineConfigDefaults(g_ecfg);
   g_ecfg.pivotLen=InpPivotLen; g_ecfg.atrLen=InpAtrLen; g_ecfg.effLen=InpEffLen;
   g_ecfg.structLen=InpStructLen; g_ecfg.impulseAtrMult=InpImpulseAtrMult;
   g_ecfg.effThresh=InpEffThresh; g_ecfg.dispThresh=InpDispThresh; g_ecfg.convMult=InpConvMult;
   g_ecfg.chochBufferATR=InpChochBufferATR; g_ecfg.beliefSmooth=InpBeliefSmooth;
   g_ecfg.liqSweepLook=InpLiqSweepLook; g_ecfg.wickFrac=InpWickFrac; g_ecfg.fuLookback=InpFuLookback;
   g_ecfg.authMin=InpAuthMin; g_ecfg.nodeScanBars=InpNodeScanBars;
   g_ecfg.minConf=InpMinConfidence; g_ecfg.historyBars=InpHistoryBars; g_ecfg.curveCtx=0;
   g_engine.Init(_Symbol,(ENUM_TIMEFRAMES)_Period,g_ecfg);

   RiskConfigDefaults(g_rcfg);
   g_rcfg.riskPerTradePct=InpRiskPerTradePct; g_rcfg.maxDailyLossPct=InpMaxDailyLossPct;
   g_rcfg.maxDrawdownPct=InpMaxDrawdownPct; g_rcfg.maxTotalRiskPct=InpMaxTotalRiskPct;
   g_rcfg.maxOpenPositions=InpMaxOpenPositions; g_rcfg.maxSpreadPoints=InpMaxSpreadPoints;
   g_rcfg.minStopATRmult=InpMinStopATRmult; g_rcfg.maxLotCap=InpMaxLotCap; g_rcfg.useEquityForSizing=true;
   g_risk.Init(_Symbol,InpMagic,g_rcfg);

   TradeConfigDefaults(g_tcfg);
   g_tcfg.magic=InpMagic; g_tcfg.commentTag="MasterSenseei v57";
   g_tcfg.slippagePoints=InpSlippagePoints; g_tcfg.useStagedTP=InpUseStagedTP;
   g_tcfg.t1ClosePct=InpT1ClosePct; g_tcfg.t2ClosePct=InpT2ClosePct;
   g_tcfg.breakEvenLockR=InpBreakEvenLockR; g_tcfg.useTrailing=InpUseTrailing;
   g_tcfg.trailATRmult=InpTrailATRmult; g_tcfg.trailStartR=InpTrailStartR;
   g_tcfg.useSession=InpUseSession; g_tcfg.sessionStartHour=InpSessionStartHour;
   g_tcfg.sessionEndHour=InpSessionEndHour; g_tcfg.tradeMonday=InpTradeMonday;
   g_tcfg.tradeFriday=InpTradeFriday; g_tcfg.fridayCutoffHour=InpFridayCutoffHour;
   g_trade.Init(_Symbol,g_tcfg);

   g_engine.ZeroResult(g_R); g_have=false;
   PrintFormat("[INIT] Master Senseei v57 EA live on %s %s. Magic=%I64d Risk/trade=%.2f%%",
               _Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),InpMagic,InpRiskPerTradePct);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,g_pfx);
   Comment("");
}

//==================================================================
bool IsNewBar()
{
   datetime t=iTime(_Symbol,_Period,0);
   if(t!=g_lastBarTime){ g_lastBarTime=t; return(true); }
   return(false);
}

double RoughATR()
{
   MqlRates rt[]; ArraySetAsSeries(rt,true);
   int len=InpAtrLen;
   if(CopyRates(_Symbol,_Period,0,len+2,rt)<len+1)
      return(SymbolInfoDouble(_Symbol,SYMBOL_POINT)*100);
   double sum=0;
   for(int k=1;k<=len;k++)
      sum+=MathMax(rt[k].high-rt[k].low,MathMax(MathAbs(rt[k].high-rt[k+1].close),MathAbs(rt[k].low-rt[k+1].close)));
   return(sum/len);
}

//==================================================================
// TICK
//==================================================================
void OnTick()
{
   g_risk.Update();

   double atrNow=(g_have && g_R.atr>0)?g_R.atr:RoughATR();
   g_trade.ManageOpen(atrNow);

   if(!IsNewBar())
   {
      if(InpShowDashboard) DrawDashboard();
      return;
   }

   SSenseeiResult r=g_engine.Evaluate();
   g_R=r; g_have=r.ready;
   if(!r.ready){ if(InpShowDashboard) DrawDashboard(); return; }

   if(InpVerboseLog)
      PrintFormat("[EVAL] %s | master=%d conf=%.0f threat=%.0f opp=%s | stack=%d(%.0f%%) net=%d pdir=%d | phase=%s life=%.0f res=%d",
                  r.action,r.master,r.confidence,r.threat,r.opportunity,r.stackDir,r.stackPct,
                  r.netBias,r.pdir,r.phaseStr,r.tree.life,r.resCode);

   if(InpManageExitOnResolve && r.action=="MANAGE / EXIT")
   {
      g_trade.CloseAll(InpMagic);
      if(InpShowDashboard) DrawDashboard();
      if(InpDrawLevels) DrawLevels();
      return;
   }

   if(InpReverseOnFlip && r.master!=0)
   {
      int opp=-r.master;
      if(g_trade.HasPositionDir(InpMagic,opp))
      {
         g_trade.CloseAllDir(InpMagic,opp);
         if(InpVerboseLog) Print("[MANAGE] Closed positions against flipped master.");
      }
   }

   if(r.action=="ATTACK")
      TryEnter(r);

   if(InpShowDashboard) DrawDashboard();
   if(InpDrawLevels)    DrawLevels();
}

//==================================================================
// ENTRY — sized to risk, staged T1/T2/T3 from the engine
//==================================================================
void TryEnter(const SSenseeiResult &r)
{
   int dir=r.master;
   if(dir==0) return;
   if(r.confidence<InpMinConfidence) return;
   if(r.threat>=InpMaxThreat) return;
   if(InpRequireStackAgree && r.stackDir!=0 && r.stackDir!=dir) return;
   if(InpRequireTreeAlive && r.tree.life<InpMinTreeLife) return;
   if(!g_trade.TimeWindowOK()){ if(InpVerboseLog) Print("[ENTRY] outside time window"); return; }

   string why;
   if(!g_risk.CanOpen(why)){ if(InpVerboseLog) PrintFormat("[ENTRY] risk gate: %s",why); return; }
   if(g_trade.HasPositionDir(InpMagic,dir) && InpMaxOpenPositions<=1) return;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double entry=(dir==1?ask:bid);
   double atr=(r.atr>0?r.atr:RoughATR());

   // stop = wave invalidation padded, floored to broker/ATR minimums
   double stop;
   if(r.stopRef>0.0) stop=(dir==1?r.stopRef-atr*InpStopATRpad:r.stopRef+atr*InpStopATRpad);
   else              stop=(dir==1?entry-atr*2.0:entry+atr*2.0);
   double rawDist=MathAbs(entry-stop);
   double dist=g_risk.ValidateStopDistance(rawDist,atr);
   stop=(dir==1?entry-dist:entry+dist);

   // targets from the engine attack sequence; sanitize ordering & RR
   double t1=r.targetRef, t2=r.t2Ref, t3=r.t3Ref;
   if(!(dir==1?t1>entry:t1<entry)) t1=(dir==1?entry+dist*1.5:entry-dist*1.5);
   if(!(dir==1?t2>t1:t2<t1))       t2=(dir==1?entry+dist*3.0:entry-dist*3.0);
   if(!(dir==1?t3>t2:t3<t2))       t3=(dir==1?entry+dist*5.0:entry-dist*5.0);

   double lot=g_risk.CalcLot(dist);
   if(lot<=0){ if(InpVerboseLog) Print("[ENTRY] lot<=0"); return; }

   if(g_trade.OpenStaged(dir,lot,stop,t1,t2,t3))
      PrintFormat("[ENTRY] %s %.2f | E=%.5f SL=%.5f T1=%.5f T2=%.5f T3=%.5f | conf=%.0f opp=%s phase=%s life=%.0f",
                  dir==1?"BUY":"SELL",lot,entry,stop,t1,t2,t3,r.confidence,r.opportunity,r.phaseStr,r.tree.life);
}

//==================================================================
// DASHBOARD — the living read of the whole brain
//==================================================================
string Bar(double v,int width=10)
{
   int f=(int)MathRound(MathMax(0,MathMin(100,v))/100.0*width);
   string s="";
   for(int i=0;i<width;i++) s+=(i<f?"|":".");
   return(s);
}
string DirTx(int d){ return(d==1?"BULL":d==-1?"BEAR":"FLAT"); }
string DirArr(int d){ return(d==1?"^":d==-1?"v":"-"); }

void DrawDashboard()
{
   SSenseeiResult r=g_R;
   string halt=g_risk.IsHalted()?("  [HALTED:"+g_risk.HaltReason()+"]"):"";
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct=(g_risk.EquityPeak()>0)?(g_risk.EquityPeak()-eq)/g_risk.EquityPeak()*100.0:0.0;
   double dayPnL=eq-g_risk.DayStartEquity();

   string t="";
   t+="===============  MASTER SENSEEI v57  ==============="+halt+"\n";
   if(!r.ready){ t+="warming up — building multi-timeframe state...\n"; Comment(t); return; }

   // 1) VERDICT
   t+=StringFormat(" VERDICT : %-13s  %s   intent: %s\n",r.action,DirTx(r.master),r.intent);
   t+=StringFormat(" %s\n",r.story);
   t+=StringFormat(" Confidence %3.0f %s   Threat %3.0f %s\n",r.confidence,Bar(r.confidence),r.threat,Bar(r.threat));
   t+=StringFormat(" Opportunity %-11s  Timing %-11s\n",r.opportunity,r.timing);
   t+=StringFormat(" Alignment %3.0f%%  Conflict %3.0f%%  Opp %3.0f\n",r.alignment,r.conflict,r.oppScore);
   t+="----------------------------------------------------\n";

   // 2) CANONICAL WAVE LIFECYCLE
   SCanonState c=r.canon;
   t+=StringFormat(" WAVE   : %s %s  %3.0f%%  fit %3.0f%%\n",DirArr(c.dir),c.phaseStr,c.waveProgress,c.waveModelFit);
   t+=StringFormat(" Energy : EDE st%d  exp %3.0f  diss %3.0f (%3.0f%%)\n",c.ede_state,c.ede_expansionEnergy,c.ede_dissipatedEnergy,c.ede_dissipationProgress);
   t+=StringFormat(" Resolve: %-10s  residual %3.0f  attractor %3.0f\n",
                   r.resCode==2?"RESOLVED":r.resCode==1?"PARTIAL":"UNRESOLVED",r.residual,r.attractor);
   t+=StringFormat(" Beliefs: Exp%3.0f Cvx%3.0f Cre%3.0f Abs%3.0f Ret%3.0f Dem%3.0f\n",
                   c.expansionBelief,c.convexityBelief,c.creationBelief,c.absorptionBelief,c.retracementBelief,c.demandReturnBelief);
   t+=StringFormat(" Liqg   : %-22s  -> %.5f\n",c.liqg_title,c.liqg_target);
   t+="----------------------------------------------------\n";

   // 3) CURVE TREE (F72)
   SCurveTree tr=r.tree;
   t+=StringFormat(" CURVE TREE: %d alive  depth %d/%d\n",tr.alive,tr.depth,tr.budgetDepth);
   t+=StringFormat(" Owner  : %s %s  energy %3.0f  %s\n",DirTx(tr.ownerDir),tr.ownerState,tr.ownerEnergy,tr.cpTrend);
   t+=StringFormat(" LIFE   : %3.0f %s  %s\n",tr.life,Bar(tr.life),tr.aliveTx);
   t+=StringFormat(" Migrate: 0.5 %.5f  0.618 %.5f\n",tr.mig50,tr.mig618);
   t+=StringFormat(" HTF    : %s (room %.1f ATR)\n",tr.htfThreat,tr.htfRoomAtr);
   t+="----------------------------------------------------\n";

   // 4) MTF CURVE MAP (fractal stack)
   t+=StringFormat(" MTF MAP (stack %s %.0f%%):\n",DirTx(r.stackDir),r.stackPct);
   t+=" ";
   for(int i=0;i<6;i++)
      t+=StringFormat("%s%s ",r.rungTf[i],DirArr(r.rungDir[i]));
   t+="\n";

   // 5) TIME ENGINE + NODE NETWORK
   STimeState te=r.time; SNetState ns=r.net;
   t+=StringFormat(" TIME   : %s| align %.0f%% conf %.0f%% | H1 %s\n",te.stack,te.align,te.conflict,te.h1Timing);
   t+=StringFormat(" NODES  : net %s pdir %s  press %+.0f  open %d cons %d elig %d\n",
                   DirTx(ns.netBias),DirTx(ns.pdir),ns.pressure,ns.openMem,ns.consumed,ns.eligN);

   // 6) PARTICIPANTS (fib interference)
   t+=StringFormat(" PARTIC : 0.618 %.5f  0.705 %.5f  0.786 %.5f\n",r.fib618,r.fib705,r.fib786);
   t+="----------------------------------------------------\n";

   // 7) PLAN + ACCOUNT
   t+=StringFormat(" PLAN   : E %.5f  SL %.5f\n",r.entryRef,r.stopRef);
   t+=StringFormat("          T1 %.5f  T2 %.5f  T3 %.5f\n",r.targetRef,r.t2Ref,r.t3Ref);
   t+=StringFormat(" BOOK   : pos %d  openRisk %.2f%%\n",g_risk.CountPositions(),g_risk.CurrentOpenRiskPct());
   t+=StringFormat(" ACCT   : eq %.2f  dayPnL %+.2f  DD %.2f%%\n",eq,dayPnL,ddPct);
   Comment(t);
}

//==================================================================
// CHART OBJECTS — make the levels visible on the price chart
//==================================================================
void HLine(string name,double price,color clr,int style,int width,string txt)
{
   string nm=g_pfx+name;
   if(price<=0){ ObjectDelete(0,nm); return; }
   if(ObjectFind(0,nm)<0)
      ObjectCreate(0,nm,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,nm,OBJPROP_PRICE,price);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,style);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,nm,OBJPROP_BACK,true);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt);
}

void DrawLevels()
{
   SSenseeiResult r=g_R;
   if(!r.ready) return;
   color up=clrDeepSkyBlue, dn=clrOrange, neut=clrGray;
   HLine("STOP", r.stopRef,  clrTomato,    STYLE_SOLID, 2, "SENSEEI invalidation");
   HLine("T1",   r.targetRef,clrLimeGreen, STYLE_DOT,   1, "T1 objective");
   HLine("T2",   r.t2Ref,    clrLimeGreen, STYLE_DOT,   1, "T2");
   HLine("T3",   r.t3Ref,    clrLimeGreen, STYLE_DASH,  1, "T3 runner");
   HLine("FT",   r.flipTop,  clrGoldenrod, STYLE_DASHDOT,1,"Flip top");
   HLine("FB",   r.flipBot,  clrGoldenrod, STYLE_DASHDOT,1,"Flip bot");
   HLine("F618", r.fib618,   neut,         STYLE_DOT,   1, "0.618");
   HLine("F705", r.fib705,   neut,         STYLE_DOT,   1, "0.705");
   HLine("F786", r.fib786,   neut,         STYLE_DOT,   1, "0.786");
   HLine("MIG",  r.tree.mig618, r.master==1?up:dn, STYLE_SOLID,1,"Curve ownership band");
   HLine("ATTR", r.canon.attractorPrice, clrViolet, STYLE_DASH, 1, "Attractor");
}
//+------------------------------------------------------------------+
