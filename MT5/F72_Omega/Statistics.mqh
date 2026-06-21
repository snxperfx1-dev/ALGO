//+------------------------------------------------------------------+
//|                                                  Statistics.mqh   |
//|        F72 OMEGA — Statistical Memory & Self-Observation Feed     |
//|                                                                   |
//|  Aggregates closed-campaign history into rolling metrics that     |
//|  Layer 14 (self-observation) and StoryConfidence read:            |
//|    hit rate · expectancy · regime drift · sample size.            |
//+------------------------------------------------------------------+
#ifndef __F72_STATISTICS_MQH__
#define __F72_STATISTICS_MQH__
#property strict
#include "Common.mqh"

class CStatistics
{
private:
   int    m_n;
   int    m_wins;
   double m_sumPnl;
   double m_sumWin;
   double m_sumLoss;
   double m_recentPnl[];     // rolling window of last N outcomes
   int    m_window;

public:
   void Init(int window=50)
   {
      m_window=window; Reset();
   }
   void Reset()
   {
      m_n=0; m_wins=0; m_sumPnl=0; m_sumWin=0; m_sumLoss=0; ArrayResize(m_recentPnl,0);
   }

   void Ingest(const SCampaign &c)
   {
      if(!c.closed) return;
      m_n++; m_sumPnl+=c.pnl;
      if(c.pnl>=0){ m_wins++; m_sumWin+=c.pnl; } else m_sumLoss+=c.pnl;
      Push(c.pnl);
   }

   void IngestAll(const SCampaign &arr[])
   {
      Reset();
      for(int i=0;i<ArraySize(arr);i++) Ingest(arr[i]);
   }

   void Push(double pnl)
   {
      int n=ArraySize(m_recentPnl);
      if(n<m_window){ ArrayResize(m_recentPnl,n+1); m_recentPnl[n]=pnl; }
      else
      {
         for(int i=0;i<m_window-1;i++) m_recentPnl[i]=m_recentPnl[i+1];
         m_recentPnl[m_window-1]=pnl;
      }
   }

   int    Samples(){ return(m_n); }
   double HitRate(){ return(m_n>0?(double)m_wins/m_n*100.0:50.0); }
   double AvgPnl(){ return(m_n>0?m_sumPnl/m_n:0.0); }
   double ProfitFactor(){ return(m_sumLoss<0?m_sumWin/MathAbs(m_sumLoss):(m_sumWin>0?3.0:1.0)); }

   //--- rolling recent hit rate (the self-observation window)
   double RecentHitRate()
   {
      int n=ArraySize(m_recentPnl);
      if(n==0) return(50.0);
      int w=0; for(int i=0;i<n;i++) if(m_recentPnl[i]>=0) w++;
      return((double)w/n*100.0);
   }

   //--- regime drift: dispersion of recent outcomes (0 stable .. 100 erratic)
   double RegimeDrift()
   {
      int n=ArraySize(m_recentPnl);
      if(n<5) return(0.0);
      double mean=0; for(int i=0;i<n;i++) mean+=m_recentPnl[i]; mean/=n;
      double var=0; for(int i=0;i<n;i++) var+=MathPow(m_recentPnl[i]-mean,2); var/=n;
      double sd=MathSqrt(var);
      double scale=MathMax(MathAbs(mean),1e-6);
      return(F72Clamp(sd/scale*40.0,0.0,100.0));
   }
};

#endif // __F72_STATISTICS_MQH__
