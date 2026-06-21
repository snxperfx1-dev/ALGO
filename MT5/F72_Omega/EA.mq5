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

input group "===== Phase-1 placeholder perception ====="
input int    InpFastEMA             = 21;             // (placeholder) fast EMA
input int    InpSlowEMA             = 55;             // (placeholder) slow EMA
input int    InpAtrLen              = 14;             // (placeholder) ATR length

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
// PERCEPTION (PHASE 1 PLACEHOLDER)
//  Minimal proxy perception so the pipeline is exercisable. This is
//  the ONLY function Phase 2 replaces — with the real multi-TF curve
//  engine (curves, compression, convexity, force, ownership, chain).
//  Everything downstream (trinity -> risk -> capital -> execution)
//  stays exactly as built here.
//==================================================================
void BuildPerception(SEngineState &s)
{
   s.time=TimeCurrent();

   double fast=Ema(_Period,InpFastEMA);
   double slow=Ema(_Period,InpSlowEMA);
   double atr =Atr(_Period,InpAtrLen);
   double price=iClose(_Symbol,_Period,0);
   if(atr<=0){ s.ready=false; return; }

   // direction proxy
   s.masterDir=(fast>slow?1:(fast<slow?-1:0));

   // FORCE: separation of EMAs normalised by ATR
   double sep=MathAbs(fast-slow)/atr;
   s.forceScore=F72Map(sep,0.0,3.0,0.0,100.0);

   // COMPRESSION: current ATR vs its longer average (low ATR => squeezed)
   double atrLong=Atr(_Period,InpAtrLen*4);
   double ratio=(atrLong>0?atr/atrLong:1.0);
   s.compression=F72Map(ratio,0.4,1.4,100.0,0.0); // tight range => high compression

   // CONVEXITY proxy: curvature of price vs EMA (placeholder neutral-ish)
   double dev=(price-slow)/atr;
   s.convexity=F72Map(MathAbs(dev),0.0,4.0,30.0,90.0);

   // ALIGNMENT: agreement of EMA slope across 3 timeframes
   int agree=0,total=0;
   ENUM_TIMEFRAMES tfs[3]; tfs[0]=PERIOD_M15; tfs[1]=PERIOD_H1; tfs[2]=PERIOD_H4;
   for(int i=0;i<3;i++)
   {
      double f=Ema(tfs[i],InpFastEMA), sl=Ema(tfs[i],InpSlowEMA);
      int dd=(f>sl?1:(f<sl?-1:0));
      if(dd!=0){ total++; if(dd==s.masterDir) agree++; }
   }
   s.alignment=(total>0?(double)agree/total*100.0:50.0);

   // Phase-3+ layers remain neutral until their modules arrive
   s.chainHealth        =F72_NEUTRAL;
   s.ownershipStability =F72_NEUTRAL;
   s.regimeScore        =F72Clamp(100.0-g_mem.RegimeDrift(),0.0,100.0);
   s.abandonment        =F72Map(s.forceScore,40.0,90.0,30.0,80.0);
   s.continuation       =F72Clamp(s.forceScore*0.5+s.alignment*0.3+s.chainHealth*0.2,0.0,100.0);

   //--- LIFE SCORE: is the story alive? (emergent) ---------------
   s.lifeScore = F72Clamp(
        s.forceScore        *0.30 +
        s.alignment         *0.25 +
        s.continuation      *0.20 +
        (100.0-s.compression)*0.10 +   // room to breathe
        s.convexity         *0.15 , 0.0,100.0);

   //--- STORY STABILITY: is the story coherent / not flipping? ----
   // proxy: alignment strength minus contradiction
   s.storyStability = F72Clamp(s.alignment*0.6 + s.regimeScore*0.4 - s.contradiction*0.3,0.0,100.0);

   //--- probability cloud (Layer 12) ------------------------------
   double cont=s.continuation, term=100.0-s.continuation*0.5-s.alignment*0.2, trans=s.contradiction+ (100.0-s.alignment)*0.5;
   double tot=MathMax(cont+term+trans,1e-6);
   s.pContinuation=cont/tot*100.0; s.pTerminal=term/tot*100.0; s.pTransfer=trans/tot*100.0;

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
   double price=EntryPrice(dir);
   if(atr<=0) atr=SymbolInfoDouble(_Symbol,SYMBOL_POINT)*100;
   double stopDist=g_risk.ValidateStopDistance(atr*2.0,atr);
   d.stop  =(dir==1?price-stopDist:price+stopDist);
   d.target=(dir==1?price+stopDist*2.0:price-stopDist*2.0); // RR2 placeholder; Phase 4 uses budget target
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

double Ema(ENUM_TIMEFRAMES tf,int len)
{
   double c[]; ArraySetAsSeries(c,true);
   int need=len*4;
   if(CopyClose(_Symbol,tf,0,need,c)<len) return(iClose(_Symbol,tf,0));
   double a=2.0/(len+1.0); double e=c[ArraySize(c)-1];
   for(int i=ArraySize(c)-2;i>=0;i--) e=e+a*(c[i]-e);
   return(e);
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
