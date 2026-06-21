//+------------------------------------------------------------------+
//|                                                          EA.mq5   |
//|                F72 OMEGA — Synthetic Market Nervous System        |
//|                          PHASE 1 — FOUNDATION                     |
//|                                                                   |
//|  The organism's skeleton. Wires the full consequence architecture |
//|  end-to-end: perception -> STATE (the trinity) -> consequences    |
//|  (ENTER/HOLD/ADD/REDUCE/REVERSE/EXIT) -> risk -> capital ->       |
//|  execution, with total explainability and immortal memory.        |
//|                                                                   |
//|  NOTHING is a signal. Everything is STATE. Risk, capital and      |
//|  execution all READ FROM the trinity; they never sit outside it.  |
//|                                                                   |
//|  Phase 1 ships a clearly-marked PLACEHOLDER perception so the     |
//|  pipeline is fully exercisable (logging, memory, paper, modes).   |
//|  Phase 2 replaces BuildPerception() with the real multi-TF curve  |
//|  engine (f_se/f_phys + gCurve). No other module changes.          |
//|                                                                   |
//|  Default mode is OBSERVER: it computes and logs everything but    |
//|  places no orders until you switch to PAPER / AUTONOMOUS.         |
//+------------------------------------------------------------------+
#property copyright "F72 OMEGA"
#property version   "1.00"
#property strict

#include "Common.mqh"
#include "Logger.mqh"
#include "Session.mqh"
#include "News.mqh"
#include "Capital.mqh"
#include "Risk.mqh"
#include "PaperTrade.mqh"
#include "Memory.mqh"
//--- Phase 2: the curve engine (perception)
#include "Curve.mqh"
#include "Force.mqh"
#include "Compression.mqh"
#include "Convexity.mqh"

//==================================================================
// INPUTS
//==================================================================
input group "===== Engine ====="
input ENUM_ENGINE_MODE InpMode      = MODE_OBSERVER;   // Operating mode
input long   InpMagic               = 720072;          // Magic number
input int    InpHeartbeatSecs       = 30;              // Timer / checkpoint cadence
input bool   InpConsoleLog          = true;            // Echo logs to journal
input bool   InpShowDashboard       = true;            // On-chart dashboard

input group "===== Risk (breathing) ====="
input double InpBaseRiskPct         = 0.25;            // Base tier
input double InpNormalRiskPct       = 0.50;            // Normal tier
input double InpStrongRiskPct       = 1.00;            // Strong-narrative tier
input double InpExceptionalRiskPct  = 2.00;            // Exceptional-alignment tier
input double InpMaxTotalExposurePct = 4.00;            // Max simultaneous open risk
input int    InpMaxConcurrent       = 6;               // Max concurrent positions
input double InpMaxSpreadPoints      = 60.0;           // Spread guard

input group "===== Capital limits ====="
input double InpDailyLossPct        = 3.0;             // Daily loss lock
input double InpWeeklyLossPct       = 8.0;             // Weekly loss lock
input double InpHardLossPct         = 15.0;            // Hard circuit breaker

input group "===== Memory / Filters ====="
input int    InpStatWindow          = 50;             // Rolling self-observation window
input int    InpNewsWindowMin       = 30;             // News proximity window (context only)

input group "===== Curve engine (perception) ====="
input int    InpPivotLen            = 5;              // f_se pivot length
input int    InpEffLen              = 10;             // efficiency lookback
input double InpEffThresh           = 0.65;           // efficiency threshold
input double InpDispThresh          = 1.5;            // displacement ATR threshold
input double InpImpulseAtrMult      = 1.5;            // impulse ATR multiple
input double InpChochBufferATR      = 0.75;           // CHoCH buffer (ATR)
input int    InpHistoryBars         = 1500;           // bars per TF for state build
input int    InpAtrLen              = 14;             // ATR length

