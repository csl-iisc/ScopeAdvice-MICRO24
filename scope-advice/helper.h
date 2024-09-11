#include "common.h"
#include "opcode_sm70.h"
#include <sstream>

/* Used to keep track of 
   blockDim: Number of threads within a threadblock
   gridDim: Number of threads within a grid, i.e., all threadblocks */
typedef struct {
    int warpsInGrid;
    int warpsPerBlock;
    int blockDim;
    long gridDim;
} dimension_t;

uint32_t isRed(Instr *inst) {
    return (strstr(inst->getOpcode(), OP_RED) != NULL);
}

uint32_t isLoad(Instr *inst) {
    return inst->isLoad();
}

uint32_t isStore(Instr *inst) {
    return inst->isStore();
}

uint32_t getLoadStoreMask(Instr *inst) {
    uint32_t mask = 0;
    if (isRed(inst)) {
        /* Treat RED equivalent to store operation (CUDA operation equivalent) */
        mask = MASK_STORE;
    } else {
        /* Other operations as provided by NVBit */
        mask |= isLoad(inst) ? MASK_LOAD : 0;
        mask |= isStore(inst) ? MASK_STORE : 0;
    }
    return mask;
}

/* All atomic instructions are STRONG!
   Use this function to check if inst is of Atomic type. */
uint32_t isStrong(Instr *inst) {
    return (strstr(inst->getOpcode(), OP_STRONG) != NULL) || (inst->isLoad() && inst->isStore());
}

/* MEMBAR type, can have different scope. Use this along with
   getScope to find the fence with appropriate scope. */
uint32_t isFence(Instr *inst) {
    return strstr(inst->getOpcode(), OP_FENCE) != NULL;
}

uint32_t isBarrier(Instr *inst) {
    return strstr(inst->getOpcode(), OP_BARRIER) != NULL;
}

uint32_t isWarpBar(Instr *inst) {
    return strstr(inst->getSass(), OP_WAR_BAR) != NULL;
}

scope_t getScope(Instr *inst) {
    if(strstr(inst->getOpcode(), OP_SYS_SCOPE) != NULL)
        return SCOPE_SYS;
    if(strstr(inst->getOpcode(), OP_GPU_SCOPE) != NULL)
        return SCOPE_GPU;
    if(strstr(inst->getOpcode(), OP_CTA_SCOPE) != NULL || strstr(inst->getOpcode(), OP_SM_SCOPE) != NULL)
        return SCOPE_CTA;
    return SCOPE_NONE;
}

std::string print_mem_access(mem_access_t *ma) {
    std::stringstream ss;
    ss << getBits(ma->info, HPOS_ID, HSZ_ID) << ",LD:" << getBit(ma->info, HPOS_LD) << ",ST:" << getBit(ma->info,HPOS_ST) << "," << getBits(ma->info, HPOS_EP, HSZ_EP);
    return ss.str();
}

void print_fence(fence_t *st) {
    std::cout << st->id << "," << st->fence_id << "," << std::hex << st->mask << std::endl;
}

/* Structures and includes used in main program */
#include <atomic>
#include <thread>
#include <time.h>
#include <unordered_map>
#include <unordered_set>
/* channel size for maintaining cpu-gpu communication */
#define CHANNEL_SIZE (2l << 20)
#define JOB_NONE -1
#define JOB_BEGIN 1

/* Parallel processing of incoming data by multiple processes and buffers */
#if DO_PARALLEL
#define NUM_BUFFERS 768
#define NUM_THREADS 12
#else
#define NUM_BUFFERS 1
#define NUM_THREADS 1
#endif

/* Job structure for distributing among workers */
typedef struct _job_info_t {
    uint32_t job_amount;
    char *buffer;
} job_info_t;
/* creating list of buffers to maintain information */
volatile job_info_t jobs[NUM_BUFFERS];
char dummy_buffer[CHANNEL_SIZE];

/* Spinlocks for job processing */
pthread_mutex_t job_lock, free_lock, async_lock;
/* two queue for maintaining free and occupied buffers */
std::vector<int> job_queue, free_queue;

/* create thread argument struct for thr_func() */
typedef struct _thread_data_t {
  int tid;
} thread_data_t;
/* Global information of threads */
pthread_t thr[NUM_THREADS];
thread_data_t thr_data[NUM_THREADS];

/* synchronization among worker threads and async_task for jobs */
pthread_barrier_t barrier;
std::atomic<int> last_job(0);

/* receiving thread and its control variables */
pthread_t recv_thread, async_task;
volatile bool recv_thread_started = false;
volatile bool recv_thread_receiving = false;
static __managed__ ChannelDev channel_dev;
static ChannelHost channel_host;
cudaStream_t stream;

uint32_t static_counter = 0;

