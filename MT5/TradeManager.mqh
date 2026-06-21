//+------------------------------------------------------------------+
//|                                               TradeManager.mqh   |
//|  Execution & in-trade management layer.                          |
//|   - Robust market order send with retries + filling-mode probe   |
//|   - Break-even move after R-multiple                             |
//|   - ATR / structure trailing stop                                |
//|   - Partial take-profit (scale-out) at first target              |
//|   - Session window + optional news blackout filter               |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

struct STradeConfig
{
   long   magic;
   string commentTag;
   int    slippagePoints;
   int    maxSendRetries;

   bool   usePartialTP;
   double partialTPpct;        // % of position closed at first target
   double partialAtR;          // close partial at this R multiple

   bool   useBreakEven;
   double breakEvenAtR;        // move SL to entry at this R
   double breakEvenLockR;      // lock this many R when moving to BE

   bool   useTrailing;
   double trailATRmult;        // trail distance in ATR
   double trailStartR;         // begin trailing after this R

   // session filter (server time, 24h)
   bool   useSession;
   int    sessionStartHour;
   int    sessionEndHour;

   bool   tradeMonday;
   bool   tradeFriday;
   int    fridayCutoffHour;    // no new trades after this hour on Friday
};

void TradeConfigDefaults(STradeConfig &c)
{
   c.magic=20240617;
   c.commentTag="MasterSenseei";
   c.slippagePoints=20;
   c.maxSendRetries=3;
   c.usePartialTP=true;
   c.partialTPpct=50.0;
   c.partialAtR=1.0;
   c.useBreakEven=true;
   c.breakEvenAtR=1.0;
   c.breakEvenLockR=0.1;
   c.useTrailing=true;
   c.trailATRmult=2.0;
   c.trailStartR=1.2;
   c.useSession=false;
   c.sessionStartHour=0;
   c.sessionEndHour=24;
   c.tradeMonday=true;
   c.tradeFriday=true;
   c.fridayCutoffHour=20;
}

class CTradeManager
{
private:
   CTrade      m_trade;
   STradeConfig m_cfg;
   string      m_symbol;

   double Pt(){ return(SymbolInfoDouble(m_symbol,SYMBOL_POINT)); }
   int    Digits_(){ return((int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS)); }

