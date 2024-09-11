// This can be ".SM" in later archs!
#define OP_CTA_SCOPE ".CTA"
#define OP_SM_SCOPE ".SM"
#define OP_GPU_SCOPE ".GPU"
#define OP_SYS_SCOPE ".SYS"

#define OP_STRONG ".STRONG"

#define OP_FENCE "MEMBAR"
#define OP_BARRIER "BAR.SYNC"
#define OP_RED "RED."

// Hack. Regular WARPSYNC causes problems
#define OP_WAR_BAR "BRA.CONV"
