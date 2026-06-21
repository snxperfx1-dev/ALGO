//+------------------------------------------------------------------+
//|                                                      Capital.mqh  |
//|              F72 OMEGA — Capital as a Living Organism             |
//|                                                                   |
//|  Tracks equity peaks and daily/weekly anchors and runs a          |
//|  drawdown STATE MACHINE. Exposes a throttle multiplier that the   |
//|  Risk layer reads. Capital does not sit outside the narrative —   |
//|  it breathes with it, but enforces hard survival limits.          |
//|                                                                   |
//|  Limits (from the philosophy): daily 3% · weekly 8% · hard 15%.   |
//+------------------------------------------------------------------+
#ifndef __F72_CAPITAL_MQH__
#define __F72_CAPITAL_MQH__
#property strict
#include "Common.mqh"
#include "Logger.mqh"

class CCapital
{
private:
   CLogger     *m_log;
   double       m_dailyLimitPct;
   double       m_weeklyLimitPct;
   double       m_hardLimitPct;
   double       m_cautionPct;     // soft throttle threshold (fraction of daily)

   double       m_equityPeak;
   double       m_dayAnchor;
   double       m_weekAnchor;
   int          m_dayStamp;
   int          m_weekStamp;
   ENUM_DD_STATE m_state;

   int DayStamp(){ MqlDateTime t; TimeToStruct(TimeCurrent(),t); return(t.year*1000+t.day_of_year); }
   int WeekStamp()
   {
      MqlDateTime t; TimeToStruct(TimeCurrent(),t);
      // ISO-ish week index from day_of_year
      return(t.year*100+(t.day_of_year/7));
   }

public:
   void Init(CLogger *log,double dailyPct=3.0,double weeklyPct=8.0,double hardPct=15.0,double cautionFrac=0.6)
   {
      m_log=log;
      m_dailyLimitPct=dailyPct; m_weeklyLimitPct=weeklyPct; m_hardLimitPct=hardPct;
      m_cautionPct=cautionFrac;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      m_equityPeak=eq; m_dayAnchor=eq; m_weekAnchor=eq;
      m_dayStamp=DayStamp(); m_weekStamp=WeekStamp();
      m_state=DD_NORMAL;
   }

   void Update()
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq>m_equityPeak) m_equityPeak=eq;

      int ds=DayStamp();
      if(ds!=m_dayStamp)
      {
         m_dayStamp=ds; m_dayAnchor=eq;
         if(m_state==DD_DAILY_LOCK || m_state==DD_CAUTION) m_state=DD_NORMAL;
      }
      int ws=WeekStamp();
      if(ws!=m_weekStamp)
      {
         m_weekStamp=ws; m_weekAnchor=eq;
         if(m_state==DD_WEEKLY_LOCK) m_state=DD_NORMAL;
      }

      double dayDD =(m_dayAnchor>0) ?(m_dayAnchor-eq)/m_dayAnchor*100.0 :0.0;
      double weekDD=(m_weekAnchor>0)?(m_weekAnchor-eq)/m_weekAnchor*100.0:0.0;
      double hardDD=(m_equityPeak>0)?(m_equityPeak-eq)/m_equityPeak*100.0:0.0;

      ENUM_DD_STATE prev=m_state;
      if(hardDD>=m_hardLimitPct)            m_state=DD_HALT;
      else if(weekDD>=m_weeklyLimitPct)     m_state=DD_WEEKLY_LOCK;
      else if(dayDD>=m_dailyLimitPct)       m_state=DD_DAILY_LOCK;
      else if(dayDD>=m_dailyLimitPct*m_cautionPct) m_state=DD_CAUTION;
      else if(m_state==DD_CAUTION && dayDD<m_dailyLimitPct*m_cautionPct*0.5) m_state=DD_NORMAL;

      if(m_state!=prev && m_log!=NULL)
         m_log.Warn("Capital",StringFormat("DD state %d -> %d (day %.2f%% week %.2f%% hard %.2f%%)",
                    (int)prev,(int)m_state,dayDD,weekDD,hardDD));
   }

   ENUM_DD_STATE State(){ return(m_state); }
   bool TradingAllowed(){ return(m_state==DD_NORMAL || m_state==DD_CAUTION); }

   // throttle multiplier applied to risk sizing
   double Throttle()
   {
      switch(m_state)
      {
         case DD_NORMAL:  return(1.0);
         case DD_CAUTION: return(0.5);
         default:         return(0.0);   // locks: no new risk
      }
   }

   double EquityPeak(){ return(m_equityPeak); }
   double DayAnchor(){ return(m_dayAnchor); }
   double WeekAnchor(){ return(m_weekAnchor); }
   double DayDDpct()
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      return((m_dayAnchor>0)?(m_dayAnchor-eq)/m_dayAnchor*100.0:0.0);
   }
   double HardDDpct()
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      return((m_equityPeak>0)?(m_equityPeak-eq)/m_equityPeak*100.0:0.0);
   }
};

#endif // __F72_CAPITAL_MQH__
