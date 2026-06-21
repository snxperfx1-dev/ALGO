//+------------------------------------------------------------------+
//|                                              SenseeiEngine.mqh    |
//|  Faithful MQL5 port of the F16 Raptor v57 / Master Senseei core  |
//|  tradeable engine (f_phys physics + f_se multi-timeframe         |
//|  structure engine + fractal stack + node/FU bias + the Senseei   |
//|  meta-intelligence that produces the ATTACK / WAIT verdict).      |
//|                                                                   |
//|  This module is PURE ANALYSIS. It places no orders. The Expert   |
//|  Advisor consumes its SSenseeiResult to make trading decisions.   |
//+------------------------------------------------------------------+
#property copyright "Master Senseei"
#property strict

//==================================================================
// CONFIGURATION (mirrors the Pine inputs that affect the signal)
//==================================================================
struct SEngineConfig
{
   // f_se / f_phys
   int    pivotLen;        // Pivot Length            (Pine: 5)
   int    atrLen;          // ATR Length              (Pine: 14)
   int    effLen;          // Efficiency Lookback     (Pine: 10)
   int    structLen;       // Structure Pivot Length  (Pine: 10)
   double impulseAtrMult;  // Impulse ATR Multiple    (Pine: 1.5)
   double effThresh;       // Efficiency Threshold    (Pine: 0.65)
   double dispThresh;      // Displacement ATR Thresh (Pine: 1.5)
   double convMult;        // Convexity ATR Multiplier(Pine: 0.01)
   double chochBufferATR;  // CHoCH Buffer (ATR)      (Pine: 0.75)
   bool   useStrictStruct; // Use Strict Structure    (Pine: true)
   // node / FU engine
   double wickFrac;        // FU spike min wick/range (Pine: 0.30)
   int    fuLookback;      // FU structure lookback   (Pine: 3)
   // meta-intelligence
   int    minConf;         // Min confidence to ATTACK(Pine: 55)
   // engine window
   int    historyBars;     // bars to iterate per TF for state build
};

void EngineConfigDefaults(SEngineConfig &c)
{
   c.pivotLen       = 5;
   c.atrLen         = 14;
   c.effLen         = 10;
   c.structLen      = 10;
   c.impulseAtrMult = 1.5;
   c.effThresh      = 0.65;
   c.dispThresh     = 1.5;
   c.convMult       = 0.01;
   c.chochBufferATR = 0.75;
   c.useStrictStruct= true;
   c.wickFrac       = 0.30;
   c.fuLookback     = 3;
   c.minConf        = 55;
   c.historyBars    = 1500;
}

//==================================================================
// PER-TIMEFRAME WAVE STATE (output of f_se + f_phys)
//==================================================================
struct SWaveState
{
   bool   valid;
   int    dir;          // wave direction by origin (-1/0/1)
   int    phase;        // 1..14 phase code (0 = none)
   double atr;
   double vel, acc, conv, csm;
   double eff, disp;
   bool   bullImp, bearImp, bullDec, bearDec;
   double curSH, curSL, prSH, prSL;
   int    bos;          // -1/0/1
   int    ch;           // -1/0/1
   double p4h, p4l;
   double inv;          // invalidation (protective extreme = stop reference)
   double tgt;          // measured objective (target reference)
   double ft, fb;       // flip zone top / bottom (entry zone)
   double cycH, cycL;
   double waveProgress; // 0..100
   double convScore, expScore, absScore, mf;
   double closePrice;   // close of the TF at evaluation
};

//==================================================================
// FU / NODE detection result (one timeframe)
//==================================================================
struct SFuState
{
   bool   valid;
   int    dir;     // -1/0/1
   double score;   // authority score
   double tip;
};

//==================================================================
// FINAL SENSEEI META-INTELLIGENCE RESULT
//==================================================================
struct SSenseeiResult
{
   bool   ready;
   // votes
   int    waveDir;       // canonical (chart-TF) wave direction
   int    stackDir;      // fractal stack direction
   double stackPct;      // fractal stack score 0..100
   int    netBias;       // node/FU bias
   int    pdir;          // node pressure direction
   int    master;        // aggregated direction
   // scores
   double alignment;
   double conflict;
   double threat;
   double confidence;
   double oppScore;
   double timeAlign;
   double timeConflict;
   double residual;
   double attractor;
   int    resCode;       // 0 unresolved,1 partial,2 resolved
   // verdict
   string opportunity;   // NONE/DEVELOPING/GOOD/STRONG/EXCEPTIONAL
   string action;        // WAIT/PREPARE/ATTACK/MANAGE / EXIT
   string timing;
   // trade geometry (from canonical wave)
   double entryRef;      // current close of canonical TF
   double stopRef;       // invalidation
   double targetRef;     // measured objective
   double flipTop;
   double flipBot;
   double atr;
   int    phase;         // canonical phase code
};

