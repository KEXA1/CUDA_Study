#include<stdint.h>
#include<cuda.h>
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <stdio.h>
#include <math.h>
#include <stdio.h>

#define CHECK(call)                                   \
do                                                    \
{                                                     \
    const cudaError_t error_code = call;              \
    if (error_code != cudaSuccess)                    \
    {                                                 \
        printf("CUDA Error:\n");                      \
        printf("    File:       %s\n", __FILE__);     \
        printf("    Line:       %d\n", __LINE__);     \
        printf("    Error code: %d\n", error_code);   \
        printf("    Error text: %s\n",                \
            cudaGetErrorString(error_code));          \
        exit(1);                                      \
    }                                                 \
} while (0)

#ifdef USE_DP
typedef double real;
#else
typedef float real;
#endif

const int NUM_REPEATS = 100;
const int N = 100000000;
const int M = sizeof(real) * N;
const int BLOCK_SIZE = 128;

void timing(real* h_x, real* d_x, const int method);

int main(void)
{
    real* h_x = (real*)malloc(M);
    for (int n = 0; n < N; ++n)
    {
        h_x[n] = 1.23;
    }
    real* d_x;
    CHECK(cudaMalloc(&d_x, M));

    printf("\nUsing global memory only:\n");
    timing(h_x, d_x, 0);
    printf("\nUsing static shared memory:\n");
    timing(h_x, d_x, 1);
    printf("\nUsing dynamic shared memory:\n");
    timing(h_x, d_x, 2);

    free(h_x);
    CHECK(cudaFree(d_x));
    return 0;
}

void __global__ reduce_global(real* d_x, real* d_y)
{
    const int tid = threadIdx.x;
 //����ָ��X���ұ߱�ʾ d_x �����  blockDim.x * blockIdx.x��Ԫ�صĵ�ַ
 //�������x �ڲ�ͬ�߳̿飬ָ��ȫ���ڴ治ͬ�ĵ�ַ---��ʹ�ò�ͬ���߳̿��dx���鲻ͬ���ֱַ���д���   
    real* x = d_x + blockDim.x * blockIdx.x;

    //blockDim.x >> 1  �ȼ��� blockDim.x /2���˺����У�λ������ ��Ӧ������������Ч
    for (int offset = blockDim.x >> 1; offset > 0; offset >>= 1)
    {
        if (tid < offset)
        {
            x[tid] += x[tid + offset];
        }
        //ͬ����䣬���ã�ͬһ���߳̿��ڵ��̰߳��մ����Ⱥ�ִ��ָ�����ͬ�������ⲻ��ͬ����
        __syncthreads();
    }

    if (tid == 0)
    {
        d_y[blockIdx.x] = x[0];
    }
}

void __global__ reduce_shared(real* d_x, real* d_y)
{
    const int tid = threadIdx.x;
    const int bid = blockIdx.x;
    const int n = bid * blockDim.x + tid;
    //�����˹����ڴ����� s_y[128]��ע��ؼ���  __shared__
    __shared__ real s_y[128];
    //��ȫ���ڴ��е����ݸ��Ƶ������ڴ���
    //�����ڴ���� ����ÿ���߳̿鶼��һ�������ڴ�����ĸ���
    s_y[tid] = (n < N) ? d_x[n] : 0.0;
    //���ú��� __syncthreads �����߳̿��ڵ�ͬ��
    __syncthreads();
    //��Լ�����ù����ڴ�����滻��ԭ����ȫ���ڴ����������ҲҪ��ס�� ÿ���߳̿鶼�����еĹ����ڴ�����������в������ڹ�Լ���̽�����ÿһ���߳�
    //���е� s_y[0] �����ͱ�������������Ԫ�صĺ�
    for (int offset = blockDim.x >> 1; offset > 0; offset >>= 1)
    {

        if (tid < offset)
        {
            s_y[tid] += s_y[tid + offset];
        }
        __syncthreads();
    }

    if (tid == 0)
    {
        d_y[bid] = s_y[0];
    }
}

void __global__ reduce_dynamic(real* d_x, real* d_y)
{
    const int tid = threadIdx.x;
    const int bid = blockIdx.x;
    const int n = bid * blockDim.x + tid;
    //���� ��̬�����ڴ� s_y[]  �޶��� extern������ָ�������С
    extern __shared__ real s_y[];
    s_y[tid] = (n < N) ? d_x[n] : 0.0;
    __syncthreads();

    for (int offset = blockDim.x >> 1; offset > 0; offset >>= 1)
    {

        if (tid < offset)
        {
            s_y[tid] += s_y[tid + offset];
        }
        __syncthreads();
    }

    if (tid == 0)
    {//��ÿһ���߳̿��й�Լ�Ľ���ӹ����ڴ� s_y[0] ���Ƶ�ȫ���� ��d_y[bid]
        d_y[bid] = s_y[0];
    }
}

real reduce(real* d_x, const int method)
{
    int grid_size = (N + BLOCK_SIZE - 1) / BLOCK_SIZE;
    const int ymem = sizeof(real) * grid_size;
    const int smem = sizeof(real) * BLOCK_SIZE;
    real* d_y;
    CHECK(cudaMalloc(&d_y, ymem));
    real* h_y = (real*)malloc(ymem);

    switch (method)
    {
    case 0:
        reduce_global << <grid_size, BLOCK_SIZE >> > (d_x, d_y);
        break;
    case 1:
        reduce_shared << <grid_size, BLOCK_SIZE >> > (d_x, d_y);
        break;
    case 2:
        reduce_dynamic << <grid_size, BLOCK_SIZE, smem >> > (d_x, d_y);
        break;
    default:
        printf("Error: wrong method\n");
        exit(1);
        break;
    }

    CHECK(cudaMemcpy(h_y, d_y, ymem, cudaMemcpyDeviceToHost));

    real result = 0.0;
    for (int n = 0; n < grid_size; ++n)
    {
        result += h_y[n];
    }

    free(h_y);
    CHECK(cudaFree(d_y));
    return result;
}

void timing(real* h_x, real* d_x, const int method)
{
    real sum = 0;

    for (int repeat = 0; repeat < NUM_REPEATS; ++repeat)
    {
        CHECK(cudaMemcpy(d_x, h_x, M, cudaMemcpyHostToDevice));

        cudaEvent_t start, stop;
        CHECK(cudaEventCreate(&start));
        CHECK(cudaEventCreate(&stop));
        CHECK(cudaEventRecord(start));
        cudaEventQuery(start);

        sum = reduce(d_x, method);

        CHECK(cudaEventRecord(stop));
        CHECK(cudaEventSynchronize(stop));
        float elapsed_time;
        CHECK(cudaEventElapsedTime(&elapsed_time, start, stop));
        printf("Time = %g ms.\n", elapsed_time);

        CHECK(cudaEventDestroy(start));
        CHECK(cudaEventDestroy(stop));
    }

    printf("sum = %f.\n", sum);
}


