#include "../../tools/common/io.h"
#include "../../tools/common/ringisa.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Device inputs/IRQ timing are replayed from the RTL bus trace. The independent
// C CPU executes every original instruction; no expected register values are
// injected. This checks architecture, not independent cycle-level peripherals.
int main(int argc, char **argv) {
    if (argc != 3)
        return 2;
    size_t size = 0;
    uint8_t *image = ri_read_file(argv[1], &size);
    if (!image || size > 16384) {
        free(image);
        return 1;
    }
    ri_cpu *cpu = calloc(1, sizeof(*cpu));
    if (!cpu) {
        free(image);
        return 1;
    }
    ri_cpu_init(cpu);
    bool good = ri_memory_map(&cpu->memory, 0, 16384, true, false) &&
                ri_memory_map(&cpu->memory, 65536, 131072, true, false) &&
                ri_memory_map(&cpu->memory, 1048576, 3 * 4096, true, true);
    for (size_t i = 0; good && i < size; i += 32) {
        size_t n = size - i < 32 ? size - i : 32;
        good = ri_phys_write(&cpu->memory, i, image + i, n);
    }
    free(image);
    FILE *trace = fopen(argv[2], "r");
    if (!trace)
        good = false;
    char line[256];
    unsigned events = 0;
    uint64_t write_addresses[32];
    uint8_t write_values[32];
    unsigned writes = 0, compared_bytes = 0;
    while (good && trace && fgets(line, sizeof(line), trace)) {
        if (++events > 1000000) {
            good = false;
            break;
        }
        if (!strncmp(line, "WRITE ", 6)) {
            unsigned long long address;
            unsigned value;
            if (writes >= 32 || sscanf(line + 6, "%llx %x", &address, &value) != 2 ||
                address < 65536 || address >= 196608 || value > 255) {
                good = false;
                break;
            }
            write_addresses[writes] = (uint64_t)address;
            write_values[writes++] = (uint8_t)value;
        } else if (!strncmp(line, "INPUT ", 6)) {
            unsigned long long address;
            unsigned value;
            if (sscanf(line + 6, "%llx %x", &address, &value) != 2) {
                good = false;
                break;
            }
            if (address < 1048576 || address >= 1060864 || (address & 3)) {
                good = false;
                break;
            }
            uint8_t bytes[4];
            for (unsigned i = 0; i < 4; i++)
                bytes[i] = (uint8_t)(value >> (i * 8));
            good = ri_phys_write(&cpu->memory, (uint64_t)address, bytes, 4);
        } else if (!strncmp(line, "TRAP ", 5)) {
            unsigned cause;
            if (sscanf(line + 5, "%u", &cause) != 1 || cause < 1 || cause > 14) {
                good = false;
                break;
            }
            if (cause == 14)
                cpu->csr[RI_IP].limb[0] = 1;
            good = writes == 0 && ri_step(cpu) == (ri_fault)cause;
            cpu->csr[RI_IP].limb[0] = 0;
        } else if (!strcmp(line, "STEP\n")) {
            good = ri_step(cpu) == RI_OK;
            for (unsigned i = 0; good && i < writes; i++) {
                uint8_t byte = 0;
                good = ri_phys_read(&cpu->memory, write_addresses[i], &byte, 1) &&
                       byte == write_values[i];
                compared_bytes++;
            }
            writes = 0;
        }
    }
    if (trace && fclose(trace))
        good = false;
    if (good && (!cpu->waiting || writes != 0))
        good = false;
    if (good) {
        char text[67];
        for (unsigned i = 0; i < 64; i++) {
            ri_format_word(cpu->r[i], text);
            printf("R%u=%s\n", i, text);
        }
        for (unsigned i = 0; i < 9; i++) {
            ri_format_word(cpu->csr[i], text);
            printf("CSR%u=%s\n", i, text);
        }
        printf("FINAL pc=%016llx%016llx\n", (unsigned long long)cpu->pc.hi,
               (unsigned long long)cpu->pc.lo);
        printf("PASS independent CPU replay; compared %u physical write bytes\n", compared_bytes);
    }
    ri_cpu_destroy(cpu);
    free(cpu);
    return good ? 0 : 1;
}
