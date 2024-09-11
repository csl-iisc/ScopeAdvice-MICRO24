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

/* every tool needs to include this once */
#include "nvbit_tool.h"

/* nvbit interface file */
#include "nvbit.h"

#include <algorithm>
#include <assert.h>
#include <fstream>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <tuple>
#include <unistd.h>

//#define DEBUG_OUT

#include "helper.h"

void handle_memory_access(mem_access_t *ma, int tid) {
    uint64_t addr = ma->addr, md_offset;
    md_offset = (addr / GRAN) % host_metadata_len;
    bool done = false;
    m_packets.fetch_add(1);
    unsigned delay = HOST_BASE_DELAY;
    while (!done) {
        uint64_t expected(access_map[md_offset].load());
        uint64_t desired(LOCKED);
        if (expected == desired) {
            /* someone holds the lock --- backoff */
            backoff(delay);
            continue;
        }

        if (access_map[md_offset].compare_exchange_strong(expected, desired)) {
            std::vector<uint64_t> *s;
            /* Zero initialized, if not, meaning some address present! */
            if (expected == 0) {
                s = new std::vector<uint64_t>;
                // (*s).reserve(UNIQ_THRESHOLD);
            } else {
                s = (std::vector<uint64_t>*)expected;
            }

            (*s).push_back(ma->info);
            expected = (uint64_t)s;
            if ((*s).size() > UNIQ_THRESHOLD) {
                pthread_mutex_lock(&async_lock);
                /* Insert offset */
                cleaner_queue.insert(md_offset);
                pthread_mutex_unlock(&async_lock);
            }
            /* Atomically write to it! */
            access_map[md_offset].exchange(expected);
            done = true;
        } else {
            /* someone got the lock --- backoff */
            backoff(delay);
        }
    }
}

/* All conditions have to be met for this to work:
   1. If multi_block
   2. If there are stores
   3. If there are weak operations, or cta scoped operations
If yes to all questions, all relevant epochs in access_map have to be utilized.
    for store epochs, next one is useful, aka, release operation
    for load epochs, previous one is useful, aka, acquire operation. */
void process_access_info(int tid, allocation record) {
    uint64_t per_thread, sidx, eidx;
    /* Divide addresses in record into NUM_THREADS portions */
    per_thread = (record.bound - record.base) / NUM_THREADS;

    /* start and end address */
    sidx = tid * per_thread + record.base;
    if (tid == NUM_THREADS - 1)
        eidx = record.bound;
    else
        eidx = (tid + 1) * per_thread + record.base;

    /* traverse across allocated addresses */
    for (uint64_t addr = sidx; addr < eidx; addr += GRAN) {
        uint64_t i = (addr / GRAN) % host_metadata_len;

        uint64_t md_offset = (addr / GRAN) % device_arguments.length;
        uint64_t md = device_arguments.memory_meta[md_offset];
        // print_md(md, addr);
        if (getBit(md, POS_MB) && getBit(md, POS_ST)) {
            if (DO_STREAM) {
                /* get content from stream_meta */
                uint64_t count = getBits(md, POS_CNT, SZ_CNT);
                for (uint64_t j = 0; j < count && j < NUM_STREAM_TRACES; j++) {
                    uint64_t _offset = md_offset + j * device_arguments.length;
                    uint64_t trace = device_arguments.stream_meta[_offset];
                    process_trace(trace);
                }
            }
            /* Traverse the set! */
            uint64_t possible_vector = access_map[i].load();
            if (possible_vector != 0) {
                std::vector<uint64_t> *s = (std::vector<uint64_t>*)possible_vector;
                for (auto trace : *s) {
                    process_trace(trace);
                }
            }
        }
    }
}

/* iterate over all allocations */
void iterate_allocations(int tid) {
    if (DO_ANALYZE) {
        for (auto each: allocation_records) {
            process_access_info(tid, each);
        }
    }
}

