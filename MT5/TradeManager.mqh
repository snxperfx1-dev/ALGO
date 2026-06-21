//+------------------------------------------------------------------+
//|                                               TradeManager.mqh   |
//|  Execution & in-trade management layer.                          |
//|   - Robust market order send with retries + filling-mode probe   |
//|   - Per-ticket state registry for STAGED scale-outs (T1/T2/T3)   |
//|   - Break-even move after first target                            |
//|   - ATR trailing on the runner                                   |
//|   - Session window + day filters                                 |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

struct STradeConfig
{
   long   magic;
   string commentTag;
   int    slippagePoints;
   int    maxSendRetries;

   // staged scale-out at the attack-sequence targets
   bool   useStagedTP;
   double t1ClosePct;          // % of original volume closed at T1
   double t2ClosePct;          // % of original volume closed at T2
   // legacy single partial (used when staged is off)
   bool   usePartialTP;
   double partialTPpct;
   double partialAtR;

   bool   useBreakEven;
   double breakEvenAtR;        // move SL to entry at this R (legacy mode)
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
   int    fridayCutoffHour;
};

void TradeConfigDefaults(STradeConfig &c)
{
   c.magic=20240617;
   c.commentTag="MasterSenseei";
   c.slippagePoints=20;
   c.maxSendRetries=3;
   c.useStagedTP=true;
   c.t1ClosePct=40.0;
   c.t2ClosePct=35.0;
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

//--- per-position management state -------------------------------
struct SPosState
{
   ulong  ticket;
   int    dir;        // 1 buy / -1 sell
   double entry;
   double risk;       // initial |entry-sl|
   double origVol;
   double t1, t2, t3;
   int    stage;      // 0 = none hit, 1 = T1 hit, 2 = T2 hit
   bool   beDone;
   bool   staged;     // managed by staged levels (vs legacy R)
};

class CTradeManager
{
private:
   CTrade       m_trade;
   STradeConfig m_cfg;
   string       m_symbol;
   SPosState    m_pos[];

   // pending levels for the next opened position
   double m_pT1, m_pT2, m_pT3; bool m_pStaged;

   double Pt(){ return(SymbolInfoDouble(m_symbol,SYMBOL_POINT)); }
   int    Digits_(){ return((int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS)); }

   void ConfigureFilling()
   {
      long fill=(long)SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE);
      if((fill & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((fill & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else                                                     m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

   int FindState(ulong tk)
   {
      for(int i=0;i<ArraySize(m_pos);i++) if(m_pos[i].ticket==tk) return(i);
      return(-1);
   }

   void AddState(const SPosState &st)
   {
      int n=ArraySize(m_pos); ArrayResize(m_pos,n+1); m_pos[n]=st;
   }

   void RemoveStateAt(int idx)
   {
      int n=ArraySize(m_pos);
      if(idx<0 || idx>=n) return;
      for(int i=idx;i<n-1;i++) m_pos[i]=m_pos[i+1];
      ArrayResize(m_pos,n-1);
   }

   bool PositionIsOpen(ulong tk)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(PositionGetTicket(i)==tk) return(true);
      return(false);
   }

   //--- create registry entries for any of our positions not tracked
   void SyncRegistry()
   {
      // purge closed
      for(int i=ArraySize(m_pos)-1;i>=0;i--)
         if(!PositionIsOpen(m_pos[i].ticket)) RemoveStateAt(i);
      // add untracked
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         if(FindState(tk)>=0) continue;
         SPosState st;
         st.ticket=tk;
         st.dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
         st.entry=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         st.risk=(sl>0?MathAbs(st.entry-sl):0);
         st.origVol=PositionGetDouble(POSITION_VOLUME);
         st.stage=0; st.beDone=false;
         // adopt pending staged levels if they match direction
         if(m_pStaged && ((st.dir==1 && m_pT1>st.entry) || (st.dir==-1 && m_pT1<st.entry)))
         { st.t1=m_pT1; st.t2=m_pT2; st.t3=m_pT3; st.staged=true; }
         else { st.t1=0; st.t2=0; st.t3=0; st.staged=false; }
         AddState(st);
      }
      m_pStaged=false; // consume pending
   }

public:
   void Init(const string sym,const STradeConfig &cfg)
   {
      m_symbol=sym; m_cfg=cfg; ArrayResize(m_pos,0);
      m_pT1=0; m_pT2=0; m_pT3=0; m_pStaged=false;
      m_trade.SetExpertMagicNumber(m_cfg.magic);
      m_trade.SetDeviationInPoints(m_cfg.slippagePoints);
      m_trade.SetAsyncMode(false);
      ConfigureFilling();
   }

   bool TimeWindowOK()
   {
      MqlDateTime t; TimeToStruct(TimeCurrent(),t);
      if(!m_cfg.tradeMonday && t.day_of_week==1) return(false);
      if(t.day_of_week==5)
      {
         if(!m_cfg.tradeFriday) return(false);
         if(t.hour>=m_cfg.fridayCutoffHour) return(false);
      }
      if(t.day_of_week==0 || t.day_of_week==6) return(false);
      if(m_cfg.useSession)
      {
         if(m_cfg.sessionStartHour<=m_cfg.sessionEndHour)
         { if(t.hour<m_cfg.sessionStartHour || t.hour>=m_cfg.sessionEndHour) return(false); }
         else
         { if(t.hour<m_cfg.sessionStartHour && t.hour>=m_cfg.sessionEndHour) return(false); }
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

   //--- open with staged targets; broker TP set to T3 (the runner)
   bool OpenStaged(int dir,double lot,double sl,double t1,double t2,double t3)
   {
      m_pT1=t1; m_pT2=t2; m_pT3=t3; m_pStaged=m_cfg.useStagedTP;
      double finalTP=(m_cfg.useStagedTP?t3:t1);
      bool ok=Open(dir,lot,sl,finalTP);
      if(!ok) m_pStaged=false;
      else    SyncRegistry();   // register immediately with the pending levels
      return(ok);
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
         bool ok=(dir==1)?m_trade.Buy(lot,m_symbol,0.0,sl,tp,m_cfg.commentTag)
                         :m_trade.Sell(lot,m_symbol,0.0,sl,tp,m_cfg.commentTag);
         uint rc=m_trade.ResultRetcode();
         if(ok && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED))
         {
            PrintFormat("[TRADE] Opened %s %.2f lots SL=%.5f TP=%.5f (%s)",
                        dir==1?"BUY":"SELL",lot,sl,tp,m_cfg.commentTag);
            return(true);
         }
         PrintFormat("[TRADE] Open attempt %d failed rc=%u (%s). Retrying...",
                     attempt,rc,m_trade.ResultRetcodeDescription());
         ConfigureFilling();
         Sleep(150);
      }
      return(false);
   }

   //--- close a fraction of original volume, respecting min/step
   bool ClosePartialVol(ulong tk,double origVol,double pct)
   {
      double minLot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double step  =SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(!PositionSelectByTicket(tk)) return(false);
      double cur=PositionGetDouble(POSITION_VOLUME);
      double closeVol=origVol*pct/100.0;
      if(step>0) closeVol=MathFloor(closeVol/step)*step;
      if(closeVol<minLot) return(false);
      if(cur-closeVol<minLot) closeVol=cur; // close all if remainder too small
      return(m_trade.PositionClosePartial(tk,closeVol));
   }

   //--- manage all this-EA positions on every tick
   void ManageOpen(double atr)
   {
      SyncRegistry();
      int digits=Digits_();
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         if(!PositionSelectByTicket(tk)) continue;

         long type=PositionGetInteger(POSITION_TYPE);
         bool isBuy=(type==POSITION_TYPE_BUY);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         double price=isBuy?SymbolInfoDouble(m_symbol,SYMBOL_BID):SymbolInfoDouble(m_symbol,SYMBOL_ASK);

         int si=FindState(tk);
         double rDist=(si>=0 && m_pos[si].risk>0)?m_pos[si].risk:((sl>0)?MathAbs(open-sl):atr);
         if(rDist<=0) rDist=atr;
         double rMult=isBuy?(price-open)/rDist:(open-price)/rDist;

         bool stagedHere=(si>=0 && m_pos[si].staged && m_pos[si].t1!=0);

         if(stagedHere)
         {
            //=========== STAGED T1/T2/T3 MANAGEMENT ===========
            // T1
            if(m_pos[si].stage<1 && ((isBuy && price>=m_pos[si].t1) || (!isBuy && price<=m_pos[si].t1)))
            {
               if(ClosePartialVol(tk,m_pos[si].origVol,m_cfg.t1ClosePct))
                  PrintFormat("[TRADE] T1 hit — closed %.0f%% at %.5f",m_cfg.t1ClosePct,m_pos[si].t1);
               // move SL to break-even+lock
               double beSL=isBuy?open+rDist*m_cfg.breakEvenLockR:open-rDist*m_cfg.breakEvenLockR;
               beSL=NormalizeDouble(beSL,digits);
               m_trade.PositionModify(tk,beSL,tp);
               m_pos[si].stage=1; m_pos[si].beDone=true;
            }
            // T2
            else if(m_pos[si].stage<2 && ((isBuy && price>=m_pos[si].t2) || (!isBuy && price<=m_pos[si].t2)))
            {
               if(ClosePartialVol(tk,m_pos[si].origVol,m_cfg.t2ClosePct))
                  PrintFormat("[TRADE] T2 hit — closed %.0f%% at %.5f",m_cfg.t2ClosePct,m_pos[si].t2);
               // lock SL at T1
               double lockSL=NormalizeDouble(m_pos[si].t1,digits);
               bool improve=(isBuy && lockSL>sl) || (!isBuy && (lockSL<sl || sl==0));
               if(improve) m_trade.PositionModify(tk,lockSL,tp);
               m_pos[si].stage=2;
            }
            // runner trail after T2
            if(m_pos[si].stage>=2 && m_cfg.useTrailing)
            {
               double trail=atr*m_cfg.trailATRmult;
               double newSL=isBuy?price-trail:price+trail;
               newSL=NormalizeDouble(newSL,digits);
               bool improve=(isBuy && newSL>sl) || (!isBuy && (newSL<sl || sl==0));
               if(improve) m_trade.PositionModify(tk,newSL,tp);
            }
         }
         else
         {
            //=========== LEGACY R-BASED MANAGEMENT ===========
            if(m_cfg.usePartialTP && rMult>=m_cfg.partialAtR)
            {
               bool alreadyManaged=(isBuy && sl>=open) || (!isBuy && sl<=open && sl>0);
               if(!alreadyManaged)
                  ClosePartialVol(tk,(si>=0?m_pos[si].origVol:PositionGetDouble(POSITION_VOLUME)),m_cfg.partialTPpct);
            }
            if(m_cfg.useBreakEven && rMult>=m_cfg.breakEvenAtR)
            {
               double beSL=isBuy?open+rDist*m_cfg.breakEvenLockR:open-rDist*m_cfg.breakEvenLockR;
               beSL=NormalizeDouble(beSL,digits);
               bool improve=(isBuy && (sl<beSL || sl==0)) || (!isBuy && (sl>beSL || sl==0));
               if(improve){ m_trade.PositionModify(tk,beSL,tp); sl=PositionGetDouble(POSITION_SL); }
            }
            if(m_cfg.useTrailing && rMult>=m_cfg.trailStartR)
            {
               double trail=atr*m_cfg.trailATRmult;
               double newSL=isBuy?price-trail:price+trail;
               newSL=NormalizeDouble(newSL,digits);
               bool improve=(isBuy && newSL>sl) || (!isBuy && (newSL<sl || sl==0));
               if(improve) m_trade.PositionModify(tk,newSL,tp);
            }
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