/* global control variables for this tool */
uint32_t instr_begin_interval = 0;
uint32_t instr_end_interval = UINT32_MAX;
int verbose = 0;
int timeout = 0;
int check_its = 0;
int debug_out = 1;
std::string kernel_id = "";
/* skip flag used to avoid re-entry on the nvbit_callback when issuing flush_channel kernel call */
bool skip_flag = false;

/* when a single kernel is invoked multiple times trace only 1 instance */
int kernel_instances = 0;
int instance = 1;

/* Things for scope-recommender trace gen */
int epoch = 0, message_passes = 0;

/* Cleaner task data and related defines */
#define UNIQ_THRESHOLD 20000
std::unordered_set<uint64_t> cleaner_queue;

uint64_t host_metadata_len;
/* Keeping track of memory accesses and fences by threads, information maintained per address */
std::atomic<uint64_t> *access_map;

/* Keeping track of fence-related information */
std::unordered_map<int, uint64_t> id_to_fence_map;
std::unordered_map<uint64_t, std::string> fence_to_lineinfo_map;

/* For measurement purposes, keeping track of number of transferred packets */
std::atomic<uint64_t> m_packets;

/* Kernel dimension information */
dimension_t kernel_dimension;

/* common structure for passing arguments to instrumented function */
__managed__ dev_args device_arguments;

/* Exponential backoff for accessing locks --- should improve performance? */
#define HOST_BASE_DELAY 16
#define HOST_MAX_DELAY 32768
#define DO_BACKOFF 1
void backoff(unsigned &us) {
    if (DO_BACKOFF && us > 0) {
        // unsigned entropy = rand() % us;
        std::this_thread::sleep_for(std::chrono::microseconds(us));
        us = us << 1;
        us = max(us, HOST_MAX_DELAY);
    }
}

uint64_t getIdx(int fence_id, uint64_t tid) {
    /* local thread id */
    uint64_t ltid = tid % kernel_dimension.blockDim;
    /* local warp id */
    uint64_t wid = ltid / WARP_SIZE;
    /* block ID */
    uint64_t bid = tid / kernel_dimension.blockDim;
    /* global warp ID */
    uint64_t idx = wid + bid * kernel_dimension.warpsPerBlock;
    /* roundUp does a ceiling, indexing is 0-based, do a - 1 */
    return fence_id * kernel_dimension.warpsInGrid + idx;
}

int getPrevSync(int fence_id, uint64_t tid) {
    fence_id--;
    uint64_t idx;
    uint32_t bit = 1 << ((tid % kernel_dimension.blockDim) % WARP_SIZE);
    while (fence_id >= 0) {
        idx = getIdx(fence_id, tid);
        if (bit & device_arguments.fence_meta[idx])
            break;
        else
            fence_id--;
    }
    return fence_id;
}

int getNextSync(int fence_id, uint64_t tid) {
    /* epoch is the last epoch */
    uint64_t idx;
    uint32_t bit = 1 << ((tid % kernel_dimension.blockDim) % WARP_SIZE);
    while (fence_id < epoch) {
        idx = getIdx(fence_id, tid);
        if (bit & device_arguments.fence_meta[idx])
            break;
        else
            fence_id++;
    }
    // printf("[GNS] %lu for %d got %d with bit %x\n", tid, lf, fence_id, bit);
    return fence_id;
}

#include "trackers.h"
/* a common function to process trace entries, present for each
   address accessed on the GPU */
void process_trace(uint64_t trace) {
    int a_epoch = getBits(trace, HPOS_EP, HSZ_EP);
    /* atomics are treated specially */
    if (getBit(trace, HPOS_LD) && getBit(trace, HPOS_ST)) {
        fence_map[a_epoch]->operations.fetch_or(ATOMIC);
        return;
    }

    int tid = getBits(trace, HPOS_ID, HSZ_ID);
    /* applying load rules */
    if (getBit(trace, HPOS_LD)) {
        uint64_t scp = getBits(trace, HPOS_SCP, HSZ_SCP);
        if (!(scp == SCOPE_GPU) && !(scp == SCOPE_SYS)) {
            a_epoch = getPrevSync(a_epoch, tid);
            fence_map[a_epoch]->not_oversynchronized.exchange(1);
        } else {
            fence_map[a_epoch]->operations.fetch_or(VOLATILE_LD);
        }
    }
    /* applying store rules */
    if (getBit(trace, HPOS_ST)) {
        a_epoch = getNextSync(a_epoch, tid);
        fence_map[a_epoch]->operations.fetch_or(VOLATILE_ST);
        fence_map[a_epoch]->not_oversynchronized.exchange(1);
    }
}

void printCounters() {
    printf("========== COUNTERS =============\n");
    printf("Static Instrumented Instructions: %d\n", static_counter);
    printf("Memory packets: %lu\n", m_packets.load());
    printf("GPU-CPU message passes: %d\n", message_passes);
}
