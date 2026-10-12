#include "../tools/common/ringisa.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned checks;
#define CHECK(x)                                                                                   \
    do {                                                                                           \
        checks++;                                                                                  \
        if (!(x)) {                                                                                \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #x);                           \
            exit(1);                                                                               \
        }                                                                                          \
    } while (0)
static ri_cpu *new_cpu(void) {
    ri_cpu *c = calloc(1, sizeof(*c));
    CHECK(c != NULL);
    ri_cpu_init(c);
    return c;
}
static void destroy(ri_cpu *c) {
    ri_cpu_destroy(c);
    free(c);
}
static void write32(ri_cpu *c, uint64_t a, uint32_t w) {
    uint8_t b[4];
    for (unsigned i = 0; i < 4; i++)
        b[i] = (uint8_t)(w >> (8 * i));
    CHECK(ri_phys_write(&c->memory, a, b, 4));
}
static void write_pte(ri_cpu *c, uint64_t address, uint64_t ppn, unsigned flags) {
    uint8_t raw[16] = {0};
    uint64_t lo = (ppn << 44) | flags, hi = ppn >> 20;
    for (unsigned i = 0; i < 8; i++) {
        raw[i] = (uint8_t)(lo >> (i * 8));
        raw[i + 8] = (uint8_t)(hi >> (i * 8));
    }
    CHECK(ri_phys_write(&c->memory, address, raw, 16));
}
static unsigned idx(ri_addr va, unsigned level) {
    unsigned s = 12 + 8 * level;
    uint64_t x = s >= 64 ? va.hi >> (s - 64) : (va.lo >> s) | (va.hi << (64 - s));
    return (unsigned)(x & (level == 14 ? 15 : 255));
}
static uint64_t map_va(ri_cpu *c, ri_addr va, uint64_t root, uint64_t physical, unsigned flags) {
    for (unsigned level = 14; level > 0; level--) {
        uint64_t table = root + (14 - level) * 4096, next = table + 4096;
        write_pte(c, table + idx(va, level) * 16, next >> 12, RI_PTE_V | RI_PTE_T);
    }
    uint64_t leaf = root + 14 * 4096 + idx(va, 0) * 16;
    write_pte(c, leaf, physical >> 12, flags);
    return leaf;
}
static void test_encoding(void) {
    CHECK(ri_encode_r(RI_ADD,64,0,0,0)==0);
    CHECK(ri_encode_r(RI_ADD,0,0,0,6)==0);
    CHECK(ri_encode_i(RI_ADDI,0,0,512,false)==0);
    CHECK(ri_encode_i(RI_MOVI,0,1,0,false)==0);
    CHECK(ri_encode_i(RI_ERET,0,0,0,true)==0);
    for (size_t k = 0; k < RI_INSTRUCTION_COUNT; k++) {
        const ri_meta *m = &ri_instructions[k];
        for (unsigned r = 0; r < 64; r++) {
            ri_inst d;
            uint32_t w = m->format == 'R' ? ri_encode_r(m->op, r, (r + 1) % 64, (r + 2) % 64, 0)
                                          : ri_encode_i(m->op, r, 0, 0, m->format == 'X');
            if (m->family == RI_SYSTEM)
                continue;
            CHECK(ri_decode(w, 0, &d));
            CHECK(d.a == r);
            if (m->format == 'R') {
                CHECK(d.b == (r + 1) % 64);
                CHECK(d.c == (r + 2) % 64);
                CHECK(!ri_decode(w | 1, 0, &d));
            }
        }
    }
    ri_inst d;
    CHECK(!ri_decode(0, 0, &d));
    CHECK(!ri_decode(ri_encode_i(RI_MOVI, 1, 0, 0, false) | 2, 0, &d));
    CHECK(ri_decode(ri_encode_i(RI_ADDI, 1, 2, -512, false), 0, &d) && d.imm == -512);
    CHECK(ri_decode(ri_encode_i(RI_ADDI, 1, 2, 511, false), 0, &d) && d.imm == 511);
    int64_t extremes[] = {-(INT64_C(1) << 41), (INT64_C(1) << 41) - 1};
    for (unsigned i = 0; i < 2; i++) {
        CHECK(ri_decode(ri_encode_i(RI_ADDI, 63, 62, extremes[i], true),
                        (uint32_t)((uint64_t)extremes[i] >> 10), &d));
        CHECK(d.imm == extremes[i]);
    }
}
static void test_values(void) {
    CHECK(!ri_addr_add((ri_addr){0, 0}, 0, NULL));
    CHECK(!ri_decode(0, 0, NULL));
    CHECK(ri_step(NULL) == RI_ILLEGAL);
    ri_word a = {{UINT64_MAX, UINT64_MAX, UINT64_MAX, 0}}, b = {{1, 0, 0, 0}}, r;
    ri_alu(RI_ADD, 256, a, b, &r);
    CHECK(r.limb[0] == 0 && r.limb[1] == 0 && r.limb[2] == 0 && r.limb[3] == 1);
    ri_alu(RI_SUB, 256, r, b, &r);
    CHECK(!memcmp(&r, &a, sizeof(r)));
    ri_alu(RI_SUB, 256, (ri_word){{0}}, b, &r);
    for (unsigned i = 0; i < 4; i++)
        CHECK(r.limb[i] == UINT64_MAX);
    for (unsigned bits = 8; bits <= 256; bits *= 2) {
        ri_alu(RI_ADD, bits, (ri_word){{UINT64_MAX, UINT64_MAX, UINT64_MAX, UINT64_MAX}}, b, &r);
        for (unsigned i = 0; i < 4; i++)
            CHECK(!r.limb[i]);
    }
    ri_alu(RI_SAR, 8, (ri_word){{128, 0, 0, 0}}, b, &r);
    CHECK(r.limb[0] == UINT64_MAX - 63 && r.limb[3] == UINT64_MAX);
    ri_simd(RI_VADD, 8, (ri_word){{255, 0, 0, 0}}, b, &r);
    CHECK(!r.limb[0]);
    ri_simd(RI_VSUB, 16, (ri_word){{0}}, b, &r);
    CHECK(r.limb[0] == 65535 && r.limb[1] == 0);
    CHECK(ri_parse_word("0xffffffffffffffffffffffffffffffff", &r) && r.limb[0] == UINT64_MAX &&
          r.limb[1] == UINT64_MAX && r.limb[2] == 0);
    CHECK(
        !ri_parse_word("0x10000000000000000000000000000000000000000000000000000000000000000", &r));
    ri_addr address;
    CHECK(ri_addr_add((ri_addr){UINT64_MAX, 7}, 1, &address) && address.lo == 0 && address.hi == 8);
    CHECK(!ri_addr_add((ri_addr){UINT64_MAX, UINT64_MAX}, 1, &address));
    CHECK(!ri_addr_add((ri_addr){0, 0}, -1, &address));
}
static void test_paging(void) {
    ri_cpu *c = new_cpu();
    CHECK(ri_memory_map(&c->memory, 0x10000, 15 * 4096, true, false));
    CHECK(ri_memory_map(&c->memory, 0x40000, 8192, true, false));
    ri_addr va = {UINT64_C(0xfedcba9876543000), UINT64_C(0xffff0123456789ab)};
    unsigned flags = RI_PTE_V | RI_PTE_R | RI_PTE_W | RI_PTE_X | RI_PTE_U | RI_PTE_A | RI_PTE_D;
    uint64_t leaf = map_va(c, va, 0x10000, 0x40000, flags);
    c->priv = RI_U;
    c->csr[RI_SATP].limb[0] = 0x10001;
    c->csr[RI_ASID].limb[0] = 1;
    uint64_t pa = 0;
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_OK && pa == 0x40000);
    CHECK(c->walks == 1);
    CHECK(ri_translate(c, va, RI_FETCH, &pa) == RI_OK && c->hits == 1);
    uint8_t b[32], out[32];
    for (unsigned i = 0; i < 32; i++)
        b[i] = (uint8_t)i;
    CHECK(ri_store(c, va, b, 32) == RI_OK);
    CHECK(ri_load(c, va, out, 32, RI_READ) == RI_OK && !memcmp(b, out, 32));
    write_pte(c, leaf, 0x41, flags);
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_OK && pa == 0x40000);
    ri_tlbi(c);
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_OK && pa == 0x41000);
    c->csr[RI_ASID].limb[0] = 2;
    uint64_t walks = c->walks;
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_OK && c->walks == walks + 1);
    ri_tlbi(c);
    write_pte(c, leaf, 0x40, flags | RI_PTE_G);
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_OK);
    walks = c->walks;
    c->csr[RI_ASID].limb[0] = 3;
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_OK && c->walks == walks);
    ri_tlbi(c);
    write_pte(c, leaf, 0x40, flags & ~RI_PTE_W);
    CHECK(ri_translate(c, va, RI_WRITE, &pa) == RI_PERMISSION);
    ri_tlbi(c);
    write_pte(c, leaf, 0x40, flags & ~RI_PTE_A);
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_PERMISSION);
    ri_tlbi(c);
    write_pte(c, leaf, 0x40, flags & ~RI_PTE_D);
    CHECK(ri_translate(c, va, RI_WRITE, &pa) == RI_PERMISSION);
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_OK);
    CHECK(ri_translate(c, va, RI_WRITE, &pa) == RI_PERMISSION);
    ri_tlbi(c);
    write_pte(c, leaf, 0x40, flags);
    c->priv = RI_S;
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_PERMISSION);
    c->priv = RI_U;
    ri_tlbi(c);
    write_pte(c, leaf, 0x40, 0);
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_PTE_INVALID);
    ri_tlbi(c);
    write_pte(c, leaf, 0x40, flags);
    uint8_t reserved = 1;
    CHECK(ri_phys_write(&c->memory, leaf + 12, &reserved, 1));
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_PTE_RESERVED);
    write_pte(c, leaf, 0x40, flags);
    ri_tlbi(c);
    /* Cross-page: first page writable, second unmapped. No first-page bytes change. */
    ri_addr edge;
    CHECK(ri_addr_add(va, 4090, &edge));
    CHECK(ri_store(c, edge, b, 32) == RI_PTE_INVALID);
    CHECK(ri_phys_read(&c->memory, 0x40ffa, out, 6));
    for (unsigned i = 0; i < 6; i++)
        CHECK(out[i] == 0);
    ri_addr second;
    CHECK(ri_addr_add(va, 4096, &second));
    write_pte(c, leaf + 16, 0x41, flags);
    ri_tlbi(c);
    CHECK(ri_store(c, edge, b, 32) == RI_OK);
    CHECK(ri_load(c, edge, out, 32, RI_READ) == RI_OK && !memcmp(b, out, 32));
    /* Highest page: every VA bit is meaningful, no canonical-address restriction. */
    ri_addr highest = {UINT64_MAX - 4095, UINT64_MAX};
    map_va(c, highest, 0x10000, 0x40000, flags);
    ri_tlbi(c);
    CHECK(ri_translate(c, (ri_addr){UINT64_MAX, UINT64_MAX}, RI_READ, &pa) == RI_OK &&
          pa == 0x40fff);
    CHECK(ri_load(c, (ri_addr){UINT64_MAX, UINT64_MAX}, out, 2, RI_READ) == RI_OVERFLOW);
    for (unsigned bit = 0; bit < 128; bit++) {
        ri_addr probe = {bit < 64 ? UINT64_C(1) << (bit % 64) : 0,
                         bit >= 64 ? UINT64_C(1) << (bit % 64) : 0};
        map_va(c, probe, 0x10000, 0x40000, flags);
        ri_tlbi(c);
        CHECK(ri_translate(c, probe, RI_READ, &pa) == RI_OK &&
              pa == 0x40000 + (bit < 12 ? (UINT64_C(1) << bit) : 0));
    }
    CHECK(ri_memory_map(&c->memory, UINT64_MAX - 4095, 4096, true, false));
    map_va(c, (ri_addr){0, 0}, 0x10000, UINT64_MAX - 4095, flags);
    ri_tlbi(c);
    CHECK(ri_translate(c, (ri_addr){4095, 0}, RI_READ, &pa) == RI_OK && pa == UINT64_MAX);
    uint8_t last = 77;
    CHECK(ri_store(c, (ri_addr){4095, 0}, &last, 1) == RI_OK);
    last = 0;
    CHECK(ri_load(c, (ri_addr){4095, 0}, &last, 1, RI_READ) == RI_OK && last == 77);
    c->csr[RI_SATP].limb[0] = 0xdead0001;
    ri_tlbi(c);
    CHECK(ri_translate(c, va, RI_READ, &pa) == RI_PHYSICAL);
    destroy(c);
}
static void test_execution(void) {
    ri_cpu *c = new_cpu();
    CHECK(ri_memory_map(&c->memory, 0, 8192, true, false));
    write32(c, 0, ri_encode_i(RI_MOVI, 1, 0, 511, false));
    write32(c, 4, ri_encode_i(RI_ADDI, 2, 1, 1000, true));
    write32(c, 8, 0);
    write32(c, 12, ri_encode_r(RI_ADD, 63, 1, 2, 5));
    write32(c, 16, ri_encode_i(RI_WFI, 0, 0, 0, false));
    CHECK(ri_step(c) == RI_OK && c->r[1].limb[0] == 511 && c->pc.lo == 4);
    CHECK(ri_step(c) == RI_OK && c->r[2].limb[0] == 1511 && c->pc.lo == 12);
    CHECK(ri_step(c) == RI_OK && c->r[63].limb[0] == 2022);
    CHECK(ri_step(c) == RI_OK && c->waiting);
    c->waiting = false;
    c->pc = (ri_addr){32, 0};
    write32(c, 32, ri_encode_i(RI_SVC, 0, 0, 7, false));
    c->csr[RI_TVEC].limb[0] = 128;
    c->priv = RI_U;
    c->csr[RI_STATUS].limb[0] = 1;
    CHECK(ri_step(c) == RI_SVC_FAULT && c->priv == RI_M && c->pc.lo == 128 &&
          c->csr[RI_EPC].limb[0] == 32 && c->csr[RI_TVAL].limb[0] == 7);
    write32(c, 128, ri_encode_i(RI_ERET, 0, 0, 0, false));
    c->csr[RI_EPC].limb[0] = 36;
    CHECK(ri_step(c) == RI_OK && c->priv == RI_U && c->pc.lo == 36 &&
          (c->csr[RI_STATUS].limb[0] & 1));
    c->priv = RI_M;
    c->pc.lo = 40;
    write32(c, 40, ri_encode_i(RI_MOVI, 0, 0, 9, false));
    CHECK(ri_step(c) == RI_OK && !c->r[0].limb[0]);
    c->csr[RI_IE].limb[0] = 1;
    c->csr[RI_IP].limb[0] = 1;
    CHECK(ri_step(c) == RI_INTERRUPT && c->csr[RI_EPC].limb[0] == 44);
    destroy(c);
}
int main(void) {
    test_encoding();
    test_values();
    test_paging();
    test_execution();
    printf("PASS %u checks\n", checks);
    return 0;
}
