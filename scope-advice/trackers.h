#define ZERO          0
#define VOLATILE_LD   1
#define VOLATILE_ST   2
#define ATOMIC        4
#define WEAK_LD       8
#define WEAK_ST       16

struct _fence_info_t {
    int id;
    bool is_redundant;
    std::atomic<int> not_oversynchronized, operations;

    _fence_info_t(int _id, bool _is_redundant) {
        id = _id;
        is_redundant =_is_redundant;
        not_oversynchronized.exchange(0);
        operations.exchange(0);
    }

    /* Note: use this function only when not_oversynchronized is 0 */
    std::string get_comment(int next) {
        std::string output;
        int cur = operations.load();
        if (DO_FILTER) {
            /* This flag loses information that helps getting the exact Variant.
               Use it for faster analysis without exact variant info.
               Problem is differentiating between Variant 1 and 3.  */
            output = is_redundant ? "redundant" : "over-synchronized";
        } else {
            if (is_redundant)
                output = "Variant 2";
            else if (!cur)
                /* When current window is empty, it means, no operations were performed in this window.
                   We deem this as Variant 3 */
                output = "Variant 3";
            else {
                /* Current window has some operations (LDV or ATM), check next window information */
                if (!next)
                    // Next window is empty, likely due to intra-block operation.
                    // We consider this as Variant 3
                    output = "Variant 3";
                else
                    // Case remaining is Variant 1
                    output = "Variant 1";
            }
        }
        return output;
    }

    void print() {
        std::cout << "FenceAt: " << id << ", ";
        std::cout << "IsRedundant: " << is_redundant << "\n";
    }
};

typedef struct _fence_info_t fence_info;
std::unordered_map<int, fence_info*> fence_map;

/* Keeping track of memory allocations by the kernel */
struct range_t {
    uint64_t base, bound;

    range_t(uint64_t _addr, uint64_t _bound) {
        base = _addr;
        bound = _bound;
    }
};
typedef struct range_t allocation;
std::vector<allocation> allocation_records;

#include <chrono>
struct duration_t {
    std::chrono::time_point<std::chrono::high_resolution_clock> begin, terminate;
    double milli;

    duration_t() {
        milli = 0;
    }

    void start() {
        begin = std::chrono::high_resolution_clock::now();
    }

    void end() {
        terminate = std::chrono::high_resolution_clock::now();
        milli += (double)std::chrono::duration_cast<std::chrono::microseconds>(terminate - begin).count() / 1000;
    }

    double getMillis() {
        return milli;
    }
};
typedef struct duration_t duration;
duration instrumentation, setup, kernel, message, detection;

double getChannelCommunicationInMillis() {
    return (double)std::chrono::duration_cast<std::chrono::microseconds>(detection.begin - message.begin).count() / 1000;
}

double getE2EInMillis() {
    if (DO_ANALYZE) {
        double part = (double)std::chrono::duration_cast<std::chrono::microseconds>(detection.terminate - kernel.begin).count() / 1000;
        return (part + instrumentation.getMillis() + setup.getMillis());
    } else {
        // Time accesses to measure NVBit overheads
        return (instrumentation.getMillis() + kernel.getMillis());
    }
}

/* Memory overhead trackers. Currently only double values.
   TODO: Consider binding them to range_t? */
double app_mem = 0, meta_mem = 0, fence_mem = 0, samp_mem = 0;

void printTrackers() {
    printf("========== TIMING ==========\n");
    printf("Instrumentation time: %lf ms\n", instrumentation.getMillis());
    printf("Setup time: %lf ms\n", setup.getMillis());
    printf("Kernel time: %lf ms\n", kernel.getMillis());
    printf("Channel process (communication channel): %lf ms\n", getChannelCommunicationInMillis());
    printf("Detection time: %lf ms\n", detection.getMillis());
    printf("E2E time: %lf ms\n", getE2EInMillis());

    printf("========== MEMORY ==========\n");
    printf("App: %lf MB\n", app_mem / (1024 * 1024));
    printf("Metadata (Stream + Agg): %lf MB\n", meta_mem / (1024 * 1024));
    printf("Metadata (Fen): %lf MB\n", fence_mem / (1024 * 1024));
    printf("Metadata (Sampling): %lf MB\n", samp_mem / (1024 * 1024));
    printf("Overhead: %lf x\n", (meta_mem + samp_mem + fence_mem) / app_mem);
}
