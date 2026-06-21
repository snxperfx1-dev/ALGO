//+------------------------------------------------------------------+
//|                                                  PaperTrade.mqh   |
//|        F72 OMEGA — Execution Shell / Broker Abstraction          |
//|                                                                   |
//|  Routes every order request by ENGINE MODE so that Observer,      |
//|  Shadow, Co-pilot and Paper modes can NEVER send a live order:    |
//|     OBSERVER  -> nothing (scores only)                            |
//|     SHADOW    -> nothing live; logged as if traded                |
//|     CO-PILOT  -> queued, awaits human approval                    |
//|     PAPER     -> simulated fills tracked internally               |
//|     AUTONOMOUS-> live hedge-mode orders (CTrade) with retries     |
//|                                                                   |
//|  Hedge-mode aware: positions are tracked by ticket so buys and    |
//|  sells can coexist (required for ownership transfer / scaling).   |
//+------------------------------------------------------------------+
#ifndef __F72_PAPERTRADE_MQH__
#define __F72_PAPERTRADE_MQH__
#property strict
#include <Trade/Trade.mqh>
#include "Common.mqh"
#include "Logger.mqh"

struct SPaperPos
{
   long               ticket;     // virtual ticket
   int                dir;
   double             vol;
   double             entry;
   double             sl;
   double             tp;
   ENUM_POSITION_ROLE role;
   long               campaignId;
   datetime           openTime;
   bool               open;
};

struct SPendingOrder      // co-pilot approval queue
{
   int                dir;
   double             lot;
   double             sl;
   double             tp;
   ENUM_POSITION_ROLE role;
   long               campaignId;
   string             comment;
   datetime           created;
   bool               active;
};

class CBroker
{
private:
   CTrade            m_trade;
   CLogger          *m_log;
   string            m_symbol;
   long              m_magic;
   ENUM_ENGINE_MODE  m_mode;
   int               m_slippage;
   int               m_retries;

   SPaperPos         m_paper[];
   long              m_paperSeq;
   double            m_paperRealized;

   SPendingOrder     m_queue[];

