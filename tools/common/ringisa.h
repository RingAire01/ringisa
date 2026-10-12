#ifndef RINGISA_H
#define RINGISA_H
#include "generated.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum {
    RI_MAX_PAGES = 16384,
    RI_ITLB_SIZE = 32,
    RI_DTLB_SIZE = 64,
    RI_L2_SIZE = 512,
    RI_PWC_SIZE = 32
};
typedef struct {
    uint64_t lo, hi;
} ri_addr;
typedef struct {
    uint64_t limb[4];
} ri_word;
typedef struct {
    const ri_meta *meta;
    unsigned a, b, c, func, length;
    int64_t imm;
    uint32_t w0, w1;
} ri_inst;
typedef enum { RI_U = 0, RI_S = 1, RI_M = 2 } ri_priv;
typedef enum { RI_FETCH = 0, RI_READ = 1, RI_WRITE = 2 } ri_access;
typedef enum {
    RI_OK = 0,
    RI_ILLEGAL = 1,
    RI_FETCH_FAULT = 2,
    RI_LOAD_FAULT = 3,
    RI_STORE_FAULT = 4,
    RI_OVERFLOW = 5,
    RI_ALIGN = 6,
    RI_PTE_INVALID = 7,
    RI_PTE_RESERVED = 8,
    RI_PERMISSION = 9,
    RI_PHYSICAL = 10,
    RI_SVC_FAULT = 11,
    RI_BREAK = 12,
    RI_PRIVILEGE = 13,
    RI_INTERRUPT = 14
} ri_fault;
typedef struct {
    uint64_t number;
    uint8_t *data;
    bool writable, device;
} ri_page;
typedef struct {
    ri_page *pages;
    size_t count, capacity;
} ri_memory;
typedef struct {
    bool valid, global;
    ri_addr vpn;
    uint64_t ppn;
    uint16_t asid, flags;
    uint64_t root;
    bool device;
} ri_tlb_entry;
typedef struct {
    bool valid;
    uint64_t address, root;
    uint16_t asid;
    ri_addr pte;
} ri_pwc_entry;
typedef struct {
    ri_word r[64], csr[RI_CSR_COUNT];
    ri_addr pc;
    ri_priv priv;
    ri_memory memory;
    ri_tlb_entry itlb[RI_ITLB_SIZE], dtlb[RI_DTLB_SIZE], l2[RI_L2_SIZE];
    ri_pwc_entry pwc[RI_PWC_SIZE];
    unsigned next_i, next_d, next_l2, next_pwc;
    bool waiting, trapped, translation_device;
    ri_fault last_fault;
    ri_addr fault_address;
    uint64_t steps, walks, hits;
    bool trace;
} ri_cpu;
bool ri_addr_add(ri_addr a, int64_t delta, ri_addr *out);
bool ri_addr_equal(ri_addr a, ri_addr b);
bool ri_parse_word(const char *text, ri_word *out);
void ri_format_word(ri_word value, char out[67]);
bool ri_decode(uint32_t w0, uint32_t w1, ri_inst *out);
uint32_t ri_encode_r(unsigned op, unsigned a, unsigned b, unsigned c, unsigned func);
uint32_t ri_encode_i(unsigned op, unsigned a, unsigned b, int64_t imm, bool extended);
bool ri_alu(unsigned op, unsigned bits, ri_word a, ri_word b, ri_word *out);
bool ri_simd(unsigned op, unsigned bits, ri_word a, ri_word b, ri_word *out);
void ri_cpu_init(ri_cpu *cpu);
void ri_cpu_destroy(ri_cpu *cpu);
bool ri_memory_map(ri_memory *mem, uint64_t base, size_t length, bool writable, bool device);
bool ri_phys_read(ri_memory *mem, uint64_t address, void *out, size_t length);
bool ri_phys_write(ri_memory *mem, uint64_t address, const void *data, size_t length);
ri_fault ri_translate(ri_cpu *cpu, ri_addr va, ri_access access, uint64_t *pa);
void ri_tlbi(ri_cpu *cpu);
ri_fault ri_load(ri_cpu *cpu, ri_addr va, void *out, size_t length, ri_access access);
ri_fault ri_store(ri_cpu *cpu, ri_addr va, const void *data, size_t length);
void ri_exception(ri_cpu *cpu, ri_fault fault, ri_addr value);
ri_fault ri_step(ri_cpu *cpu);
#endif
