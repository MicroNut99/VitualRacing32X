/*
 * PicoDrive Debugger Core Bridge
 *
 * This file provides accessor functions for pdcore to access PicoDrive's
 * internal emulator state. Place this file in pico/ directory.
 *
 * Build with: USE_PDCORE=1 make
 */

#include "pico_int.h"
#include "../cpu/sh2/sh2.h"

/* External SH2 instances from PicoDrive */
extern SH2 msh2;  /* Master SH2 */
extern SH2 ssh2;  /* Slave SH2 */

/*
 * pdcore accessor functions
 * These provide opaque pointers to PicoDrive's internal structures
 */

void *picodrive_get_pico32x_state(void)
{
    return (void *)&Pico32x;
}

void *picodrive_get_sh2_master(void)
{
    return (void *)&msh2;
}

void *picodrive_get_sh2_slave(void)
{
    return (void *)&ssh2;
}

void *picodrive_get_pico_state(void)
{
    return (void *)&Pico;
}

/* Get 32X memory regions */
void *picodrive_get_sdram(void)
{
    return Pico32xMem ? Pico32xMem->sdram : NULL;
}

void *picodrive_get_dram(void)
{
    return Pico32xMem ? Pico32xMem->dram : NULL;
}

unsigned int picodrive_get_sdram_size(void)
{
    return sizeof(Pico32xMem->sdram);  /* 256KB */
}

unsigned int picodrive_get_dram_size(void)
{
    return sizeof(Pico32xMem->dram);   /* 2x128KB frame buffers */
}