void worker(int id) {

    int jobs_handled = 0;
    while (1) {

        int i = JOB_NONE;
        pthread_mutex_lock(&job_lock);
        if (job_queue.size() != 0) {
            i = job_queue.back();
            job_queue.pop_back();
        }
        pthread_mutex_unlock(&job_lock);

        if (i != JOB_NONE) {
            channel_t *chan = (channel_t*)jobs[i].buffer;
            /* Each worker-thread figures out their own content */
            uint32_t num_entries = jobs[i].job_amount / sizeof(channel_t);
            uint32_t start_entry = 0;
            // printf("%d: Got job of size: %u (%uB)\n", id, num_entries, jobs[i].job_amount);

            while (start_entry < num_entries) {
                channel_t *c = &chan[start_entry];
                // printf("%d: processing %u @%p\n", id, start_entry, c);
                if (c->type == TYPE_MEM) {
                    handle_memory_access(&c->ma, id);
                }
                start_entry += 1;
            }

            /* Push back to free queue */
            pthread_mutex_lock(&free_lock);
            free_queue.push_back(i);
            pthread_mutex_unlock(&free_lock);

            // printf("%d: %d done, waiting .... status\n", id, i);
            jobs_handled += 1;
        } else if (last_job.load() == JOB_NONE) {
            /* no job in queue and last job seen by distributor, break */
            // printf("%d: all jobs done ... exiting\n", id);
            break;
        }
    }

    // printf("%d: finished %d jobs ... moving to detection. Wait till dedup reaches barrier\n", id, jobs_handled);
    pthread_barrier_wait(&barrier);
    // avoid races on 'detection' var ... make only 1 thread update it
    if (id == 0)
        detection.start();
    /* Parallelize detection logic */
    iterate_allocations(id);
    // jobs being equally allocated among workers, they are expected to finish together
    if (id == 0)
        detection.end();
}

void set_meta(int id, allocation record) {
    /* only 1 thread does this! Avoid launching too many tasks! */
    if (id != 0)
        return;

    uint64_t sidx, eidx, size, length = device_arguments.length;
    uint32_t *base = device_arguments.memory_meta, *end;
    sidx = (record.base / GRAN) % length;
    eidx = (record.bound / GRAN) % length;
    if (sidx > eidx) {
        /* first half */
        size = (uint64_t)(base + eidx) - (uint64_t)base;
        cudaMemsetAsync(device_arguments.memory_meta, 0, size, stream);
        end = base + length;
        /* second half */
        size = (uint64_t)end - (uint64_t)(base + sidx);
        cudaMemsetAsync(device_arguments.memory_meta + sidx, 0, size, stream);
    } else {
        size = record.bound - record.base;
        cudaMemsetAsync(device_arguments.memory_meta + sidx, 0, size, stream);
    }
}

void *async_zero(void *arg) {
    thread_data_t *data = (thread_data_t *)arg;
    int tid = data->tid;
    uint64_t per_thread, s_addr, e_addr, sidx, eidx, size;

    /* Wait till the instrumenation completes. Syncing with main thread (which does instrumenttion) */
    pthread_barrier_wait(&barrier);

    for (auto record: allocation_records) {
        per_thread = (record.bound - record.base) / NUM_THREADS;

        /* start and end address */
        s_addr = tid * per_thread + record.base;
        if (tid == NUM_THREADS - 1)
            e_addr = record.bound;
        else
            e_addr = (tid + 1) * per_thread + record.base;

        sidx = (s_addr / GRAN) % host_metadata_len;
        eidx = (e_addr / GRAN) % host_metadata_len;
        if (sidx > eidx) {
            std::atomic<uint64_t> *end = access_map + host_metadata_len;
            /* first half */
            size = (uint64_t)(access_map + eidx) - (uint64_t)access_map;
            memset((uint64_t*) access_map, 0, size);
            /* second half */
            size = (uint64_t)end - (uint64_t)(access_map + sidx);
            memset((uint64_t*) access_map + sidx, 0, size);
        } else {
            memset((uint64_t*) access_map + sidx, 0, e_addr - s_addr);
        }
        set_meta(tid, record);
    }
    /* Wait till setup is complete. Syncing with min thread (which does device metadata setup) */
    pthread_barrier_wait(&barrier);

    worker(tid);
    pthread_exit(NULL);
}

