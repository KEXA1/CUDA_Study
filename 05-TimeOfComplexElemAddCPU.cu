#include <math.h>
#include <stdio.h>
#include <math.h>
#include <stdio.h>
#include<stdint.h>
#include<cuda.h>
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
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

const int NUM_REPEATS = 10;
const real x0 = 100.0;
void arithmetic(real* x, const real x0, const int N);

int main(void)
{
    const int N = 10000;
    const int M = sizeof(real) * N;
    real* x = (real*)malloc(M);

    float t_sum = 0;
    float t2_sum = 0;
    for (int repeat = 0; repeat <= NUM_REPEATS; ++repeat)
    {
        for (int n = 0; n < N; ++n)
        {
            x[n] = 0.0;
        }

        cudaEvent_t start, stop;
        CHECK(cudaEventCreate(&start));
        CHECK(cudaEventCreate(&stop));
        CHECK(cudaEventRecord(start));
        cudaEventQuery(start);

        arithmetic(x, x0, N);

        CHECK(cudaEventRecord(stop));
        CHECK(cudaEventSynchronize(stop));
        float elapsed_time;
        CHECK(cudaEventElapsedTime(&elapsed_time, start, stop));
        printf("Time = %g ms.\n", elapsed_time);

        if (repeat > 0)
        {
            t_sum += elapsed_time;
            t2_sum += elapsed_time * elapsed_time;
        }

        CHECK(cudaEventDestroy(start));
        CHECK(cudaEventDestroy(stop));
    }

    const float t_ave = t_sum / NUM_REPEATS;
    const float t_err = sqrt(t2_sum / NUM_REPEATS - t_ave * t_ave);
    printf("Time = %g +- %g ms.\n", t_ave, t_err);

    free(x);
    return 0;
}

void arithmetic(real* x, const real x0, const int N)
{
    for (int n = 0; n < N; ++n)
    {
        real x_tmp = x[n];
        while (sqrt(x_tmp) < x0)
        {
            ++x_tmp;
        }
        x[n] = x_tmp;
    }
}
