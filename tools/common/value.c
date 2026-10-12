#include "ringisa.h"
#include <ctype.h>
#include <stdio.h>
#include <string.h>

bool ri_addr_equal(ri_addr a, ri_addr b) {
    return a.lo == b.lo && a.hi == b.hi;
}
bool ri_addr_add(ri_addr a, int64_t delta, ri_addr *out) {
    if (!out)
        return false;
    ri_addr r = a;
    if (delta >= 0) {
        uint64_t n = (uint64_t)delta;
        r.lo += n;
        if (r.lo < a.lo) {
            if (a.hi == UINT64_MAX)
                return false;
            r.hi++;
        }
    } else {
        uint64_t n = 0 - (uint64_t)delta;
        r.lo -= n;
        if (a.lo < n) {
            if (!a.hi)
                return false;
            r.hi--;
        }
    }
    *out = r;
    return true;
}
bool ri_parse_word(const char *text, ri_word *out) {
    if (!text || !out)
        return false;
    ri_word r = {{0}};
    bool neg = false;
    unsigned base = 10, count = 0;
    if (*text == '-' || *text == '+') {
        neg = *text == '-';
        text++;
    }
    if (text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
        base = 16;
        text += 2;
    }
    for (; *text; text++) {
        unsigned char c = (unsigned char)*text;
        unsigned d;
        if (c >= '0' && c <= '9')
            d = c - '0';
        else if (c >= 'a' && c <= 'f')
            d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F')
            d = c - 'A' + 10;
        else
            return false;
        if (d >= base || ++count > 256)
            return false;
        uint64_t carry = d;
        for (unsigned i = 0; i < 4; i++) {
            uint64_t lo = r.limb[i] & UINT32_MAX, hi = r.limb[i] >> 32;
            uint64_t x = lo * base + carry;
            uint64_t y = hi * base + (x >> 32);
            r.limb[i] = (y << 32) | (x & UINT32_MAX);
            carry = y >> 32;
        }
        if (carry)
            return false;
    }
    if (!count)
        return false;
    if (neg) {
        uint64_t carry = 1;
        for (unsigned i = 0; i < 4; i++) {
            r.limb[i] = ~r.limb[i];
            uint64_t x = r.limb[i] + carry;
            carry = carry && x == 0;
            r.limb[i] = x;
        }
    }
    *out = r;
    return true;
}
void ri_format_word(ri_word v, char out[67]) {
    if (!out)
        return;
    (void)snprintf(out, 67, "0x%016llx%016llx%016llx%016llx", (unsigned long long)v.limb[3],
                   (unsigned long long)v.limb[2], (unsigned long long)v.limb[1],
                   (unsigned long long)v.limb[0]);
}
static unsigned bit(ri_word v, unsigned n) {
    return (unsigned)((v.limb[n / 64] >> (n % 64)) & 1);
}
static void putbit(ri_word *v, unsigned n, unsigned x) {
    v->limb[n / 64] |= (uint64_t)x << (n % 64);
}
static void narrow(ri_word *v, unsigned bits, bool sign) {
    unsigned s = sign ? bit(*v, bits - 1) : 0;
    for (unsigned n = bits; n < 256; n++) {
        uint64_t mask = UINT64_C(1) << (n % 64);
        if (s)
            v->limb[n / 64] |= mask;
        else
            v->limb[n / 64] &= ~mask;
    }
}
static int compare(ri_word a, ri_word b, unsigned bits, bool sign) {
    if (sign && bit(a, bits - 1) != bit(b, bits - 1))
        return bit(a, bits - 1) ? -1 : 1;
    for (unsigned n = bits; n > 0; n--)
        if (bit(a, n - 1) != bit(b, n - 1))
            return bit(a, n - 1) ? 1 : -1;
    return 0;
}
bool ri_alu(unsigned op, unsigned bits, ri_word a, ri_word b, ri_word *out) {
    if (!out || bits < 8 || bits > 256 || (bits & (bits - 1)) || op < RI_ADD || op > RI_MUL)
        return false;
    ri_word r = {{0}};
    unsigned carry = 0;
    if (op == RI_ADD || op == RI_SUB)
        for (unsigned n = 0; n < bits; n++) {
            unsigned x = bit(a, n), y = bit(b, n);
            if (op == RI_ADD) {
                unsigned sum = x + y + carry;
                putbit(&r, n, sum & 1);
                carry = sum >> 1;
            } else {
                unsigned borrow = x < y + carry;
                putbit(&r, n, (x - y - carry) & 1);
                carry = borrow;
            }
        }
    else if (op == RI_MUL) {
        for (unsigned j = 0; j < bits; j++)
            if (bit(b, j)) {
                carry = 0;
                for (unsigned n = j; n < bits; n++) {
                    unsigned sum = bit(r, n) + bit(a, n - j) + carry;
                    uint64_t mask = UINT64_C(1) << (n % 64);
                    r.limb[n / 64] = (r.limb[n / 64] & ~mask) | ((uint64_t)(sum & 1) << (n % 64));
                    carry = sum >> 1;
                }
            }
    } else if (op == RI_AND || op == RI_OR || op == RI_XOR)
        for (unsigned i = 0; i < 4; i++)
            r.limb[i] = op == RI_AND  ? (a.limb[i] & b.limb[i])
                        : op == RI_OR ? (a.limb[i] | b.limb[i])
                                      : (a.limb[i] ^ b.limb[i]);
    else if (op == RI_SLTU || op == RI_SLTS)
        r.limb[0] = compare(a, b, bits, op == RI_SLTS) < 0;
    else {
        unsigned shift = (unsigned)(b.limb[0] & (bits - 1));
        for (unsigned n = 0; n < bits; n++) {
            unsigned x = 0;
            if (op == RI_SHL) {
                if (n >= shift)
                    x = bit(a, n - shift);
            } else if (n + shift < bits)
                x = bit(a, n + shift);
            else if (op == RI_SAR)
                x = bit(a, bits - 1);
            putbit(&r, n, x);
        }
    }
    narrow(&r, bits, op == RI_SAR);
    *out = r;
    return true;
}
bool ri_simd(unsigned op, unsigned bits, ri_word a, ri_word b, ri_word *out) {
    if (!out || bits < 8 || bits > 64 || (bits & (bits - 1)) || op < RI_VADD || op > RI_VEQ)
        return false;
    ri_word r = {{0}};
    uint64_t mask = bits == 64 ? UINT64_MAX : ((UINT64_C(1) << bits) - 1);
    for (unsigned n = 0; n < 256; n += bits) {
        unsigned i = n / 64, s = n % 64;
        uint64_t x = (a.limb[i] >> s) & mask, y = (b.limb[i] >> s) & mask, z = 0;
        switch (op) {
        case RI_VADD:
            z = x + y;
            break;
        case RI_VSUB:
            z = x - y;
            break;
        case RI_VAND:
            z = x & y;
            break;
        case RI_VOR:
            z = x | y;
            break;
        case RI_VXOR:
            z = x ^ y;
            break;
        case RI_VMUL:
            z = x * y;
            break;
        case RI_VEQ:
            z = x == y ? mask : 0;
            break;
        default:
            break;
        }
        r.limb[i] |= (z & mask) << s;
    }
    *out = r;
    return true;
}
static const ri_meta *metadata(unsigned op) {
    for (size_t i = 0; i < RI_INSTRUCTION_COUNT; i++) {
        if (ri_instructions[i].op == op)
            return &ri_instructions[i];
    }
    return NULL;
}
uint32_t ri_encode_r(unsigned op, unsigned a, unsigned b, unsigned c, unsigned func) {
    const ri_meta *meta = metadata(op);
    if (!meta || meta->format != 'R' || a >= 64 || b >= 64 || c >= 64 ||
        func >= (meta->family == RI_SCALAR ? 6u : 4u))
        return 0;
    return (op << 24) | (a << 18) | (b << 12) | (c << 6) | (func << 2);
}
uint32_t ri_encode_i(unsigned op, unsigned a, unsigned b, int64_t imm, bool ext) {
    const ri_meta *meta = metadata(op);
    if (!meta || meta->format == 'R' || a >= 64 || b >= 64 ||
        (ext ? (imm < -(INT64_C(1) << 41) || imm >= (INT64_C(1) << 41))
             : (imm < -512 || imm > 511)))
        return 0;
    uint32_t word = (op << 24) | (a << 18) | (b << 12) | (((uint32_t)imm & 1023) << 2) |
                    (ext ? 1u : 0u);
    ri_inst decoded;
    return ri_decode(word, ext ? (uint32_t)((uint64_t)imm >> 10) : 0, &decoded) ? word : 0;
}
bool ri_decode(uint32_t w0, uint32_t w1, ri_inst *out) {
    if (!out)
        return false;
    ri_inst d = {0};
    unsigned l = w0 & 3;
    if (l > 1)
        return false;
    d.meta = metadata(w0 >> 24);
    if (!d.meta)
        return false;
    d.a = (w0 >> 18) & 63;
    d.b = (w0 >> 12) & 63;
    d.c = (w0 >> 6) & 63;
    d.func = (w0 >> 2) & 15;
    d.length = l ? 8 : 4;
    d.w0 = w0;
    d.w1 = w1;
    uint64_t raw = (w0 >> 2) & 1023;
    if (l)
        raw |= (uint64_t)w1 << 10;
    unsigned bits = l ? 42 : 10;
    d.imm = (raw & (UINT64_C(1) << (bits - 1))) ? -(int64_t)((UINT64_C(1) << bits) - raw)
                                                : (int64_t)raw;
    if (d.meta->format == 'R' && (l || d.func >= (d.meta->family == RI_SCALAR ? 6u : 4u)))
        return false;
    if (d.meta->format == 'X' && (!l || d.b || ((w0 >> 2) & 1023) > 7))
        return false;
    if (d.meta->op == RI_MOVI && d.b)
        return false;
    switch (d.meta->op) {
    case RI_SVC:
    case RI_BRK:
        if (d.a || d.b || d.imm < 0)
            return false;
        break;
    case RI_ERET:
    case RI_WFI:
    case RI_FENCE:
    case RI_TLBI:
        if (l || d.a || d.b || d.imm)
            return false;
        break;
    case RI_CSRR:
        if (l || d.b || d.imm < 0 || d.imm >= RI_CSR_COUNT)
            return false;
        break;
    case RI_CSRW:
        if (l || d.a || d.imm < 0 || d.imm >= RI_CSR_COUNT)
            return false;
        break;
    default:
        break;
    }
    *out = d;
    return true;
}