//==================================================================
// ENGINE CLASS
//==================================================================
class CSenseeiEngine
{
private:
   SEngineConfig     m_cfg;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_ladder[6];   // climbing 6-TF ladder; index 2 = canonical

   //--- helpers --------------------------------------------------
   double Clamp(double v,double lo,double hi){ return(v<lo?lo:(v>hi?hi:v)); }
   int    Sign(double v){ return(v>0?1:(v<0?-1:0)); }

   //--- build the adaptive timeframe ladder (mirrors Pine _wtf1..6)
   void BuildLadder(ENUM_TIMEFRAMES chartTF)
   {
      int csec=PeriodSeconds(chartTF);
      m_ladder[2]=chartTF;                       // _wtf3 = chart (canonical)
      if(csec<3600) // intraday <= ~M59
      {
         m_ladder[0]=PERIOD_M1;
         m_ladder[1]=PERIOD_M3;
         m_ladder[3]=PERIOD_M15;
         m_ladder[4]=PERIOD_H1;
         m_ladder[5]=PERIOD_H4;
      }
      else if(csec<14400) // < H4
      {
         m_ladder[0]=PERIOD_H1;
         m_ladder[1]=PERIOD_H2;
         m_ladder[3]=PERIOD_H8;
         m_ladder[4]=PERIOD_H12;
         m_ladder[5]=PERIOD_D1;
      }
      else if(csec<86400) // < D1
      {
         m_ladder[0]=PERIOD_H4;
         m_ladder[1]=PERIOD_H8;
         m_ladder[3]=PERIOD_D1;
         m_ladder[4]=PERIOD_W1;
         m_ladder[5]=PERIOD_MN1;
      }
      else
      {
         m_ladder[0]=PERIOD_D1;
         m_ladder[1]=PERIOD_W1;
         m_ladder[3]=PERIOD_W1;
         m_ladder[4]=PERIOD_MN1;
         m_ladder[5]=PERIOD_MN1;
      }
   }

public:
   void Init(const string sym, ENUM_TIMEFRAMES chartTF, const SEngineConfig &cfg)
   {
      m_symbol=sym;
      m_cfg=cfg;
      BuildLadder(chartTF);
   }

   ENUM_TIMEFRAMES CanonicalTF(){ return(m_ladder[2]); }
   ENUM_TIMEFRAMES LadderTF(int i){ return(m_ladder[(i<0?0:(i>5?5:i))]); }

