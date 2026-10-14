/*
 * Simple Debugger Example - Using pdcore API
 *
 * Demonstrates how to use pdcore for basic debugging tasks:
 * - Set breakpoints
 * - Inspect CPU state
 * - Read/write memory
 * - Single-step execution
 */

#include "pdcore.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Breakpoint handler - called when breakpoint is hit */
pd_breakpoint_action_t my_breakpoint_handler(
    pd_t *emu, pd_cpu_t cpu, uint32_t pc, void *user_data)
{
    (void)user_data;

    printf("\n*** Breakpoint hit at PC=0x%08x on %s ***\n",
           pc, cpu == PD_CPU_MASTER ? "Master SH2" : "Slave SH2");

    /* Get and display CPU state */
    pd_sh2_regs_t regs;
    if (pd_get_sh2_regs(emu, cpu, &regs) == 0) {
        printf("Register dump:\n");
        printf("  R0  = 0x%08x  R4  = 0x%08x  R8  = 0x%08x  R12 = 0x%08x\n",
               regs.r[0], regs.r[4], regs.r[8], regs.r[12]);
        printf("  R1  = 0x%08x  R5  = 0x%08x  R9  = 0x%08x  R13 = 0x%08x\n",
               regs.r[1], regs.r[5], regs.r[9], regs.r[13]);
        printf("  R2  = 0x%08x  R6  = 0x%08x  R10 = 0x%08x  R14 = 0x%08x\n",
               regs.r[2], regs.r[6], regs.r[10], regs.r[14]);
        printf("  R3  = 0x%08x  R7  = 0x%08x  R11 = 0x%08x  SP  = 0x%08x\n",
               regs.r[3], regs.r[7], regs.r[11], regs.r[15]);
        printf("  PC  = 0x%08x  SR  = 0x%08x  PR  = 0x%08x\n",
               regs.pc, regs.sr, regs.pr);
        printf("  Cycles: %u  Instructions: %u\n",
               regs.cycle_count, regs.instruction_count);
    }

    /* Halt execution so user can inspect */
    return PD_BP_HALT;
}

/* Conditional breakpoint - only halts when R0 == specific value */
pd_breakpoint_action_t conditional_breakpoint_handler(
    pd_t *emu, pd_cpu_t cpu, uint32_t pc, void *user_data)
{
    uint32_t target_value = *(uint32_t *)user_data;
    pd_sh2_regs_t regs;

    if (pd_get_sh2_regs(emu, cpu, &regs) == 0) {
        if (regs.r[0] == target_value) {
            printf("\n*** Conditional breakpoint: R0=0x%08x at PC=0x%08x ***\n",
                   regs.r[0], pc);
            return PD_BP_HALT;
        }
    }

    /* Condition not met - continue execution */
    return PD_BP_CONTINUE;
}

/* Dump memory contents in hex format */
void dump_memory(pd_t *emu, uint32_t address, size_t size)
{
    uint8_t buf[256];
    size_t chunk_size = (size > 256) ? 256 : size;

    printf("\nMemory dump at 0x%08x (%zu bytes):\n", address, size);

    for (size_t offset = 0; offset < size; offset += chunk_size) {
        size_t read_size = (size - offset > chunk_size) ? chunk_size : size - offset;

        if (pd_mem_read(emu, PD_BUS_SH2_SDRAM, address + offset, buf, read_size) == 0) {
            for (size_t i = 0; i < read_size; i += 16) {
                printf("  %08zx: ", address + offset + i);
                for (size_t j = 0; j < 16 && (i + j) < read_size; j++) {
                    printf("%02x ", buf[i + j]);
                }
                printf("\n");
            }
        }
    }
}

/* Single-step execution with trace */
void trace_execution(pd_t *emu, int num_instructions)
{
    pd_stop_info_t stop_info;
    pd_sh2_regs_t regs;

    printf("\n=== Tracing %d instructions ===\n", num_instructions);

    for (int i = 0; i < num_instructions; i++) {
        /* Get state before instruction */
        if (pd_get_sh2_regs(emu, PD_CPU_MASTER, &regs) == 0) {
            printf("[%04d] PC=0x%08x  R0=0x%08x  SP=0x%08x%s\n",
                   i, regs.pc, regs.r[0], regs.r[15],
                   regs.in_delay_slot ? " [DELAY]" : "");
        }

        /* Execute one instruction */
        pd_step_instruction(emu, PD_CPU_MASTER, &stop_info);
    }

    printf("=== Trace complete ===\n");
}

