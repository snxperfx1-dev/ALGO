//+------------------------------------------------------------------+
//|                                              SenseeiEngine.mqh    |
//|  FULL MQL5 port of the F16 Raptor v57 / Master Senseei brain.    |
//|                                                                   |
//|  This is the complete analytical engine — not just a trade       |
//|  trigger. It reconstructs, faithfully:                            |
//|    * f_phys physics + f_se fixed-TF structure engine (per rung)   |
//|    * the canonical chart-TF wave LIFECYCLE: observation scores,   |
//|      EDE / RE / EAE energy-resolution-attractor framework, the    |
//|      belief engine, convexity maturity, dual waveProgress, and    |
//|      the liqg liquidation-wave overlay                            |
//|    * the F72 recursive CURVE TREE (origin->extreme curves, depth, |
//|      emergent node phase, ownership, "is the trade alive" life)   |
//|    * the Time Intelligence Engine (MN/W/D/H4/H1 bias + sequence)  |
//|    * the node / FU authority network (netBias + pressure)         |
//|    * the fractal stack + MTF curve map                            |
//|    * participant fib interference zones                           |
//|    * the Senseei meta-intelligence verdict + intent + story       |
//|                                                                   |
//|  Pure analysis. Places no orders. The EA consumes SSenseeiResult. |
//+------------------------------------------------------------------+
#property strict
#include "SenseeiTypes.mqh"

class CSenseeiEngine
{
private:
   SEngineConfig     m_cfg;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_ladder[6];   // climbing 6-TF ladder; index 2 = canonical

   double Clamp(double v,double lo,double hi){ return(v<lo?lo:(v>hi?hi:v)); }
   int    Sign(double v){ return(v>0?1:(v<0?-1:0)); }
   double SimNorm(double v,double ideal,double tol){ double d=MathAbs(v-ideal)/MathMax(tol,1e-10); return(Clamp(1.0-d,0.0,1.0)); }

   void BuildLadder(ENUM_TIMEFRAMES chartTF)
   {
      int csec=PeriodSeconds(chartTF);
      m_ladder[2]=chartTF;
      if(csec<3600)
      { m_ladder[0]=PERIOD_M1; m_ladder[1]=PERIOD_M3; m_ladder[3]=PERIOD_M15; m_ladder[4]=PERIOD_H1; m_ladder[5]=PERIOD_H4; }
      else if(csec<14400)
      { m_ladder[0]=PERIOD_H1; m_ladder[1]=PERIOD_H2; m_ladder[3]=PERIOD_H8; m_ladder[4]=PERIOD_H12; m_ladder[5]=PERIOD_D1; }
      else if(csec<86400)
      { m_ladder[0]=PERIOD_H4; m_ladder[1]=PERIOD_H8; m_ladder[3]=PERIOD_D1; m_ladder[4]=PERIOD_W1; m_ladder[5]=PERIOD_MN1; }
      else
      { m_ladder[0]=PERIOD_D1; m_ladder[1]=PERIOD_W1; m_ladder[3]=PERIOD_W1; m_ladder[4]=PERIOD_MN1; m_ladder[5]=PERIOD_MN1; }
   }

public:
   void Init(const string sym, ENUM_TIMEFRAMES chartTF, const SEngineConfig &cfg)
   {
      m_symbol=sym; m_cfg=cfg; BuildLadder(chartTF);
   }
   ENUM_TIMEFRAMES CanonicalTF(){ return(m_ladder[2]); }
   ENUM_TIMEFRAMES LadderTF(int i){ return(m_ladder[(i<0?0:(i>5?5:i))]); }