//==================================================================
// GLOBALS
//==================================================================
CLogger      g_log;
CSession     g_sess;
CNews        g_news;
CCapital     g_cap;
CRiskEngine  g_risk;
CBroker      g_broker;
CMemory      g_mem;
//--- Phase 2 curve engine
CCurveEngine g_curve;
CForce       g_force;
CCompression g_comp;
CConvexity   g_convx;
SCurveStack  g_stack;
SCurve       g_gcurve;          // canonical chart-TF curve (gCurve)

SEngineState g_state;
ENUM_ENGINE_MODE g_mode;
datetime     g_lastBar=0;
long         g_campaign=-1;     // single active campaign (multi-campaign in Phase 5)
int          g_lastEntryDir=0;

//==================================================================
// INIT
//==================================================================
int OnInit()
{
   g_mode=InpMode;

   g_log.Init(F72_ROOT,InpConsoleLog,LL_INFO);
   g_log.Info("EA",StringFormat("F72 OMEGA %s booting on %s %s | mode=%s",
              F72_VERSION,_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),ModeText(g_mode)));

   g_news.Init(F72_ROOT,InpNewsWindowMin);
   g_cap.Init(GetPointer(g_log),InpDailyLossPct,InpWeeklyLossPct,InpHardLossPct,0.6);

   SRiskParams rp; RiskParamsDefaults(rp);
   rp.baseRiskPct=InpBaseRiskPct; rp.normalRiskPct=InpNormalRiskPct;
   rp.strongRiskPct=InpStrongRiskPct; rp.exceptionalRiskPct=InpExceptionalRiskPct;
   rp.maxTotalExposurePct=InpMaxTotalExposurePct; rp.maxConcurrent=InpMaxConcurrent;
   rp.maxSpreadPoints=InpMaxSpreadPoints;
   g_risk.Init(_Symbol,InpMagic,GetPointer(g_log),GetPointer(g_cap),GetPointer(g_news),rp);

   g_broker.Init(_Symbol,InpMagic,g_mode,GetPointer(g_log),20,3);
   g_mem.Init(GetPointer(g_log),_Symbol,F72_ROOT,InpStatWindow);

   //--- Phase 2: curve engine
   SCurveCfg cc; CurveCfgDefaults(cc);
   cc.pivotLen=InpPivotLen; cc.atrLen=InpAtrLen; cc.effLen=InpEffLen;
   cc.effThresh=InpEffThresh; cc.dispThresh=InpDispThresh;
   cc.impulseAtrMult=InpImpulseAtrMult; cc.chochBufferATR=InpChochBufferATR;
   cc.historyBars=InpHistoryBars;
   g_curve.Init(_Symbol,cc);
   g_comp.Init(_Symbol);
   StackInit(g_stack); CurveInit(g_gcurve);

   StateInit(g_state);

   EventSetTimer(MathMax(5,InpHeartbeatSecs));
   g_log.Info("EA","boot complete — organism online");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_mem.Checkpoint();
   g_log.Info("EA",StringFormat("shutdown (reason=%d) — memory checkpointed",reason));
   Comment("");
}

//==================================================================
// TIMER — heartbeat: capital refresh + memory checkpoint
//==================================================================
void OnTimer()
{
   g_cap.Update();
   g_mem.Checkpoint();
}

//==================================================================
// NEW BAR
//==================================================================
bool IsNewBar()
{
   datetime t=iTime(_Symbol,_Period,0);
   if(t!=g_lastBar){ g_lastBar=t; return(true); }
   return(false);
}

//==================================================================
// TICK — the perception/decision/consequence loop
//==================================================================
void OnTick()
{
   g_cap.Update();
   g_broker.PaperUpdate();

   // perception updates STATE every tick; decisions are consequences
   BuildPerception(g_state);
   ComputeSelfObservation(g_state);

   SDecision d; DecisionInit(d);
   Decide(g_state,d);
   Act(g_state,d);

   if(InpShowDashboard) DrawDashboard(d);
}