/* Main debugger program */
int main(int argc, char *argv[])
{
    pd_config_t config = {0};
    pd_t *emu;
    int choice;

    printf("╔════════════════════════════════════════════════════════════╗\n");
    printf("║  Simple PicoDrive Debugger                                ║\n");
    printf("║  Using pdcore API                                          ║\n");
    printf("╚════════════════════════════════════════════════════════════╝\n\n");

    /* Create emulator */
    if (argc > 1) {
        config.rom_path = argv[1];
        printf("Loading ROM: %s\n", config.rom_path);
    }

    emu = pd_create(&config);
    if (!emu) {
        fprintf(stderr, "Error: Failed to create emulator\n");
        return 1;
    }

    /* Interactive menu */
    while (1) {
        printf("\n--- Debugger Menu ---\n");
        printf("1. Set breakpoint at address\n");
        printf("2. Set conditional breakpoint (R0 == value)\n");
        printf("3. Run for N cycles\n");
        printf("4. Run for N frames\n");
        printf("5. Single-step N instructions\n");
        printf("6. Dump registers\n");
        printf("7. Dump memory\n");
        printf("8. Modify register\n");
        printf("9. Clear all breakpoints\n");
        printf("0. Exit\n");
        printf("Choice: ");

        if (scanf("%d", &choice) != 1) {
            break;
        }

        switch (choice) {
            case 1: {
                uint32_t addr;
                printf("Enter breakpoint address (hex): 0x");
                scanf("%x", &addr);

                int bp_id = pd_bp_exec_add(emu, PD_CPU_MASTER, addr,
                                           my_breakpoint_handler, NULL);
                if (bp_id >= 0) {
                    printf("Breakpoint #%d set at 0x%08x\n", bp_id, addr);
                } else {
                    printf("Failed to set breakpoint\n");
                }
                break;
            }

            case 2: {
                static uint32_t condition_value;
                uint32_t addr;
                printf("Enter breakpoint address (hex): 0x");
                scanf("%x", &addr);
                printf("Enter R0 value to match (hex): 0x");
                scanf("%x", &condition_value);

                int bp_id = pd_bp_exec_add(emu, PD_CPU_MASTER, addr,
                                           conditional_breakpoint_handler,
                                           &condition_value);
                if (bp_id >= 0) {
                    printf("Conditional breakpoint #%d set (R0==0x%08x at 0x%08x)\n",
                           bp_id, condition_value, addr);
                } else {
                    printf("Failed to set breakpoint\n");
                }
                break;
            }

            case 3: {
                uint64_t cycles;
                printf("Enter number of cycles: ");
                scanf("%llu", (unsigned long long *)&cycles);

                pd_stop_info_t stop_info;
                pd_stop_reason_t reason = pd_run_cycles(emu, cycles, &stop_info);

                printf("Stopped: ");
                switch (reason) {
                    case PD_STOP_CYCLE_LIMIT:
                        printf("Cycle limit reached\n");
                        break;
                    case PD_STOP_HALT:
                        printf("Halted (breakpoint?)\n");
                        break;
                    default:
                        printf("Unknown reason\n");
                        break;
                }
                printf("Total cycles: %lu\n", (unsigned long)stop_info.master_cycles);
                break;
            }

            case 4: {
                uint32_t frames;
                printf("Enter number of frames: ");
                scanf("%u", &frames);

                pd_stop_info_t stop_info;
                pd_run_frames(emu, frames, &stop_info);
                printf("Completed %u frame(s)\n", frames);
                break;
            }

            case 5: {
                int num_steps;
                printf("Enter number of steps: ");
                scanf("%d", &num_steps);

                trace_execution(emu, num_steps);
                break;
            }

            case 6: {
                pd_sh2_regs_t regs;
                if (pd_get_sh2_regs(emu, PD_CPU_MASTER, &regs) == 0) {
                    printf("\n=== Master SH2 Registers ===\n");
                    for (int i = 0; i < 16; i += 4) {
                        printf("R%-2d = 0x%08x  R%-2d = 0x%08x  R%-2d = 0x%08x  R%-2d = 0x%08x\n",
                               i, regs.r[i], i+1, regs.r[i+1],
                               i+2, regs.r[i+2], i+3, regs.r[i+3]);
                    }
                    printf("PC  = 0x%08x  SR  = 0x%08x  PR  = 0x%08x\n",
                           regs.pc, regs.sr, regs.pr);
                    printf("GBR = 0x%08x  VBR = 0x%08x\n", regs.gbr, regs.vbr);
                    printf("MACH= 0x%08x  MACL= 0x%08x\n", regs.mach, regs.macl);
                    printf("Cycles: %u  Instructions: %u\n",
                           regs.cycle_count, regs.instruction_count);
                }
                break;
            }

            case 7: {
                uint32_t addr;
                size_t size;
                printf("Enter memory address (hex): 0x");
                scanf("%x", &addr);
                printf("Enter size (bytes): ");
                scanf("%zu", &size);

                dump_memory(emu, addr, size);
                break;
            }

            case 8: {
                int reg_num;
                uint32_t value;
                printf("Enter register number (0-15): ");
                scanf("%d", &reg_num);

                if (reg_num < 0 || reg_num > 15) {
                    printf("Invalid register number\n");
                    break;
                }

                printf("Enter new value (hex): 0x");
                scanf("%x", &value);

                pd_sh2_regs_t regs;
                if (pd_get_sh2_regs(emu, PD_CPU_MASTER, &regs) == 0) {
                    regs.r[reg_num] = value;
                    if (pd_set_sh2_regs(emu, PD_CPU_MASTER, &regs) == 0) {
                        printf("R%d set to 0x%08x\n", reg_num, value);
                    }
                }
                break;
            }

            case 9: {
                pd_bp_exec_clear(emu, PD_CPU_MASTER);
                printf("All breakpoints cleared\n");
                break;
            }

            case 0:
                printf("Exiting...\n");
                goto cleanup;

            default:
                printf("Invalid choice\n");
                break;
        }
    }

cleanup:
    pd_destroy(emu);
    printf("Debugger closed\n");
    return 0;
}
