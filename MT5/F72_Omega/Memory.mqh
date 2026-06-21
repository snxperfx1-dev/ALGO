//+------------------------------------------------------------------+
//|                                                       Memory.mqh  |
//|          F72 OMEGA — Living Campaign Memory (Layer 2 + feed)      |
//|                                                                   |
//|  Owns the lifecycle of active campaigns (birth -> update ->       |
//|  death) and bridges to CampaignDB for immortality + CStatistics   |
//|  for rolling self-knowledge. On death a campaign is written to    |
//|  disk and folded into the statistics so the organism learns.     |
//+------------------------------------------------------------------+
#ifndef __F72_MEMORY_MQH__
#define __F72_MEMORY_MQH__
#property strict
#include "Common.mqh"
#include "Logger.mqh"
#include "CampaignDB.mqh"
#include "Statistics.mqh"

class CMemory
{
private:
   CLogger     *m_log;
   CCampaignDB  m_db;
   CStatistics  m_stats;
   string       m_symbol;
   SCampaign    m_active[];     // currently-living campaigns

   int Find(long id)
   {
      for(int i=0;i<ArraySize(m_active);i++) if(m_active[i].id==id) return(i);
      return(-1);
   }

public:
   void Init(CLogger *log,const string symbol,const string root=F72_ROOT,int statWindow=50)
   {
      m_log=log; m_symbol=symbol;
      m_db.Init(log,symbol,root);
      m_stats.Init(statWindow);
      ArrayResize(m_active,0);

      // load history into statistics (immortal memory)
      SCampaign hist[];
      int n=m_db.LoadAll(hist);
      m_stats.IngestAll(hist);
      if(m_log!=NULL) m_log.Info("Memory",StringFormat("loaded %d historical campaigns | hitRate=%.1f%% PF=%.2f",
                      n,m_stats.HitRate(),m_stats.ProfitFactor()));
   }

   CStatistics *Stats(){ return(GetPointer(m_stats)); }

   //--- birth
   long Birth(int dir,ENUM_CAMPAIGN_PHASE phase,const string session,const string newsEnv)
   {
      SCampaign c; CampaignInit(c);
      c.id=m_db.NextId(); c.symbol=m_symbol; c.birth=TimeCurrent();
      c.dir=dir; c.phase=phase; c.session=session; c.newsEnv=newsEnv;
      int n=ArraySize(m_active); ArrayResize(m_active,n+1); m_active[n]=c;
      if(m_log!=NULL) m_log.Info("Memory",StringFormat("campaign %I64d BIRTH dir=%d phase=%s",c.id,dir,PhaseText(phase)));
      return(c.id);
   }

   //--- per-tick update of a living campaign's profiles
   void Update(long id,const SEngineState &s,double favorable,double adverse)
   {
      int i=Find(id); if(i<0) return;
      m_active[i].compressionProfile=F72Lerp(m_active[i].compressionProfile,s.compression,0.05);
      m_active[i].convexityProfile  =F72Lerp(m_active[i].convexityProfile,  s.convexity,  0.05);
      m_active[i].forceProfile      =MathMax(m_active[i].forceProfile,      s.forceScore);
      m_active[i].peakLifeScore     =MathMax(m_active[i].peakLifeScore,     s.lifeScore);
      m_active[i].peakForce         =MathMax(m_active[i].peakForce,         s.forceScore);
      if(favorable>m_active[i].maxFavorable) m_active[i].maxFavorable=favorable;
      if(adverse  <m_active[i].maxAdverse)   m_active[i].maxAdverse=adverse;
   }

   void SetPhase(long id,ENUM_CAMPAIGN_PHASE p)
   {
      int i=Find(id); if(i<0) return;
      if(m_active[i].phase!=p && m_log!=NULL)
         m_log.Info("Memory",StringFormat("campaign %I64d phase %s -> %s",id,PhaseText(m_active[i].phase),PhaseText(p)));
      m_active[i].phase=p;
   }

   void NoteTransition(long id,int type){ int i=Find(id); if(i>=0) m_active[i].transitionType=type; }
   void NoteFailureSwing(long id,int type){ int i=Find(id); if(i>=0) m_active[i].failureSwingType=type; }
   void NoteFu(long id){ int i=Find(id); if(i>=0) m_active[i].fuInteractions++; }
   void NoteTerminal(long id){ int i=Find(id); if(i>=0) m_active[i].terminalInduction=true; }
   void AddRecursion(long id){ int i=Find(id); if(i>=0) m_active[i].recursionDepth++; }

   //--- death -> persist + learn
   void Death(long id,double pnl,int transitionType)
   {
      int i=Find(id); if(i<0) return;
      m_active[i].death=TimeCurrent();
      m_active[i].durationSecs=(long)(m_active[i].death-m_active[i].birth);
      m_active[i].pnl=pnl;
      m_active[i].transitionType=transitionType;
      m_active[i].phase=CP_DEATH;
      m_active[i].closed=true;
      m_db.Save(m_active[i]);
      m_stats.Ingest(m_active[i]);
      if(m_log!=NULL) m_log.Info("Memory",StringFormat("campaign %I64d DEATH pnl=%.2f dur=%ds | newHit=%.1f%%",
                      id,pnl,(int)m_active[i].durationSecs,m_stats.RecentHitRate()));
      // remove from active
      int n=ArraySize(m_active);
      for(int k=i;k<n-1;k++) m_active[k]=m_active[k+1];
      ArrayResize(m_active,n-1);
   }

   int ActiveCount(){ return(ArraySize(m_active)); }
   bool GetActive(int idx,SCampaign &out)
   {
      if(idx<0 || idx>=ArraySize(m_active)) return(false);
      out=m_active[idx]; return(true);
   }

   //--- periodic checkpoint of living campaigns (crash safety)
   void Checkpoint()
   {
      for(int i=0;i<ArraySize(m_active);i++) m_db.Save(m_active[i]);
   }

   //--- self-observation feed -> StoryConfidence
   double RecentHitRate(){ return(m_stats.RecentHitRate()); }
   double RegimeDrift(){ return(m_stats.RegimeDrift()); }
   int    Samples(){ return(m_stats.Samples()); }
   double ProfitFactor(){ return(m_stats.ProfitFactor()); }
};

#endif // __F72_MEMORY_MQH__