void *deduplicate(void *arg) {

    unsigned long long cleaner_jobs = 0, cleaned = 0;
    while (1) {
        if (last_job.load() == JOB_NONE)
            break;

        if (cleaner_queue.size() == 0)
            continue;

        pthread_mutex_lock(&async_lock);
        cleaner_jobs++;
        std::unordered_set<uint64_t> l_job = cleaner_queue;
        cleaner_queue.clear();
        pthread_mutex_unlock(&async_lock);
        // printf("cleaner: got job of size: %lu\n", l_job.size());
        for (uint64_t s: l_job) {
            /* Set has offsets into access_map, no need to recalculate */
            bool done = false;
            unsigned delay = HOST_BASE_DELAY;
            while (!done) {
                uint64_t expected(access_map[s].load());
                uint64_t desired(LOCKED);
                if (expected == desired) {
                    /* someone holds the lock --- backoff */
                    backoff(delay);
                    continue;
                }

                if (access_map[s].compare_exchange_strong(expected, desired)) {
                    std::vector<uint64_t> *se = (std::vector<uint64_t>*)expected;

                    std::sort((*se).begin(), (*se).end());
                    (*se).erase(std::unique((*se).begin(), (*se).end()), (*se).end());

                    expected = (uint64_t)se;
                    cleaned++;
                    /* Atomically write to it! */
                    access_map[s].exchange(expected);
                    done = true;
                } else {
                    /* someone got the lock --- backoff */
                    backoff(delay);
                }
            }
        }
    }
    /* Participate in the barrier. Syncing with worker threads (waiting after processing all packets) */
    pthread_barrier_wait(&barrier);
    // printf("[Cleaner] Clean jobs: %llu, Cleaned offsets: %llu .... exiting\n", cleaner_jobs, cleaned);
    pthread_exit(NULL);
}

void prefetch_device_metadata() {
    /* use stream to prefetch fence content */
    cudaMemPrefetchAsync(device_arguments.fence_meta, sizeof(uint32_t) * kernel_dimension.warpsInGrid * epoch, cudaCpuDeviceId, stream);
    uint64_t base, bound, sidx, eidx, size;
    /* prefetch memory metadata */
    for (auto each: allocation_records) {
        base = each.base;
        bound = each.bound;

        sidx = (base / GRAN) % device_arguments.length;
        eidx = (bound / GRAN) % device_arguments.length;
        /* if eidx < sidx, requires roundabout */
        if (eidx < sidx) {
            uint32_t* end = device_arguments.memory_meta + host_metadata_len;
            size = (uint64_t)end - (uint64_t)(device_arguments.memory_meta + sidx);
            cudaMemPrefetchAsync(device_arguments.memory_meta + sidx, size, cudaCpuDeviceId, stream);
            size = (uint64_t)(device_arguments.memory_meta + eidx) - (uint64_t)device_arguments.memory_meta;
            cudaMemPrefetchAsync(device_arguments.memory_meta, size, cudaCpuDeviceId, stream);
        } else {
            cudaMemPrefetchAsync(device_arguments.memory_meta + sidx, bound - base, cudaCpuDeviceId, stream);
        }
    }
}

void *distributor(void *) {
    while(recv_thread_started) {

        /* Spin-lock to check size */
        pthread_mutex_lock(&free_lock);
        /* It's ok to do this while holding lock as the procedure is short */
        if (free_queue.size() != 0) {
            int i = free_queue.back();
            uint32_t num_recv_bytes = 0;
            /* Boss thread --- waits for generated data to process */
            if (recv_thread_receiving && (num_recv_bytes = channel_host.recv(jobs[i].buffer, CHANNEL_SIZE)) > 0) {
                message_passes += 1;
                /* Don't have to reset this! */
                if (message_passes == 1)
                    message.start();

                /* Write job information */
                jobs[i].job_amount = num_recv_bytes;
                // printf("Boss: set up job %d\n", i);

                pthread_mutex_lock(&job_lock);
                /* Remove from free queue */
                free_queue.pop_back();
                /* Push to job queue */
                job_queue.push_back(i);
                pthread_mutex_unlock(&job_lock);

                /* Check if it was last message */
                char *recv = jobs[i].buffer;
                recv = recv + num_recv_bytes - sizeof(channel_t);
                channel_t *possible_last_message = (channel_t*)recv;
                if (possible_last_message->type == TYPE_INV) {
                    /* distributor can now return, nothing more to do */
                    recv_thread_receiving = false;
                    last_job.exchange(JOB_NONE);
                    /* No break as lock needs to be released */
                    message.end();
                }
            } else if (!recv_thread_receiving) {
                /* Re executing instrumented kernel can generate messages. If not processed
                   can block the kernel. Process them by putting content in a dummy buffer. */
                num_recv_bytes = channel_host.recv(&dummy_buffer, CHANNEL_SIZE);
            }
        }
        /* Release lock */
        pthread_mutex_unlock(&free_lock);
    }
    // prefetch_device_metadata();
    pthread_exit(NULL);
}