   //--------------------------------------------------------------
   // FU / NODE detector (port of f_fuPool) — evaluated on the last
   // CLOSED bar of a timeframe.
   //--------------------------------------------------------------
   SFuState ComputeFU(ENUM_TIMEFRAMES tf)
   {
      SFuState s;
      s.valid=false; s.dir=0; s.score=0.0; s.tip=0.0;
      int need=m_cfg.fuLookback+m_cfg.atrLen+5;
      MqlRates r[];
      ArraySetAsSeries(r,true);
      int got=CopyRates(m_symbol,tf,0,need+2,r);
      if(got<need) return(s);
      // use last CLOSED bar => index 1
      int b=1;
      double rng=MathMax(r[b].high-r[b].low,1e-10);
      // previous structure highs/lows over lookback (offset by 1)
      double pHi=-DBL_MAX, pLo=DBL_MAX;
      for(int k=b+1;k<=b+m_cfg.fuLookback;k++){ if(r[k].high>pHi) pHi=r[k].high; if(r[k].low<pLo) pLo=r[k].low; }
      // local extreme over lookback including current
      double locHi=-DBL_MAX, locLo=DBL_MAX;
      for(int k=b;k<=b+m_cfg.fuLookback-1;k++){ if(r[k].high>locHi) locHi=r[k].high; if(r[k].low<locLo) locLo=r[k].low; }
      double uw=(r[b].high-MathMax(r[b].open,r[b].close))/rng;
      double lw=(MathMin(r[b].open,r[b].close)-r[b].low)/rng;
      bool localTop=(r[b].high>=locHi);
      bool localBot=(r[b].low<=locLo);
      bool bear=(uw>=m_cfg.wickFrac) && ((r[b].high>=pHi && r[b].close<pHi) || (localTop && r[b].close<r[b].open));
      bool bull=(lw>=m_cfg.wickFrac) && ((r[b].low<=pLo  && r[b].close>pLo)  || (localBot && r[b].close>r[b].open));
      double atr=ComputeATR(r,b,m_cfg.atrLen);
      if(bear){ s.dir=-1; s.tip=r[b].high; s.valid=true; }
      else if(bull){ s.dir=1; s.tip=r[b].low; s.valid=true; }
      if(s.valid)
      {
         double bH=MathMax(r[b].open,r[b].close);
         double bL=MathMin(r[b].open,r[b].close);
         double wk=(s.dir==-1)?(s.tip-bH)/MathMax(atr,1e-10):(bL-s.tip)/MathMax(atr,1e-10);
         // confirmation: close beyond body extreme on the same bar approximated false
         double sc=20.0+MathMin(25.0,wk*15.0)+(wk>1.0?15.0:0.0)+(wk>1.5?10.0:0.0);
         s.score=sc;
      }
      return(s);
   }

   //--------------------------------------------------------------
   // Wilder ATR on a series array (index 0 = newest) at bar b
   //--------------------------------------------------------------
   double ComputeATR(const MqlRates &r[], int b, int len)
   {
      int n=ArraySize(r);
      if(b+len+1>=n) len=MathMax(1,n-b-2);
      double sum=0.0;
      for(int k=b;k<b+len;k++)
      {
         double tr=MathMax(r[k].high-r[k].low,
                   MathMax(MathAbs(r[k].high-r[k+1].close),MathAbs(r[k].low-r[k+1].close)));
         sum+=tr;
      }
      return(sum/len);
   }

