//+------------------------------------------------------------------+
//|                                                       Logger.mqh  |
//|              F72 OMEGA — Structured Explainability Log            |
//|                                                                   |
//|  Every module emits its "why" through this. Writes CSV under      |
//|  MQL5/Files/F72_Omega/logs/ and mirrors to the Experts journal.   |
//|  Explainability is non-negotiable: nothing is a black box.        |
//+------------------------------------------------------------------+
#ifndef __F72_LOGGER_MQH__
#define __F72_LOGGER_MQH__
#property strict
#include "Common.mqh"

enum ENUM_LOG_LEVEL { LL_DEBUG=0, LL_INFO=1, LL_WARN=2, LL_ERROR=3 };

class CLogger
{
private:
   string m_root;          // F72_Omega
   string m_decisionFile;
   string m_execFile;
   string m_transferFile;
   string m_exceptionFile;
   bool   m_console;
   ENUM_LOG_LEVEL m_minLevel;

   void EnsureTree()
   {
      // FolderCreate is relative to MQL5/Files (sandbox)
      FolderCreate(m_root);
      FolderCreate(m_root+"/logs");
      FolderCreate(m_root+"/campaigns");
      FolderCreate(m_root+"/rolling");
      FolderCreate(m_root+"/backtests");
      FolderCreate(m_root+"/paper");
      FolderCreate(m_root+"/exports");
   }

   void EnsureHeader(const string file,const string header)
   {
      if(FileIsExist(file)) return;
      int h=FileOpen(file,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h!=INVALID_HANDLE){ FileWriteString(h,header+"\n"); FileClose(h); }
   }

   void AppendLine(const string file,const string line)
   {
      int h=FileOpen(file,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h==INVALID_HANDLE){ Print("[LOGGER] cannot open ",file," err=",GetLastError()); return; }
      FileSeek(h,0,SEEK_END);
      FileWriteString(h,line+"\n");
      FileClose(h);
   }

   string Stamp(){ return(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)); }

public:
   void Init(const string root=F72_ROOT,bool console=true,ENUM_LOG_LEVEL minLevel=LL_INFO)
   {
      m_root=root; m_console=console; m_minLevel=minLevel;
      m_decisionFile =m_root+"/logs/decision_log.csv";
      m_execFile     =m_root+"/logs/execution_log.csv";
      m_transferFile =m_root+"/logs/transfer_log.csv";
      m_exceptionFile=m_root+"/logs/exception_log.csv";
      EnsureTree();
      EnsureHeader(m_decisionFile,"time,symbol,mode,decision,dir,role,riskPct,stop,target,reason,reasonText,life,stability,confidence,note");
      EnsureHeader(m_execFile,    "time,symbol,action,ticket,volume,price,sl,tp,retcode,comment");
      EnsureHeader(m_transferFile,"time,symbol,fromDir,toDir,campaignId,reason,note");
      EnsureHeader(m_exceptionFile,"time,symbol,level,where,detail,lastError");
   }

   //--- general journal line
   void Log(ENUM_LOG_LEVEL lvl,const string where,const string msg)
   {
      if(lvl<m_minLevel) return;
      string tag=(lvl==LL_DEBUG?"DBG":lvl==LL_INFO?"INF":lvl==LL_WARN?"WRN":"ERR");
      if(m_console) Print("[F72][",tag,"][",where,"] ",msg);
      if(lvl>=LL_WARN)
         AppendLine(m_exceptionFile,StringFormat("%s,%s,%s,%s,%s,%d",
                    Stamp(),_Symbol,tag,where,msg,GetLastError()));
   }

   void Info(const string where,const string msg){ Log(LL_INFO,where,msg); }
   void Warn(const string where,const string msg){ Log(LL_WARN,where,msg); }
   void Error(const string where,const string msg){ Log(LL_ERROR,where,msg); }
   void Debug(const string where,const string msg){ Log(LL_DEBUG,where,msg); }

   //--- the explainability record for every decision
   void Decision(const string symbol,ENUM_ENGINE_MODE mode,const SDecision &d,const SEngineState &st)
   {
      string line=StringFormat("%s,%s,%s,%s,%d,%s,%.3f,%.5f,%.5f,%d,%s,%.1f,%.1f,%.1f,%s",
         Stamp(),symbol,ModeText(mode),DecisionText(d.type),d.dir,RoleText(d.role),
         d.riskPct,d.stop,d.target,(int)d.reason,ReasonText(d.reason),
         st.lifeScore,st.storyStability,st.storyConfidence,d.note);
      AppendLine(m_decisionFile,line);
      if(m_console)
         Print(StringFormat("[F72][DECISION] %s %s dir=%d role=%s risk=%.2f%% why=%s | life=%.0f stab=%.0f conf=%.0f",
               DecisionText(d.type),symbol,d.dir,RoleText(d.role),d.riskPct,ReasonText(d.reason),
               st.lifeScore,st.storyStability,st.storyConfidence));
   }

   //--- order execution record
   void Execution(const string symbol,const string action,ulong ticket,double vol,double price,
                  double sl,double tp,uint retcode,const string comment)
   {
      AppendLine(m_execFile,StringFormat("%s,%s,%s,%I64u,%.2f,%.5f,%.5f,%.5f,%u,%s",
                 Stamp(),symbol,action,ticket,vol,price,sl,tp,retcode,comment));
   }

   //--- ownership transfer record
   void Transfer(const string symbol,int fromDir,int toDir,long campaignId,ENUM_REASON reason,const string note)
   {
      AppendLine(m_transferFile,StringFormat("%s,%s,%d,%d,%I64d,%s,%s",
                 Stamp(),symbol,fromDir,toDir,campaignId,ReasonText(reason),note));
   }
};

#endif // __F72_LOGGER_MQH__