__global__ void flush_channel() {
    /* push memory access with negative cta id to communicate the kernel is
     * completed */
    channel_t c;
    c.type = TYPE_INV;
    device_arguments.channel_dev->push(&c, sizeof(channel_t));

    /* flush channel */
    device_arguments.channel_dev->flush();
}


/* Set used to avoid re-instrumenting the same functions multiple times */
std::unordered_set<CUfunction> already_instrumented;
void instrument_function_if_needed(CUcontext ctx, CUfunction func) {
    /* Get related functions of the kernel (device function that can be
     * called by the kernel) */
    std::vector<CUfunction> related_functions = nvbit_get_related_functions(ctx, func);

    /* add kernel itself to the related function vector */
    related_functions.push_back(func);

    /* iterate on function */
    for (auto f : related_functions) {
        /* "recording" function was instrumented, if set insertion failed
         * we have already encountered this function */
        if (!already_instrumented.insert(f).second) {
            continue;
        }

        uint64_t base_addr = nvbit_get_func_addr(f);
        const std::vector<Instr *> &instrs = nvbit_get_instrs(ctx, f);
        if (verbose) {
            printf("Inspecting function %s at address 0x%lx\n", nvbit_get_func_name(ctx, f), nvbit_get_func_addr(f));
        }

        uint32_t cnt = 0;
        /* iterate on all the static instructions in the function */
        bool memory_between = false;
        /* Inserting one for KERNEL_BEGIN */
        fence_map[-1] = new fence_info(-1, !memory_between);
        for (auto instr : instrs) {
            uint64_t offset = instr->getOffset();
            if (cnt < instr_begin_interval || cnt >= instr_end_interval ||
                (instr->getMemorySpace() == InstrType::MemorySpace::NONE && !isBarrier(instr) &&
                !isFence(instr) && !(isWarpBar(instr) && check_its))) {
                cnt++;
                continue;
            }
            
            cnt++;
            if (verbose) {
                instr->printDecoded();
            }

           if (isBarrier(instr)) {
                if (!memory_between) {
                    /* Make previous fence a candidate for redundancy! Case where fence comes before barrier */
                    if (epoch != 0)
                        fence_map[epoch - 1]->is_redundant = true;
                }
                memory_between = false;
                continue;
            }

            /* Need only device scope for now, not useful to keep track of block scope */
            if(isFence(instr) && getScope(instr) == SCOPE_GPU) {
                /* Add some instrumentation information! */
                nvbit_insert_call(instr, "instrument_fence", IPOINT_BEFORE);
                /* predicate value */
                nvbit_add_call_arg_guard_pred_val(instr);
                /* epoch value */
                volatile int l_epoch = epoch;
                nvbit_add_call_arg_const_val32(instr, (uint32_t)l_epoch);
                /* pointer to location with device_arguments struct */
                nvbit_add_call_arg_const_val64(instr, (uint64_t)&device_arguments);

                /* Maintain info for making suggestions later */
                uint64_t addr =  base_addr + offset;
                if (fence_to_lineinfo_map.find(addr) == fence_to_lineinfo_map.end()) {
                    id_to_fence_map[epoch] = addr;

                    char* file_name;
                    char* dir_name;
                    uint32_t line;
                    bool avail = nvbit_get_line_info(ctx, f, instr->getOffset(), &file_name, &dir_name, &line);
                    std::string output;
                    if(avail)
                        output = std::string(file_name) + " - Kernel " + std::string(nvbit_get_func_name(ctx, f)) + ": Line " + std::to_string(line) + "    " + instr->getSass();
                    else
                        output = std::string(instr->getSass()) + " - Kernel " + std::string(nvbit_get_func_name(ctx, f)) + ": Sass offset " + std::to_string(instr->getOffset());
                    fence_to_lineinfo_map[addr] = output;

                    /* Information for type of OS if memory_between -> not_redundant */
                    fence_map[epoch] = new fence_info(epoch, !memory_between);
                    memory_between = false;
                    /* This epoch will be used during memory instrumentation */
                    epoch += 1;
                }
                continue;
            }

            int mref_idx = 0;
            /* iterate on the operands */
            for (int i = 0; i < instr->getNumOperands(); i++) {
                /* get the operand "i" */
                const InstrType::operand_t *op = instr->getOperand(i);

                if (op->type == InstrType::OperandType::MREF && 
                    (instr->getMemorySpace() == InstrType::MemorySpace::GENERIC
                    || instr->getMemorySpace() == InstrType::MemorySpace::GLOBAL)) {
                    /* insert call to the instrumentation function with its
                     * arguments */
                    nvbit_insert_call(instr, "instrument_mem", IPOINT_BEFORE);
                    /* predicate value */
                    nvbit_add_call_arg_guard_pred_val(instr);
                    /* memory reference 64 bit address */
                    nvbit_add_call_arg_mref_addr64(instr, mref_idx);
                    /* information about memory operation */
                    nvbit_add_call_arg_const_val32(instr, getScope(instr) | getLoadStoreMask(instr));
                    /* A precaution to copy to local */
                    volatile int l_epoch = epoch;
                    nvbit_add_call_arg_const_val32(instr, l_epoch);
                    /* add pointer to channel_dev*/
                    nvbit_add_call_arg_const_val32(instr, (uint32_t)instr->getSize());
                    /* add instruction value */
                    int l_counter = static_counter;
                    nvbit_add_call_arg_const_val32(instr, (uint32_t)l_counter);
                    static_counter += 1;
                    /* pointer to location with device_arguments struct */
                    nvbit_add_call_arg_const_val64(instr, (uint64_t)&device_arguments);
                    mref_idx++;
                    memory_between = true;
                } else if (op->type == InstrType::OperandType::MREF &&
                    instr->getMemorySpace() == InstrType::MemorySpace::SHARED) {
                    memory_between = true;
                }
            }
        }
        /* Inserting final one, KERNEL_END */
        fence_map[epoch] = new fence_info(epoch, !memory_between);
    }
}


