//+------------------------------------------------------------------+
//|                                                  Compression.mqh  |
//|            F72 OMEGA — Compression Intelligence (Layer 5)         |
//|                                                                   |
//|  "The greatest edge. Not direction. Compression."                 |
//|  Compression determines how much TIME price has. Wide convexity   |
//|  => large recursive transitions. Tight => failure swings, fast    |
//|  entries, violence. Tracked everywhere, not just locally.         |
//|                                                                   |
//|  Score 0..100 where HIGH = tightly squeezed (little room to       |
//|  breathe), LOW = wide / breathing.                                |
//+------------------------------------------------------------------+
#ifndef __F72_COMPRESSION_MQH__
#define __F72_COMPRESSION_MQH__
#property strict
#include "Common.mqh"
#include "CurveState.mqh"

class CCompression
{
private:
   string m_symbol;

   double AtrLen(ENUM_TIMEFRAMES tf,int len)
   {
      MqlRates r[]; ArraySetAsSeries(r,true);
      if(CopyRates(m_symbol,tf,0,len+2,r)<len+1) return(0.0);
      double s=0; for(int k=1;k<=len;k++) s+=MathMax(r[k].high-r[k].low,MathMax(MathAbs(r[k].high-r[k+1].close),MathAbs(r[k].low-r[k+1].close)));
      return(s/len);
   }

public:
   void Init(const string sym){ m_symbol=sym; }

   // compression of one curve/timeframe (HIGH = squeezed)
   double Score(const SCurve &c,ENUM_TIMEFRAMES tf,int atrLen=14)
   {
      if(!c.valid) return(F72_NEUTRAL);

      // 1) ATR contraction: short ATR vs long ATR (tight range => squeezed)
      double aShort=AtrLen(tf,atrLen);
      double aLong =AtrLen(tf,atrLen*4);
      double contraction=(aLong>0)?F72Map(aShort/aLong,0.4,1.3,100.0,0.0):F72_NEUTRAL;

      // 2) the curve's own local compression index (low disp + low eff)
      double local=c.compIdx;

      // 3) flip-zone proximity: price coiling inside the flip zone squeezes
      double coil=0.0;
      if(c.ft!=0.0 && c.fb!=0.0)
      {
         double mid=(c.ft+c.fb)/2.0;
         double half=MathMax((c.ft-c.fb)/2.0,1e-10);
         double d=MathAbs(c.closePrice-mid)/half;        // 0 at mid, 1 at edge
         coil=F72Clamp((1.0-MathMin(d,1.0))*100.0,0.0,100.0);
      }

      // 4) late-phase retracement coil (capacity drain / sweep build)
      double phaseCoil=(c.phase==11||c.phase==12||c.phase==2)?60.0:0.0;

      double raw=contraction*0.40 + local*0.30 + coil*0.20 + phaseCoil*0.10;
      return(F72Clamp(raw,0.0,100.0));
   }

   // "can price breathe?" — inverse, for life scoring
   double BreathingRoom(const SCurve &c,ENUM_TIMEFRAMES tf,int atrLen=14)
   {
      return(100.0-Score(c,tf,atrLen));
   }
};

#endif // __F72_COMPRESSION_MQH__
