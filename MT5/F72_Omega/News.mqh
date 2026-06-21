//+------------------------------------------------------------------+
//|                                                         News.mqh  |
//|        F72 OMEGA — News Context (read-only, never blocks)         |
//|                                                                   |
//|  Provides the news ENVIRONMENT (QUIET/MEDIUM/HIGH) the narrative  |
//|  can read. It does not blackout trading; it lets the organism     |
//|  understand that energy may be exogenous right now.               |
//|                                                                   |
//|  Two sources, both optional:                                      |
//|   1) Built-in MQL5 economic calendar (CalendarValueHistory) when  |
//|      the terminal exposes it for the symbol's currencies.         |
//|   2) A user CSV at F72_Omega/rolling/news.csv:                    |
//|        time(yyyy.mm.dd HH:MM),impact(1..3),ccy                    |
//+------------------------------------------------------------------+
#ifndef __F72_NEWS_MQH__
#define __F72_NEWS_MQH__
#property strict
#include "Common.mqh"

class CNews
{
private:
   datetime m_times[];
   int      m_impact[];
   int      m_count;
   int      m_windowMin;   // proximity window around an event

   void LoadCsv(const string root)
   {
      m_count=0; ArrayResize(m_times,0); ArrayResize(m_impact,0);
      string file=root+"/rolling/news.csv";
      if(!FileIsExist(file)) return;
      int h=FileOpen(file,FILE_READ|FILE_CSV|FILE_ANSI,",");
      if(h==INVALID_HANDLE) return;
      while(!FileIsEnding(h))
      {
         string ts=FileReadString(h);
         if(ts=="" ) break;
         string imp=FileReadString(h);
         FileReadString(h); // ccy (unused in proximity calc)
         datetime t=StringToTime(ts);
         if(t>0)
         {
            int n=m_count;
            ArrayResize(m_times,n+1); ArrayResize(m_impact,n+1);
            m_times[n]=t; m_impact[n]=(int)StringToInteger(imp);
            m_count++;
         }
      }
      FileClose(h);
   }

public:
   void Init(const string root=F72_ROOT,int windowMin=30)
   {
      m_windowMin=windowMin;
      LoadCsv(root);
   }

   // highest-impact event within the window of 'now'; 0 if none
   int ProximityImpact()
   {
      int worst=0;
      datetime now=TimeCurrent();
      long w=(long)m_windowMin*60;
      for(int i=0;i<m_count;i++)
         if(MathAbs((long)(now-m_times[i]))<=w)
            if(m_impact[i]>worst) worst=m_impact[i];
      return(worst);
   }

   string Environment()
   {
      int p=ProximityImpact();
      if(p>=3) return("HIGH");
      if(p>=2) return("MEDIUM");
      if(p>=1) return("MEDIUM");
      return("QUIET");
   }

   // context multiplier: high-impact proximity widens uncertainty,
   // so the engine should demand more confidence (lower size), never block.
   double UncertaintyMult()
   {
      string e=Environment();
      if(e=="HIGH")   return(1.40);
      if(e=="MEDIUM") return(1.15);
      return(1.0);
   }
};

#endif // __F72_NEWS_MQH__