void set_allocations(nvbit_api_cuda_t cbid, void *params) {
    uint64_t local_base, local_bound;
    setup.start();
    switch(cbid) {
        case API_CUDA_cuMemAlloc_v2: {
            cuMemAlloc_v2_params *p1 = (cuMemAlloc_v2_params *)params;
            local_base = (uint64_t)*p1->dptr;
            local_bound = (uint64_t)*p1->dptr + p1->bytesize;
            break;
        }
        case API_CUDA_cuMemAllocManaged: {
            cuMemAllocManaged_params *p2 = (cuMemAllocManaged_params *)params;
            local_base = (uint64_t)*p2->dptr;
            local_bound = (uint64_t)*p2->dptr + p2->bytesize;
            break;
        }
        case API_CUDA_cuMemAllocPitch_v2: {
            cuMemAllocPitch_v2_params *p3 = (cuMemAllocPitch_v2_params *)params;
            local_base = (uint64_t)*p3->dptr;
            local_bound = (uint64_t)*p3->dptr + (p3->WidthInBytes * p3->Height);
            break;
        }
        case API_CUDA_cuModuleGetGlobal_v2: {
            cuModuleGetGlobal_v2_params_st *p4 = (cuModuleGetGlobal_v2_params_st *)params;
            local_base = (uint64_t)*p4->dptr;
            /* HACK: size for global allocations not available. Correct way is (uint64_t)*(p4->bytes) */
            local_bound = (uint64_t)*p4->dptr + NUM_THREADS * GRAN * 2;
            break;
        }
        default:
            return;
    }
    allocation_records.emplace_back(local_base, local_bound);
    app_mem += (local_bound - local_base);
    // for in-GPU metadata, 4B per each 4B addr
    meta_mem += (local_bound - local_base);
    // for in-GPU trace, NUM_STREAM_TRACES * 4B per each 4B addr (only when enabled)
    if (DO_STREAM)
        meta_mem += ((local_bound - local_base) * NUM_STREAM_TRACES);
    setup.end();
}


