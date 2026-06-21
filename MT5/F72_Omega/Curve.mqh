//+------------------------------------------------------------------+
//|                                                        Curve.mqh  |
//|             F72 OMEGA — The Curve Engine (Layer 0 / 4)            |
//|                                                                   |
//|  Faithful MQL5 port of the f_phys physics + f_se fixed-TF         |
//|  structure engine (pivots, BOS/CHoCH, impulse-leg spawn, flip     |
//|  zone, invalidation, target, 14-state phase machine, recursion).  |
//|  Produces one SCurve per timeframe and assembles the fractal      |
//|  stack (M1·M3·M5·M15·H1·H4·D1) + the canonical chart curve.       |
//+------------------------------------------------------------------+
#ifndef __F72_CURVE_MQH__
#define __F72_CURVE_MQH__
#property strict
#include "Common.mqh"
#include "CurveState.mqh"

struct SCurveCfg
{
   int    pivotLen, atrLen, effLen;
   double effThresh, dispThresh, convMult, impulseAtrMult, chochBufferATR;
   int    historyBars;
};

void CurveCfgDefaults(SCurveCfg &c)
{
   c.pivotLen=5; c.atrLen=14; c.effLen=10;
   c.effThresh=0.65; c.dispThresh=1.5; c.convMult=0.01;
   c.impulseAtrMult=1.5; c.chochBufferATR=0.75; c.historyBars=1500;
}

class CCurveEngine
{
private:
   string    m_symbol;
   SCurveCfg m_cfg;

public:
   void Init(const string sym,const SCurveCfg &cfg){ m_symbol=sym; m_cfg=cfg; }

   //--------------------------------------------------------------
   // Compute a single timeframe's curve on the last CLOSED bar.
   //--------------------------------------------------------------
   SCurve Compute(ENUM_TIMEFRAMES tf)
   {
      SCurve w; CurveInit(w); w.tf=tf;
      MqlRates r[]; ArraySetAsSeries(r,false);
      int got=CopyRates(m_symbol,tf,0,m_cfg.historyBars,r);
      if(got<m_cfg.pivotLen*4 || got<16) return(w);
      RunSE(r,got,got-2,w);
      w.tf=tf;
      return(w);
   }

   //--------------------------------------------------------------
   // The fractal stack — the organism across timeframes.
   //--------------------------------------------------------------
   SCurveStack ComputeStack(ENUM_TIMEFRAMES chartTF)
   {
      SCurveStack s; StackInit(s);
      ENUM_TIMEFRAMES tfs[F72_STACK_TFS];
      tfs[0]=PERIOD_M1; tfs[1]=PERIOD_M3; tfs[2]=PERIOD_M5; tfs[3]=PERIOD_M15;
      tfs[4]=PERIOD_H1; tfs[5]=PERIOD_H4; tfs[6]=PERIOD_D1;

      int bull=0,bear=0; s.n=0;
      for(int i=0;i<F72_STACK_TFS;i++)
      {
         s.tf[i]=Compute(tfs[i]);
         if(s.tf[i].valid)
         {
            s.n++;
            if(s.tf[i].dir==1) bull++; else if(s.tf[i].dir==-1) bear++;
         }
         if(tfs[i]==chartTF) s.canonical=i;
      }
      s.stackDir=(bull>bear?1:(bear>bull?-1:0));
      s.stackPct=(s.n>0)?(double)MathMax(bull,bear)/F72_STACK_TFS*100.0:50.0;

      // upward support: do M1/M3/M5 agree with H1/H4 (the higher intent)?
      int hi=(s.tf[4].valid?s.tf[4].dir:0);
      if(hi==0) hi=(s.tf[5].valid?s.tf[5].dir:0);
      int support=0,tot=0;
      for(int i=0;i<4;i++) if(s.tf[i].valid && hi!=0){ tot++; if(s.tf[i].dir==hi) support++; }
      s.upwardSupport=(tot>0?(double)support/tot*100.0:50.0);
      return(s);
   }

   //--------------------------------------------------------------
   // f_se + f_phys lifecycle (oldest-first array), capture at bar.
   //--------------------------------------------------------------
   void RunSE(const MqlRates &r[], int n, int captureBar, SCurve &w)
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
         double accN=vel-velP; accP=acc; acc=accN; conv=acc-accP; csm=csm+aC*(conv-csm);

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
            w.ft=(hFt?ft:0); w.fb=(hFt?fb:0); w.inv=(hInv?inv:0); w.tgt=(hTgt?tgt:0);
            w.p4h=p4h; w.p4l=p4l; w.cycH=(hCycH?cycH:0); w.cycL=(hCycL?cycL:0);
            w.atExtreme=atExtreme; w.extended=extended; w.atFlip=atFlip;
            w.retrFrac=retrFrac; w.recBrk=recBrk; w.waveProgress=wp;
            w.convScore=convScore; w.expScore=expScore; w.absScore=absScore;
            w.compIdx=compIdx; w.modelFit=mf; w.closePrice=c;
         }
      }
   }
};

#endif // __F72_CURVE_MQH__