//==================================================================
// PERCEPTION (PHASE 2 — REAL CURVE ENGINE)
//  Builds the fractal stack (M1..D1) and the canonical chart curve,
//  then derives the trinity + layer state from real curve physics:
//  force, compression, convexity, alignment, abandonment,
//  continuation. Phase 3 adds chain health & ownership; Phase 4
//  the narrative engine. Everything downstream is unchanged.
//==================================================================
void BuildPerception(SEngineState &s)
{
   s.time=TimeCurrent();

   g_gcurve=g_curve.Compute(_Period);
   g_stack =g_curve.ComputeStack(_Period);
   if(!g_gcurve.valid){ s.ready=false; return; }

   int dir=g_gcurve.dir;
   s.masterDir=dir;

   //--- FORCE (Layer 0 physics) -----------------------------------
   double fCanon=g_force.Score(g_gcurve);
   double fStack=g_force.StackForce(g_stack);
   s.forceScore=F72Clamp(fCanon*0.5+fStack*0.5,0.0,100.0);

   //--- COMPRESSION (Layer 5) -------------------------------------
   s.compression=g_comp.Score(g_gcurve,_Period,InpAtrLen);
   double breathe=100.0-s.compression;

   //--- CONVEXITY / curvature maturity ----------------------------
   s.convexity=g_convx.Maturity(g_gcurve);

   //--- ALIGNMENT (Layer 4): rungs agreeing with the canonical dir
   int agree=0,total=0;
   for(int i=0;i<F72_STACK_TFS;i++)
   {
      if(!g_stack.tf[i].valid || g_stack.tf[i].dir==0) continue;
      total++; if(g_stack.tf[i].dir==dir) agree++;
   }
   s.alignment=(total>0?(double)agree/total*100.0:50.0);

   //--- phase vitality: where in its life is the canonical curve? --
   int ph=g_gcurve.phase;
   double phaseVitality=(ph>=1&&ph<=4)?85.0:(ph>=5&&ph<=7)?55.0:(ph>=8&&ph<=10)?70.0:(ph>=11)?25.0:50.0;

   //--- Phase 3+ layers remain neutral until their modules arrive --
   s.chainHealth        =F72_NEUTRAL;
   s.ownershipStability =F72_NEUTRAL;
   s.regimeScore        =F72Clamp(100.0-g_mem.RegimeDrift(),0.0,100.0);

   //--- ABANDONMENT (Layer 6): extended impulse leaving structure --
   double abnd=0.0;
   if(g_gcurve.extended) abnd+=40.0;
   abnd+=F72Map(s.forceScore,40.0,90.0,0.0,35.0);
   abnd+=F72Map(breathe,30.0,90.0,0.0,25.0);
   if(g_gcurve.atExtreme) abnd*=0.7;   // still pinned to the extreme => not yet abandoned
   s.abandonment=F72Clamp(abnd,0.0,100.0);

   //--- CONTINUATION (Layer 7): can I hold? -----------------------
   double cont=s.forceScore*0.35 + s.alignment*0.25 + g_stack.upwardSupport*0.20 + phaseVitality*0.20;
   if(ph>=11) cont*=0.6;               // draining/returning => weak continuation
   s.continuation=F72Clamp(cont,0.0,100.0);

   //--- LIFE SCORE: is the story alive? (emergent) ----------------
   s.lifeScore=F72Clamp(
        s.forceScore   *0.28 +
        s.alignment    *0.22 +
        s.continuation *0.18 +
        breathe        *0.10 +
        phaseVitality  *0.22 , 0.0,100.0);

   //--- STORY STABILITY: coherent / not flipping ------------------
   s.storyStability=F72Clamp(
        s.alignment*0.45 + s.regimeScore*0.25 + g_stack.upwardSupport*0.30 - s.contradiction*0.30,
        0.0,100.0);

   //--- probability cloud (Layer 12) ------------------------------
   double pc=s.continuation;
   double pt=(ph>=10?60.0:0.0)+(100.0-s.forceScore)*0.3+(g_gcurve.atExtreme?20.0:0.0);
   double px=s.contradiction+(100.0-g_stack.upwardSupport)*0.4+((g_gcurve.dir!=g_stack.stackDir && g_stack.stackDir!=0)?20.0:0.0);
   double tot2=MathMax(pc+pt+px,1e-6);
   s.pContinuation=pc/tot2*100.0; s.pTerminal=pt/tot2*100.0; s.pTransfer=px/tot2*100.0;

   s.ready=true;
}