void set_dimension(cuLaunchKernel_params *p) {
    kernel_dimension.blockDim = p->blockDimX * p->blockDimY * p->blockDimZ;
    kernel_dimension.warpsPerBlock = roundUp(kernel_dimension.blockDim, WARP_SIZE);
    kernel_dimension.gridDim = p->gridDimX * p->gridDimY * p->gridDimZ * kernel_dimension.blockDim;
    kernel_dimension.warpsInGrid = roundUp(kernel_dimension.gridDim, WARP_SIZE);
    /* Set information that can be sent to instrumented device functions */
    device_arguments.threads_per_block = kernel_dimension.blockDim;
    device_arguments.threads = kernel_dimension.gridDim;
}



void set_sampling_meta() {
    if (!DO_SAMPLING)
        return;

    /* Requires kernel_dimension to be set! */
    srand(time(0));
    uint64_t blocks = (kernel_dimension.gridDim / kernel_dimension.blockDim) + 1;
    /* Set up metadata for instr-thread level sampling, no need to instrument this, skipping */
    skip_flag = true;
    cudaMallocManaged((void**)&device_arguments.random_meta, sizeof(char) * blocks);
    samp_mem += sizeof(char) * blocks;
    for (uint64_t i = 0; i < blocks; i++) {
        /* create a random number between SAMP_BASE and PER_THREAD_PER_INSTR */
        device_arguments.random_meta[i] = rand() % (PER_THREAD_PER_INSTR - SAMP_BASE + 1) + SAMP_BASE;
    }
    cudaMallocManaged((void**)&device_arguments.sampling_meta, sizeof(char) * kernel_dimension.gridDim * static_counter);
    samp_mem += sizeof(char) * kernel_dimension.gridDim * static_counter;
    // memset async as the driver launches the kernel after these operations are over
    cudaMemsetAsync(device_arguments.sampling_meta, 0, sizeof(char) * kernel_dimension.gridDim * static_counter, stream);
    skip_flag = false;
}


void set_fence_meta() {
    int entries = kernel_dimension.warpsInGrid;
    skip_flag = true;
    // Should consider a different multiple here if the threads_per_block is not a multiple of WARP_SIZE
    cudaMallocManaged((void**)&device_arguments.fence_meta, sizeof(uint32_t) * entries * epoch);
    fence_mem +=  sizeof(uint32_t) * entries * epoch;
    device_arguments.warps_per_grid = entries;
    skip_flag = false;
}

/*****************************************************
 *                                                   *
 *  NVBIT Instrumentation Interface Calls Below      *
 *                                                   *
******************************************************/


void nvbit_at_init() {
    setenv("CUDA_MANAGED_FORCE_DEVICE_ALLOC", "1", 1);
    GET_VAR_INT(instr_begin_interval, "INSTR_BEGIN", 0,
        "Beginning of the instruction interval where to apply instrumentation");
    GET_VAR_INT(instr_end_interval, "INSTR_END", UINT32_MAX,
        "End of the instruction interval where to apply instrumentation");
    GET_VAR_INT(verbose, "TOOL_VERBOSE", 0, "Enable verbosity inside the tool (def = 0)");
    GET_VAR_INT(timeout, "TIMEOUT", 0, "Time in seconds after which to quit detection (0 = never; def = 0)");
    GET_VAR_INT(debug_out, "DEBUG", 0, "Output debug info (def = 0)");
    GET_VAR_STR(kernel_id, "KERNELID", "Specific kernel that needs to be traced (def = all)");
    GET_VAR_INT(instance, "INSTANCE", 1, "The dynamic instance of the KERNELID to be traced (def = first)");
    std::string pad(100, '-');
    printf ("%s\n", pad.c_str());
}


