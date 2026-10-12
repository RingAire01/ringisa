#include "../common/io.h"
#include "../common/ringisa.h"
#include <stdio.h>
#include <stdlib.h>
static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: ringisa-dis binary\n");
        return 2;
    }
    size_t size;
    uint8_t *data = ri_read_file(argv[1], &size);
    if (!data || size % 4) {
        fprintf(stderr, "invalid input\n");
        free(data);
        return 1;
    }
    for (size_t off = 0; off < size;) {
        uint32_t w0 = get32(data + off), w1 = off + 8 <= size ? get32(data + off + 4) : 0;
        ri_inst d;
        if (((w0 & 3) == 1 && off + 8 > size) || !ri_decode(w0, w1, &d)) {
            printf(".word 0x%08x\n", w0);
            off += 4;
            continue;
        }
        unsigned op = d.meta->op;
        if (d.meta->format == 'R')
            printf("%s.%u R%u, R%u, R%u\n", d.meta->name, 8u << d.func, d.a, d.b, d.c);
        else if (op == RI_CHUNK)
            printf("CHUNK R%u, %u, 0x%08x\n", d.a, (d.w0 >> 2) & 1023, w1);
        else {
            printf("%s%s", d.meta->name, d.length == 8 ? ".X" : "");
            if (op == RI_ERET || op == RI_WFI || op == RI_FENCE || op == RI_TLBI)
                printf("\n");
            else if (op == RI_SVC || op == RI_BRK)
                printf(" %lld\n", (long long)d.imm);
            else if (op == RI_MOVI || op == RI_CSRR)
                printf(" R%u, %lld\n", d.a, (long long)d.imm);
            else if (op == RI_CSRW)
                printf(" R%u, %lld\n", d.b, (long long)d.imm);
            else
                printf(" R%u, R%u, %lld\n", d.a, d.b, (long long)d.imm);
        }
        off += d.length;
    }
    free(data);
    return ferror(stdout) ? 1 : 0;
}
