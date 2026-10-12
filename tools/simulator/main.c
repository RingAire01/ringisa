#include "../common/io.h"
#include "../common/ringisa.h"
#include "debug.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr,
                "usage: ringisa-sim binary [--steps N] [--trace] [--inspect] [--debug] [--pc U128] "
                "[--satp U64] [--asid U16] [--priv U|S|M] [--tvec U128] [--handle-traps]\n");
        return 2;
    }
    uint64_t limit = 100000, satp = 0, asid = 0;
    bool trace = false, inspect = false, handle_traps = false, debug = false;
    ri_addr initial_pc = {0, 0}, tvec = {0, 0};
    ri_priv privilege = RI_M;
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--trace"))
            trace = true;
        else if (!strcmp(argv[i], "--inspect"))
            inspect = true;
        else if (!strcmp(argv[i], "--handle-traps"))
            handle_traps = true;
        else if (!strcmp(argv[i], "--debug"))
            debug = true;
        else if (!strcmp(argv[i], "--priv") && i + 1 < argc) {
            const char *p = argv[++i];
            if (!strcmp(p, "U"))
                privilege = RI_U;
            else if (!strcmp(p, "S"))
                privilege = RI_S;
            else if (!strcmp(p, "M"))
                privilege = RI_M;
            else
                return 2;
        } else if ((!strcmp(argv[i], "--pc") || !strcmp(argv[i], "--satp") ||
                    !strcmp(argv[i], "--asid") || !strcmp(argv[i], "--tvec")) &&
                   i + 1 < argc) {
            const char *option = argv[i];
            ri_word v;
            if (!ri_parse_word(argv[++i], &v) || v.limb[2] || v.limb[3])
                return 2;
            if (!strcmp(option, "--pc"))
                initial_pc = (ri_addr){v.limb[0], v.limb[1]};
            else if (!strcmp(option, "--tvec"))
                tvec = (ri_addr){v.limb[0], v.limb[1]};
            else if (!strcmp(option, "--satp")) {
                if (v.limb[1] || (v.limb[0] & 4094))
                    return 2;
                satp = v.limb[0];
            } else {
                if (v.limb[1] || v.limb[0] > 65535)
                    return 2;
                asid = v.limb[0];
            }
        } else if (!strcmp(argv[i], "--steps") && i + 1 < argc) {
            char *end;
            errno = 0;
            limit = strtoull(argv[++i], &end, 10);
            if (errno || *end || !limit || limit > 100000000) {
                fprintf(stderr, "invalid step limit\n");
                return 2;
            }
        } else {
            fprintf(stderr, "unknown option\n");
            return 2;
        }
    }
    size_t size;
    uint8_t *data = ri_read_file(argv[1], &size);
    if (!data || !size || size % 4) {
        fprintf(stderr, "invalid binary\n");
        free(data);
        return 1;
    }
    ri_cpu *cpu = calloc(1, sizeof(*cpu));
    if (!cpu) {
        free(data);
        return 1;
    }
    ri_cpu_init(cpu);
    cpu->trace = trace;
    cpu->pc = initial_pc;
    cpu->priv = privilege;
    cpu->csr[RI_SATP].limb[0] = satp;
    cpu->csr[RI_ASID].limb[0] = asid;
    cpu->csr[RI_TVEC] = (ri_word){{tvec.lo, tvec.hi, 0, 0}};
    size_t mapped = (size + 4095) & ~(size_t)4095;
    bool good = ri_memory_map(&cpu->memory, 0, mapped, true, false);
    for (size_t i = 0; good && i < size;) {
        size_t n = size - i > 32 ? 32 : size - i;
        good = ri_phys_write(&cpu->memory, i, data + i, n);
        i += n;
    }
    free(data);
    ri_fault fault = RI_OK;
    if (good && debug)
        fault = ri_debug(cpu, limit);
    else
        for (uint64_t i = 0; good && i < limit && !cpu->waiting; i++) {
            fault = ri_step(cpu);
            if (fault && !handle_traps)
                break;
        }
    char value[67];
    printf("steps=%llu pc=%016llx%016llx fault=%u waiting=%u walks=%llu hits=%llu\n",
           (unsigned long long)cpu->steps, (unsigned long long)cpu->pc.hi,
           (unsigned long long)cpu->pc.lo, (unsigned)fault, (unsigned)cpu->waiting,
           (unsigned long long)cpu->walks, (unsigned long long)cpu->hits);
    if (inspect) {
        for (unsigned i = 0; i < 64; i++) {
            ri_format_word(cpu->r[i], value);
            printf("R%u=%s\n", i, value);
        }
        for (unsigned i = 0; i < RI_CSR_COUNT; i++) {
            ri_format_word(cpu->csr[i], value);
            printf("CSR%u=%s\n", i, value);
        }
        uint8_t bytes[32];
        if (ri_phys_read(&cpu->memory, 0, bytes, 32)) {
            printf("physical[0:32]=");
            for (unsigned i = 0; i < 32; i++)
                printf("%02x", bytes[i]);
            printf("\n");
        }
        if (ri_phys_read(&cpu->memory, 0x80000, bytes, 32)) {
            printf("MEM=");
            for (unsigned i = 0; i < 32; i++)
                printf("%02x", bytes[i]);
            printf("\n");
        }
    }
    bool finished = good && !fault && (cpu->waiting || debug);
    ri_cpu_destroy(cpu);
    free(cpu);
    return finished ? 0 : 1;
}