void nvbit_at_cuda_event (CUcontext ctx, int is_exit, nvbit_api_cuda_t cbid,
                         const char *name, void *params, CUresult *pStatus) {
    if (skip_flag) return;

    /* returning from memory allocation APIs */
    if (is_exit && cbid == API_CUDA_cuMemAlloc_v2) {
        set_allocations(API_CUDA_cuMemAlloc_v2, params);
        return;
    } else if (is_exit && cbid == API_CUDA_cuMemAllocManaged) {
        set_allocations(API_CUDA_cuMemAllocManaged, params);
        return;
    } else if (is_exit && cbid == API_CUDA_cuMemAllocPitch_v2) {
        set_allocations(API_CUDA_cuMemAllocPitch_v2, params);
        return;
    } else if (is_exit && cbid == API_CUDA_cuModuleGetGlobal_v2) {
        set_allocations(API_CUDA_cuModuleGetGlobal_v2, params);
        return;
    }

    if (cbid == API_CUDA_cuLaunchKernel_ptsz || cbid == API_CUDA_cuLaunchKernel ||
        cbid == API_CUDA_cuLaunchCooperativeKernel || cbid == API_CUDA_cuLaunchCooperativeKernel_ptsz) {

        cuLaunchKernel_params *p = (cuLaunchKernel_params *)params;
        if (!kernel_id.empty()) {
            // Check for no match. Skip the kernel
            if(strstr(nvbit_get_func_name(ctx, p->f), kernel_id.c_str()) == NULL)
                return;

            if (!is_exit) {
                // Given kernel, increase instance count. Only increment on entry
                kernel_instances += 1;
            }
            // If this is the suggested instance do it, else skip
            if (kernel_instances != instance) {
                // Disable instrumentation if the instance is not to be traced
                // Only do this after required instance is traced
                if (kernel_instances > instance) {
                    nvbit_enable_instrumented(ctx, p->f, false);
                }
                return;
            }
        }

        if (!is_exit) {
            instrumentation.start();
            instrument_function_if_needed(ctx, p->f);
            nvbit_enable_instrumented(ctx, p->f, true);
            instrumentation.end();
            setup.start();
            /* let dedup thread move ahead as well! */
            last_job.exchange(JOB_BEGIN);

            /* Start zeroing, this will wake up the workers, after instrumentation completes! */
            pthread_barrier_wait(&barrier);

            int nregs;
            CUDA_SAFECALL (cuFuncGetAttribute (&nregs, CU_FUNC_ATTRIBUTE_NUM_REGS, p->f));

            int shmem_static_nbytes;
            CUDA_SAFECALL (cuFuncGetAttribute (&shmem_static_nbytes, CU_FUNC_ATTRIBUTE_SHARED_SIZE_BYTES, p->f));
            printf ("Kernel %s - grid size %d,%d,%d - block size %d,%d,%d - nregs "
                "%d - shmem %d - cuda stream id %ld\n", nvbit_get_func_name(ctx, p->f),
                p->gridDimX, p->gridDimY, p->gridDimZ, p->blockDimX, p->blockDimY,
                p->blockDimZ, nregs, shmem_static_nbytes + p->sharedMemBytes, (uint64_t)p->hStream);

            /* Useful for calculation later */
            set_dimension(p);
            /* Information needed for implementing execution sampling */
            set_sampling_meta();
            /* initialize fence meta */
            set_fence_meta();

            /* Ensure that workers have completed zeroing! */
            pthread_barrier_wait(&barrier);

            /* sync zeroing */
            cudaStreamSynchronize(stream);

            setup.end();
            kernel.start();
            /* Ensure that boss thread now starts listening for GPU jobs */
            recv_thread_receiving = true;
        } else {
            /* Removing this can cause trouble, as flush marker below must be set after kernel finishes */
            cudaDeviceSynchronize ();
            cudaError_t error = cudaGetLastError ();
            if (error != cudaSuccess) {
                printf ("CUDA error_%d: %s\n", error, cudaGetErrorName (error));
                assert (false);
            }
            kernel.end();
            /* Will be launching a kernel from here, so skip all instrumentation of that one */
            skip_flag = true;

            flush_channel<<<1,1>>> ();
            cudaDeviceSynchronize ();
            error = cudaGetLastError ();
            if (error != cudaSuccess) {
                printf ("CUDA error_%d: %s\n", error, cudaGetErrorName (error));
                assert (false);
            }
            
            /* All good, restart instrumentation */
            skip_flag = false;
        }
    }
}