   //--------------------------------------------------------------
   // FULL WAVE STATE (port of f_phys + f_se), iterated bar-by-bar
   // from oldest->newest over a window, returning the latest state
   // on the last CLOSED bar.
   //--------------------------------------------------------------
   SWaveState ComputeWave(ENUM_TIMEFRAMES tf)
   {
      SWaveState w; ZeroWave(w);
      int bars=m_cfg.historyBars;
      MqlRates r[];
      ArraySetAsSeries(r,false); // oldest first for forward iteration
      int got=CopyRates(m_symbol,tf,0,bars,r);
      if(got<m_cfg.structLen*4 || got<3) return(w);
      int n=got;
      int pv=m_cfg.pivotLen;
      int effL=m_cfg.effLen;
      double effT=m_cfg.effThresh;
      double dispT=m_cfg.dispThresh;
      double convM=m_cfg.convMult;
      double impM=m_cfg.impulseAtrMult;
      double chBuf=m_cfg.chochBufferATR;

      // physics EMA state
      double vel=0.0, velPrev=0.0, acc=0.0, accPrev=0.0, conv=0.0, csm=0.0;
      double atr=0.0; bool atrInit=false;
      double alphaVel=2.0/(3.0+1.0); // ema length 3
      double alphaCsm=2.0/(3.0+1.0);

      // structure state
      double curSH=0,curSL=0,prSH=0,prSL=0; bool hasCurSH=false,hasCurSL=false,hasPrSH=false,hasPrSL=false;
      double lastP=0; int lastD=0; double prevP=0; int prevD=0; bool hasLast=false,hasPrev=false;

      // wave context
      int    dir=0;
      double ft=0,fb=0,p4h=0,p4l=0,inv=0,tgt=0,cycH=0,cycL=0;
      bool   hasFt=false,hasInv=false,hasCycH=false,hasCycL=false,hasTgt=false;

      // inducement / bos chain
      bool bos1=false,bos2=false; double protSw=0,protSw2=0; bool hasProtSw=false,hasProtSw2=false;
      double indOrig=0,indExt=0; bool hasIndOrig=false,hasIndExt=false,indBrk=false;
      int lastDirSeen=0;

      // recursive transition
      int recBrk=0; bool recArm=true;

      // phase state machine
      int pst=0;

      for(int i=1;i<n;i++)
      {
         double c=r[i].close, o=r[i].open, h=r[i].high, l=r[i].low, cp=r[i-1].close;
         // ATR (Wilder)
         double tr=MathMax(h-l,MathMax(MathAbs(h-cp),MathAbs(l-cp)));
         if(!atrInit){ atr=tr; atrInit=true; } else atr=(atr*(m_cfg.atrLen-1)+tr)/m_cfg.atrLen;
         double atrSafe=MathMax(atr,1e-10);

         // physics
         double dv=c-cp;
         velPrev=vel;
         vel=vel+alphaVel*(dv-vel);
         double accNew=vel-velPrev;
         accPrev=acc; acc=accNew;
         double convNew=acc-accPrev;
         conv=convNew;
         csm=csm+alphaCsm*(conv-csm);

         // efficiency / displacement
         double mv=0.0, ps=0.0;
         if(i-effL>=0)
         {
            mv=MathAbs(c-r[i-effL].close);
            for(int k=0;k<effL;k++){ if(i-k-1>=0) ps+=MathAbs(r[i-k].close-r[i-k-1].close); }
         }
         double eff=(ps>0?mv/ps:0.0);
         double disp=(h-l)/atrSafe;
         bool bullImp=(eff>effT && vel>velPrev && acc>0 && c>o && disp>dispT);
         bool bearImp=(eff>effT && vel<velPrev && acc<0 && c<o && disp>dispT);
         bool bullDec=(MathAbs(acc)<MathAbs(accPrev)*0.8 && vel>0);
         bool bearDec=(MathAbs(acc)<MathAbs(accPrev)*0.8 && vel<0);

         // pivots confirmed at i-pv
         double pH=0,pL=0; bool hasPH=false,hasPL=false;
         int mid=i-pv;
         if(mid-pv>=0 && i<n)
         {
            bool isPH=true,isPL=true;
            double hm=r[mid].high, lm=r[mid].low;
            for(int k=mid-pv;k<=mid+pv;k++)
            {
               if(k==mid) continue;
               if(r[k].high>=hm) isPH=false;
               if(r[k].low<=lm)  isPL=false;
            }
            if(isPH){ hasPH=true; pH=hm; }
            if(isPL){ hasPL=true; pL=lm; }
         }

         // structure highs/lows
         if(hasPH)
         {
            prSH=(hasCurSH?curSH:pH); hasPrSH=true;
            curSH=pH; hasCurSH=true;
         }
         if(hasPL)
         {
            prSL=(hasCurSL?curSL:pL); hasPrSL=true;
            curSL=pL; hasCurSL=true;
         }
         // pivot event
         double eP=0; int eD=0;
         if(hasPH){ eP=pH; eD=1; }
         else if(hasPL){ eP=pL; eD=-1; }
         if(eD!=0)
         {
            prevP=lastP; prevD=lastD; hasPrev=hasLast;
            lastP=eP; lastD=eD; hasLast=true;
         }

         bool bullBOS=(hasPrSH && c>prSH);
         bool bearBOS=(hasPrSL && c<prSL);
         bool bullCH =(hasPrSH && c>prSH+atr*chBuf);
         bool bearCH =(hasPrSL && c<prSL-atr*chBuf);

         bool eLong =(hasPH && hasPrev && prevD==-1 && (pH-prevP)>atr*impM);
         bool eShort=(hasPL && hasPrev && prevD==1  && (prevP-pL)>atr*impM);

         bool hasCtx=(dir!=0 && hasFt);
         bool flipDn=(dir==1 && bearCH);
         bool flipUp=(dir==-1 && bullCH);
         bool isRev=((eLong && dir==-1)||(eShort && dir==1)||flipUp||flipDn);
         bool spawn=((eLong||eShort||flipUp||flipDn) && (!hasCtx||isRev));

         if(spawn && hasLast && hasPrev)
         {
            int nd=(eLong?1:(eShort?-1:(flipUp?1:-1)));
            double hi=MathMax(lastP,prevP);
            double lo=MathMin(lastP,prevP);
            dir=nd;
            ft=hi; fb=lo; hasFt=true;
            p4h=hi; p4l=lo;
            cycH=h; cycL=l; hasCycH=true; hasCycL=true;
            inv=(nd==1?lo:hi); hasInv=true;
            double rng=(hasPrSH && hasPrSL)?MathAbs(prSH-prSL):atr*5.0;
            tgt=(nd==1?hi+rng:lo-rng); hasTgt=true;
            // reset recursion / bos chain on spawn-driven dir change handled below
         }
         if(dir==1){ cycH=(hasCycH?MathMax(cycH,h):h); hasCycH=true; }
         if(dir==-1){ cycL=(hasCycL?MathMin(cycL,l):l); hasCycL=true; }

         // inducement / bos chain reset on dir change
         bool reset=(dir!=lastDirSeen);
         lastDirSeen=dir;
         if(reset)
         {
            bos1=false; bos2=false; hasProtSw=false; hasProtSw2=false;
            hasIndOrig=false; hasIndExt=false; indBrk=false;
         }
         if(dir==1 && hasPL){ protSw2=protSw; hasProtSw2=hasProtSw; protSw=pL; hasProtSw=true; }
         if(dir==-1 && hasPH){ protSw2=protSw; hasProtSw2=hasProtSw; protSw=pH; hasProtSw=true; }
         bool oppBOS=((dir==1 && hasProtSw && c<protSw)||(dir==-1 && hasProtSw && c>protSw));
         if(!bos1 && oppBOS){ bos1=true; indOrig=(dir==1?(hasCycH?cycH:h):(hasCycL?cycL:l)); hasIndOrig=true; }
         if(bos1 && !bos2 && oppBOS && hasProtSw2 && ((dir==1)?(c<protSw2):(c>protSw2))) bos2=true;
         if(bos1 && dir==1){ indExt=(hasIndExt?MathMin(indExt,c):c); hasIndExt=true; }
         if(bos1 && dir==-1){ indExt=(hasIndExt?MathMax(indExt,c):c); hasIndExt=true; }
         if(bos2 && hasIndOrig)
         {
            if(dir==1 && c>indOrig) indBrk=true;
            if(dir==-1 && c<indOrig) indBrk=true;
         }

         // scores
         double convScore=MathMin(MathAbs(csm)/MathMax(atr*convM,1e-10)*50.0,100.0);
         double expScore =MathMin(eff/MathMax(effT,1e-10)*50.0+disp/MathMax(dispT,1e-10)*50.0,100.0);
         double absScore =(eff<effT*0.7 && MathAbs(vel)<MathAbs(velPrev)*0.6)?60.0+convScore*0.4:convScore*0.3;
         bool momExpStrong=(eff>effT*0.75 && (dir==1?vel>0:vel<0));
         bool momDecaying=(dir==1?bullDec:bearDec);
         bool momCounter =(dir==1?bearImp:bullImp);
         bool momExhaust =(eff<effT*0.65 && absScore>40.0);
         bool physConvDevel=(convScore>35.0);
         bool physTransfer =(convScore>48.0 || absScore>40.0);
         bool physCapLow   =(absScore>45.0 || eff<effT*0.6);

         // direction by origin
         int wdir=(hasInv?(c>inv?1:(c<inv?-1:dir)):dir);
         bool atFlip=(hasFt && c<=ft && c>=fb);
         bool expanding=(momExpStrong||eLong||eShort||(wdir==1?bullImp:bearImp));
         bool atExtreme=(wdir==1?(h>=(hasCycH?cycH:h)):(wdir==-1?(l<=(hasCycL?cycL:l)):false));
         double extr=(wdir==1?(hasCycH?cycH:c):(hasCycL?cycL:c));
         bool extended=(hasInv && MathAbs(extr-inv)>atr*1.5);
         double compIdx=MathMin(100.0,MathMax(0.0,(1.0-MathMin(disp/MathMax(dispT,1e-10),1.0))*60.0+(1.0-MathMin(eff/MathMax(effT,1e-10),1.0))*40.0));

         // recursive transition
         bool phase2CH=((dir==1 && bearCH)||(dir==-1 && bullCH));
         if(reset || (atExtreme && extended)){ recBrk=0; recArm=true; }
         if((dir==1 && hasPH)||(dir==-1 && hasPL)) recArm=true;
         if((phase2CH||oppBOS) && recArm && !atExtreme){ recBrk++; recArm=false; }
         double fzMid=(hasFt?(ft+fb)/2.0:0.0);
         double retrFrac=(hasFt && MathAbs(extr-fzMid)>1e-10)?MathAbs(extr-c)/MathAbs(extr-fzMid):0.0;
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
         }

         // store state as of the last CLOSED bar (index n-1 is the forming bar)
         if(i==n-2)
         {
            int phase=pst;
            if(phase==5 && dir==-1) phase=6;
            if(phase==13 && dir==-1) phase=14;
            double wp=(pst==0?5.0:pst==1?15.0:pst==2?25.0:pst==3?33.0:pst==4?42.0:pst==5?55.0:pst==7?65.0:pst==8?75.0:pst==9?85.0:pst==10?90.0:pst==11?94.0:pst==12?97.0:100.0);
            double mf=MathMin(MathMax(expScore,MathMax(absScore,convScore))*0.70+(dir!=0?30.0:0.0),100.0);

            w.valid=true;
            w.dir=wdir;
            w.phase=phase;
            w.atr=atr;
            w.vel=vel; w.acc=acc; w.conv=conv; w.csm=csm;
            w.eff=eff; w.disp=disp;
            w.bullImp=bullImp; w.bearImp=bearImp; w.bullDec=bullDec; w.bearDec=bearDec;
            w.curSH=(hasCurSH?curSH:0); w.curSL=(hasCurSL?curSL:0);
            w.prSH=(hasPrSH?prSH:0); w.prSL=(hasPrSL?prSL:0);
            w.bos=(bullBOS?1:(bearBOS?-1:0));
            w.ch=(bullCH?1:(bearCH?-1:0));
            w.p4h=p4h; w.p4l=p4l;
            w.inv=(hasInv?inv:0);
            w.tgt=(hasTgt?tgt:0);
            w.ft=(hasFt?ft:0); w.fb=(hasFt?fb:0);
            w.cycH=(hasCycH?cycH:0); w.cycL=(hasCycL?cycL:0);
            w.waveProgress=wp;
            w.convScore=convScore; w.expScore=expScore; w.absScore=absScore; w.mf=mf;
            w.closePrice=c;
         }
      }
      return(w);
   }

   void ZeroWave(SWaveState &w)
   {
      w.valid=false; w.dir=0; w.phase=0; w.atr=0;
      w.vel=0; w.acc=0; w.conv=0; w.csm=0; w.eff=0; w.disp=0;
      w.bullImp=false; w.bearImp=false; w.bullDec=false; w.bearDec=false;
      w.curSH=0; w.curSL=0; w.prSH=0; w.prSL=0; w.bos=0; w.ch=0;
      w.p4h=0; w.p4l=0; w.inv=0; w.tgt=0; w.ft=0; w.fb=0;
      w.cycH=0; w.cycL=0; w.waveProgress=0;
      w.convScore=0; w.expScore=0; w.absScore=0; w.mf=0; w.closePrice=0;
   }

   //--------------------------------------------------------------
   // RESOLUTION / RESIDUAL / ATTRACTOR (port of EDE/RE/EAE in spirit)
   // derived from the canonical wave phase + progress + geometry.
   //--------------------------------------------------------------
   void ComputeEnergy(const SWaveState &cw, int &resCode, double &residual, double &attractor)
   {
      // dissipation progress proxy from phase
      double dissip=0.0;
      int ph=cw.phase;
      // expansion family
      if(ph==2||ph==3||ph==4) dissip+=25.0;
      if(ph==3||ph==4) dissip+=25.0;
      if(ph==4) dissip+=25.0;
      if(ph>=5) dissip+=25.0;
      if(ph==7) dissip=MathMax(dissip,40.0);
      if(ph==8) dissip=MathMax(dissip,55.0);
      if(ph==9) dissip=MathMax(dissip,65.0);
      if(ph==10) dissip=MathMax(dissip,75.0);
      if(ph==11||ph==12) dissip=MathMax(dissip,85.0);
      if(ph==13||ph==14) dissip=95.0;
      dissip=Clamp(dissip,0.0,100.0);

      double expEnergy=Clamp(cw.expScore*0.5+(cw.bullImp||cw.bearImp?30.0:0.0)+cw.eff*20.0,0.0,100.0);
      double dissipated=Clamp((ph>=2?cw.absScore*0.4:0.0)+(ph>=3?cw.convScore*0.3:0.0),0.0,100.0);
      residual=Clamp(MathMax(0.0,expEnergy-dissipated),0.0,100.0);

      bool objectiveReached=(ph>=5);
      bool fullDissip=(dissip>=75.0);
      bool returned=(ph==13||ph==14);
      if(returned && fullDissip) resCode=2;
      else if(objectiveReached && dissip>=50.0) resCode=1;
      else resCode=0;

      // attractor: pull toward flip zone (unresolved) or origin (partial)
      double distScore=0.0;
      if(cw.ft!=0.0 && cw.fb!=0.0)
      {
         double zmid=(cw.ft+cw.fb)/2.0;
         distScore=MathMax(0.0,30.0-MathAbs(cw.closePrice-zmid)/MathMax(cw.atr,1e-10)*5.0);
      }
      attractor=Clamp(residual*0.4+(resCode==0?30.0:resCode==1?20.0:5.0)+distScore,0.0,100.0);
   }

   //--------------------------------------------------------------
   // MASTER EVALUATION — runs the whole stack and returns verdict.
   //--------------------------------------------------------------
   SSenseeiResult Evaluate()
   {
      SSenseeiResult res; ZeroResult(res);

      // 1) Per-TF wave states for the 6-TF ladder (direction stack)
      SWaveState w[6];
      for(int i=0;i<6;i++) w[i]=ComputeWave(m_ladder[i]);
      SWaveState cw=w[2]; // canonical = chart TF rung
      if(!cw.valid) return(res);

      // fractal stack
      int bull=0,bear=0;
      for(int i=0;i<6;i++)
      {
         if(!w[i].valid) continue;
         if(w[i].dir==1) bull++;
         else if(w[i].dir==-1) bear++;
      }
      int stackDir=(bull>bear?1:(bear>bull?-1:0));
      double stackPct=(double)MathMax(bull,bear)/6.0*100.0;

      // 2) Node / FU bias across higher timeframes (netBias + pressure)
      ENUM_TIMEFRAMES nodeTFs[7];
      nodeTFs[0]=PERIOD_MN1; nodeTFs[1]=PERIOD_W1; nodeTFs[2]=PERIOD_D1;
      nodeTFs[3]=PERIOD_H4;  nodeTFs[4]=PERIOD_H1; nodeTFs[5]=PERIOD_M15; nodeTFs[6]=PERIOD_M5;
      int netBias=0; bool netSet=false;
      double bullAuth=0.0, bearAuth=0.0; int eligN=0;
      for(int i=0;i<7;i++)
      {
         SFuState f=ComputeFU(nodeTFs[i]);
         if(f.valid)
         {
            eligN++;
            double auth=f.score+(7-i)*4.0; // higher TF => more weight
            if(f.dir==1) bullAuth+=auth; else if(f.dir==-1) bearAuth+=auth;
            if(!netSet){ netBias=f.dir; netSet=true; } // first (highest TF) valid sets bias
         }
      }
      if(!netSet)
      {
         // fallback to EMA50 on chart
         double ema=EMAclose(m_ladder[2],50);
         double c=iClose(m_symbol,m_ladder[2],1);
         netBias=(c>ema?1:(c<ema?-1:0));
      }
      double pressure=((bullAuth+bearAuth)>0)?(bullAuth-bearAuth)/(bullAuth+bearAuth)*100.0:0.0;
      int pdir=(pressure>12?1:(pressure<-12?-1:0));

      // 3) Time bias (HTF direction agreement) — use the upper ladder rungs
      int tBull=0,tBear=0;
      for(int i=2;i<6;i++){ if(!w[i].valid) continue; if(w[i].dir==1) tBull++; else if(w[i].dir==-1) tBear++; }
      double timeAlign=((tBull+tBear)>0)?(double)MathMax(tBull,tBear)/(tBull+tBear)*100.0:50.0;
      double timeConflict=100.0-timeAlign;

      // 4) Energy framework
      int resCode; double residual,attractor;
      ComputeEnergy(cw,resCode,residual,attractor);

      // 5) Meta-intelligence (votes)
      int waveDir=cw.dir;
      int vt1=waveDir, vt2=stackDir, vt3=netBias, vt4=pdir;
      int sum=vt1+vt2+vt3+vt4;
      int master=(sum>0?1:(sum<0?-1:0));
      int cast=(vt1!=0?1:0)+(vt2!=0?1:0)+(vt3!=0?1:0)+(vt4!=0?1:0);
      int forV=((vt1==master&&vt1!=0)?1:0)+((vt2==master&&vt2!=0)?1:0)+((vt3==master&&vt3!=0)?1:0)+((vt4==master&&vt4!=0)?1:0);
      double alignment=(cast>0?(double)forV/cast*100.0:50.0);
      double conflict =(cast>0?(double)(cast-forV)/cast*100.0:0.0);
      double timeConflictW=timeConflict;
      double threat=Clamp(conflict*0.40+residual*0.28+timeConflictW*0.12+((pdir!=0&&pdir!=master)?18.0:0.0)+(resCode==1?10.0:0.0),0.0,100.0);
      double confidence=Clamp(alignment*0.40+timeAlign*0.12+stackPct*0.18+attractor*0.15+MathMin(15.0,eligN*1.2)-threat*0.20,0.0,100.0);
      double oppScore=Clamp(alignment*0.40+attractor*0.30+stackPct*0.30-threat*0.35,0.0,100.0);

      string opportunity=(master==0?"NONE":(conflict>60?"DEVELOPING":(oppScore<20?"NONE":(oppScore<40?"DEVELOPING":(oppScore<62?"GOOD":(oppScore<82?"STRONG":"EXCEPTIONAL"))))));
      string action;
      if(master==0) action="WAIT";
      else if(conflict>60) action="WAIT";
      else if(resCode==2) action="MANAGE / EXIT";
      else if((opportunity=="STRONG"||opportunity=="EXCEPTIONAL") && confidence>=m_cfg.minConf && threat<45) action="ATTACK";
      else if(opportunity=="GOOD"||opportunity=="STRONG") action="PREPARE";
      else action="WAIT";

      double wpp=cw.waveProgress;
      string timing=(resCode==2?"RESOLVED":(wpp<15?"VERY EARLY":(wpp<35?"EARLY":(wpp<55?"DEVELOPING":(wpp<80?"MID CYCLE":(wpp<96?"LATE":"TERMINAL"))))));

      // populate
      res.ready=true;
      res.waveDir=waveDir; res.stackDir=stackDir; res.stackPct=stackPct;
      res.netBias=netBias; res.pdir=pdir; res.master=master;
      res.alignment=alignment; res.conflict=conflict; res.threat=threat;
      res.confidence=confidence; res.oppScore=oppScore;
      res.timeAlign=timeAlign; res.timeConflict=timeConflict;
      res.residual=residual; res.attractor=attractor; res.resCode=resCode;
      res.opportunity=opportunity; res.action=action; res.timing=timing;
      res.entryRef=cw.closePrice;
      res.stopRef=cw.inv;
      res.targetRef=cw.tgt;
      res.flipTop=cw.ft; res.flipBot=cw.fb;
      res.atr=cw.atr; res.phase=cw.phase;
      return(res);
   }

   void ZeroResult(SSenseeiResult &r)
   {
      r.ready=false;
      r.waveDir=0; r.stackDir=0; r.stackPct=0; r.netBias=0; r.pdir=0; r.master=0;
      r.alignment=0; r.conflict=0; r.threat=0; r.confidence=0; r.oppScore=0;
      r.timeAlign=0; r.timeConflict=0; r.residual=0; r.attractor=0; r.resCode=0;
      r.opportunity="NONE"; r.action="WAIT"; r.timing="";
      r.entryRef=0; r.stopRef=0; r.targetRef=0; r.flipTop=0; r.flipBot=0; r.atr=0; r.phase=0;
   }

   //--- small helpers --------------------------------------------
   double EMAclose(ENUM_TIMEFRAMES tf,int len)
   {
      double c[];
      ArraySetAsSeries(c,true);
      int need=len*3;
      if(CopyClose(m_symbol,tf,0,need,c)<len) return(iClose(m_symbol,tf,1));
      double a=2.0/(len+1.0);
      double e=c[ArraySize(c)-1];
      for(int i=ArraySize(c)-2;i>=1;i--) e=e+a*(c[i]-e);
      return(e);
   }
};
//+------------------------------------------------------------------+