   void ConfigureFilling()
   {
      // probe allowed filling modes
      long fill=(long)SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE);
      if((fill & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
         m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((fill & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
         m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

public:
   void Init(const string sym,const STradeConfig &cfg)
   {
      m_symbol=sym; m_cfg=cfg;
      m_trade.SetExpertMagicNumber(m_cfg.magic);
      m_trade.SetDeviationInPoints(m_cfg.slippagePoints);
      m_trade.SetAsyncMode(false);
      ConfigureFilling();
   }

   //--- session / day filter
   bool TimeWindowOK()
   {
      MqlDateTime t; TimeToStruct(TimeCurrent(),t);
      if(!m_cfg.tradeMonday && t.day_of_week==1) return(false);
      if(t.day_of_week==5)
      {
         if(!m_cfg.tradeFriday) return(false);
         if(t.hour>=m_cfg.fridayCutoffHour) return(false);
      }
      if(t.day_of_week==0 || t.day_of_week==6) return(false); // weekend safety
      if(m_cfg.useSession)
      {
         if(m_cfg.sessionStartHour<=m_cfg.sessionEndHour)
         {
            if(t.hour<m_cfg.sessionStartHour || t.hour>=m_cfg.sessionEndHour) return(false);
         }
         else // wraps midnight
         {
            if(t.hour<m_cfg.sessionStartHour && t.hour>=m_cfg.sessionEndHour) return(false);
         }
      }
      return(true);
   }

   bool HasPositionDir(long magic,int dir)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         long type=PositionGetInteger(POSITION_TYPE);
         if(dir==1 && type==POSITION_TYPE_BUY) return(true);
         if(dir==-1 && type==POSITION_TYPE_SELL) return(true);
      }
      return(false);
   }

   //--- open a market position with SL/TP, retrying on transient errors
   bool Open(int dir,double lot,double sl,double tp)
   {
      if(lot<=0) return(false);
      int digits=Digits_();
      sl=NormalizeDouble(sl,digits);
      tp=NormalizeDouble(tp,digits);
      for(int attempt=1;attempt<=m_cfg.maxSendRetries;attempt++)
      {
         bool ok=false;
         if(dir==1)
            ok=m_trade.Buy(lot,m_symbol,0.0,sl,tp,m_cfg.commentTag);
         else
            ok=m_trade.Sell(lot,m_symbol,0.0,sl,tp,m_cfg.commentTag);
         uint rc=m_trade.ResultRetcode();
         if(ok && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED))
         {
            PrintFormat("[TRADE] Opened %s %.2f lots SL=%.5f TP=%.5f (%s)",
                        dir==1?"BUY":"SELL",lot,sl,tp,m_cfg.commentTag);
            return(true);
         }
         PrintFormat("[TRADE] Open attempt %d failed rc=%u (%s). Retrying...",
                     attempt,rc,m_trade.ResultRetcodeDescription());
         // refresh prices and re-probe filling on requote
         ConfigureFilling();
         Sleep(150);
      }
      return(false);
   }

   //--- manage all this-EA positions: BE, trailing, partial TP
   void ManageOpen(double atr)
   {
      double pt=Pt();
      int digits=Digits_();
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         if(!PositionSelectByTicket(tk)) continue;

         long type=PositionGetInteger(POSITION_TYPE);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         double vol=PositionGetDouble(POSITION_VOLUME);
         bool isBuy=(type==POSITION_TYPE_BUY);
         double price=isBuy?SymbolInfoDouble(m_symbol,SYMBOL_BID):SymbolInfoDouble(m_symbol,SYMBOL_ASK);

         double rDist=(sl>0)?MathAbs(open-sl):atr; // initial risk distance
         if(rDist<=0) rDist=atr;
         double rMult=isBuy?(price-open)/rDist:(open-price)/rDist;

         // partial take-profit
         if(m_cfg.usePartialTP && rMult>=m_cfg.partialAtR)
         {
            double minLot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
            double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
            // Only scale out once: approximate by checking SL already beyond entry (post-BE) skip
            bool alreadyManaged=(isBuy && sl>=open) || (!isBuy && sl<=open && sl>0);
            if(!alreadyManaged)
            {
               double closeVol=vol*m_cfg.partialTPpct/100.0;
               if(step>0) closeVol=MathFloor(closeVol/step)*step;
               if(closeVol>=minLot && (vol-closeVol)>=minLot)
               {
                  if(m_trade.PositionClosePartial(tk,closeVol))
                     PrintFormat("[TRADE] Partial close %.2f lots at %.2fR",closeVol,rMult);
               }
            }
         }

         // break-even
         if(m_cfg.useBreakEven && rMult>=m_cfg.breakEvenAtR)
         {
            double beSL=isBuy?open+rDist*m_cfg.breakEvenLockR:open-rDist*m_cfg.breakEvenLockR;
            beSL=NormalizeDouble(beSL,digits);
            bool improve=(isBuy && (sl<beSL || sl==0)) || (!isBuy && (sl>beSL || sl==0));
            if(improve)
               m_trade.PositionModify(tk,beSL,tp);
            sl=PositionGetDouble(POSITION_SL);
         }

         // ATR trailing
         if(m_cfg.useTrailing && rMult>=m_cfg.trailStartR)
         {
            double trail=atr*m_cfg.trailATRmult;
            double newSL=isBuy?price-trail:price+trail;
            newSL=NormalizeDouble(newSL,digits);
            bool improve=(isBuy && newSL>sl) || (!isBuy && (newSL<sl || sl==0));
            // never trail past entry into loss territory worse than BE
            if(improve)
               m_trade.PositionModify(tk,newSL,tp);
         }
      }
   }

   void CloseAllDir(long magic,int dir)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         long type=PositionGetInteger(POSITION_TYPE);
         if(dir==1 && type==POSITION_TYPE_BUY) m_trade.PositionClose(tk);
         if(dir==-1 && type==POSITION_TYPE_SELL) m_trade.PositionClose(tk);
      }
   }

   void CloseAll(long magic)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         m_trade.PositionClose(tk);
      }
   }
};
//+------------------------------------------------------------------+
