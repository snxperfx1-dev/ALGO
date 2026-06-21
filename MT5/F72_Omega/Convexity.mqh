//+------------------------------------------------------------------+
//|                                                    Convexity.mqh  |
//|                F72 OMEGA — Convexity / Curvature Maturity         |
//|                                                                   |
//|  Energy bends. Convexity measures how mature the bend is — from   |
//|  a straight impulse (low) to a fully-formed reversal arc (high).  |
//|  Wide convexity precedes large recursive transitions; the         |
//|  curvature maturity tells the narrative how 'cooked' the curve is.|
//+------------------------------------------------------------------+
#ifndef __F72_CONVEXITY_MQH__
#define __F72_CONVEXITY_MQH__
#property strict
#include "Common.mqh"
#include "CurveState.mqh"

class CConvexity
{
public:
   // 0..100 curvature maturity of a curve
   double Maturity(const SCurve &c)
   {
      if(!c.valid) return(F72_NEUTRAL);
      double base = c.convScore;                                 // |csm| normalised
      double transfer = ((c.dir==1 && c.bearImp)||(c.dir==-1 && c.bullImp))?25.0:0.0; // counter-impulse = bending
      double recursion = F72Clamp(c.recBrk*20.0,0.0,40.0);       // recursive breaks = maturing arc
      double retrace = c.retrFrac*30.0;                          // retracing toward flip = arc completing
      double phaseMat = (c.phase>=8?20.0:c.phase>=5?12.0:c.phase>=2?6.0:0.0);
      double raw = base*0.45 + transfer + recursion*0.5 + retrace*0.5 + phaseMat;
      return(F72Clamp(raw,0.0,100.0));
   }

   // convexity "shift" sign: is the curve bending up or down right now?
   int ShiftDir(const SCurve &c)
   {
      if(!c.valid) return(0);
      double th=c.atr*0.01;
      if(c.csm>th)  return(1);
      if(c.csm<-th) return(-1);
      return(0);
   }
};

#endif // __F72_CONVEXITY_MQH__