void nvbit_at_ctx_init (CUcontext ctx) {
    setup.start();
    if (!recv_thread_started) {
        /* Initialize job content */
        for (int i = 0; i < NUM_BUFFERS; i++) {
            jobs[i].job_amount = 0;
            jobs[i].buffer = (char *)malloc (CHANNEL_SIZE);
            free_queue.push_back(i);
        }

        /* Need not init this for every ctx, just once! */
        recv_thread_started = true;
        channel_host.init (0, CHANNEL_SIZE, &channel_dev, NULL);
        /* set up channel in device_arguments */
        device_arguments.channel_dev = &channel_dev;
        /* Init locks for job, free queues, async */
        pthread_mutex_init(&async_lock, NULL);
        pthread_mutex_init(&free_lock, NULL);
        pthread_mutex_init(&job_lock, NULL);
        /* Creates a barrier with workers + async_task amount of threads */
        pthread_barrier_init(&barrier, NULL, NUM_THREADS + 1);
        /* Create boss thread */
        int result = pthread_create (&recv_thread, NULL, distributor, NULL);
        /* Create cleaner thread */
        result = pthread_create (&async_task, NULL, deduplicate, NULL);
        for (int i = 0; i < NUM_THREADS; ++i) {
            thr_data[i].tid = i;
            /* Create multiple worker threads! */
            if ((result = pthread_create(&thr[i], NULL, async_zero, &thr_data[i]))) {
                fprintf(stderr, "error: pthread_create, rc: %d\n", result);
            }
        }
        uint64_t free = 0, total = 0;
        CUDA_SAFECALL(cudaMemGetInfo(&free, &total));
        host_metadata_len = roundUp(total, GRAN);
        /* UVM ensures lazy allocation at 64K boundaries. Below allocations create a hash map for all posisble locations present on
           the GPU. Being lazily allocated, it does not consume the whole GPU memory area even though the VA space is quite large. */
        cudaMallocManaged((void**)&device_arguments.memory_meta, sizeof(uint32_t) * host_metadata_len);
        if (DO_STREAM)
            cudaMallocManaged((void**)&device_arguments.stream_meta, sizeof(uint32_t) * host_metadata_len * NUM_STREAM_TRACES);
        device_arguments.length = host_metadata_len;
        access_map = new std::atomic<uint64_t>[host_metadata_len];
        /* creating high priority stream for prefetching, async memset and memcpy */
        int high, low;
        cudaDeviceGetStreamPriorityRange(&low, &high);
        cudaStreamCreateWithPriority(&stream, cudaStreamNonBlocking, high);
        /* Initialize global variables as well  */
        static_counter = 0;
        allocation_records.clear();
        last_job.exchange(0);
    }
    setup.end();
}

void nvbit_at_ctx_term(CUcontext ctx) {
    if (!recv_thread_started)
        return;

    recv_thread_started = false;
    pthread_join (recv_thread, NULL);
    pthread_join (async_task, NULL);
    /* Wait till all worker threads are done */
    for (int i = 0; i < NUM_THREADS; i++) {
        //if (verbose) {
        //    printf("Joined: %d, with status: %d\n", i, pthread_join(thr[i], NULL));
        //}
        pthread_join(thr[i], NULL);
    }

    if (DO_ANALYZE) {
        /* Print suggestions */
        printf("========== SUGGESTIONS ==========\n");
        for (int i = 0; i < epoch; i++) {
            auto current = fence_map[i];
            if (!current->not_oversynchronized.load()) {
                uint64_t addr = id_to_fence_map[i];
                auto next = fence_map[i+1];
                /* NOTE: wrapper script depends on this format. Do not change without changing the wrapper! */
                printf("Fence@: %lx | Epoch: %d | Info: %s | Type: %s\n", addr, i, fence_to_lineinfo_map[addr].c_str(),
                    fence_map[i]->get_comment(next->operations.load()).c_str());
            }
        }
    }
    printCounters();
    printTrackers();
}
