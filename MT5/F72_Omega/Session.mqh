//+------------------------------------------------------------------+
//|                                                      Session.mqh  |
//|        F72 OMEGA — Session Context (read-only, never blocks)      |
//|                                                                   |
//|  The engine trades 24/5. Sessions are CONTEXT the narrative can   |
//|  read (energy behaves differently across Asia/London/NY), never   |
//|  a blackout. "Don't trade Fridays" is a human shortcut — absent.  |
//+------------------------------------------------------------------+
#ifndef __F72_SESSION_MQH__
#define __F72_SESSION_MQH__
#property strict
#include "Common.mqh"

class CSession
{
public:
   string Current(){ return(F72Session(TimeCurrent())); }

   // a coarse "energy expectation" multiplier by session — context only
   double EnergyBias()
   {
      string s=Current();
      if(s=="OVERLAP") return(1.15);   // London/NY overlap: highest energy
      if(s=="LONDON")  return(1.05);
      if(s=="NY")      return(1.05);
      if(s=="ASIA")    return(0.90);   // compression-prone
      return(0.85);                    // off-hours
   }

   bool IsWeekendGap()
   {
      MqlDateTime d; TimeToStruct(TimeCurrent(),d);
      return(d.day_of_week==0 || d.day_of_week==6);
   }
};

#endif // __F72_SESSION_MQH__
