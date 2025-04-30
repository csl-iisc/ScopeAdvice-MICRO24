// Measuring time for each fence operation
// $> nvcc -arch=sm_XY fence_measure.cu -o fence_measure
// $> ./fence_measure

#include <stdio.h>

#define BLOCKS  1
#define THREADS 1

#define SCOPES  3
#define BLOCK   0
#define DEVICE  1
#define SYSTEM  2

#define ACQ_REL 0

__device__ void init(int *time) {
    for (int i = 0; i < SCOPES; i++)
        time[i] = 0;
}

__device__ __inline__ void blk() {
    if (!ACQ_REL)
        asm volatile ("membar.cta;" ::);
    else
        asm volatile ("fence.acq_rel.cta;" ::);
}

__device__ __inline__ void gpu() {
    if (!ACQ_REL)
        asm volatile ("membar.gl;" ::);
    else
        asm volatile ("fence.acq_rel.gpu;" ::);
}

__device__ __inline__ void sys() {
    if (!ACQ_REL)
        asm volatile ("membar.sys;" ::);
    else
        asm volatile ("fence.acq_rel.sys;" ::);
}

__global__ void tf(int *time)  {
    init(time);

    blk();   // ensure no reordering beyond this point
    int start = clock();
    blk();   // measuring block-scoped fence timing
    time[BLOCK] = clock() - start;

    blk();   // ensure no reordering beyond this point
    start = clock();
    gpu();   // measuring device-scoped fence timing
    time[DEVICE] = clock() - start;

    blk();   // ensure no reordering beyond this point
    start = clock();
    sys();   // measuring system-scoped fence timing
    time[SYSTEM] = clock() - start;
}

int main() {
    int *dev_ptr;
    int host_ptr[SCOPES];
    int blk = 0, dev = 0, sys = 0;

    cudaMalloc((void **)&dev_ptr, sizeof(int) * SCOPES);
    tf<<<BLOCKS, THREADS>>>(dev_ptr);
    cudaMemcpy(host_ptr, dev_ptr, sizeof(int) * SCOPES, cudaMemcpyDeviceToHost);
    blk = host_ptr[BLOCK];
    dev = host_ptr[DEVICE];
    sys = host_ptr[SYSTEM];

    printf("Block (B): %d, Device (D): %d, System (S): %d\n", blk, dev, sys);
    printf("Ratios\n[D/B]: %lf, [S/B]: %lf\n", (double)dev / blk, (double)sys / blk);
    return 0;
}

