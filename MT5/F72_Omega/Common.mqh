//+------------------------------------------------------------------+
//|                                                       Common.mqh  |
//|                        F72 OMEGA — Shared Foundation              |
//|                                                                   |
//|  The bottom of the dependency hierarchy. Holds ONLY enums,        |
//|  data structures, constants and pure math helpers. No module      |
//|  logic, no I/O, no circular includes.                             |
//|                                                                   |
//|  Dependency order (never invert):                                 |
//|   Universe -> Curve -> Compression -> Convexity -> Force ->       |
//|   Ownership -> Recursion -> Chain -> Narrative -> LifeScore ->    |
//|   StoryStability -> StoryConfidence -> Risk -> Capital -> Exec    |
//|                                                                   |
//|  PRINCIPLE: nothing is a signal. Everything is STATE. ENTER/HOLD/ |
//|  ADD/REDUCE/REVERSE/EXIT are consequences of the trinity:         |
//|     LifeScore  ·  StoryStability  ·  StoryConfidence              |
//+------------------------------------------------------------------+
#ifndef __F72_COMMON_MQH__
#define __F72_COMMON_MQH__
#property strict

#define F72_VERSION        "OMEGA.1.0"
#define F72_ROOT           "F72_Omega"        // under MQL5/Files/
#define F72_NEUTRAL        50.0               // neutral score baseline

//==================================================================
// ENUMS
//==================================================================
enum ENUM_ENGINE_MODE
{
   MODE_OBSERVER    = 0,   // no orders, scores + logging only
   MODE_COPILOT     = 1,   // engine suggests, human approves (queued)
   MODE_AUTONOMOUS  = 2,   // engine controls fully
   MODE_PAPER       = 3,   // simulated fills, no live orders
   MODE_SHADOW      = 4    // compute + log as if trading, compare to reality
};

enum ENUM_DECISION
{
   DEC_NONE     = 0,
   DEC_ENTER    = 1,
   DEC_HOLD     = 2,
   DEC_ADD      = 3,   // pyramiding / progression
   DEC_REDUCE   = 4,   // scale out
   DEC_REVERSE  = 5,   // ownership transfer
   DEC_EXIT     = 6
};

enum ENUM_POSITION_ROLE
{
   ROLE_NONE        = 0,
   ROLE_ORIGIN      = 1,   // the campaign's founding position
   ROLE_ENTRY       = 2,   // flip-zone entries
   ROLE_PROGRESSION = 3,   // continuation pyramids
   ROLE_TERMINAL    = 4    // terminal / counter / hedge-transfer position
};

enum ENUM_CAMPAIGN_PHASE
{
   CP_BIRTH       = 0,
   CP_HEALTHY     = 1,
   CP_EXPANSION   = 2,
   CP_ABANDON     = 3,   // extreme abandoned, support migrated
   CP_ENTRY_CYCLE = 4,
   CP_CONTINUATION= 5,
   CP_TERMINAL    = 6,   // terminal induction
   CP_TRANSITION  = 7,   // supply/demand transfer
   CP_DEATH       = 8
};

enum ENUM_DD_STATE
{
   DD_NORMAL      = 0,
   DD_CAUTION     = 1,   // soft throttle engaged
   DD_DAILY_LOCK  = 2,   // daily loss limit hit
   DD_WEEKLY_LOCK = 3,   // weekly loss limit hit
   DD_HALT        = 4    // hard circuit breaker
};

// Explainability reason codes — every decision carries one.
enum ENUM_REASON
{
   R_NONE                 = 0,
   R_STORY_ALIVE_ALIGNED  = 100,  // enter: living story + alignment
   R_CONTINUATION_HEALTHY = 101,  // add: chain healthy, force strong
   R_FLIPZONE_ENTRY       = 102,
   R_PROGRESSION_PYRAMID  = 103,
   R_STORY_WEAKENING      = 200,  // reduce: narrative diverging
   R_FORCE_DECAY          = 201,
   R_COMPRESSION_SQUEEZE  = 202,
   R_OWNERSHIP_CONTESTED  = 203,
   R_TERMINAL_INDUCTION   = 300,  // exit/reverse: terminal detected
   R_OWNERSHIP_TRANSFER   = 301,  // reverse: transfer confirmed
   R_CHAIN_DETERIORATING  = 302,
   R_STORY_DEAD           = 303,
   R_RISK_DAILY_LOCK      = 400,  // blocked: risk circuit breakers
   R_RISK_WEEKLY_LOCK     = 401,
   R_RISK_HARD_HALT       = 402,
   R_RISK_EXPOSURE_CAP    = 403,
   R_SPREAD_GUARD         = 404,
   R_CONFIDENCE_LOW       = 405,  // engine self-doubt throttle
   R_MODE_OBSERVER        = 406,  // not trading by mode
   R_AWAITING_APPROVAL    = 407   // co-pilot queue
};

