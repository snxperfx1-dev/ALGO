//+------------------------------------------------------------------+
//|                                                   CurveState.mqh  |
//|              F72 OMEGA — Curve Data Structures (Layer 0/4)        |
//|                                                                   |
//|  "Price is the visible consequence of millions of participants    |
//|   interacting through time. Everything becomes curves."           |
//|                                                                   |
//|  SCurve = the structural + physics state of ONE timeframe's wave  |
//|  (the f_se / f_phys output). SCurveStack = the fractal organism:  |
//|  the same instrument perceived across M1·M3·M5·M15·H1·H4·D1 as    |
//|  ONE body, with alignment measured between rungs.                 |
//+------------------------------------------------------------------+
#ifndef __F72_CURVESTATE_MQH__
#define __F72_CURVESTATE_MQH__
#property strict
#include "Common.mqh"

#define F72_STACK_TFS 7

struct SCurve
{
   bool            valid;
   ENUM_TIMEFRAMES tf;
   int             dir;        // wave direction by origin (-1/0/1)
   int             phase;      // 1..14 (see PhaseText / CurvePhaseStr)
   double          atr;

   // physics (f_phys)
   double          vel, acc, conv, csm;
   double          eff, disp;
   bool            bullImp, bearImp, bullDec, bearDec;
   bool            bullCH, bearCH;
   bool            vd70, vd50;

   // structure (f_se)
   double          curSH, curSL, prSH, prSL;
   int             bos, ch;        // -1/0/1 this bar
   double          ft, fb;         // flip zone top/bottom (point-4 origin)
   double          inv;            // invalidation (protective extreme)
   double          tgt;            // measured objective
   double          p4h, p4l;
   double          cycH, cycL;     // running cycle extremes

   // lifecycle context
   bool            atExtreme, extended, atFlip;
   double          retrFrac;       // retrace fraction toward flip zone
   int             recBrk;         // recursive transition count
   double          waveProgress;   // f_se internal 0..100

   // raw component scores (consumed by Force/Compression/Convexity)
   double          convScore;      // |csm| normalised
   double          expScore;       // efficiency + displacement
   double          absScore;       // absorption
   double          compIdx;        // local compression index
   double          modelFit;       // 0..100
   double          closePrice;
};

void CurveInit(SCurve &c)
{
   c.valid=false; c.tf=PERIOD_CURRENT; c.dir=0; c.phase=0; c.atr=0;
   c.vel=0; c.acc=0; c.conv=0; c.csm=0; c.eff=0; c.disp=0;
   c.bullImp=false; c.bearImp=false; c.bullDec=false; c.bearDec=false;
   c.bullCH=false; c.bearCH=false; c.vd70=false; c.vd50=false;
   c.curSH=0; c.curSL=0; c.prSH=0; c.prSL=0; c.bos=0; c.ch=0;
   c.ft=0; c.fb=0; c.inv=0; c.tgt=0; c.p4h=0; c.p4l=0; c.cycH=0; c.cycL=0;
   c.atExtreme=false; c.extended=false; c.atFlip=false; c.retrFrac=0; c.recBrk=0;
   c.waveProgress=0; c.convScore=0; c.expScore=0; c.absScore=0; c.compIdx=0;
   c.modelFit=0; c.closePrice=0;
}

string CurvePhaseStr(int p)
{
   switch(p)
   {
      case 1:  return("Expansion");
      case 2:  return("Momentum Decay");
      case 3:  return("Expansion Induction");
      case 4:  return("Expansion Liquidity");
      case 5:  return("Peak Formation");
      case 6:  return("Trough Formation");
      case 7:  return("Energy Transfer");
      case 8:  return("Creation");
      case 9:  return("Flip-Zone Test");
      case 10: return("Retracement Induction");
      case 11: return("Capacity Drain");
      case 12: return("Liquidity Sweep");
      case 13: return("Demand Return");
      case 14: return("Supply Return");
      default: return("Forming");
   }
}

//==================================================================
// THE FRACTAL STACK — one organism across timeframes (Layer 4)
//==================================================================
struct SCurveStack
{
   SCurve  tf[F72_STACK_TFS];   // M1,M3,M5,M15,H1,H4,D1
   int     n;
   int     canonical;           // index of chart-TF rung (or nearest)
   int     stackDir;            // dominant direction across rungs
   double  stackPct;            // agreement %
   // is the lower TF supporting or fighting the higher TF?
   double  upwardSupport;       // 0..100: M1->H1->H4 coherence
};

void StackInit(SCurveStack &s)
{
   for(int i=0;i<F72_STACK_TFS;i++) CurveInit(s.tf[i]);
   s.n=0; s.canonical=2; s.stackDir=0; s.stackPct=50.0; s.upwardSupport=50.0;
}

#endif // __F72_CURVESTATE_MQH__
