//+------------------------------------------------------------------+
//|                                                RiskManager.mqh   |
//|  Hedge-fund-grade risk & capital protection layer.               |
//|   - Fixed-fractional position sizing from stop distance          |
//|   - ATR-floored / broker-stop-level-aware stop validation        |
//|   - Daily loss limit (hard stop for the trading day)             |
//|   - Max drawdown circuit breaker (equity peak based)             |
//|   - Exposure caps (max open positions, max risk concurrently)    |
//|   - Spread guard                                                  |
//+------------------------------------------------------------------+
#property strict

struct SRiskConfig
{
   double riskPerTradePct;     // % of equity risked per trade
   double maxDailyLossPct;     // halt trading after this daily loss
   double maxDrawdownPct;      // circuit breaker on equity peak drawdown
   double maxTotalRiskPct;     // max simultaneous open risk
   int    maxOpenPositions;    // cap on concurrent positions (this EA)
   double maxSpreadPoints;     // skip entries above this spread
   double minStopATRmult;      // floor stop distance at N * ATR
   double maxLotCap;           // absolute lot ceiling (safety)
   bool   useEquityForSizing;  // size off equity (true) or balance
};

void RiskConfigDefaults(SRiskConfig &c)
{
   c.riskPerTradePct  = 0.5;
   c.maxDailyLossPct  = 3.0;
   c.maxDrawdownPct   = 15.0;
   c.maxTotalRiskPct  = 2.0;
   c.maxOpenPositions = 3;
   c.maxSpreadPoints  = 35.0;
   c.minStopATRmult   = 0.6;
   c.maxLotCap        = 50.0;
   c.useEquityForSizing = true;
}

class CRiskManager
{
private:
   SRiskConfig m_cfg;
   string      m_symbol;
   long        m_magic;
   double      m_equityPeak;
   double      m_dayStartEquity;
   int         m_dayStamp;       // day-of-year stamp for daily reset
   bool        m_halted;
   string      m_haltReason;

   int DayStamp()
   {
      MqlDateTime t; TimeToStruct(TimeCurrent(),t);
      return(t.year*1000+t.day_of_year);
   }

public:
   void Init(const string sym,long magic,const SRiskConfig &cfg)
   {
      m_symbol=sym; m_magic=magic; m_cfg=cfg;
      m_equityPeak=AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartEquity=m_equityPeak;
      m_dayStamp=DayStamp();
      m_halted=false; m_haltReason="";
   }

   bool   IsHalted(){ return(m_halted); }
   string HaltReason(){ return(m_haltReason); }

   //--- call every tick to maintain equity tracking & breakers
   void Update()
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq>m_equityPeak) m_equityPeak=eq;

      // daily reset
      int ds=DayStamp();
      if(ds!=m_dayStamp)
      {
         m_dayStamp=ds;
         m_dayStartEquity=eq;
         // a new day clears a daily-loss halt, but NOT a drawdown halt
         if(m_haltReason=="DAILY_LOSS") { m_halted=false; m_haltReason=""; }
      }

      // daily loss limit
      double dayLossPct=(m_dayStartEquity>0)?(m_dayStartEquity-eq)/m_dayStartEquity*100.0:0.0;
      if(!m_halted && dayLossPct>=m_cfg.maxDailyLossPct)
      {
         m_halted=true; m_haltReason="DAILY_LOSS";
         PrintFormat("[RISK] Daily loss limit hit (%.2f%%). Trading halted for the day.",dayLossPct);
      }

      // max drawdown circuit breaker
      double ddPct=(m_equityPeak>0)?(m_equityPeak-eq)/m_equityPeak*100.0:0.0;
      if(!m_halted && ddPct>=m_cfg.maxDrawdownPct)
      {
         m_halted=true; m_haltReason="MAX_DRAWDOWN";
         PrintFormat("[RISK] Max drawdown breaker hit (%.2f%%). Trading halted.",ddPct);
      }
   }

   //--- count this EA's open positions on the symbol
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

   //--- current open risk (sum of |entry-sl| * value) as % equity
   double CurrentOpenRiskPct()
   {
      double base=SizingBase();
      if(base<=0) return(0.0);
      double risk=0.0;
      double tickVal=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSz =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickSz<=0) return(0.0);
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
         double dist=MathAbs(open-sl);
         double moneyRisk=dist/tickSz*tickVal*vol;
         risk+=moneyRisk;
      }
      return(risk/base*100.0);
   }

   double SizingBase()
   {
      return(m_cfg.useEquityForSizing?AccountInfoDouble(ACCOUNT_EQUITY):AccountInfoDouble(ACCOUNT_BALANCE));
   }

   //--- spread guard
   bool SpreadOK()
   {
      double spread=(double)SymbolInfoInteger(m_symbol,SYMBOL_SPREAD);
      if(spread<=0)
      {
         double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
         double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
         double pt=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
         spread=(pt>0)?(ask-bid)/pt:0;
      }
      return(spread<=m_cfg.maxSpreadPoints);
   }

   //--- can we open a new trade right now?
   bool CanOpen(string &reason)
   {
      if(m_halted){ reason="HALTED:"+m_haltReason; return(false); }
      if(CountPositions()>=m_cfg.maxOpenPositions){ reason="MAX_POSITIONS"; return(false); }
      if(CurrentOpenRiskPct()>=m_cfg.maxTotalRiskPct){ reason="MAX_TOTAL_RISK"; return(false); }
      if(!SpreadOK()){ reason="SPREAD_TOO_WIDE"; return(false); }
      reason="OK";
      return(true);
   }

   //--- validate / floor a stop distance against ATR and broker stop level
   double ValidateStopDistance(double rawDist,double atr)
   {
      double minByATR=atr*m_cfg.minStopATRmult;
      double pt=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      long   stopLevel=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
      double minByBroker=(stopLevel+5)*pt;
      double d=MathMax(rawDist,MathMax(minByATR,minByBroker));
      return(d);
   }

   //--- position size from risk %, stop distance in price
   double CalcLot(double stopDistance)
   {
      double base=SizingBase();
      double riskMoney=base*m_cfg.riskPerTradePct/100.0;
      double tickVal=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSz =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickSz<=0 || tickVal<=0 || stopDistance<=0) return(0.0);
      double lossPerLot=stopDistance/tickSz*tickVal;
      if(lossPerLot<=0) return(0.0);
      double lot=riskMoney/lossPerLot;

      double minLot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double maxLot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      double step  =SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(step>0) lot=MathFloor(lot/step)*step;
      lot=MathMax(lot,minLot);
      lot=MathMin(lot,MathMin(maxLot,m_cfg.maxLotCap));
      return(NormalizeDouble(lot,2));
   }

   double EquityPeak(){ return(m_equityPeak); }
   double DayStartEquity(){ return(m_dayStartEquity); }
};
//+------------------------------------------------------------------+