string ReasonText(ENUM_REASON r)
{
   switch(r)
   {
      case R_STORY_ALIVE_ALIGNED:  return("Living story + multi-TF alignment");
      case R_CONTINUATION_HEALTHY: return("Continuation: chain healthy, force strong");
      case R_FLIPZONE_ENTRY:       return("Flip-zone entry");
      case R_PROGRESSION_PYRAMID:  return("Progression pyramid (continuation)");
      case R_STORY_WEAKENING:      return("Story weakening / narrative divergence");
      case R_FORCE_DECAY:          return("Force decay");
      case R_COMPRESSION_SQUEEZE:  return("Compression squeeze");
      case R_OWNERSHIP_CONTESTED:  return("Ownership contested");
      case R_TERMINAL_INDUCTION:   return("Terminal induction detected");
      case R_OWNERSHIP_TRANSFER:   return("Ownership transfer confirmed");
      case R_CHAIN_DETERIORATING:  return("Chain health deteriorating");
      case R_STORY_DEAD:           return("Story dead");
      case R_RISK_DAILY_LOCK:      return("Blocked: daily loss lock");
      case R_RISK_WEEKLY_LOCK:     return("Blocked: weekly loss lock");
      case R_RISK_HARD_HALT:       return("Blocked: hard circuit breaker");
      case R_RISK_EXPOSURE_CAP:    return("Blocked: exposure cap");
      case R_SPREAD_GUARD:         return("Blocked: spread guard");
      case R_CONFIDENCE_LOW:       return("Throttled: engine confidence low");
      case R_MODE_OBSERVER:        return("Observer mode: no orders");
      case R_AWAITING_APPROVAL:    return("Co-pilot: awaiting approval");
      default:                     return("—");
   }
}

string ModeText(ENUM_ENGINE_MODE m)
{
   switch(m)
   {
      case MODE_OBSERVER:   return("OBSERVER");
      case MODE_COPILOT:    return("CO-PILOT");
      case MODE_AUTONOMOUS: return("AUTONOMOUS");
      case MODE_PAPER:      return("PAPER");
      case MODE_SHADOW:     return("SHADOW");
   }
   return("?");
}

string DecisionText(ENUM_DECISION d)
{
   switch(d)
   {
      case DEC_ENTER:   return("ENTER");
      case DEC_HOLD:    return("HOLD");
      case DEC_ADD:     return("ADD");
      case DEC_REDUCE:  return("REDUCE");
      case DEC_REVERSE: return("REVERSE");
      case DEC_EXIT:    return("EXIT");
   }
   return("NONE");
}

string RoleText(ENUM_POSITION_ROLE r)
{
   switch(r)
   {
      case ROLE_ORIGIN:      return("ORIGIN");
      case ROLE_ENTRY:       return("ENTRY");
      case ROLE_PROGRESSION: return("PROGRESSION");
      case ROLE_TERMINAL:    return("TERMINAL");
   }
   return("NONE");
}

string PhaseText(ENUM_CAMPAIGN_PHASE p)
{
   switch(p)
   {
      case CP_BIRTH:        return("BIRTH");
      case CP_HEALTHY:      return("HEALTHY");
      case CP_EXPANSION:    return("EXPANSION");
      case CP_ABANDON:      return("ABANDONMENT");
      case CP_ENTRY_CYCLE:  return("ENTRY-CYCLE");
      case CP_CONTINUATION: return("CONTINUATION");
      case CP_TERMINAL:     return("TERMINAL");
      case CP_TRANSITION:   return("TRANSITION");
      case CP_DEATH:        return("DEATH");
   }
   return("?");
}

//==================================================================
// THE ENGINE STATE — the organism's continuously-updated nervous
// system. Phase 1 ships this as the canonical container with
// neutral defaults; later phases populate each field from its
// owning module. NOTHING here is a signal — it is all STATE.
//==================================================================
struct SEngineState
{
   datetime time;
   int      masterDir;        // -1 / 0 / +1 emergent directional bias

   //--- THE TRINITY (everything emerges into these) ---------------
   double   lifeScore;        // is the story alive?            0..100
   double   storyStability;   // is the story stable/coherent?  0..100
   double   storyConfidence;  // how much do I trust myself?    0..100

   //--- lower-layer state (feeds the trinity) ---------------------
   double   forceScore;       // expansion / displacement force 0..100
   double   chainHealth;      // lineage vitality               0..100
   double   ownershipStability;//curve ownership certainty      0..100
   double   compression;      // can price breathe?             0..100 (high=tight)
   double   convexity;        // curvature maturity             0..100
   double   alignment;        // multi-TF agreement             0..100
   double   confidence;       // market-read confidence         0..100
   double   regimeScore;      // regime stability               0..100
   double   abandonment;      // extreme-abandonment score      0..100
   double   continuation;     // continuation (can I hold?)     0..100

   //--- Layer 12 probability cloud (sums ~100) --------------------
   double   pContinuation;
   double   pTerminal;
   double   pTransfer;

   //--- Layer 14 self-observation ---------------------------------
   double   recentHitRate;    // rolling win rate               0..100
   double   contradiction;    // internal disagreement          0..100
   bool     overfitFlag;

