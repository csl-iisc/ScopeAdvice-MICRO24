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
#include <stdio.h>

// Comment to remove printfs
//#define DEBUG

#include "utils/utils.h"

/* for channel */
#include "utils/channel.hpp"

/* contains definition of the mem_access_t structure */
#include "common.h"

__device__ __inline__
void dev_sleep(int &delay) {
    if(delay) {
        csleep(delay);
        /* Architecture dependent instruction. Available from volta onwards. */
        //__nanosleep(delay);
        delay *= 2;
        delay = min(delay, MAX_DELAY);
    }
}


__device__ __inline__
void set_device_metadata(uint64_t &metadata, uint32_t op_mask, uint64_t bid) {
    uint64_t old_id = getBits(metadata, POS_ID, SZ_ID);
    uint64_t first = getBit(metadata, POS_F);
    /* This is the important information */
    if (bid != old_id && first != 0) {
        setBit(metadata, POS_MB);
    }
    setBit(metadata, POS_F);

    uint64_t old_st = getBit(metadata, POS_ST);
    setBit(metadata, POS_ST, old_st | (op_mask & MASK_STORE));

    setBits(metadata, POS_ID, SZ_ID, bid);
    // This metadata also houses 'count' of traces present in stream_meta.
    // The field is updated in send_trace method.
}


__device__ __inline__
uint64_t set_host_metadata(long id, int epoch, uint32_t op_mask) {
    uint64_t info = 0;
    setBit(info, HPOS_LD, MASK_LOAD & op_mask);
    setBit(info, HPOS_ST, MASK_STORE & op_mask);
    setBits(info, HPOS_SCP, HSZ_SCP, (op_mask & SCOPE_CTA) | (op_mask & SCOPE_GPU) | (op_mask & SCOPE_SYS));
    setBits(info, HPOS_ID, HSZ_ID, id);
    setBits(info, HPOS_EP, HSZ_EP, epoch);
    return info;
}


__device__ __inline__
bool skip_trace(uint32_t op_mask) {
    bool skip = false;
    if (DO_FILTER) {
        // First two bits in mask is the scope of the operation, get it!
        int scp = (op_mask & 3);
        /* A Load and with scope greater than equal to device is enough
           for a volatile load and atomics with device_scope or larger */
        if ((MASK_LOAD & op_mask) && (scp >= SCOPE_GPU))
            skip = true;
    }
    return skip;
}

__device__ __inline__
bool skip_instrumentation(dev_args *dev, uint64_t global_tid, uint64_t global_bid, int instr) {
    bool skip = true;
    long dimension = dev->threads;
    /* Location of pointer, is of char pointer */;
    char *instr_meta = dev->sampling_meta;

    char local = instr_meta[dimension * instr + global_tid];
    /* Once every PER_THREAD_PER_INSTR instructions */
    if (local == 0  || local == dev->random_meta[global_bid])
        skip = false;
    local += 1;
    if (local > PER_THREAD_PER_INSTR)
        local = SAMP_BASE;
    instr_meta[dimension * instr + global_tid] = local;
    return skip;
}

/*
 * This method performs a number of operations and runs optimizations
 * 1. Update the in-GPU metadata maintained per address (md_up)
 * 2. Filters trace based on the type of operation (skip_trace)
 * 3. Maintain some content on the GPU {a.k.a. streaming access-type content}
 */
__device__ __inline__
bool send_trace(dev_args *dev, uint64_t offset, uint64_t tid, int epoch, uint32_t op_mask, uint64_t &md_up, uint64_t bid) {
    /* first set up content inside GPU aggregate metadata */
    set_device_metadata(md_up, op_mask, bid);
    /* return value */
    bool should_trace = false;
    // Do not maintain trace in stream_meta (version 1) if it does not help in detection
    if (!skip_trace(op_mask)) {
        uint64_t count = getBits(md_up, POS_CNT, SZ_CNT);
        if (DO_STREAM && count < NUM_STREAM_TRACES) {
            // prepare the trace that needs recording
            uint64_t trace = set_host_metadata(tid, epoch, op_mask);
            if (count != 0) {
                // some traces exist, write to a new position
                offset = offset + count * dev->length;
            }
            uint32_t *stream_meta = dev->stream_meta;
            stream_meta[offset] = trace;
            /* update count in aggregate metadata */
            count += 1;
            setBits(md_up, POS_CNT, SZ_CNT, count);
        } else {
            // no place in stream_meta, send it to host!
            should_trace = true;
        }
    }
    return should_trace;
}

