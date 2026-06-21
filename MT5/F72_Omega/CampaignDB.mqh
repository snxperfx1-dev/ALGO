//+------------------------------------------------------------------+
//|                                                  CampaignDB.mqh   |
//|            F72 OMEGA — Immortal Campaign Persistence (Layer 2)    |
//|                                                                   |
//|  Serialises the SCampaign schema to JSON under                    |
//|     MQL5/Files/F72_Omega/campaigns/<SYMBOL>/campaign_<YR>_<ID>.json|
//|  and reloads them on init for statistical memory. The machine     |
//|  does not forget: every campaign becomes immortal.                |
//+------------------------------------------------------------------+
#ifndef __F72_CAMPAIGNDB_MQH__
#define __F72_CAMPAIGNDB_MQH__
#property strict
#include "Common.mqh"
#include "Logger.mqh"

class CCampaignDB
{
private:
   CLogger *m_log;
   string   m_root;
   string   m_symbol;
   string   m_dir;        // campaigns/<symbol>
   long     m_seq;        // next id

   //--- tiny JSON helpers (writer) --------------------------------
   string KV(const string k,const string v,bool last=false){ return("  \""+k+"\": \""+v+"\""+(last?"":",")+"\n"); }
   string KN(const string k,double v,bool last=false){ return(StringFormat("  \"%s\": %.6f%s\n",k,v,(last?"":","))); }
   string KI(const string k,long v,bool last=false){ return(StringFormat("  \"%s\": %I64d%s\n",k,v,(last?"":","))); }
   string KB(const string k,bool v,bool last=false){ return("  \""+k+"\": "+(v?"true":"false")+(last?"":",")+"\n"); }

   //--- tiny JSON helpers (reader, tolerant key extraction) -------
   string Raw(const string file)
   {
      if(!FileIsExist(file)) return("");
      int h=FileOpen(file,FILE_READ|FILE_TXT|FILE_ANSI);
      if(h==INVALID_HANDLE) return("");
      string s="";
      while(!FileIsEnding(h)) s+=FileReadString(h)+"\n";
      FileClose(h);
      return(s);
   }
   string Token(const string json,const string key)
   {
      string pat="\""+key+"\"";
      int p=StringFind(json,pat);
      if(p<0) return("");
      p=StringFind(json,":",p);
      if(p<0) return("");
      p++;
      // skip spaces/quotes
      int n=StringLen(json);
      while(p<n)
      {
         ushort ch=StringGetCharacter(json,p);
         if(ch==' '||ch=='\"'||ch=='\t') p++; else break;
      }
      string out="";
      while(p<n)
      {
         ushort ch=StringGetCharacter(json,p);
         if(ch==','||ch=='\n'||ch=='\r'||ch=='\"'||ch=='}') break;
         out+=ShortToString(ch); p++;
      }
      StringTrimLeft(out); StringTrimRight(out);
      return(out);
   }
   double NumOf(const string json,const string key){ string t=Token(json,key); return(t==""?0.0:StringToDouble(t)); }
   long   IntOf(const string json,const string key){ string t=Token(json,key); return(t==""?0:(long)StringToInteger(t)); }
   bool   BoolOf(const string json,const string key){ return(Token(json,key)=="true"); }

public:
   void Init(CLogger *log,const string symbol,const string root=F72_ROOT)
   {
      m_log=log; m_symbol=symbol; m_root=root;
      m_dir=m_root+"/campaigns/"+symbol;
      FolderCreate(m_dir);
      m_seq=LoadMaxId()+1;
      if(m_log!=NULL) m_log.Info("CampaignDB",StringFormat("ready for %s (next id=%I64d)",symbol,m_seq));
   }

   long NextId(){ return(m_seq++); }

   //--- scan existing files to continue id sequence after restart
   long LoadMaxId()
   {
      long mx=0;
      string name; long find=FileFindFirst(m_dir+"/*.json",name);
      if(find!=INVALID_HANDLE)
      {
         do
         {
            // expect campaign_<year>_<id>.json
            int u=StringFind(name,"_",StringFind(name,"_")+1);
            if(u>0)
            {
               string idpart=StringSubstr(name,u+1);
               int dot=StringFind(idpart,".");
               if(dot>0) idpart=StringSubstr(idpart,0,dot);
               long v=(long)StringToInteger(idpart);
               if(v>mx) mx=v;
            }
         } while(FileFindNext(find,name));
         FileFindClose(find);
      }
      return(mx);
   }