//==================================================================
// SELF-OBSERVATION (Layer 14) — engine confidence in ITSELF
//==================================================================
void ComputeSelfObservation(SEngineState &s)
{
   double hit=g_mem.RecentHitRate();           // rolling win rate
   double drift=g_mem.RegimeDrift();            // regime erraticness
   int    samples=g_mem.Samples();

   s.recentHitRate=hit;

   // contradiction: disagreement between direction proxies vs alignment
   s.contradiction=F72Clamp((100.0-s.alignment)*0.6 + drift*0.4,0.0,100.0);

   // confidence in the market read (distinct from self-trust)
   s.confidence=F72Clamp(s.alignment*0.5 + s.forceScore*0.3 + s.regimeScore*0.2,0.0,100.0);

   //--- STORY CONFIDENCE: "how much do I trust myself?" -----------
   // grows with hit rate + sample size + low drift + low contradiction
   double sampleConf=F72Map((double)samples,0.0,30.0,40.0,100.0); // cold-start humility
   s.storyConfidence=F72Clamp(
        hit                *0.35 +
        sampleConf         *0.20 +
        (100.0-drift)      *0.20 +
        (100.0-s.contradiction)*0.25 , 0.0,100.0);

   s.overfitFlag=(drift>70.0 && samples>20);
}

//==================================================================
// DECIDE — consequences emerge from the trinity. No signal logic.
//==================================================================
void Decide(const SEngineState &s,SDecision &d)
{
   DecisionInit(d);
   if(!s.ready){ d.type=DEC_NONE; d.reason=R_NONE; return; }

   bool inPosition=(PositionCountMine()>0 || g_broker.PaperOpenCount()>0);
   int  dir=s.masterDir;

   // ----- EXIT / REVERSE consequences (story dying or transferring)
   if(inPosition)
   {
      if(s.pTransfer>=55.0 && s.contradiction>=55.0)
      {
         d.type=DEC_REVERSE; d.dir=-g_lastEntryDir; d.role=ROLE_TERMINAL;
         d.reason=R_OWNERSHIP_TRANSFER; d.note="transfer prob high + contradiction";
         Geometry(s,d.dir,d); SizeFor(s,d); return;
      }
      if(s.lifeScore<40.0)
      {
         d.type=DEC_EXIT; d.dir=g_lastEntryDir; d.reason=R_STORY_DEAD;
         d.note="lifeScore collapsed"; return;
      }
      if(s.pTerminal>=60.0)
      {
         d.type=DEC_REDUCE; d.dir=g_lastEntryDir; d.reason=R_TERMINAL_INDUCTION;
         d.note="terminal probability elevated"; return;
      }
      // continuation pyramiding (ADD) — best opportunities per philosophy
      if(s.continuation>=70.0 && s.lifeScore>=70.0 && s.storyConfidence>=60.0 && dir==g_lastEntryDir)
      {
         d.type=DEC_ADD; d.dir=dir; d.role=ROLE_PROGRESSION;
         d.reason=R_PROGRESSION_PYRAMID; d.note="healthy continuation";
         Geometry(s,dir,d); SizeFor(s,d); return;
      }
      d.type=DEC_HOLD; d.dir=g_lastEntryDir; d.reason=R_CONTINUATION_HEALTHY; d.note="holding the story";
      return;
   }

   // ----- ENTER consequence (a living, aligned, trusted story)
   if(dir!=0 && s.lifeScore>=65.0 && s.alignment>=60.0 && s.storyStability>=55.0 && s.storyConfidence>=45.0)
   {
      d.type=DEC_ENTER; d.dir=dir; d.role=ROLE_ORIGIN;
      d.reason=R_STORY_ALIVE_ALIGNED; d.note="living aligned story";
      Geometry(s,dir,d); SizeFor(s,d); return;
   }

   d.type=DEC_NONE; d.reason=R_NONE; d.note="story not yet actionable";
}