extern "C" __device__ __noinline__
void instrument_fence(int pred, uint32_t fenceId, uint64_t args) {
#if DO_ANALYZE
    if (!pred)
        return;

    unsigned mask = __activemask();
    unsigned selectedThread = ((mask - 1) & mask) ^ mask;
    uint64_t tid = serializeId(threadIdx.x, threadIdx.y, threadIdx.z, blockDim.x, blockDim.y, blockDim.z);

    /* Only 1 thread within active ones sends information */
    if (selectedThread & (1 << (tid % WARP_SIZE))) {
        dev_args *dev = (dev_args *)args;

        uint64_t wid = tid / WARP_SIZE;
        uint64_t warps_per_blk = roundUp(blockDim.x * blockDim.y * blockDim.z, WARP_SIZE);
        uint64_t bid = serializeId(blockIdx.x, blockIdx.y, blockIdx.z, gridDim.x, gridDim.y, gridDim.z);
        /* global warpid */
        wid = wid + bid * warps_per_blk;

        /* set fence metadata */
        uint64_t idx = dev->warps_per_grid * fenceId + wid;
        atomicOr(&dev->fence_meta[idx], mask);
    }

    __syncwarp(mask);
#endif
}

/* Tracing memory accesses by each thread
   1. predicate - guard predicate for the instruction
   2. addr - virtual address accessed by the instruciton
   3. op_mask - load/store/scope of operation
   4. epoch - for further analysis
 */
extern "C" __device__ __noinline__
void instrument_mem(int pred, uint64_t addr, uint32_t op_mask, volatile int epoch, uint32_t size, uint32_t instr, uint64_t args) {
#if DO_ANALYZE
    if (!pred)
        return;

    // Check if address belongs to global memory using PTX
    int is_global_mem;
    asm (".reg .pred p;\
        isspacep.global  p, %1;\
        selp.u32 %0,1,0,p;\
        ":"=r"(is_global_mem): "l"(addr));

    if(is_global_mem) {
        unsigned mask = __activemask();
        dev_args *dev = (dev_args *)args;

        // threadId -- global
        uint64_t tid = serializeId(threadIdx.x, threadIdx.y, threadIdx.z, blockDim.x, blockDim.y, blockDim.z);
        uint64_t bid = serializeId(blockIdx.x, blockIdx.y, blockIdx.z, gridDim.x, gridDim.y, gridDim.z);
        tid = tid + bid * dev->threads_per_block;

        /* Skip: Execution sampling */
        if (DO_SAMPLING && skip_instrumentation(dev, tid, bid, instr)) {
            /* non-sampled instance, do nothing */
        } else {
            uint32_t *md_array = dev->memory_meta;
            uint64_t len = dev->length;
            int offset = 0, delay = BASE_DELAY;

            do {
                uint64_t md_offset = (addr + offset) / GRAN;
                md_offset = md_offset % len;
                unsigned int* md_addr = &(md_array)[md_offset];
                uint32_t md = atomicAdd(md_addr, 0);
                /* Need to lock before updating metadata, custom locking method */
                if (md == D_LOCKED) {
                    dev_sleep(delay);
                    continue;
                }

                if (atomicCAS(md_addr, md, D_LOCKED) == md) {
                    __threadfence();
                    uint64_t md_up = md;
                    /* should trace be tracked? */
                    bool trace = send_trace(dev, md_offset, tid, epoch, op_mask, md_up, bid);
                    md = md_up;
                    __threadfence();
                    /* update GPU metadata */
                    atomicExch(md_addr, md);
                    /* send the trace after releasing the lock */
                    if (trace) {
                        mem_access_t ma;
                        ma.addr = addr + offset;
                        ma.info = set_host_metadata(tid, epoch, op_mask);

                        channel_t c;
                        c.type = TYPE_MEM;
                        c.ma = ma;
                        ChannelDev *cdev = dev->channel_dev;
                        cdev->push (&c, sizeof(channel_t));
                    }
                    /* recorded meta, go to next size-offset */
                    offset += GRAN;
                    /* reset backoff delay for the next offset */
                    delay = BASE_DELAY;
                } else {
                    dev_sleep(delay);
                }
            } while(offset < size);
        }

        /* sync */
        __syncwarp(mask);
    }
#endif
}
