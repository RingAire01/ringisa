#include "../../tools/common/ringisa.h"
#include <stdio.h>
#include <stdlib.h>

static int fail_at = -1, calls, live;
void *ri_test_calloc(size_t n, size_t size) {
    if (calls++ == fail_at)
        return NULL;
    void *p = calloc(n, size);
    if (p)
        live++;
    return p;
}
void *ri_test_realloc(void *old, size_t size) {
    if (calls++ == fail_at)
        return NULL;
    bool new_allocation = old == NULL;
    void *p = realloc(old, size);
    if (p && new_allocation)
        live++;
    return p;
}
void ri_test_free(void *p) {
    if (p)
        live--;
    free(p);
}
int main(void) {
    for (int failure = 0; failure < 5; failure++) {
        ri_cpu cpu;
        ri_cpu_init(&cpu);
        fail_at = failure;
        calls = 0;
        bool ok = ri_memory_map(&cpu.memory, 0, 3 * 4096, true, false);
        if (ok != (failure >= 4) || (!ok && cpu.memory.count != 0)) {
            fprintf(stderr, "allocation rollback failed at%d\n", failure);
            return 1;
        }
        fail_at = -1;
        ri_cpu_destroy(&cpu);
        if (live) {
            fprintf(stderr, "leak after failure%d: %d\n", failure, live);
            return 1;
        }
    }
    ri_cpu cpu;
    ri_cpu_init(&cpu);
    calls = 0;
    fail_at = -1;
    if (!ri_memory_map(&cpu.memory, 0, 4096, true, false))
        return 1;
    uint8_t value = 123;
    if (!ri_phys_write(&cpu.memory, 0, &value, 1))
        return 1;
    calls = 0;
    fail_at = 0;
    if (ri_memory_map(&cpu.memory, 4096, 4096, true, false) || cpu.memory.count != 1)
        return 1;
    uint8_t got = 0;
    if (!ri_phys_read(&cpu.memory, 0, &got, 1) || got != 123)
        return 1;
    fail_at = -1;
    ri_cpu_destroy(&cpu);
    if (live)
        return 1;
    puts("PASS allocation failure injection, rollback, existing memory preservation, no tracked "
         "leaks");
    return 0;
}