   string TfLabel(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return("M1");  case PERIOD_M3:  return("M3");
         case PERIOD_M5:  return("M5");  case PERIOD_M15: return("M15");
         case PERIOD_M30: return("M30"); case PERIOD_H1:  return("H1");
         case PERIOD_H2:  return("H2");  case PERIOD_H4:  return("H4");
         case PERIOD_H8:  return("H8");  case PERIOD_H12: return("H12");
         case PERIOD_D1:  return("D1");  case PERIOD_W1:  return("W1");
         case PERIOD_MN1: return("MN");  default: return(EnumToString(tf));
      }
   }

   string PhaseStr(int p)
   {
      switch(p)
      {
         case 1:  return("Expansion");
         case 2:  return("Momentum Decay");
         case 3:  return("Expansion Induction");
         case 4:  return("Expansion Liquidity");
         case 5:  return("Peak Formation");
         case 6:  return("Trough Formation");
         case 7:  return("Energy Transfer");
         case 8:  return("Creation");
         case 9:  return("Flip-Zone Test");
         case 10: return("Retracement Induction");
         case 11: return("Capacity Drain");
         case 12: return("Liquidity Sweep");
         case 13: return("Demand Return");
         case 14: return("Supply Return");
         default: return("Forming");
      }
   }

   //--------------------------------------------------------------
   // Wilder ATR on a series array (index 0 newest) at bar b
   //--------------------------------------------------------------
   double ATRseries(const MqlRates &r[], int b, int len)
   {
      int n=ArraySize(r);
      if(b+len+1>=n) len=MathMax(1,n-b-2);
      double sum=0.0;
      for(int k=b;k<b+len;k++)
      {
         double tr=MathMax(r[k].high-r[k].low,MathMax(MathAbs(r[k].high-r[k+1].close),MathAbs(r[k].low-r[k+1].close)));
         sum+=tr;
      }
      return(sum/len);
   }

   //--------------------------------------------------------------
   // FU / NODE detector (port of f_fuPool) on the last closed bar
   //--------------------------------------------------------------
   SFuState ComputeFUat(const MqlRates &r[], int b)
   {
      SFuState s; s.valid=false; s.dir=0; s.score=0.0; s.tip=0.0;
      int n=ArraySize(r);
      if(b+m_cfg.fuLookback+2>=n) return(s);
      double rng=MathMax(r[b].high-r[b].low,1e-10);
      double pHi=-DBL_MAX,pLo=DBL_MAX;
      for(int k=b+1;k<=b+m_cfg.fuLookback;k++){ if(r[k].high>pHi) pHi=r[k].high; if(r[k].low<pLo) pLo=r[k].low; }
      double locHi=-DBL_MAX,locLo=DBL_MAX;
      for(int k=b;k<=b+m_cfg.fuLookback-1;k++){ if(r[k].high>locHi) locHi=r[k].high; if(r[k].low<locLo) locLo=r[k].low; }
      double uw=(r[b].high-MathMax(r[b].open,r[b].close))/rng;
      double lw=(MathMin(r[b].open,r[b].close)-r[b].low)/rng;
      bool localTop=(r[b].high>=locHi);
      bool localBot=(r[b].low<=locLo);
      bool bear=(uw>=m_cfg.wickFrac) && ((r[b].high>=pHi && r[b].close<pHi) || (localTop && r[b].close<r[b].open));
      bool bull=(lw>=m_cfg.wickFrac) && ((r[b].low<=pLo  && r[b].close>pLo)  || (localBot && r[b].close>r[b].open));
      double atr=ATRseries(r,b,m_cfg.atrLen);
      if(bear){ s.dir=-1; s.tip=r[b].high; s.valid=true; }
      else if(bull){ s.dir=1; s.tip=r[b].low; s.valid=true; }
      if(s.valid)
      {
         double bH=MathMax(r[b].open,r[b].close), bL=MathMin(r[b].open,r[b].close);
         double wk=(s.dir==-1)?(s.tip-bH)/MathMax(atr,1e-10):(bL-s.tip)/MathMax(atr,1e-10);
         s.score=20.0+MathMin(25.0,wk*15.0)+(wk>1.0?15.0:0.0)+(wk>1.5?10.0:0.0);
      }
      return(s);
   }

   SFuState ComputeFU(ENUM_TIMEFRAMES tf)
   {
      SFuState s; s.valid=false; s.dir=0; s.score=0; s.tip=0;
      int need=m_cfg.fuLookback+m_cfg.atrLen+8;
      MqlRates r[]; ArraySetAsSeries(r,true);
      if(CopyRates(m_symbol,tf,0,need+2,r)<need) return(s);
      return(ComputeFUat(r,1));
   }

   //==============================================================
   // f_se + f_phys per timeframe -> full SWaveState on last closed
   //==============================================================
   SWaveState ComputeWave(ENUM_TIMEFRAMES tf)
   {
      SWaveState w; ZeroWave(w);
      MqlRates r[]; ArraySetAsSeries(r,false);
      int got=CopyRates(m_symbol,tf,0,m_cfg.historyBars,r);
      if(got<m_cfg.structLen*4 || got<8) return(w);
      int n=got;
      RunSE(r,n,n-2,w);
      return(w);
   }

   //--------------------------------------------------------------
   // The core f_se lifecycle, evaluated up to captureBar (oldest-
   // first array). Fills SWaveState at captureBar.
   //--------------------------------------------------------------
   void RunSE(const MqlRates &r[], int n, int captureBar, SWaveState &w)
   {
      int pv=m_cfg.pivotLen, effL=m_cfg.effLen;
      double effT=m_cfg.effThresh, dispT=m_cfg.dispThresh, convM=m_cfg.convMult;
      double impM=m_cfg.impulseAtrMult, chBuf=m_cfg.chochBufferATR;

      double vel=0,velP=0,acc=0,accP=0,conv=0,csm=0,atr=0; bool atrInit=false;
      double aV=2.0/4.0, aC=2.0/4.0;
      double curSH=0,curSL=0,prSH=0,prSL=0; bool hCurSH=false,hCurSL=false,hPrSH=false,hPrSL=false;
      double lastP=0; int lastD=0; double prevP=0; int prevD=0; bool hLast=false,hPrev=false;
      int dir=0; double ft=0,fb=0,p4h=0,p4l=0,inv=0,tgt=0,cycH=0,cycL=0;
      bool hFt=false,hInv=false,hCycH=false,hCycL=false,hTgt=false;
      bool bos1=false,bos2=false; double protSw=0,protSw2=0; bool hProt=false,hProt2=false;
      double indOrig=0,indExt=0; bool hIndO=false,hIndE=false,indBrk=false;
      int lastDirSeen=0,recBrk=0; bool recArm=true; int pst=0;

      for(int i=1;i<=captureBar;i++)
      {
         double c=r[i].close,o=r[i].open,h=r[i].high,l=r[i].low,cp=r[i-1].close;
         double tr=MathMax(h-l,MathMax(MathAbs(h-cp),MathAbs(l-cp)));
         if(!atrInit){ atr=tr; atrInit=true; } else atr=(atr*(m_cfg.atrLen-1)+tr)/m_cfg.atrLen;
         double atrS=MathMax(atr,1e-10);

         double dv=c-cp; velP=vel; vel=vel+aV*(dv-vel);
         double accN=vel-velP; accP=acc; acc=accN;
         conv=acc-accP; csm=csm+aC*(conv-csm);

         double mv=0,ps=0;
         if(i-effL>=0){ mv=MathAbs(c-r[i-effL].close); for(int k=0;k<effL;k++){ if(i-k-1>=0) ps+=MathAbs(r[i-k].close-r[i-k-1].close); } }
         double eff=(ps>0?mv/ps:0.0);
         double disp=(h-l)/atrS;
         bool bullImp=(eff>effT && vel>velP && acc>0 && c>o && disp>dispT);
         bool bearImp=(eff>effT && vel<velP && acc<0 && c<o && disp>dispT);
         bool bullDec=(MathAbs(acc)<MathAbs(accP)*0.8 && vel>0);
         bool bearDec=(MathAbs(acc)<MathAbs(accP)*0.8 && vel<0);
         bool vd70=(MathAbs(vel)<MathAbs(velP)*0.7);
         bool vd50=(MathAbs(vel)<MathAbs(velP)*0.5);

         double pH=0,pL=0; bool hPH=false,hPL=false; int mid=i-pv;
         if(mid-pv>=0)
         {
            bool isPH=true,isPL=true; double hm=r[mid].high,lm=r[mid].low;
            for(int k=mid-pv;k<=mid+pv;k++){ if(k==mid) continue; if(r[k].high>=hm) isPH=false; if(r[k].low<=lm) isPL=false; }
            if(isPH){ hPH=true; pH=hm; } if(isPL){ hPL=true; pL=lm; }
         }
         if(hPH){ prSH=(hCurSH?curSH:pH); hPrSH=true; curSH=pH; hCurSH=true; }
         if(hPL){ prSL=(hCurSL?curSL:pL); hPrSL=true; curSL=pL; hCurSL=true; }
         double eP=0; int eD=0;
         if(hPH){ eP=pH; eD=1; } else if(hPL){ eP=pL; eD=-1; }
         if(eD!=0){ prevP=lastP; prevD=lastD; hPrev=hLast; lastP=eP; lastD=eD; hLast=true; }

         bool bullBOS=(hPrSH && c>prSH);
         bool bearBOS=(hPrSL && c<prSL);
         bool bullCH =(hPrSH && c>prSH+atr*chBuf);
         bool bearCH =(hPrSL && c<prSL-atr*chBuf);
         bool eLong =(hPH && hPrev && prevD==-1 && (pH-prevP)>atr*impM);
         bool eShort=(hPL && hPrev && prevD==1  && (prevP-pL)>atr*impM);

         bool hasCtx=(dir!=0 && hFt);
         bool flipDn=(dir==1 && bearCH);
         bool flipUp=(dir==-1 && bullCH);
         bool isRev=((eLong && dir==-1)||(eShort && dir==1)||flipUp||flipDn);
         bool spawn=((eLong||eShort||flipUp||flipDn) && (!hasCtx||isRev));
         if(spawn && hLast && hPrev)
         {
            int nd=(eLong?1:(eShort?-1:(flipUp?1:-1)));
            double hi=MathMax(lastP,prevP), lo=MathMin(lastP,prevP);
            dir=nd; ft=hi; fb=lo; hFt=true; p4h=hi; p4l=lo;
            cycH=h; cycL=l; hCycH=true; hCycL=true;
            inv=(nd==1?lo:hi); hInv=true;
            double rng=(hPrSH && hPrSL)?MathAbs(prSH-prSL):atr*5.0;
            tgt=(nd==1?hi+rng:lo-rng); hTgt=true;
         }
         if(dir==1){ cycH=(hCycH?MathMax(cycH,h):h); hCycH=true; }
         if(dir==-1){ cycL=(hCycL?MathMin(cycL,l):l); hCycL=true; }

         bool reset=(dir!=lastDirSeen); lastDirSeen=dir;
         if(reset){ bos1=false; bos2=false; hProt=false; hProt2=false; hIndO=false; hIndE=false; indBrk=false; }
         if(dir==1 && hPL){ protSw2=protSw; hProt2=hProt; protSw=pL; hProt=true; }
         if(dir==-1 && hPH){ protSw2=protSw; hProt2=hProt; protSw=pH; hProt=true; }
         bool oppBOS=((dir==1 && hProt && c<protSw)||(dir==-1 && hProt && c>protSw));
         if(!bos1 && oppBOS){ bos1=true; indOrig=(dir==1?(hCycH?cycH:h):(hCycL?cycL:l)); hIndO=true; }
         if(bos1 && !bos2 && oppBOS && hProt2 && ((dir==1)?(c<protSw2):(c>protSw2))) bos2=true;
         if(bos1 && dir==1){ indExt=(hIndE?MathMin(indExt,c):c); hIndE=true; }
         if(bos1 && dir==-1){ indExt=(hIndE?MathMax(indExt,c):c); hIndE=true; }
         if(bos2 && hIndO){ if(dir==1 && c>indOrig) indBrk=true; if(dir==-1 && c<indOrig) indBrk=true; }

         double convScore=MathMin(MathAbs(csm)/MathMax(atr*convM,1e-10)*50.0,100.0);
         double expScore =MathMin(eff/MathMax(effT,1e-10)*50.0+disp/MathMax(dispT,1e-10)*50.0,100.0);
         double absScore =(eff<effT*0.7 && MathAbs(vel)<MathAbs(velP)*0.6)?60.0+convScore*0.4:convScore*0.3;
         bool momExpStrong=(eff>effT*0.75 && (dir==1?vel>0:vel<0));
         bool momDecaying=(dir==1?bullDec:bearDec);
         bool momCounter =(dir==1?bearImp:bullImp);
         bool momExhaust =(eff<effT*0.65 && absScore>40.0);
         bool physConvDevel=(convScore>35.0);
         bool physTransfer =(convScore>48.0 || absScore>40.0);
         bool physCapLow   =(absScore>45.0 || eff<effT*0.6);

         int wdir=(hInv?(c>inv?1:(c<inv?-1:dir)):dir);
         bool atFlip=(hFt && c<=ft && c>=fb);
         bool expanding=(momExpStrong||eLong||eShort||(wdir==1?bullImp:bearImp));
         bool atExtreme=(wdir==1?(h>=(hCycH?cycH:h)):(wdir==-1?(l<=(hCycL?cycL:l)):false));
         double extr=(wdir==1?(hCycH?cycH:c):(hCycL?cycL:c));
         bool extended=(hInv && MathAbs(extr-inv)>atr*1.5);
         double compIdx=MathMin(100.0,MathMax(0.0,(1.0-MathMin(disp/MathMax(dispT,1e-10),1.0))*60.0+(1.0-MathMin(eff/MathMax(effT,1e-10),1.0))*40.0));

         bool phase2CH=((dir==1 && bearCH)||(dir==-1 && bullCH));
         if(reset || (atExtreme && extended)){ recBrk=0; recArm=true; }
         if((dir==1 && hPH)||(dir==-1 && hPL)) recArm=true;
         if((phase2CH||oppBOS) && recArm && !atExtreme){ recBrk++; recArm=false; }
         double fzMid=(hFt?(ft+fb)/2.0:0.0);
         double retrFrac=(hFt && MathAbs(extr-fzMid)>1e-10)?MathAbs(extr-c)/MathAbs(extr-fzMid):0.0;
         double recDom=MathMin(100.0,MathMax(recBrk*(30.0-compIdx*0.15),retrFrac*80.0));
         bool transferDone=(recDom>=50.0);

         if(reset) pst=0;
         if(dir!=0 && !reset)
         {
            if(pst==0 && expanding) pst=1;
            if(pst==1 && !atExtreme && momDecaying && physConvDevel) pst=2;
            if(pst==2 && !atExtreme && momCounter && physTransfer) pst=3;
            if(pst==3 && !atExtreme && (bos1||bos2||indBrk) && physTransfer) pst=4;
            if(pst>=1 && pst<=7 && atExtreme && extended) pst=5;
            if(pst==5 && !atExtreme && (recBrk>=1||momExhaust)) pst=7;
            if(pst==7 && transferDone) pst=8;
            if(pst==8 && atFlip) pst=9;
            if(pst==9 && ((dir==1&&bullImp)||(dir==-1&&bearImp))) pst=10;
            if(pst==10 && (oppBOS||physCapLow)) pst=11;
            if(pst==11 && ((dir==1 && l<fb)||(dir==-1 && h>ft))) pst=12;
            if(pst==12 && ((dir==1&&bullCH)||(dir==-1&&bearCH))) pst=13;
         }

         if(i==captureBar)
         {
            int phase=pst;
            if(phase==5 && dir==-1) phase=6;
            if(phase==13 && dir==-1) phase=14;
            double wp=(pst==0?5.0:pst==1?15.0:pst==2?25.0:pst==3?33.0:pst==4?42.0:pst==5?55.0:pst==7?65.0:pst==8?75.0:pst==9?85.0:pst==10?90.0:pst==11?94.0:pst==12?97.0:100.0);
            double mf=MathMin(MathMax(expScore,MathMax(absScore,convScore))*0.70+(dir!=0?30.0:0.0),100.0);
            w.valid=true; w.dir=wdir; w.phase=phase; w.atr=atr;
            w.vel=vel; w.acc=acc; w.conv=conv; w.csm=csm; w.eff=eff; w.disp=disp;
            w.bullImp=bullImp; w.bearImp=bearImp; w.bullDec=bullDec; w.bearDec=bearDec;
            w.bullCH=bullCH; w.bearCH=bearCH; w.vd70=vd70; w.vd50=vd50;
            w.curSH=(hCurSH?curSH:0); w.curSL=(hCurSL?curSL:0);
            w.prSH=(hPrSH?prSH:0); w.prSL=(hPrSL?prSL:0);
            w.bos=(bullBOS?1:(bearBOS?-1:0)); w.ch=(bullCH?1:(bearCH?-1:0));
            w.p4h=p4h; w.p4l=p4l; w.inv=(hInv?inv:0); w.tgt=(hTgt?tgt:0);
            w.ft=(hFt?ft:0); w.fb=(hFt?fb:0); w.cycH=(hCycH?cycH:0); w.cycL=(hCycL?cycL:0);
            w.waveProgress=wp; w.convScore=convScore; w.expScore=expScore; w.absScore=absScore;
            w.mf=mf; w.comp=compIdx; w.sh=(hCurSH?curSH:0); w.sl=(hCurSL?curSL:0); w.closePrice=c;
         }
      }
   }

   void ZeroWave(SWaveState &w)
   {
      w.valid=false; w.dir=0; w.phase=0; w.atr=0; w.vel=0; w.acc=0; w.conv=0; w.csm=0;
      w.eff=0; w.disp=0; w.bullImp=false; w.bearImp=false; w.bullDec=false; w.bearDec=false;
      w.bullCH=false; w.bearCH=false; w.vd70=false; w.vd50=false;
      w.curSH=0; w.curSL=0; w.prSH=0; w.prSL=0; w.bos=0; w.ch=0; w.p4h=0; w.p4l=0;
      w.inv=0; w.tgt=0; w.ft=0; w.fb=0; w.cycH=0; w.cycL=0; w.waveProgress=0;
      w.convScore=0; w.expScore=0; w.absScore=0; w.mf=0; w.comp=0; w.sh=0; w.sl=0; w.closePrice=0;
   }

   //==============================================================
   // CANONICAL LIFECYCLE + CURVE TREE (chart timeframe)
   //  Runs ONE bar-by-bar pass over the chart series reproducing
   //  the observation layer, EDE/RE/EAE energy framework, belief
   //  engine, convexity maturity, dual waveProgress, the liqg
   //  liquidation overlay, and the F72 recursive curve tree.
   //==============================================================
   void ComputeCanonical(SCanonState &cs, SCurveTree &tr)
   {
      ZeroCanon(cs); ZeroTree(tr);
      ENUM_TIMEFRAMES tf=m_ladder[2];
      MqlRates r[]; ArraySetAsSeries(r,false);
      int got=CopyRates(m_symbol,tf,0,m_cfg.historyBars,r);
      if(got<m_cfg.structLen*4 || got<32) return;
      int n=got; int cap=n-2;

      // --- f_se internal lifecycle state (same as RunSE, but we
      //     keep per-bar values to drive the higher layers) -------
      int pv=m_cfg.pivotLen, effL=m_cfg.effLen, sweepL=m_cfg.liqSweepLook;
      double effT=m_cfg.effThresh, dispT=m_cfg.dispThresh, convM=m_cfg.convMult;
      double impM=m_cfg.impulseAtrMult, chBuf=m_cfg.chochBufferATR;
      double vel=0,velP=0,acc=0,accP=0,conv=0,csm=0,atr=0; bool atrInit=false;
      double aV=2.0/4.0, aC=2.0/4.0;
      double curSH=0,curSL=0,prSH=0,prSL=0; bool hCurSH=false,hCurSL=false,hPrSH=false,hPrSL=false;
      double lastP=0; int lastD=0; double prevP=0; int prevD=0; bool hLast=false,hPrev=false;
      int dir=0; double ft=0,fb=0,p4h=0,p4l=0,inv=0,tgt=0,cycH=0,cycL=0;
      bool hFt=false,hInv=false,hCycH=false,hCycL=false,hTgt=false;
      bool bos1=false,bos2=false; double protSw=0,protSw2=0; bool hProt=false,hProt2=false;
      double indOrig=0,indExt=0; bool hIndO=false,hIndE=false,indBrk=false;
      int lastDirSeen=0,recBrk=0; bool recArm=true; int pst=0;

      // --- higher-layer smoothed/persistent state ----------------
      double bSm=2.0/(m_cfg.beliefSmooth+1.0);
      double expB=0,cvxB=0,creB=0,absB=0,retB=0,demB=0;     // beliefs
      double convMat=0;                                      // convexity maturity (smoothed)
      double waveProg=30.0;                                  // dual waveProgress (smoothed)
      int    completedCycles=0;

      // --- curve tree storage ------------------------------------
      SCurveNode tree[]; int nNodes=0; ArrayResize(tree,0);
      int rootId=-1; int ownerId=-1;

      double finStructBias=0;

      for(int i=1;i<=cap;i++)
      {
         double c=r[i].close,o=r[i].open,h=r[i].high,l=r[i].low,cp=r[i-1].close;
         double tr0=MathMax(h-l,MathMax(MathAbs(h-cp),MathAbs(l-cp)));
         if(!atrInit){ atr=tr0; atrInit=true; } else atr=(atr*(m_cfg.atrLen-1)+tr0)/m_cfg.atrLen;
         double atrS=MathMax(atr,1e-10);

         double dv=c-cp; velP=vel; vel=vel+aV*(dv-vel);
         double accN=vel-velP; accP=acc; acc=accN; conv=acc-accP; csm=csm+aC*(conv-csm);

         double mv=0,ps=0;
         if(i-effL>=0){ mv=MathAbs(c-r[i-effL].close); for(int k=0;k<effL;k++){ if(i-k-1>=0) ps+=MathAbs(r[i-k].close-r[i-k-1].close); } }
         double eff=(ps>0?mv/ps:0.0);
         double disp=(h-l)/atrS;
         bool bullImp=(eff>effT && vel>velP && acc>0 && c>o && disp>dispT);
         bool bearImp=(eff>effT && vel<velP && acc<0 && c<o && disp>dispT);
         bool bullDec=(MathAbs(acc)<MathAbs(accP)*0.8 && vel>0);
         bool bearDec=(MathAbs(acc)<MathAbs(accP)*0.8 && vel<0);
         bool bullConvShift=(csm>atr*convM && (i>1));
         bool bearConvShift=(csm<-atr*convM && (i>1));

         // pivots
         double pH=0,pL=0; bool hPH=false,hPL=false; int mid=i-pv;
         if(mid-pv>=0)
         {
            bool isPH=true,isPL=true; double hm=r[mid].high,lm=r[mid].low;
            for(int k=mid-pv;k<=mid+pv;k++){ if(k==mid) continue; if(r[k].high>=hm) isPH=false; if(r[k].low<=lm) isPL=false; }
            if(isPH){ hPH=true; pH=hm; } if(isPL){ hPL=true; pL=lm; }
         }
         if(hPH){ prSH=(hCurSH?curSH:pH); hPrSH=true; curSH=pH; hCurSH=true; }
         if(hPL){ prSL=(hCurSL?curSL:pL); hPrSL=true; curSL=pL; hCurSL=true; }
         double eP=0; int eD=0;
         if(hPH){ eP=pH; eD=1; } else if(hPL){ eP=pL; eD=-1; }
         if(eD!=0){ prevP=lastP; prevD=lastD; hPrev=hLast; lastP=eP; lastD=eD; hLast=true; }

         bool bullBOS=(hPrSH && c>prSH);
         bool bearBOS=(hPrSL && c<prSL);
         bool bullCH =(hPrSH && c>prSH+atr*chBuf);
         bool bearCH =(hPrSL && c<prSL-atr*chBuf);
         bool eLong =(hPH && hPrev && prevD==-1 && (pH-prevP)>atr*impM);
         bool eShort=(hPL && hPrev && prevD==1  && (prevP-pL)>atr*impM);

         bool hasCtx=(dir!=0 && hFt);
         bool flipDn=(dir==1 && bearCH);
         bool flipUp=(dir==-1 && bullCH);
         bool isRev=((eLong && dir==-1)||(eShort && dir==1)||flipUp||flipDn);
         bool spawn=((eLong||eShort||flipUp||flipDn) && (!hasCtx||isRev));
         if(spawn && hLast && hPrev)
         {
            int nd=(eLong?1:(eShort?-1:(flipUp?1:-1)));
            double hi=MathMax(lastP,prevP), lo=MathMin(lastP,prevP);
            dir=nd; ft=hi; fb=lo; hFt=true; p4h=hi; p4l=lo;
            cycH=h; cycL=l; hCycH=true; hCycL=true;
            inv=(nd==1?lo:hi); hInv=true;
            double rng=(hPrSH && hPrSL)?MathAbs(prSH-prSL):atr*5.0;
            tgt=(nd==1?hi+rng:lo-rng); hTgt=true;
         }
         if(dir==1){ cycH=(hCycH?MathMax(cycH,h):h); hCycH=true; }
         if(dir==-1){ cycL=(hCycL?MathMin(cycL,l):l); hCycL=true; }

         bool reset=(dir!=lastDirSeen); lastDirSeen=dir;
         if(reset){ bos1=false; bos2=false; hProt=false; hProt2=false; hIndO=false; hIndE=false; indBrk=false; }
         if(dir==1 && hPL){ protSw2=protSw; hProt2=hProt; protSw=pL; hProt=true; }
         if(dir==-1 && hPH){ protSw2=protSw; hProt2=hProt; protSw=pH; hProt=true; }
         bool oppBOS=((dir==1 && hProt && c<protSw)||(dir==-1 && hProt && c>protSw));
         if(!bos1 && oppBOS){ bos1=true; indOrig=(dir==1?(hCycH?cycH:h):(hCycL?cycL:l)); hIndO=true; }
         if(bos1 && !bos2 && oppBOS && hProt2 && ((dir==1)?(c<protSw2):(c>protSw2))) bos2=true;
         if(bos1 && dir==1){ indExt=(hIndE?MathMin(indExt,c):c); hIndE=true; }
         if(bos1 && dir==-1){ indExt=(hIndE?MathMax(indExt,c):c); hIndE=true; }
         if(bos2 && hIndO){ if(dir==1 && c>indOrig) indBrk=true; if(dir==-1 && c<indOrig) indBrk=true; }

         double convScore=MathMin(MathAbs(csm)/MathMax(atr*convM,1e-10)*50.0,100.0);
         double expScore =MathMin(eff/MathMax(effT,1e-10)*50.0+disp/MathMax(dispT,1e-10)*50.0,100.0);
         double absScore =(eff<effT*0.7 && MathAbs(vel)<MathAbs(velP)*0.6)?60.0+convScore*0.4:convScore*0.3;
         bool momExpStrong=(eff>effT*0.75 && (dir==1?vel>0:vel<0));
         bool momDecaying=(dir==1?bullDec:bearDec);
         bool momCounter =(dir==1?bearImp:bullImp);
         bool momExhaust =(eff<effT*0.65 && absScore>40.0);
         bool physConvDevel=(convScore>35.0);
         bool physTransfer =(convScore>48.0 || absScore>40.0);
         bool physCapLow   =(absScore>45.0 || eff<effT*0.6);

         int wdir=(hInv?(c>inv?1:(c<inv?-1:dir)):dir);
         bool atFlip=(hFt && c<=ft && c>=fb);
         bool expanding=(momExpStrong||eLong||eShort||(wdir==1?bullImp:bearImp));
         bool atExtreme=(wdir==1?(h>=(hCycH?cycH:h)):(wdir==-1?(l<=(hCycL?cycL:l)):false));
         double extr=(wdir==1?(hCycH?cycH:c):(hCycL?cycL:c));
         bool extended=(hInv && MathAbs(extr-inv)>atr*1.5);
         double compIdx=MathMin(100.0,MathMax(0.0,(1.0-MathMin(disp/MathMax(dispT,1e-10),1.0))*60.0+(1.0-MathMin(eff/MathMax(effT,1e-10),1.0))*40.0));

         bool phase2CH=((dir==1 && bearCH)||(dir==-1 && bullCH));
         if(reset || (atExtreme && extended)){ recBrk=0; recArm=true; }
         if((dir==1 && hPH)||(dir==-1 && hPL)) recArm=true;
         if((phase2CH||oppBOS) && recArm && !atExtreme){ recBrk++; recArm=false; }
         double fzMid=(hFt?(ft+fb)/2.0:0.0);
         double retrFrac=(hFt && MathAbs(extr-fzMid)>1e-10)?MathAbs(extr-c)/MathAbs(extr-fzMid):0.0;
         double recDom=MathMin(100.0,MathMax(recBrk*(30.0-compIdx*0.15),retrFrac*80.0));
         bool transferDone=(recDom>=50.0);

         // phase machine
         if(reset) pst=0;
         if(dir!=0 && !reset)
         {
            if(pst==0 && expanding) pst=1;
            if(pst==1 && !atExtreme && momDecaying && physConvDevel) pst=2;
            if(pst==2 && !atExtreme && momCounter && physTransfer) pst=3;
            if(pst==3 && !atExtreme && (bos1||bos2||indBrk) && physTransfer) pst=4;
            if(pst>=1 && pst<=7 && atExtreme && extended) pst=5;
            if(pst==5 && !atExtreme && (recBrk>=1||momExhaust)) pst=7;
            if(pst==7 && transferDone) pst=8;
            if(pst==8 && atFlip) pst=9;
            if(pst==9 && ((dir==1&&bullImp)||(dir==-1&&bearImp))) pst=10;
            if(pst==10 && (oppBOS||physCapLow)) pst=11;
            if(pst==11 && ((dir==1 && l<fb)||(dir==-1 && h>ft))) pst=12;
            if(pst==12 && ((dir==1&&bullCH)||(dir==-1&&bearCH))) pst=13;
            if(pst==13) { completedCycles++; }
         }

         // structure bias (HH/HL vs LH/LL)
         int sb=0;
         if(hCurSH && hPrSH && hCurSL && hPrSL)
         {
            bool hh=curSH>prSH, hl=curSL>prSL, lh=curSH<prSH, ll=curSL<prSL;
            sb=((hh&&hl)?1:((lh&&ll)?-1:0));
         }

         //========== OBSERVATION LAYER ==========
         double obsExp=Clamp(expScore,0,100);
         double obsDecay=Clamp((vd70?40.0:0.0)+(vd50?30.0:0.0)+(momDecaying?30.0:0.0),0,100);
         double obsCurv=convScore;
         double obsAbs=absScore;
         // liquidity sweep over sweepL
         double swH=-DBL_MAX,swL=DBL_MAX;
         for(int k=i-1;k>=MathMax(1,i-sweepL);k--){ if(r[k].high>swH) swH=r[k].high; if(r[k].low<swL) swL=r[k].low; }
         bool sweepBull=(l<swL && c>swL);
         bool sweepBear=(h>swH && c<swH);
         double obsLiq=Clamp((sweepBull||sweepBear?55.0:0.0)+(atFlip?25.0:0.0)+(indBrk?20.0:0.0),0,100);

         //========== BELIEF ENGINE (smoothed) ==========
         double expRaw=Clamp(obsExp*0.6+(expanding?40.0:0.0),0,100);
         double cvxRaw=Clamp(obsCurv*0.7+(physConvDevel?30.0:0.0),0,100);
         double creRaw=Clamp((pst>=7?50.0:0.0)+(transferDone?30.0:0.0)+(atFlip?20.0:0.0),0,100);
         double absRaw=Clamp(obsAbs*0.7+(momExhaust?30.0:0.0),0,100);
         double retRaw=Clamp((recBrk>0?40.0:0.0)+retrFrac*60.0,0,100);
         double demRaw=Clamp((sweepBull||sweepBear?40.0:0.0)+(pst>=12?40.0:0.0)+(indBrk?20.0:0.0),0,100);
         expB+=bSm*(expRaw-expB); cvxB+=bSm*(cvxRaw-cvxB); creB+=bSm*(creRaw-creB);
         absB+=bSm*(absRaw-absB); retB+=bSm*(retRaw-retB); demB+=bSm*(demRaw-demB);

         //========== CONVEXITY MATURITY (smoothed) ==========
         double cvxMatRaw=Clamp(convScore*0.5+(physTransfer?30.0:0.0)+(momCounter?20.0:0.0),0,100);
         convMat+=bSm*(cvxMatRaw-convMat);

         //========== DUAL WAVE PROGRESS (smoothed) ==========
         // geometric: retrace position of price within origin->extreme
         double geom=0;
         if(hInv && MathAbs(extr-inv)>1e-10) geom=Clamp(MathAbs(c-inv)/MathAbs(extr-inv)*100.0,0,100);
         // physical: phase anchor blended with convexity maturity
         double phAnchor=(pst==0?5.0:pst==1?15.0:pst==2?25.0:pst==3?33.0:pst==4?42.0:pst==5?55.0:pst==7?65.0:pst==8?75.0:pst==9?85.0:pst==10?90.0:pst==11?94.0:pst==12?97.0:100.0);
         double convWeight=MathMax(0.0,1.0-MathAbs(phAnchor-47.5)/14.5);
         double physP=phAnchor+(convMat/100.0)*(phAnchor-33.0)*0.50*convWeight;
         double rawWP=geom*0.60+physP*0.40;
         waveProg+=bSm*(rawWP-waveProg); waveProg=Clamp(waveProg,0,100);

         //========== CURVE TREE (F72) ==========
         // root = chart wave; spawn a child curve on each CHoCH that
         // creates a new directional leg; track origin/extreme/energy.
         double curveEnergy=Clamp(expScore*0.5+convScore*0.3+(dir!=0?20.0:0.0),0,100);
         if(spawn && hLast && hPrev)
         {
            // close prior owner (mark recursion), spawn new root-level node
            SCurveNode nd; nd.id=nNodes; nd.parent=rootId; nd.dir=dir;
            nd.origin=inv; nd.extreme=(dir==1?h:l); nd.energy=curveEnergy;
            nd.alive=true; nd.depth=(rootId<0?0:1); nd.state=PhaseStr(pst);
            nd.bar=i; nd.comp=compIdx; nd.mat=convMat; nd.srcTf=0;
            ArrayResize(tree,nNodes+1); tree[nNodes]=nd; rootId=nNodes; ownerId=nNodes; nNodes++;
         }
         else if((bullCH||bearCH) && ownerId>=0 && nNodes>0)
         {
            // CHoCH within the wave => recursive child curve
            int cdir=(bullCH?1:-1);
            if(tree[ownerId].dir!=cdir)
            {
               SCurveNode nd; nd.id=nNodes; nd.parent=ownerId; nd.dir=cdir;
               nd.origin=c; nd.extreme=c; nd.energy=curveEnergy;
               nd.alive=true; nd.depth=tree[ownerId].depth+1; nd.state=PhaseStr(pst);
               nd.bar=i; nd.comp=compIdx; nd.mat=convMat; nd.srcTf=0;
               ArrayResize(tree,nNodes+1); tree[nNodes]=nd;
               tree[ownerId].alive=true; ownerId=nNodes; nNodes++;
            }
         }
         // update owner extreme / energy / emergent state
         if(ownerId>=0)
         {
            if(tree[ownerId].dir==1) tree[ownerId].extreme=MathMax(tree[ownerId].extreme,h);
            else if(tree[ownerId].dir==-1) tree[ownerId].extreme=MathMin(tree[ownerId].extreme,l);
            tree[ownerId].energy=tree[ownerId].energy*0.92+curveEnergy*0.08;
            tree[ownerId].state=PhaseStr(pst);
            tree[ownerId].comp=compIdx; tree[ownerId].mat=convMat;
            // a node dies when price reclaims its origin against its direction
            if(tree[ownerId].dir==1 && c<tree[ownerId].origin) tree[ownerId].alive=false;
            if(tree[ownerId].dir==-1 && c>tree[ownerId].origin) tree[ownerId].alive=false;
         }

         finStructBias=sb;

         //========== capture final-bar state ==========
         if(i==cap)
         {
            int phase=pst;
            if(phase==5 && dir==-1) phase=6;
            if(phase==13 && dir==-1) phase=14;

            cs.valid=true; cs.dir=wdir; cs.structBias=(int)finStructBias;
            cs.phaseCode=phase; cs.phaseStr=PhaseStr(phase); cs.atr=atr;
            cs.velocity=vel; cs.acceleration=acc; cs.convexity=conv; cs.convSmooth=csm;
            cs.efficiency=eff; cs.displacement=disp;
            cs.bullImpulse=bullImp; cs.bearImpulse=bearImp; cs.bullMomDecay=bullDec; cs.bearMomDecay=bearDec;
            cs.bullConvShift=bullConvShift; cs.bearConvShift=bearConvShift;
            cs.obs_Expansion=obsExp; cs.obs_Decay=obsDecay; cs.obs_Curvature=obsCurv;
            cs.obs_Absorption=obsAbs; cs.obs_Liquidity=obsLiq;
            cs.expansionBelief=expB; cs.convexityBelief=cvxB; cs.creationBelief=creB;
            cs.absorptionBelief=absB; cs.retracementBelief=retB; cs.demandReturnBelief=demB;
            cs.convexityMaturity=convMat; cs.waveProgress=waveProg;
            cs.inv=(hInv?inv:0); cs.tgt=(hTgt?tgt:0); cs.ft=(hFt?ft:0); cs.fb=(hFt?fb:0);
            cs.p4h=p4h; cs.p4l=p4l; cs.cycH=(hCycH?cycH:0); cs.cycL=(hCycL?cycL:0);
            cs.sh=(hCurSH?curSH:0); cs.sl=(hCurSL?curSL:0);

            //===== EDE — Energy Dissipation Engine =====
            double expEnergy=Clamp(expB*0.6+expScore*0.4,0,100);
            double dissipated=Clamp((phase>=2?absB*0.4:0.0)+(phase>=3?cvxB*0.3:0.0)+(phase>=5?30.0:0.0)+(phase>=8?20.0:0.0),0,100);
            double dissipProg=Clamp((phase>=2?20.0:0.0)+(phase>=3?15.0:0.0)+(phase>=5?20.0:0.0)+(phase>=7?15.0:0.0)+(phase>=8?10.0:0.0)+(phase>=11?10.0:0.0)+(phase>=13?10.0:0.0),0,100);
            int edeState=(phase<=1?1:phase<=4?2:phase<=7?3:phase<=10?4:5);
            cs.ede_state=edeState; cs.ede_expansionEnergy=expEnergy;
            cs.ede_dissipatedEnergy=dissipated; cs.ede_dissipationProgress=dissipProg;

            //===== RE — Resolution Engine =====
            double residual=Clamp(MathMax(0.0,expEnergy-dissipated),0,100);
            int    expectedCycles=2+(MathAbs(cs.structBias)>0?1:0);
            double recCompletion=Clamp((double)completedCycles/expectedCycles*100.0,0,100);
            bool   objectiveReached=(phase>=5);
            bool   absorbedReturned=(phase==13||phase==14);
            bool   fullDissip=(dissipProg>=75.0);
            int    resCode=(absorbedReturned && fullDissip && recCompletion>=60.0)?2:((objectiveReached && dissipProg>=50.0)?1:0);
            cs.residual=residual; cs.resCode=resCode;

            //===== EAE — Emergent Attractor Engine =====
            double zmid=(hFt?(ft+fb)/2.0:c);
            double dist=MathAbs(c-zmid)/atrS;
            double distScore=MathMax(0.0,30.0-dist*5.0);
            double attractor=Clamp(residual*0.4+(resCode==0?30.0:resCode==1?20.0:5.0)+distScore+convMat*0.1,0,100);
            double attractorPrice=(resCode==0?(hTgt?tgt:zmid):zmid);
            cs.attractor=attractor; cs.attractorPrice=attractorPrice;
            cs.attractorLabel=(resCode==0?"OBJECTIVE":"FLIP RETURN");
            cs.waveModelFit=MathMin(MathMax(expScore,MathMax(absScore,convScore))*0.7+(dir!=0?30.0:0.0),100.0);
            cs.phaseConfidence=Clamp(cs.waveModelFit,0,100);
            cs.phaseIntegrity=Clamp(100.0-MathAbs(geom-phAnchor),0,100);

            //===== liqg liquidation-wave overlay =====
            bool inducPhase=(phase==3||phase==10);
            bool liqPhase=(phase==4||phase==12);
            cs.liqg_active=(inducPhase||liqPhase);
            cs.liqg_dir=dir;
            cs.liqg_target=(dir==1?(hCycH?cycH:c)+atr*1.5:(hCycL?cycL:c)-atr*1.5);
            cs.liqg_distPct=Clamp(MathAbs(c-cs.liqg_target)/atrS*20.0,0,100);
            cs.liqg_subPhase=(inducPhase?"INDUCTION":liqPhase?"LIQUIDITY GRAB":"—");
            cs.liqg_title=(cs.liqg_active?(dir==1?"BULL ":"BEAR ")+cs.liqg_subPhase:"DORMANT");

            //===== attack sequence levels =====
            double entryRef=(hFt?(ft+fb)/2.0:c);
            cs.atkEntry=entryRef; cs.atkStop=(hInv?inv:0);
            cs.atkT1=(hTgt?tgt:0);
            cs.atkT2=(dir==1?entryRef+MathAbs(entryRef-(hInv?inv:entryRef))*3.0:entryRef-MathAbs(entryRef-(hInv?inv:entryRef))*3.0);
            cs.atkT3=(dir==1?(hCycH?cycH:c)+atr*4.0:(hCycL?cycL:c)-atr*4.0);
         }
      }

      //===== finalise CURVE TREE result =====
      tr.alive=0; tr.depth=0;
      for(int k=0;k<nNodes;k++){ if(tree[k].alive) tr.alive++; if(tree[k].depth>tr.depth) tr.depth=tree[k].depth; }
      if(ownerId>=0)
      {
         tr.ownerDir=tree[ownerId].dir; tr.ownerDepth=tree[ownerId].depth;
         tr.ownerEnergy=tree[ownerId].energy; tr.ownerState=tree[ownerId].state;
         tr.ownerOrigin=tree[ownerId].origin; tr.ownerExtreme=tree[ownerId].extreme;
         double span=MathAbs(tree[ownerId].extreme-tree[ownerId].origin);
         tr.mig50 =tree[ownerId].origin+(tree[ownerId].dir==1?span*0.50:-span*0.50);
         tr.mig618=tree[ownerId].origin+(tree[ownerId].dir==1?span*0.382:-span*0.382);
      }
      // "is the trade alive" life score
      double life=Clamp(tr.ownerEnergy*0.5+(tr.alive>0?25.0:0.0)+(cs.resCode==0?15.0:cs.resCode==1?5.0:0.0)+(cs.dir==tr.ownerDir && cs.dir!=0?10.0:0.0),0,100);
      tr.life=life;
      tr.aliveTx=(life>=66?"ALIVE — owner in control":life>=40?"CONTESTED":"DECAYING / resolve");
      tr.cpForce=tr.ownerEnergy;
      tr.cpState=(tr.ownerDir==1?"DEMAND owns":tr.ownerDir==-1?"SUPPLY owns":"BALANCED");
      tr.cpTrend=(tr.ownerEnergy>=55?"STRENGTHENING":tr.ownerEnergy>=35?"HOLDING":"WEAKENING");
      tr.recursionComplete=(cs.resCode==2);
      tr.budgetDepth=2+MathAbs(cs.structBias);
      tr.htfRoomAtr=(cs.atr>0?MathAbs((cs.tgt!=0?cs.tgt:cs.atkT3)-cs.atkEntry)/cs.atr:0);
      tr.htfThreat=(tr.htfRoomAtr>=4.0?"CLEAR RUNWAY":tr.htfRoomAtr>=2.0?"MODERATE":"TIGHT — HTF wall near");
   }

   //==============================================================
   // TIME INTELLIGENCE ENGINE (MN/W/D/H4/H1 bias + sequence)
   //==============================================================
   STimeState ComputeTimeEngine()
   {
      STimeState t; t.dir=0; t.align=50; t.conflict=50; t.stack=""; t.seq=""; t.h1Timing="BALANCED"; t.h1LowProb=50;
      ENUM_TIMEFRAMES tfs[5]; tfs[0]=PERIOD_MN1; tfs[1]=PERIOD_W1; tfs[2]=PERIOD_D1; tfs[3]=PERIOD_H4; tfs[4]=PERIOD_H1;
      string lbl[5]; lbl[0]="MN"; lbl[1]="W"; lbl[2]="D"; lbl[3]="H4"; lbl[4]="H1";
      int bull=0,bear=0; string stack="";
      for(int i=0;i<5;i++)
      {
         double op=iOpen(m_symbol,tfs[i],0);
         double cl=iClose(m_symbol,tfs[i],0);
         int b=(cl>op?1:(cl<op?-1:0));
         if(b==1) bull++; else if(b==-1) bear++;
         stack+=lbl[i]+(b==1?"+":b==-1?"-":"=")+" ";
      }
      t.dir=(bull>bear?1:(bear>bull?-1:0));
      t.align=((bull+bear)>0)?(double)MathMax(bull,bear)/(bull+bear)*100.0:50.0;
      t.conflict=100.0-t.align;
      t.stack=stack;
      // H1 timing — where is H1 vs its open/prior range
      double h1o=iOpen(m_symbol,PERIOD_H1,0), h1c=iClose(m_symbol,PERIOD_H1,0);
      double h1ph=iHigh(m_symbol,PERIOD_H1,1), h1pl=iLow(m_symbol,PERIOD_H1,1);
      double rng=MathMax(h1ph-h1pl,1e-10);
      double pos=Clamp((h1c-h1pl)/rng*100.0,0,100);
      t.h1LowProb=100.0-pos;
      t.h1Timing=(t.h1LowProb>=55?"LOW FIRST":t.h1LowProb<=45?"HIGH FIRST":"BALANCED");
      t.seq=(t.dir==1?"HTF demand stacking":t.dir==-1?"HTF supply stacking":"HTF balanced");
      return(t);
   }

   //==============================================================
   // NODE / FU AUTHORITY NETWORK
   //==============================================================
   SNetState ComputeNodeNetwork()
   {
      SNetState ns; ns.netBias=0; ns.eligN=0; ns.openMem=0; ns.consumed=0;
      ns.bullAuth=0; ns.bearAuth=0; ns.pressure=0; ns.pdir=0; ns.fezHi=0; ns.fezLo=0;
      ENUM_TIMEFRAMES tfs[7]; int wt[7];
      tfs[0]=PERIOD_MN1; wt[0]=9; tfs[1]=PERIOD_W1; wt[1]=8; tfs[2]=PERIOD_D1; wt[2]=7;
      tfs[3]=PERIOD_H4;  wt[3]=6; tfs[4]=PERIOD_H1; wt[4]=5; tfs[5]=PERIOD_M15; wt[5]=4; tfs[6]=PERIOD_M5; wt[6]=3;
      bool netSet=false;
      double fezBullPx=0,fezBearPx=0; bool haveBull=false,haveBear=false;
      double curPrice=iClose(m_symbol,m_ladder[2],0);
      for(int i=0;i<7;i++)
      {
         int need=m_cfg.nodeScanBars;
         MqlRates r[]; ArraySetAsSeries(r,true);
         int got=CopyRates(m_symbol,tfs[i],0,need,r);
         if(got<m_cfg.fuLookback+m_cfg.atrLen+8) continue;
         // highest-TF valid FU at the most recent event sets netBias
         double lastTip=0; bool tipSet=false;
         // scan recent bars for unbroken FU nodes
         for(int b=1;b<got-(m_cfg.fuLookback+2);b++)
         {
            SFuState f=ComputeFUat(r,b);
            if(!f.valid) continue;
            if(tipSet && MathAbs(f.tip-lastTip)<1e-9) continue;
            lastTip=f.tip; tipSet=true;
            // consumed if price has traded through the tip against node dir
            bool consumed=(f.dir==-1?curPrice>f.tip:curPrice<f.tip);
            double auth=f.score+wt[i]*4.0;
            if(consumed){ ns.consumed++; }
            else
            {
               ns.openMem++;
               if(auth>=m_cfg.authMin)
               {
                  ns.eligN++;
                  if(f.dir==1){ ns.bullAuth+=auth; if(!haveBull && f.tip<curPrice){ fezBullPx=f.tip; haveBull=true; } }
                  else if(f.dir==-1){ ns.bearAuth+=auth; if(!haveBear && f.tip>curPrice){ fezBearPx=f.tip; haveBear=true; } }
               }
            }
            if(!netSet && b<=2){ ns.netBias=f.dir; netSet=true; } // most recent on highest TF
            if(ns.openMem>120) break;
         }
      }
      if(!netSet)
      {
         double ema=EMAclose(m_ladder[2],50);
         double c=iClose(m_symbol,m_ladder[2],1);
         ns.netBias=(c>ema?1:(c<ema?-1:0));
      }
      double tot=ns.bullAuth+ns.bearAuth;
      ns.pressure=(tot>0)?(ns.bullAuth-ns.bearAuth)/tot*100.0:0.0;
      ns.pdir=(ns.pressure>12?1:(ns.pressure<-12?-1:0));
      ns.fezHi=(haveBear?fezBearPx:0); ns.fezLo=(haveBull?fezBullPx:0);
      return(ns);
   }

   //==============================================================
   // MASTER EVALUATION — assemble the whole brain + verdict
   //==============================================================
   SSenseeiResult Evaluate()
   {
      SSenseeiResult res; ZeroResult(res);

      // 1) fractal stack of 6 ladder rungs
      SWaveState w[6];
      for(int i=0;i<6;i++) w[i]=ComputeWave(m_ladder[i]);
      int bull=0,bear=0;
      for(int i=0;i<6;i++)
      {
         res.rungTf[i]=TfLabel(m_ladder[i]);
         res.rungDir[i]=(w[i].valid?w[i].dir:0);
         res.rungPhase[i]=(w[i].valid?w[i].phase:0);
         res.rungProg[i]=(w[i].valid?w[i].waveProgress:0);
         if(!w[i].valid) continue;
         if(w[i].dir==1) bull++; else if(w[i].dir==-1) bear++;
      }
      int stackDir=(bull>bear?1:(bear>bull?-1:0));
      double stackPct=(double)MathMax(bull,bear)/6.0*100.0;

      // 2) canonical lifecycle + curve tree
      SCanonState cs; SCurveTree tr;
      ComputeCanonical(cs,tr);
      if(!cs.valid) return(res);

      // 3) node network
      SNetState ns=ComputeNodeNetwork();

      // 4) time engine
      STimeState te=ComputeTimeEngine();

      // 5) meta-intelligence votes
      int waveDir=cs.dir;
      int vt1=waveDir, vt2=stackDir, vt3=ns.netBias, vt4=ns.pdir;
      int sum=vt1+vt2+vt3+vt4;
      int master=(sum>0?1:(sum<0?-1:0));
      int cast=(vt1!=0?1:0)+(vt2!=0?1:0)+(vt3!=0?1:0)+(vt4!=0?1:0);
      int forV=((vt1==master&&vt1!=0)?1:0)+((vt2==master&&vt2!=0)?1:0)+((vt3==master&&vt3!=0)?1:0)+((vt4==master&&vt4!=0)?1:0);
      double alignment=(cast>0?(double)forV/cast*100.0:50.0);
      double conflict =(cast>0?(double)(cast-forV)/cast*100.0:0.0);

      double threat=Clamp(conflict*0.40+cs.residual*0.28+te.conflict*0.12+((ns.pdir!=0&&ns.pdir!=master)?18.0:0.0)+(cs.resCode==1?10.0:0.0)+(tr.life<40?10.0:0.0),0,100);
      double confidence=Clamp(alignment*0.40+te.align*0.12+stackPct*0.18+cs.attractor*0.12+tr.life*0.08+MathMin(12.0,ns.eligN*1.0)-threat*0.20,0,100);
      double oppScore=Clamp(alignment*0.40+cs.attractor*0.30+stackPct*0.30-threat*0.35,0,100);

      string opportunity=(master==0?"NONE":(conflict>60?"DEVELOPING":(oppScore<20?"NONE":(oppScore<40?"DEVELOPING":(oppScore<62?"GOOD":(oppScore<82?"STRONG":"EXCEPTIONAL"))))));
      string action;
      if(master==0) action="WAIT";
      else if(conflict>60) action="WAIT";
      else if(cs.resCode==2) action="MANAGE / EXIT";
      else if((opportunity=="STRONG"||opportunity=="EXCEPTIONAL") && confidence>=m_cfg.minConf && threat<45) action="ATTACK";
      else if(opportunity=="GOOD"||opportunity=="STRONG") action="PREPARE";
      else action="WAIT";

      double wpp=cs.waveProgress;
      string timing=(cs.resCode==2?"RESOLVED":(wpp<15?"VERY EARLY":(wpp<35?"EARLY":(wpp<55?"DEVELOPING":(wpp<80?"MID CYCLE":(wpp<96?"LATE":"TERMINAL"))))));

      // intent — what the market is trying to do
      string intent;
      if(cs.liqg_active) intent=(cs.liqg_dir==1?"Engineer liquidity then mark UP":"Engineer liquidity then mark DOWN");
      else if(cs.phaseCode<=4) intent=(master==1?"Expand demand higher":master==-1?"Expand supply lower":"Build position");
      else if(cs.phaseCode<=7) intent="Form extreme / transfer energy";
      else if(cs.phaseCode<=10) intent="Test flip-zone, induce late entries";
      else intent="Return to value / resolve cycle";

      // story
      string dirTx=(master==1?"Bullish":master==-1?"Bearish":"Neutral");
      string story=StringFormat("%s wave · %.0f%% · %s · stack %d/6 · %s · %s.",
                   dirTx,cs.waveProgress,cs.phaseStr,(int)MathRound(stackPct/100.0*6.0),tr.aliveTx,timing);

      // participant fib zones (origin->extreme of canonical leg)
      double oA=(cs.inv!=0?cs.inv:cs.atkEntry);
      double eB=(cs.dir==1?(cs.cycH!=0?cs.cycH:cs.atkEntry):(cs.cycL!=0?cs.cycL:cs.atkEntry));
      double span=(eB-oA);
      res.fib618=eB-span*0.382;
      res.fib705=eB-span*0.295;
      res.fib786=eB-span*0.214;
      res.fibFlip=(cs.ft!=0?(cs.ft+cs.fb)/2.0:oA+span*0.5);

      // populate result
      res.ready=true; res.barTime=iTime(m_symbol,m_ladder[2],0);
      res.waveDir=waveDir; res.stackDir=stackDir; res.stackPct=stackPct;
      res.netBias=ns.netBias; res.pdir=ns.pdir; res.master=master;
      res.alignment=alignment; res.conflict=conflict; res.threat=threat;
      res.confidence=confidence; res.oppScore=oppScore;
      res.timeAlign=te.align; res.timeConflict=te.conflict;
      res.residual=cs.residual; res.attractor=cs.attractor; res.resCode=cs.resCode;
      res.opportunity=opportunity; res.action=action; res.timing=timing;
      res.intent=intent; res.story=story;
      res.entryRef=cs.atkEntry; res.stopRef=cs.atkStop; res.targetRef=cs.atkT1;
      res.t2Ref=cs.atkT2; res.t3Ref=cs.atkT3;
      res.flipTop=cs.ft; res.flipBot=cs.fb; res.atr=cs.atr;
      res.phase=cs.phaseCode; res.phaseStr=cs.phaseStr;
      res.canon=cs; res.tree=tr; res.time=te; res.net=ns;
      return(res);
   }

   //--- zeroers --------------------------------------------------
   void ZeroCanon(SCanonState &c)
   {
      c.valid=false; c.dir=0; c.structBias=0; c.phaseCode=0; c.phaseStr="Forming"; c.atr=0;
      c.velocity=0; c.acceleration=0; c.convexity=0; c.convSmooth=0; c.efficiency=0; c.displacement=0;
      c.bullImpulse=false; c.bearImpulse=false; c.bullMomDecay=false; c.bearMomDecay=false;
      c.bullConvShift=false; c.bearConvShift=false;
      c.obs_Expansion=0; c.obs_Decay=0; c.obs_Curvature=0; c.obs_Absorption=0; c.obs_Liquidity=0;
      c.ede_state=0; c.ede_expansionEnergy=0; c.ede_dissipatedEnergy=0; c.ede_dissipationProgress=0;
      c.resCode=0; c.residual=0; c.attractor=0; c.attractorPrice=0; c.attractorLabel="";
      c.liqg_active=false; c.liqg_dir=0; c.liqg_target=0; c.liqg_distPct=0; c.liqg_subPhase="—"; c.liqg_title="DORMANT";
      c.expansionBelief=0; c.convexityBelief=0; c.creationBelief=0; c.absorptionBelief=0; c.retracementBelief=0; c.demandReturnBelief=0;
      c.convexityMaturity=0; c.waveProgress=0; c.waveModelFit=0; c.phaseConfidence=0; c.phaseIntegrity=0;
      c.inv=0; c.tgt=0; c.ft=0; c.fb=0; c.p4h=0; c.p4l=0; c.cycH=0; c.cycL=0; c.sh=0; c.sl=0;
      c.atkEntry=0; c.atkStop=0; c.atkT1=0; c.atkT2=0; c.atkT3=0;
   }
   void ZeroTree(SCurveTree &t)
   {
      t.alive=0; t.depth=0; t.ownerDir=0; t.ownerDepth=0; t.ownerEnergy=0; t.ownerState="";
      t.ownerOrigin=0; t.ownerExtreme=0; t.life=0; t.aliveTx="—"; t.cpState="—"; t.cpForce=0; t.cpTrend="—";
      t.mig50=0; t.mig618=0; t.htfThreat="—"; t.htfRoomAtr=0; t.budgetDepth=0; t.recursionComplete=false;
   }
   void ZeroResult(SSenseeiResult &r)
   {
      r.ready=false; r.barTime=0;
      r.waveDir=0; r.stackDir=0; r.stackPct=0; r.netBias=0; r.pdir=0; r.master=0;
      r.alignment=0; r.conflict=0; r.threat=0; r.confidence=0; r.oppScore=0;
      r.timeAlign=0; r.timeConflict=0; r.residual=0; r.attractor=0; r.resCode=0;
      r.opportunity="NONE"; r.action="WAIT"; r.timing=""; r.intent=""; r.story="";
      r.entryRef=0; r.stopRef=0; r.targetRef=0; r.t2Ref=0; r.t3Ref=0;
      r.flipTop=0; r.flipBot=0; r.atr=0; r.phase=0; r.phaseStr="Forming";
      r.fib618=0; r.fib705=0; r.fib786=0; r.fibFlip=0;
      ZeroCanon(r.canon); ZeroTree(r.tree);
      r.time.dir=0; r.time.align=0; r.time.conflict=0; r.time.stack=""; r.time.seq=""; r.time.h1Timing=""; r.time.h1LowProb=0;
      r.net.netBias=0; r.net.eligN=0; r.net.openMem=0; r.net.consumed=0; r.net.bullAuth=0; r.net.bearAuth=0; r.net.pressure=0; r.net.pdir=0; r.net.fezHi=0; r.net.fezLo=0;
      for(int i=0;i<6;i++){ r.rungDir[i]=0; r.rungPhase[i]=0; r.rungProg[i]=0; r.rungTf[i]=""; }
   }

   double EMAclose(ENUM_TIMEFRAMES tf,int len)
   {
      double c[]; ArraySetAsSeries(c,true);
      int need=len*3;
      if(CopyClose(m_symbol,tf,0,need,c)<len) return(iClose(m_symbol,tf,1));
      double a=2.0/(len+1.0); double e=c[ArraySize(c)-1];
      for(int i=ArraySize(c)-2;i>=1;i--) e=e+a*(c[i]-e);
      return(e);
   }
};
//+------------------------------------------------------------------+
