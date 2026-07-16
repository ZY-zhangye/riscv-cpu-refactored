#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include "../../platform/my_cpu_mmio.h"

/* ---- Platform capabilities ---- */
#define HAS_FLOAT          0
#define HAS_TIME_H         0
#define USE_CLOCK          0
#define HAS_STDIO          0
#define HAS_PRINTF         0

/* ---- Data types ---- */
typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef unsigned int   ee_u32;
typedef float          ee_f32;
typedef unsigned char  ee_u8;
typedef ee_u32         ee_ptr_int;
typedef ee_u32         ee_size_t;

/* ---- Timing via 175MHz hardware timer ---- */
typedef ee_u32 CORE_TICKS;
#define CORETIMETYPE             ee_u32
#define GETMYTIME(_t)            (*(_t) = mmio_read32(TIMER_VALUE))
#define MYTIMEDIFF(fin, ini)     ((ini) - (fin))
#define TIMER_RES_DIVIDER        1
#define NSECS_PER_SEC            175000000u
#define EE_TICKS_PER_SEC         (NSECS_PER_SEC / TIMER_RES_DIVIDER)
#define SAMPLE_TIME_IMPLEMENTATION 1

#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x) - 1) & ~3))

/* ---- Configuration ---- */
#define SEED_METHOD        SEED_VOLATILE
#define MEM_METHOD         MEM_STATIC
#define MULTITHREAD        1
#define MAIN_HAS_NOARGC    1
#define MAIN_HAS_NORETURN  1

#define COMPILER_VERSION "GCC " __VERSION__
#define COMPILER_FLAGS    "-O2 -march=rv32im_zicsr -mabi=ilp32"
#define MEM_LOCATION      "STATIC"
#define ITERATIONS        0

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) \
    && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

int ee_printf(const char *fmt, ...);

#endif /* CORE_PORTME_H */