//==================================================================
// ACT — translate a consequence into execution, gated by risk/mode
//==================================================================
void Act(const SEngineState &s,SDecision &d)
{
   if(d.type==DEC_NONE || d.type==DEC_HOLD)
   {
      // still log holds occasionally? keep journal clean: only state changes logged below
      return;
   }

   // risk gate (consequences still respect survival limits)
   if(d.type==DEC_ENTER || d.type==DEC_ADD || d.type==DEC_REVERSE)
   {
      ENUM_REASON gate=g_risk.Gate(s);
      if(gate!=R_NONE)
      {
         d.reason=gate; d.note="blocked: "+ReasonText(gate);
         g_log.Decision(_Symbol,g_mode,d,s);
         return;
      }
   }

   // observer/shadow never order, but ALWAYS log the consequence
   g_log.Decision(_Symbol,g_mode,d,s);

   double lot=0.0;
   if(d.riskPct>0 && d.stop>0)
   {
      double dist=MathAbs(EntryPrice(d.dir)-d.stop);
      lot=g_risk.CalcLot(d.riskPct,dist);
   }

   if(d.type==DEC_ENTER || d.type==DEC_ADD)
   {
      bool placed=g_broker.Open(d.dir,lot,d.stop,d.target,d.role,(g_campaign<0?0:g_campaign),
                                StringFormat("F72:%s:%s",DecisionText(d.type),ReasonText(d.reason)));
      if(placed)
      {
         g_lastEntryDir=d.dir;
         if(d.type==DEC_ENTER && g_campaign<0)
            g_campaign=g_mem.Birth(d.dir,CP_HEALTHY,g_sess.Current(),g_news.Environment());
         else if(d.type==DEC_ADD && g_campaign>=0)
            g_mem.AddRecursion(g_campaign);
         if(g_campaign>=0) g_mem.Update(g_campaign,s,0,0);
      }
   }
   else if(d.type==DEC_REVERSE)
   {
      g_broker.CloseAllLive(); g_broker.CloseAllPaper();
      if(g_campaign>=0){ g_mem.NoteTransition(g_campaign,2); CloseCampaign(s,2); }
      bool placed=g_broker.Open(d.dir,lot,d.stop,d.target,ROLE_TERMINAL,0,"F72:REVERSE");
      if(placed){ g_lastEntryDir=d.dir; g_campaign=g_mem.Birth(d.dir,CP_TRANSITION,g_sess.Current(),g_news.Environment()); }
      g_log.Transfer(_Symbol,-d.dir,d.dir,g_campaign,d.reason,d.note);
   }
   else if(d.type==DEC_REDUCE)
   {
      // Phase 1: reduce == flatten paper / log intent (scale-out granularity in Phase 5)
      if(g_broker.IsPaper()) g_broker.CloseAllPaper();
      if(g_campaign>=0) g_mem.NoteTerminal(g_campaign);
   }
   else if(d.type==DEC_EXIT)
   {
      g_broker.CloseAllLive(); g_broker.CloseAllPaper();
      if(g_campaign>=0) CloseCampaign(s,(d.reason==R_OWNERSHIP_TRANSFER?2:0));
      g_lastEntryDir=0;
   }
}

