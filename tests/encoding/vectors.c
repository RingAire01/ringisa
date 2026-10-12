#include "../../tools/common/ringisa.h"
#include <stdint.h>
#include <stdio.h>
static uint32_t rng = UINT32_C(0x52495341);
static uint32_t random32(void) {
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}
static void emit(uint32_t w0, uint32_t w1) {
    ri_inst d;
    printf("%x%08x%08x\n", ri_decode(w0, w1, &d) ? 1 : 0, w1, w0);
}
int main(void) {
    for (unsigned op = 0; op < 256; op++)
        for (unsigned length = 0; length < 4; length++)
            for (unsigned func = 0; func < 16; func++)
                emit((op << 24) | (func << 2) | length, 0);
    for (unsigned i = 0; i < 10000; i++)
        emit(random32(), random32());
    return ferror(stdout) ? 1 : 0;
}
