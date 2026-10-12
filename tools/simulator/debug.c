#include "debug.h"
#include <stdio.h>
#include <string.h>

static void inspect_registers(ri_cpu *cpu, bool csrs) {
    char text[67];
    unsigned count = csrs ? RI_CSR_COUNT : 64;
    for (unsigned i = 0; i < count; i++) {
        ri_format_word(csrs ? cpu->csr[i] : cpu->r[i], text);
        printf("%s%u=%s\n", csrs ? "CSR" : "R", i, text);
    }
}
ri_fault ri_debug(ri_cpu *cpu, uint64_t budget) {
    if (!cpu || !budget)
        return RI_ILLEGAL;
    char line[4096];
    ri_fault last = RI_OK;
    printf("commands: step [N], run [N], regs, csr, pc, mem VA N, pmem PA N, quit\n");
    for (;;) {
        printf("ringisa> ");
        fflush(stdout);
        if (!fgets(line, sizeof(line), stdin))
            break;
        if (!strchr(line, '\n') && !feof(stdin)) {
            int c;
            while ((c = getchar()) != '\n' && c != EOF) {
            }
            fprintf(stderr, "command too long\n");
            continue;
        }
        char *tokens[4];
        unsigned count = 0;
        char *token = strtok(line, " \t\r\n");
        while (token && count < 4) {
            tokens[count++] = token;
            token = strtok(NULL, " \t\r\n");
        }
        if (!count)
            continue;
        if (count > 3 || token) {
            fprintf(stderr, "too many operands\n");
            continue;
        }
        if (!strcmp(tokens[0], "quit") && count == 1)
            break;
        if (!strcmp(tokens[0], "regs") && count == 1) {
            inspect_registers(cpu, false);
            continue;
        }
        if (!strcmp(tokens[0], "csr") && count == 1) {
            inspect_registers(cpu, true);
            continue;
        }
        if (!strcmp(tokens[0], "pc") && count == 1) {
            printf("PC=0x%016llx%016llx\n", (unsigned long long)cpu->pc.hi,
                   (unsigned long long)cpu->pc.lo);
            continue;
        }
        if ((!strcmp(tokens[0], "step") || !strcmp(tokens[0], "run")) && count <= 2) {
            uint64_t n = !strcmp(tokens[0], "step") ? 1 : budget;
            if (count == 2) {
                ri_word value;
                if (!ri_parse_word(tokens[1], &value) || value.limb[1] || value.limb[2] ||
                    value.limb[3] || !value.limb[0] || value.limb[0] > budget) {
                    fprintf(stderr, "invalid step count\n");
                    continue;
                }
                n = value.limb[0];
            }
            if (!budget) {
                fprintf(stderr, "instruction budget exhausted\n");
                continue;
            }
            for (uint64_t i = 0; i < n && !cpu->waiting; i++) {
                last = ri_step(cpu);
                budget--;
                if (last)
                    break;
            }
            printf("PC=%016llx%016llx fault=%u waiting=%u budget=%llu\n",
                   (unsigned long long)cpu->pc.hi, (unsigned long long)cpu->pc.lo, (unsigned)last,
                   (unsigned)cpu->waiting, (unsigned long long)budget);
            continue;
        }
        if ((!strcmp(tokens[0], "mem") || !strcmp(tokens[0], "pmem")) && count == 3) {
            ri_word address, n;
            bool physical = !strcmp(tokens[0], "pmem");
            if (!ri_parse_word(tokens[1], &address) || address.limb[2] || address.limb[3] ||
                (physical && address.limb[1]) || !ri_parse_word(tokens[2], &n) || n.limb[1] ||
                n.limb[2] || n.limb[3] || !n.limb[0] || n.limb[0] > 32) {
                fprintf(stderr, "invalid address or byte count\n");
                continue;
            }
            uint8_t data[32];
            ri_fault fault =
                physical ? (ri_phys_read(&cpu->memory, address.limb[0], data, (size_t)n.limb[0])
                                ? RI_OK
                                : RI_PHYSICAL)
                         : ri_load(cpu, (ri_addr){address.limb[0], address.limb[1]}, data,
                                   (size_t)n.limb[0], RI_READ);
            if (fault)
                printf("memory fault=%u\n", (unsigned)fault);
            else {
                for (unsigned i = 0; i < n.limb[0]; i++)
                    printf("%02x", data[i]);
                printf("\n");
            }
            continue;
        }
        fprintf(stderr, "unknown command or invalid operands\n");
    }
    return last;
}