//==================================================================
// Helpers
//==================================================================
void CloseCampaign(const SEngineState &s,int transitionType)
{
   if(g_campaign<0) return;
   double pnl=g_broker.IsPaper()?g_broker.PaperRealized():AccountInfoDouble(ACCOUNT_PROFIT);
   g_mem.Death(g_campaign,pnl,transitionType);
   g_campaign=-1;
}

void Geometry(const SEngineState &s,int dir,SDecision &d)
{
   double atr=Atr(_Period,InpAtrLen);
   if(atr<=0) atr=SymbolInfoDouble(_Symbol,SYMBOL_POINT)*100;
   double price=EntryPrice(dir);
   // stop = the curve's real invalidation (protective extreme), ATR-padded;
   // fall back to a 2*ATR stop if the curve has no context yet.
   double stop;
   if(g_gcurve.valid && g_gcurve.inv>0.0)
      stop=(dir==1?g_gcurve.inv-atr*0.5:g_gcurve.inv+atr*0.5);
   else
      stop=(dir==1?price-atr*2.0:price+atr*2.0);
   double dist=g_risk.ValidateStopDistance(MathAbs(price-stop),atr);
   d.stop=(dir==1?price-dist:price+dist);
   // target = the curve's measured objective if it sits the right side
   bool tgtOK=(g_gcurve.valid && g_gcurve.tgt>0.0 && ((dir==1&&g_gcurve.tgt>price)||(dir==-1&&g_gcurve.tgt<price)));
   d.target=tgtOK?g_gcurve.tgt:(dir==1?price+dist*2.0:price-dist*2.0);
}

void SizeFor(const SEngineState &s,SDecision &d)
{
   d.riskPct=g_risk.EffectiveRiskPct(s);
}

double EntryPrice(int dir){ return(dir==1?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID)); }

int PositionCountMine()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      n++;
   }
   return(n);
}

double Atr(ENUM_TIMEFRAMES tf,int len)
{
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,tf,0,len+2,r)<len+1) return(0.0);
   double sum=0;
   for(int k=1;k<=len;k++)
      sum+=MathMax(r[k].high-r[k].low,MathMax(MathAbs(r[k].high-r[k+1].close),MathAbs(r[k].low-r[k+1].close)));
   return(sum/len);
}

//==================================================================
// TRADE TRANSACTION — record fills for explainability
//==================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.symbol==_Symbol)
         g_log.Info("Trade",StringFormat("deal %I64u type=%d vol=%.2f price=%.5f",
                    trans.deal,(int)trans.deal_type,trans.volume,trans.price));
   }
}

//==================================================================
// DASHBOARD
//==================================================================
string BarStr(double v,int w=12)
{
   int f=(int)MathRound(F72Clamp(v,0,100)/100.0*w);
   string s=""; for(int i=0;i<w;i++) s+=(i<f?"#":"."); return(s);
}
string ShortTf(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1: return("M1"); case PERIOD_M3: return("M3"); case PERIOD_M5: return("M5");
      case PERIOD_M15:return("M15");case PERIOD_M30:return("M30");case PERIOD_H1: return("H1");
      case PERIOD_H4: return("H4"); case PERIOD_D1: return("D1"); case PERIOD_W1: return("W1");
      case PERIOD_MN1:return("MN"); default: return("?");
   }
}
string DDtxt(ENUM_DD_STATE st)
{
   switch(st){case DD_NORMAL:return("NORMAL");case DD_CAUTION:return("CAUTION");
              case DD_DAILY_LOCK:return("DAILY-LOCK");case DD_WEEKLY_LOCK:return("WEEKLY-LOCK");
              case DD_HALT:return("HARD-HALT");} return("?");
}