   void ConfigureFilling()
   {
      long fill=(long)SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE);
      if((fill & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((fill & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else                                                     m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

   double Ask(){ return(SymbolInfoDouble(m_symbol,SYMBOL_ASK)); }
   double Bid(){ return(SymbolInfoDouble(m_symbol,SYMBOL_BID)); }
   int    Digits_(){ return((int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS)); }

public:
   void Init(const string sym,long magic,ENUM_ENGINE_MODE mode,CLogger *log,int slippage=20,int retries=3)
   {
      m_symbol=sym; m_magic=magic; m_mode=mode; m_log=log; m_slippage=slippage; m_retries=retries;
      m_paperSeq=1; m_paperRealized=0.0;
      ArrayResize(m_paper,0); ArrayResize(m_queue,0);
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetAsyncMode(false);
      ConfigureFilling();
   }

   void SetMode(ENUM_ENGINE_MODE m){ m_mode=m; }
   ENUM_ENGINE_MODE Mode(){ return(m_mode); }

   bool IsLive(){ return(m_mode==MODE_AUTONOMOUS); }
   bool IsPaper(){ return(m_mode==MODE_PAPER); }

   //================================================================
   // OPEN — routes by mode. Returns true if an order/sim was placed
   // (co-pilot returns false but queues).
   //================================================================
   bool Open(int dir,double lot,double sl,double tp,ENUM_POSITION_ROLE role,long campaignId,const string comment)
   {
      if(lot<=0 || dir==0) return(false);
      int digits=Digits_();
      sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);

      switch(m_mode)
      {
         case MODE_OBSERVER:
            return(false); // never trades

         case MODE_SHADOW:
            if(m_log!=NULL) m_log.Execution(m_symbol,"SHADOW_OPEN",0,lot,(dir==1?Ask():Bid()),sl,tp,0,comment);
            return(true);

         case MODE_COPILOT:
            QueueOrder(dir,lot,sl,tp,role,campaignId,comment);
            return(false);

         case MODE_PAPER:
            return(PaperOpen(dir,lot,sl,tp,role,campaignId,comment));

         case MODE_AUTONOMOUS:
            return(LiveOpen(dir,lot,sl,tp,role,comment));
      }
      return(false);
   }

   //--- LIVE -------------------------------------------------------
   bool LiveOpen(int dir,double lot,double sl,double tp,ENUM_POSITION_ROLE role,const string comment)
   {
      for(int a=1;a<=m_retries;a++)
      {
         bool ok=(dir==1)?m_trade.Buy(lot,m_symbol,0.0,sl,tp,comment)
                         :m_trade.Sell(lot,m_symbol,0.0,sl,tp,comment);
         uint rc=m_trade.ResultRetcode();
         if(ok && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED))
         {
            if(m_log!=NULL) m_log.Execution(m_symbol,"LIVE_OPEN",m_trade.ResultOrder(),lot,
                            m_trade.ResultPrice(),sl,tp,rc,comment);
            return(true);
         }
         if(m_log!=NULL) m_log.Warn("Broker",StringFormat("LiveOpen attempt %d rc=%u %s",a,rc,m_trade.ResultRetcodeDescription()));
         ConfigureFilling();
         Sleep(150);
      }
      return(false);
   }

   //--- PAPER ------------------------------------------------------
   bool PaperOpen(int dir,double lot,double sl,double tp,ENUM_POSITION_ROLE role,long campaignId,const string comment)
   {
      SPaperPos p;
      p.ticket=m_paperSeq++; p.dir=dir; p.vol=lot;
      p.entry=(dir==1?Ask():Bid()); p.sl=sl; p.tp=tp; p.role=role;
      p.campaignId=campaignId; p.openTime=TimeCurrent(); p.open=true;
      int n=ArraySize(m_paper); ArrayResize(m_paper,n+1); m_paper[n]=p;
      if(m_log!=NULL) m_log.Execution(m_symbol,"PAPER_OPEN",(ulong)p.ticket,lot,p.entry,sl,tp,0,comment);
      return(true);
   }

   //--- mark-to-market paper positions; auto-close on SL/TP --------
   void PaperUpdate()
   {
      if(m_mode!=MODE_PAPER) return;
      double bid=Bid(), ask=Ask();
      for(int i=0;i<ArraySize(m_paper);i++)
      {
         if(!m_paper[i].open) continue;
         double px=(m_paper[i].dir==1?bid:ask);
         bool hitSL=(m_paper[i].sl>0 && ((m_paper[i].dir==1 && px<=m_paper[i].sl)||(m_paper[i].dir==-1 && px>=m_paper[i].sl)));
         bool hitTP=(m_paper[i].tp>0 && ((m_paper[i].dir==1 && px>=m_paper[i].tp)||(m_paper[i].dir==-1 && px<=m_paper[i].tp)));
         if(hitSL || hitTP)
            PaperClose(i,hitTP?"PAPER_TP":"PAPER_SL");
      }
   }

   void PaperClose(int idx,const string why)
   {
      if(idx<0 || idx>=ArraySize(m_paper) || !m_paper[idx].open) return;
      double px=(m_paper[idx].dir==1?Bid():Ask());
      double tickVal=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSz =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      double pnl=0.0;
      if(tickSz>0) pnl=(px-m_paper[idx].entry)*m_paper[idx].dir/tickSz*tickVal*m_paper[idx].vol;
      m_paperRealized+=pnl;
      m_paper[idx].open=false;
      if(m_log!=NULL) m_log.Execution(m_symbol,why,(ulong)m_paper[idx].ticket,m_paper[idx].vol,px,
                      m_paper[idx].sl,m_paper[idx].tp,0,StringFormat("pnl=%.2f",pnl));
   }

   double PaperRealized(){ return(m_paperRealized); }
   double PaperFloating()
   {
      double bid=Bid(), ask=Ask();
      double tickVal=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSz =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      double f=0.0;
      if(tickSz<=0) return(0.0);
      for(int i=0;i<ArraySize(m_paper);i++)
      {
         if(!m_paper[i].open) continue;
         double px=(m_paper[i].dir==1?bid:ask);
         f+=(px-m_paper[i].entry)*m_paper[i].dir/tickSz*tickVal*m_paper[i].vol;
      }
      return(f);
   }
   int PaperOpenCount()
   {
      int n=0; for(int i=0;i<ArraySize(m_paper);i++) if(m_paper[i].open) n++; return(n);
   }

   //--- CO-PILOT queue --------------------------------------------
   void QueueOrder(int dir,double lot,double sl,double tp,ENUM_POSITION_ROLE role,long campaignId,const string comment)
   {
      SPendingOrder q;
      q.dir=dir; q.lot=lot; q.sl=sl; q.tp=tp; q.role=role; q.campaignId=campaignId;
      q.comment=comment; q.created=TimeCurrent(); q.active=true;
      int n=ArraySize(m_queue); ArrayResize(m_queue,n+1); m_queue[n]=q;
      if(m_log!=NULL) m_log.Info("Broker",StringFormat("CO-PILOT queued %s %.2f lots (awaiting approval)",
                      dir==1?"BUY":"SELL",lot));
   }
   int  PendingCount(){ int n=0; for(int i=0;i<ArraySize(m_queue);i++) if(m_queue[i].active) n++; return(n); }

   // Approve the oldest active queued order -> sends live (if autonomous switch) / paper
   bool ApproveNext(ENUM_ENGINE_MODE executeAs)
   {
      for(int i=0;i<ArraySize(m_queue);i++)
      {
         if(!m_queue[i].active) continue;
         m_queue[i].active=false;
         ENUM_ENGINE_MODE save=m_mode; m_mode=executeAs;
         bool ok=Open(m_queue[i].dir,m_queue[i].lot,m_queue[i].sl,m_queue[i].tp,
                      m_queue[i].role,m_queue[i].campaignId,"approved:"+m_queue[i].comment);
         m_mode=save;
         return(ok);
      }
      return(false);
   }

   //--- LIVE position helpers -------------------------------------
   int LivePositions()
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

   void CloseAllLive()
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         m_trade.PositionClose(tk);
      }
   }

   void CloseAllPaper()
   {
      for(int i=0;i<ArraySize(m_paper);i++) if(m_paper[i].open) PaperClose(i,"PAPER_FORCE");
   }
};

#endif // __F72_PAPERTRADE_MQH__
