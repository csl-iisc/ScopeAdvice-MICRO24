/* Copyright (c) 2019, NVIDIA CORPORATION. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of NVIDIA CORPORATION nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#include <stdint.h>
#include <string>

/* Added for dev_metadata struct */
#include "utils/utils.h"
#include "utils/channel.hpp"

#ifndef COMMON_H
#define COMMON_H

#define WARP_SIZE 32

#define BYTE  uint8_t
#define HWORD uint16_t
#define WORD  uint32_t
#define DWORD uint64_t
#define ULL   unsigned long long int

#define LOCKED (uint64_t)-2
#define D_LOCKED (uint32_t)-2
#define GRAN 4
#define BASE_DELAY 100
#define MAX_DELAY 6400
#define SAMP_BASE 1
#define PER_THREAD_PER_INSTR 15
#define NUM_STREAM_TRACES 2

// Needed to avoid typecasting issues
#define ONE ((uint64_t)1)

#ifdef DEBUG
#define debug_printf(...) { unsigned masker = __activemask(); \
        unsigned sThread = ((masker - 1) & masker) ^ masker; \
        if((1 << (threadIdx.x % WARP_SIZE)) & sThread) printf(__VA_ARGS__);}
#else
#define debug_printf(...) 
#endif

// optimization switches
#define DO_FILTER 1
#define DO_PARALLEL 1
#define DO_SAMPLING 1
#define DO_STREAM 1
// evaluation flag to measure NVBit overhead
#define DO_ANALYZE 1

/* Below enums are used for the creation of 'info' member in mem_access_t struct.
 * It maintains information necessary for host processing, in a bitwise manner.
 * h_position_t: position of corresponding metadata in 'info'
 * h_sizes_t: size of corresponding metadata in h_position_t (default 1)
 */
typedef enum : uint32_t {
    HPOS_LD = 0,
    HPOS_ST = 1,
    HPOS_SCP = 2,
    HPOS_ID = 4,
    HPOS_EP = 27,
} h_position_t;


typedef enum : uint32_t {
    HSZ_SCP = 2,
    HSZ_ID = 23,
    HSZ_EP = 5,
} h_sizes_t;

/* @brief: Information collected in the instrumentation function and passed
 * on the channel from the GPU to the CPU

 * @args
 * addr: Global address where the operation took place
 * info: Metadata maintained for minimizing transmission size
 */
typedef struct {
    uint64_t addr;
    uint64_t info;
} mem_access_t;


/* @brief: Information collected in the instrumentation function for sync mappings.
           Can be fence, syncthreads
 * @args
 * id: id corresponding to which thread
 * sync_id: fence_id corresponding to static code instrumentation
 * epoch: essentially keeping track of fences seen so far
 */
typedef struct {
    uint64_t id;
    uint32_t mask;
    uint32_t fence_id;
} fence_t;

typedef enum : uint8_t {
    TYPE_INV = 0,
    TYPE_MEM = 1,
    TYPE_SYN = 2
} type_t;

/* @brief: Information received in the channel, it can be of barrier_t or mem_access_t

 * The channel can pass different types of information. Encode them as struct and keep
 * them as part of the union struct. This minimizes the size of the struct that the channel
 * needs.
 */
typedef struct {
    type_t type;
    union {
        fence_t st;
        mem_access_t ma;
    };
} channel_t;

// WARN: These definitions are used in the post-processing script as well. Change wisely
typedef enum : uint32_t { 
    SCOPE_NONE = 0,
    SCOPE_CTA  = 1,
    SCOPE_GPU  = 2,
    SCOPE_SYS  = 3
} scope_t;

typedef enum : uint32_t {
    MASK_LOAD   = 4,
    MASK_STORE  = 8,
    MASK_ATOMIC = 12, // (MASK_LOAD | MASK_STORE)
    MASK_STRONG = 16,
    MASK_RED = 32,
} op_mask_t;

/* Below enums are meant for bitwise metadata maintained on the GPU, and later transferred
 * to the CPU. 
 * position_t - Position in metadata for corresponding information
 * sizes_t - Size of the corresponding metada from position_t
 */
typedef enum : uint32_t {
    POS_F = 0,
    POS_ST = 1,
    POS_MB = 2, // 3 is reserved for GLOBAL / SHARED region
    POS_ID = 4,
    POS_CNT = 24,
} position_t;

typedef enum : uint32_t {
    SZ_ID = 20,
    SZ_CNT = 2,
} sizes_t;

/* Maintain a single struct that needs to be sent to instrumented function,
 * rather than adding each parameter to the function, add it to struct
 */
typedef struct _device_arguments {
    uint64_t threads;
    uint32_t threads_per_block;
    /* communication channel between GPU-CPU */
    ChannelDev *channel_dev;
    /* in-GPU metadata for tracing access per GRAN memory */
    uint32_t *memory_meta;
    uint64_t length;
    /* metadata for execution sampling */
    char *sampling_meta;
    char *random_meta;
    /* in-GPU fence metadata maintained */
    uint32_t *fence_meta;
    uint32_t warps_per_grid;
    /* in-GPU metadata for maintaining trace */
    uint32_t *stream_meta;
} dev_args;

static __inline__ __device__ const char *scopeToStr(scope_t scope) {
    switch(scope) {
        case SCOPE_CTA: return "CTA"; break;
        case SCOPE_GPU: return "GPU"; break;
        case SCOPE_SYS: return "SYS"; break;
        default:
        case SCOPE_NONE: return "NONE"; break;
    }
}

#define hasMask(val, mask) (((val) & (mask)) == (mask))
#define roundUp(divisor, dividend) CEILING(divisor, dividend)

static __inline__ __device__ int serializeId(int x, int y, int z, int xSize, int ySize, int zSize) {
    return x + (y + z * ySize) * xSize; 
}

static __inline__ __device__ __host__ uint64_t getBit(uint64_t loc, uint64_t offset) {
    return (((ONE << offset) & loc) ? ONE : 0);
}

static __inline__ __device__ __host__ void setBit(uint64_t &loc, uint64_t offset, uint64_t val = ONE) {
    if(val) // Set bit
        loc = ((ONE << offset) | loc);
    else    // Unset bit
        loc = ((~(ONE << offset)) & loc);
}

static __inline__ __device__ __host__ uint64_t getBits(uint64_t loc, uint64_t start, uint64_t depth) {
    return (loc >> start) & ((ONE << depth) - ONE);
}

static __inline__ __device__ __host__ void setBits(uint64_t &loc, uint64_t start, uint64_t depth, uint64_t val) {
    // Unset bits from start to start + depth
    if(start + depth == 64) // Special case to avoid overflow
        loc &= ~((0xffffffffffffffff) ^ ((ONE << start) - ONE));
    else
        loc &= ~(((ONE << (start + depth)) - ONE) ^ ((ONE << start) - ONE));
    loc |= ((val & ((ONE << depth) - ONE)) << start);
}

static __inline__ __device__ __host__ void print_md(uint64_t md, uint64_t addr) {
    printf("Addr(%lx) Multi-Block (%lu), ST(%lu), CurId(%lu)\n", addr, getBit(md, POS_MB),
                       getBit(md, POS_ST), getBits(md, POS_ID, SZ_ID));
}

#endif /*COMMON_H*/