   bool     ready;            // engine has enough data to act
};

void StateInit(SEngineState &s)
{
   s.time=0; s.masterDir=0;
   s.lifeScore=F72_NEUTRAL; s.storyStability=F72_NEUTRAL; s.storyConfidence=F72_NEUTRAL;
   s.forceScore=F72_NEUTRAL; s.chainHealth=F72_NEUTRAL; s.ownershipStability=F72_NEUTRAL;
   s.compression=F72_NEUTRAL; s.convexity=F72_NEUTRAL; s.alignment=F72_NEUTRAL;
   s.confidence=F72_NEUTRAL; s.regimeScore=F72_NEUTRAL; s.abandonment=F72_NEUTRAL;
   s.continuation=F72_NEUTRAL;
   s.pContinuation=34.0; s.pTerminal=33.0; s.pTransfer=33.0;
   s.recentHitRate=50.0; s.contradiction=0.0; s.overfitFlag=false;
   s.ready=false;
}

//==================================================================
// A DECISION — the consequence the engine emits. Always carries a
// reason (explainability is non-negotiable).
//==================================================================
struct SDecision
{
   ENUM_DECISION      type;
   int                dir;        // -1 / +1
   ENUM_POSITION_ROLE role;
   double             riskPct;    // sized fraction of equity
   double             stop;       // price
   double             target;     // price
   ENUM_REASON        reason;
   string             note;       // free-text explanation
};

void DecisionInit(SDecision &d)
{
   d.type=DEC_NONE; d.dir=0; d.role=ROLE_NONE;
   d.riskPct=0.0; d.stop=0.0; d.target=0.0; d.reason=R_NONE; d.note="";
}

//==================================================================
// CAMPAIGN SCHEMA (Layer 2 — immortal memory). Persisted as JSON.
//==================================================================
struct SCampaign
{
   long     id;
   string   symbol;
   datetime birth;
   datetime death;
   long     parentId;
   int      childCount;
   string   childIds;          // comma-separated for portable JSON
   int      dir;
   ENUM_CAMPAIGN_PHASE phase;

   // profiles (summarised numerically for statistical memory)
   double   compressionProfile;
   double   convexityProfile;
   double   forceProfile;
   int      recursionDepth;

   int      transitionType;    // 0 none / 1 continuation / 2 transfer / 3 death
   int      failureSwingType;  // 0 none / 1 bull-FU / 2 bear-FU
   long     durationSecs;
   string   session;           // ASIA / LONDON / NY / OVERLAP / OFF
   string   newsEnv;           // QUIET / MEDIUM / HIGH
   int      fuInteractions;
   bool     terminalInduction;

   // outcome (filled on death)
   double   pnl;
   double   maxFavorable;
   double   maxAdverse;
   double   peakLifeScore;
   double   peakForce;
   bool     closed;
};

void CampaignInit(SCampaign &c)
{
   c.id=0; c.symbol=""; c.birth=0; c.death=0; c.parentId=-1; c.childCount=0; c.childIds="";
   c.dir=0; c.phase=CP_BIRTH;
   c.compressionProfile=0; c.convexityProfile=0; c.forceProfile=0; c.recursionDepth=0;
   c.transitionType=0; c.failureSwingType=0; c.durationSecs=0; c.session=""; c.newsEnv="QUIET";
   c.fuInteractions=0; c.terminalInduction=false;
   c.pnl=0; c.maxFavorable=0; c.maxAdverse=0; c.peakLifeScore=0; c.peakForce=0; c.closed=false;
}

//==================================================================
// PURE MATH HELPERS
//==================================================================
double F72Clamp(double v,double lo,double hi){ return(v<lo?lo:(v>hi?hi:v)); }
double F72Lerp(double a,double b,double t){ return(a+(b-a)*F72Clamp(t,0.0,1.0)); }
int    F72Sign(double v){ return(v>0?1:(v<0?-1:0)); }
double F72EmaStep(double prev,double x,int len){ double a=2.0/(len+1.0); return(prev+a*(x-prev)); }
double F72Map(double v,double inLo,double inHi,double outLo,double outHi)
{
   if(MathAbs(inHi-inLo)<1e-12) return(outLo);
   double t=(v-inLo)/(inHi-inLo);
   return(F72Clamp(outLo+(outHi-outLo)*t,MathMin(outLo,outHi),MathMax(outLo,outHi)));
}

//--- session classification from server time ----------------------
string F72Session(datetime t)
{
   MqlDateTime d; TimeToStruct(t,d);
   int h=d.hour;
   // approximate server-hour bands (broker GMT+2/3 typical); engine
   // does NOT block on these — context only.
   bool london = (h>=9 && h<17);
   bool ny     = (h>=14 && h<23);
   bool asia   = (h>=0 && h<9);
   if(london && ny) return("OVERLAP");
   if(london)       return("LONDON");
   if(ny)           return("NY");
   if(asia)         return("ASIA");
   return("OFF");
}

#endif // __F72_COMMON_MQH__
