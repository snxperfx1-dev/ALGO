//+------------------------------------------------------------------+
//|                                                        Force.mqh  |
//|                 F72 OMEGA — Force Intelligence                   |
//|                                                                   |
//|  Expansion / displacement force of a curve: how hard is energy    |
//|  travelling right now, and is it directional? Energy cannot       |
//|  travel infinitely in straight lines — force decays into curves.  |
//+------------------------------------------------------------------+
#ifndef __F72_FORCE_MQH__
#define __F72_FORCE_MQH__
#property strict
#include "Common.mqh"
#include "CurveState.mqh"

class CForce
{
public:
   // 0..100 directional force of a single curve
   double Score(const SCurve &c)
   {
      if(!c.valid) return(F72_NEUTRAL);
      double eff = F72Map(c.eff,0.0,1.0,0.0,100.0);
      double dsp = F72Map(c.disp,0.0,3.0,0.0,100.0);
      double imp = ((c.dir==1 && c.bullImp)||(c.dir==-1 && c.bearImp))?100.0:0.0;
      double expanding = c.expScore;
      double velMag = F72Map(MathAbs(c.vel)/MathMax(c.atr,1e-10),0.0,1.0,0.0,100.0);
      double raw = eff*0.25 + dsp*0.20 + expanding*0.25 + imp*0.15 + velMag*0.15;
      // decay penalty: momentum dying reduces force
      if((c.dir==1 && c.bullDec)||(c.dir==-1 && c.bearDec)) raw*=0.80;
      if(c.vd50) raw*=0.85;
      return(F72Clamp(raw,0.0,100.0));
   }

   // stack-weighted force: higher timeframes carry more weight
   double StackForce(const SCurveStack &s)
   {
      double w[7]; w[0]=0.6; w[1]=0.8; w[2]=1.0; w[3]=1.3; w[4]=1.7; w[5]=2.0; w[6]=2.4;
      double num=0,den=0;
      for(int i=0;i<F72_STACK_TFS;i++)
      {
         if(!s.tf[i].valid) continue;
         num+=Score(s.tf[i])*w[i]; den+=w[i];
      }
      return(den>0?F72Clamp(num/den,0.0,100.0):F72_NEUTRAL);
   }
};

#endif // __F72_FORCE_MQH__