void DrawDashboard(const SDecision &d)
{
   SEngineState s=g_state;
   string t="";
   t+="==========  F72 OMEGA  ("+F72_VERSION+")  ==========\n";
   t+=StringFormat(" Mode %-11s  Session %-8s  News %-7s\n",ModeText(g_mode),g_sess.Current(),g_news.Environment());
   if(!s.ready){ t+=" perceiving... (insufficient history)\n"; Comment(t); return; }
   t+="--------------------  TRINITY  --------------------\n";
   t+=StringFormat(" LIFE       %5.1f %s\n",s.lifeScore,BarStr(s.lifeScore));
   t+=StringFormat(" STABILITY  %5.1f %s\n",s.storyStability,BarStr(s.storyStability));
   t+=StringFormat(" CONFIDENCE %5.1f %s\n",s.storyConfidence,BarStr(s.storyConfidence));
   t+="--------------------  LAYERS  ---------------------\n";
   t+=StringFormat(" Dir %-4s  Force %3.0f  Align %3.0f  Conf %3.0f\n",
                   (s.masterDir==1?"BULL":s.masterDir==-1?"BEAR":"FLAT"),s.forceScore,s.alignment,s.confidence);
   t+=StringFormat(" Compress %3.0f  Convex %3.0f  Regime %3.0f  Contra %3.0f\n",
                   s.compression,s.convexity,s.regimeScore,s.contradiction);
   t+=StringFormat(" Continuation %3.0f  Abandon %3.0f  ChainH %3.0f\n",
                   s.continuation,s.abandonment,s.chainHealth);
   t+="--------------------  CURVE  ----------------------\n";
   t+=StringFormat(" %s  %s  prog %3.0f%%  inv %.5f  tgt %.5f\n",
                   (g_gcurve.dir==1?"^":g_gcurve.dir==-1?"v":"-"),CurvePhaseStr(g_gcurve.phase),
                   g_gcurve.waveProgress,g_gcurve.inv,g_gcurve.tgt);
   t+=" Stack ";
   for(int i=0;i<F72_STACK_TFS;i++)
   {
      string tl=ShortTf(g_stack.tf[i].tf);
      string ar=(g_stack.tf[i].dir==1?"+":g_stack.tf[i].dir==-1?"-":"=");
      t+=tl+ar+" ";
   }
   t+=StringFormat("\n Stack %s %.0f%%  upSupport %.0f%%\n",
                   (g_stack.stackDir==1?"BULL":g_stack.stackDir==-1?"BEAR":"FLAT"),g_stack.stackPct,g_stack.upwardSupport);
   t+="------------------  PROB CLOUD  -------------------\n";
   t+=StringFormat(" Continue %4.0f%%   Terminal %4.0f%%   Transfer %4.0f%%\n",
                   s.pContinuation,s.pTerminal,s.pTransfer);
   t+="------------------  CONSEQUENCE  ------------------\n";
   t+=StringFormat(" %s  dir=%d  risk=%.2f%%  why: %s\n",
                   DecisionText(d.type),d.dir,d.riskPct,ReasonText(d.reason));
   t+="-------------------  CAPITAL  ---------------------\n";
   t+=StringFormat(" DD-state %-11s  dayDD %.2f%%  hardDD %.2f%%\n",DDtxt(g_cap.State()),g_cap.DayDDpct(),g_cap.HardDDpct());
   t+=StringFormat(" Positions %d  paperOpen %d  pendingApprove %d\n",
                   PositionCountMine(),g_broker.PaperOpenCount(),g_broker.PendingCount());
   t+="-------------------  MEMORY  ----------------------\n";
   t+=StringFormat(" Campaigns(samples) %d  hitRate %.1f%%  PF %.2f  drift %.0f\n",
                   g_mem.Samples(),g_mem.RecentHitRate(),g_mem.ProfitFactor(),g_mem.RegimeDrift());
   t+=StringFormat(" Active campaign id %I64d\n",g_campaign);
   if(g_broker.IsPaper())
      t+=StringFormat(" Paper P&L  realized %.2f  floating %.2f\n",g_broker.PaperRealized(),g_broker.PaperFloating());
   Comment(t);
}
//+------------------------------------------------------------------+