   string PathFor(const SCampaign &c)
   {
      MqlDateTime d; TimeToStruct(c.birth>0?c.birth:TimeCurrent(),d);
      return(StringFormat("%s/campaign_%04d_%06I64d.json",m_dir,d.year,c.id));
   }

   bool Save(const SCampaign &c)
   {
      string j="{\n";
      j+=KI("id",c.id);
      j+=KV("symbol",c.symbol);
      j+=KI("birth",(long)c.birth);
      j+=KI("death",(long)c.death);
      j+=KI("parentId",c.parentId);
      j+=KI("childCount",c.childCount);
      j+=KV("childIds",c.childIds);
      j+=KI("dir",c.dir);
      j+=KI("phase",(long)c.phase);
      j+=KN("compressionProfile",c.compressionProfile);
      j+=KN("convexityProfile",c.convexityProfile);
      j+=KN("forceProfile",c.forceProfile);
      j+=KI("recursionDepth",c.recursionDepth);
      j+=KI("transitionType",c.transitionType);
      j+=KI("failureSwingType",c.failureSwingType);
      j+=KI("durationSecs",c.durationSecs);
      j+=KV("session",c.session);
      j+=KV("newsEnv",c.newsEnv);
      j+=KI("fuInteractions",c.fuInteractions);
      j+=KB("terminalInduction",c.terminalInduction);
      j+=KN("pnl",c.pnl);
      j+=KN("maxFavorable",c.maxFavorable);
      j+=KN("maxAdverse",c.maxAdverse);
      j+=KN("peakLifeScore",c.peakLifeScore);
      j+=KN("peakForce",c.peakForce);
      j+=KB("closed",c.closed,true);
      j+="}\n";

      string file=PathFor(c);
      int h=FileOpen(file,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h==INVALID_HANDLE){ if(m_log!=NULL) m_log.Error("CampaignDB","cannot write "+file); return(false); }
      FileWriteString(h,j);
      FileClose(h);
      return(true);
   }

   bool Load(const string file,SCampaign &c)
   {
      string j=Raw(file);
      if(j=="") return(false);
      CampaignInit(c);
      c.id=IntOf(j,"id");
      c.symbol=Token(j,"symbol");
      c.birth=(datetime)IntOf(j,"birth");
      c.death=(datetime)IntOf(j,"death");
      c.parentId=IntOf(j,"parentId");
      c.childCount=(int)IntOf(j,"childCount");
      c.childIds=Token(j,"childIds");
      c.dir=(int)IntOf(j,"dir");
      c.phase=(ENUM_CAMPAIGN_PHASE)IntOf(j,"phase");
      c.compressionProfile=NumOf(j,"compressionProfile");
      c.convexityProfile=NumOf(j,"convexityProfile");
      c.forceProfile=NumOf(j,"forceProfile");
      c.recursionDepth=(int)IntOf(j,"recursionDepth");
      c.transitionType=(int)IntOf(j,"transitionType");
      c.failureSwingType=(int)IntOf(j,"failureSwingType");
      c.durationSecs=IntOf(j,"durationSecs");
      c.session=Token(j,"session");
      c.newsEnv=Token(j,"newsEnv");
      c.fuInteractions=(int)IntOf(j,"fuInteractions");
      c.terminalInduction=BoolOf(j,"terminalInduction");
      c.pnl=NumOf(j,"pnl");
      c.maxFavorable=NumOf(j,"maxFavorable");
      c.maxAdverse=NumOf(j,"maxAdverse");
      c.peakLifeScore=NumOf(j,"peakLifeScore");
      c.peakForce=NumOf(j,"peakForce");
      c.closed=BoolOf(j,"closed");
      return(true);
   }

   //--- load all closed campaigns into an array (for statistics)
   int LoadAll(SCampaign &arr[])
   {
      ArrayResize(arr,0);
      string name; long find=FileFindFirst(m_dir+"/*.json",name);
      if(find==INVALID_HANDLE) return(0);
      int cnt=0;
      do
      {
         SCampaign c;
         if(Load(m_dir+"/"+name,c))
         {
            int n=ArraySize(arr); ArrayResize(arr,n+1); arr[n]=c; cnt++;
         }
      } while(FileFindNext(find,name));
      FileFindClose(find);
      return(cnt);
   }
};

#endif // __F72_CAMPAIGNDB_MQH__
