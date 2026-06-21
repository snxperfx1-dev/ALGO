//+------------------------------------------------------------------+
//|                                                         Risk.mqh  |
//|             F72 OMEGA — Risk That Breathes                       |
//|                                                                   |
//|  Static risk contradicts the philosophy. Risk allocation is a     |
//|  CONSEQUENCE of the trinity + lower scores, not an arbitrary %.   |
//|                                                                   |
//|   base 0.25%  ·  normal 0.5%  ·  strong 1%  ·  exceptional 2%     |
//|                                                                   |
//|  Final size = tier  x  capitalThrottle  x  (1/newsUncertainty)    |
//|  x  confidenceFactor, then floored/capped and converted to lots   |
//|  from the actual stop distance. Hard exposure + spread guards.    |
//+------------------------------------------------------------------+
#ifndef __F72_RISK_MQH__
#define __F72_RISK_MQH__
#property strict
#include "Common.mqh"
#include "Logger.mqh"
#include "Capital.mqh"
#include "News.mqh"

struct SRiskParams
{
   double baseRiskPct;        // 0.25
   double normalRiskPct;      // 0.5
   double strongRiskPct;      // 1.0
   double exceptionalRiskPct; // 2.0
   double maxTotalExposurePct;// max simultaneous open risk
   int    maxConcurrent;      // max concurrent campaign positions
   double maxSpreadPoints;
   double minStopATRmult;
   double maxLotCap;
   bool   useEquity;
};

void RiskParamsDefaults(SRiskParams &p)
{
   p.baseRiskPct=0.25; p.normalRiskPct=0.5; p.strongRiskPct=1.0; p.exceptionalRiskPct=2.0;
   p.maxTotalExposurePct=4.0; p.maxConcurrent=6; p.maxSpreadPoints=60.0;
   p.minStopATRmult=0.6; p.maxLotCap=50.0; p.useEquity=true;
}

class CRiskEngine
{
private:
   CLogger  *m_log;
   CCapital *m_cap;
   CNews    *m_news;
   SRiskParams m_p;
   string   m_symbol;
   long     m_magic;

   double SizingBase()
   {
      return(m_p.useEquity?AccountInfoDouble(ACCOUNT_EQUITY):AccountInfoDouble(ACCOUNT_BALANCE));
   }

public:
   void Init(const string sym,long magic,CLogger *log,CCapital *cap,CNews *news,const SRiskParams &p)
   {
      m_symbol=sym; m_magic=magic; m_log=log; m_cap=cap; m_news=news; m_p=p;
   }

   //--- the narrative tier -> base risk percentage
   //  Driven by the trinity: a story must be ALIVE, STABLE and the
   //  engine must TRUST ITSELF to escalate size.
   double TierRiskPct(const SEngineState &s)
   {
      double trust=(s.lifeScore*0.45+s.storyStability*0.30+s.storyConfidence*0.25);
      // alignment + chain must corroborate for the top tier
      bool corroborated=(s.alignment>=66 && s.chainHealth>=60 && s.confidence>=60);
      if(trust>=82 && corroborated && s.contradiction<20) return(m_p.exceptionalRiskPct);
      if(trust>=68 && s.alignment>=55)                    return(m_p.strongRiskPct);
      if(trust>=55)                                       return(m_p.normalRiskPct);
      return(m_p.baseRiskPct);
   }

   //--- effective risk % after throttles
   double EffectiveRiskPct(const SEngineState &s)
   {
      double tier=TierRiskPct(s);
      double throttle=(m_cap!=NULL)?m_cap.Throttle():1.0;
      double newsMult=(m_news!=NULL)?(1.0/m_news.UncertaintyMult()):1.0;
      // engine self-doubt: low storyConfidence shrinks size further
      double confFactor=F72Map(s.storyConfidence,30.0,80.0,0.5,1.0);
      double eff=tier*throttle*newsMult*confFactor;
      return(F72Clamp(eff,0.0,m_p.exceptionalRiskPct));
   }

   //--- exposure / position / spread gates. Returns reason (R_NONE = ok)
   ENUM_REASON Gate(const SEngineState &s)
   {
      if(m_cap!=NULL)
      {
         ENUM_DD_STATE st=m_cap.State();
         if(st==DD_HALT)        return(R_RISK_HARD_HALT);
         if(st==DD_WEEKLY_LOCK) return(R_RISK_WEEKLY_LOCK);
         if(st==DD_DAILY_LOCK)  return(R_RISK_DAILY_LOCK);
      }
      if(CountPositions()>=m_p.maxConcurrent)        return(R_RISK_EXPOSURE_CAP);
      if(CurrentExposurePct()>=m_p.maxTotalExposurePct) return(R_RISK_EXPOSURE_CAP);
      if(!SpreadOK())                                return(R_SPREAD_GUARD);
      if(s.storyConfidence<30.0)                     return(R_CONFIDENCE_LOW);
      return(R_NONE);
   }

   bool SpreadOK()
   {
      double sp=(double)SymbolInfoInteger(m_symbol,SYMBOL_SPREAD);
      if(sp<=0)
      {
         double pt=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
         double a=SymbolInfoDouble(m_symbol,SYMBOL_ASK), b=SymbolInfoDouble(m_symbol,SYMBOL_BID);
         sp=(pt>0)?(a-b)/pt:0;
      }
      return(sp<=m_p.maxSpreadPoints);
   }

   int CountPositions()
   {
      int n=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         n++;
      }
      return(n);
   }

   double CurrentExposurePct()
   {
      double base=SizingBase(); if(base<=0) return(0.0);
      double tickVal=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSz =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickSz<=0) return(0.0);
      double risk=0.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         double sl=PositionGetDouble(POSITION_SL);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double vol=PositionGetDouble(POSITION_VOLUME);
         if(sl<=0) continue;
         risk+=MathAbs(open-sl)/tickSz*tickVal*vol;
      }
      return(risk/base*100.0);
   }

   double ValidateStopDistance(double rawDist,double atr)
   {
      double minATR=atr*m_p.minStopATRmult;
      double pt=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      long stopLvl=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
      double minBroker=(stopLvl+5)*pt;
      return(MathMax(rawDist,MathMax(minATR,minBroker)));
   }

   //--- convert risk% + stop distance to a normalized lot
   double CalcLot(double riskPct,double stopDistance)
   {
      if(riskPct<=0 || stopDistance<=0) return(0.0);
      double base=SizingBase();
      double riskMoney=base*riskPct/100.0;
      double tickVal=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSz =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickSz<=0 || tickVal<=0) return(0.0);
      double lossPerLot=stopDistance/tickSz*tickVal;
      if(lossPerLot<=0) return(0.0);
      double lot=riskMoney/lossPerLot;
      double minLot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double maxLot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      double step  =SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(step>0) lot=MathFloor(lot/step)*step;
      lot=MathMax(lot,minLot);
      lot=MathMin(lot,MathMin(maxLot,m_p.maxLotCap));
      return(NormalizeDouble(lot,2));
   }
};

#endif // __F72_RISK_MQH__
