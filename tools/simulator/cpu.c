#include "../common/ringisa.h"
#include <stdio.h>
#include <string.h>

static ri_addr address(ri_word v) {
    return (ri_addr){v.limb[0], v.limb[1]};
}
static ri_word addrword(ri_addr a) {
    return (ri_word){{a.lo, a.hi, 0, 0}};
}
static uint32_t little32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
void ri_exception(ri_cpu *c, ri_fault fault, ri_addr value) {
    if (!c)
        return;
    uint64_t status = c->csr[RI_STATUS].limb[0];
    c->csr[RI_EPC] = addrword(c->pc);
    c->csr[RI_TVAL] = addrword(value);
    c->csr[RI_CAUSE] = (ri_word){{(uint64_t)fault, 0, 0, 0}};
    c->csr[RI_STATUS].limb[0] =
        (status & ~UINT64_C(31)) | ((uint64_t)c->priv << 1) | ((status & 1) << 3) | 16;
    c->priv = RI_M;
    c->pc = address(c->csr[RI_TVEC]);
    c->waiting = false;
    c->trapped = true;
    c->last_fault = fault;
}
ri_fault ri_step(ri_cpu *c) {
    if (!c)
        return RI_ILLEGAL;
    memset(&c->r[0], 0, sizeof(c->r[0]));
    ri_fault fault = RI_OK;
    ri_addr tval = c->pc, next = {0, 0};
    ri_word result = {{0}};
    bool write = false;
    c->trapped = false;
    if ((c->csr[RI_STATUS].limb[0] & 1) && (c->csr[RI_IE].limb[0] & c->csr[RI_IP].limb[0])) {
        ri_exception(c, RI_INTERRUPT, (ri_addr){0, 0});
        return RI_INTERRUPT;
    }
    if (c->waiting)
        return RI_OK;
    if (c->pc.lo & 3) {
        fault = RI_ALIGN;
        goto trap;
    }
    uint8_t raw[8] = {0};
    fault = ri_load(c, c->pc, raw, 4, RI_FETCH);
    if (fault) {
        tval = c->fault_address;
        goto trap;
    }
    uint32_t w0 = little32(raw), w1 = 0;
    if ((w0 & 3) == 1) {
        ri_addr extension;
        if (!ri_addr_add(c->pc, 4, &extension)) {
            fault = RI_OVERFLOW;
            goto trap;
        }
        fault = ri_load(c, extension, raw + 4, 4, RI_FETCH);
        if (fault) {
            tval = c->fault_address;
            goto trap;
        }
        w1 = little32(raw + 4);
    }
    ri_inst d;
    if (!ri_decode(w0, w1, &d)) {
        fault = RI_ILLEGAL;
        tval = (ri_addr){w0, 0};
        goto trap;
    }
    if (!ri_addr_add(c->pc, d.length, &next)) {
        fault = RI_OVERFLOW;
        goto trap;
    }
    unsigned op = d.meta->op;
    if (c->trace)
        fprintf(stderr, "%016llx%016llx %s R%u,R%u imm=%lld\n", (unsigned long long)c->pc.hi,
                (unsigned long long)c->pc.lo, d.meta->name, d.a, d.b, (long long)d.imm);
    if (d.meta->family == RI_SCALAR) {
        ri_alu(op, 8u << d.func, c->r[d.b], c->r[d.c], &result);
        write = true;
    } else if (d.meta->family == RI_SIMD) {
        ri_simd(op, 8u << d.func, c->r[d.b], c->r[d.c], &result);
        write = true;
    } else if (d.meta->family == RI_LOAD || d.meta->family == RI_STORE) {
        ri_addr ea;
        if (!ri_addr_add(address(c->r[d.b]), d.imm, &ea)) {
            fault = RI_OVERFLOW;
            tval = address(c->r[d.b]);
            goto trap;
        }
        unsigned n = d.meta->bits / 8;
        uint8_t bytes[32];
        if (d.meta->family == RI_LOAD) {
            fault = ri_load(c, ea, bytes, n, RI_READ);
            if (fault) {
                tval = c->fault_address;
                goto trap;
            }
            for (unsigned i = 0; i < n; i++)
                result.limb[i / 8] |= (uint64_t)bytes[i] << (8 * (i % 8));
            if (d.meta->sign && (bytes[n - 1] & 128))
                for (unsigned i = n; i < 32; i++)
                    result.limb[i / 8] |= UINT64_C(255) << (8 * (i % 8));
            write = true;
        } else {
            for (unsigned i = 0; i < n; i++)
                bytes[i] = (uint8_t)(c->r[d.a].limb[i / 8] >> (8 * (i % 8)));
            fault = ri_store(c, ea, bytes, n);
            if (fault) {
                tval = c->fault_address;
                goto trap;
            }
        }
    } else if (d.meta->family == RI_BRANCH) {
        bool taken = false;
        ri_word cmp;
        if (op == RI_BEQ || op == RI_BNE) {
            taken = memcmp(&c->r[d.a], &c->r[d.b], sizeof(ri_word)) == 0;
            if (op == RI_BNE)
                taken = !taken;
        } else {
            ri_alu(op == RI_BLTU ? RI_SLTU : RI_SLTS, 256, c->r[d.a], c->r[d.b], &cmp);
            taken = cmp.limb[0] != 0;
        }
        if (taken) {
            if (!ri_addr_add(c->pc, d.imm * 4, &next)) {
                fault = RI_OVERFLOW;
                goto trap;
            }
        }
    } else
        switch (op) {
        case RI_ADDI: {
            ri_word immediate = {{(uint64_t)d.imm, d.imm < 0 ? UINT64_MAX : 0,
                                  d.imm < 0 ? UINT64_MAX : 0, d.imm < 0 ? UINT64_MAX : 0}};
            ri_alu(RI_ADD, 256, c->r[d.b], immediate, &result);
            write = true;
            break;
        }
        case RI_MOVI:
            result = (ri_word){{(uint64_t)d.imm, d.imm < 0 ? UINT64_MAX : 0,
                                d.imm < 0 ? UINT64_MAX : 0, d.imm < 0 ? UINT64_MAX : 0}};
            write = true;
            break;
        case RI_CHUNK: {
            result = c->r[d.a];
            unsigned index = (d.w0 >> 2) & 1023, shift = (index % 2) * 32;
            uint64_t mask = UINT64_C(0xffffffff) << shift;
            result.limb[index / 2] = (result.limb[index / 2] & ~mask) | ((uint64_t)d.w1 << shift);
            write = true;
            break;
        }
        case RI_JAL: {
            ri_addr base = d.b ? address(c->r[d.b]) : c->pc;
            ri_addr target;
            if (!ri_addr_add(base, d.imm * 4, &target)) {
                fault = RI_OVERFLOW;
                tval = base;
                goto trap;
            }
            if (target.lo & 3) {
                fault = RI_ALIGN;
                tval = target;
                goto trap;
            }
            result = addrword(next);
            next = target;
            write = true;
            break;
        }
        case RI_SVC:
            fault = RI_SVC_FAULT;
            tval = (ri_addr){(uint64_t)d.imm, 0};
            goto trap;
        case RI_BRK:
            fault = RI_BREAK;
            tval = (ri_addr){(uint64_t)d.imm, 0};
            goto trap;
        case RI_ERET: {
            uint64_t status = c->csr[RI_STATUS].limb[0];
            if (c->priv != RI_M || !(status & 16)) {
                fault = RI_PRIVILEGE;
                goto trap;
            }
            unsigned previous = (unsigned)((status >> 1) & 3);
            if (previous > 2) {
                fault = RI_ILLEGAL;
                goto trap;
            }
            next = address(c->csr[RI_EPC]);
            if (next.lo & 3) {
                fault = RI_ALIGN;
                tval = next;
                goto trap;
            }
            c->priv = (ri_priv)previous;
            c->csr[RI_STATUS].limb[0] = (status & ~UINT64_C(31)) | ((status >> 3) & 1);
            break;
        }
        case RI_WFI:
            if (c->priv == RI_U) {
                fault = RI_PRIVILEGE;
                goto trap;
            }
            c->waiting = true;
            break;
        case RI_FENCE:
            break;
        case RI_TLBI:
            if (c->priv == RI_U) {
                fault = RI_PRIVILEGE;
                goto trap;
            }
            ri_tlbi(c);
            break;
        case RI_CSRR:
        case RI_CSRW: {
            unsigned csr = (unsigned)d.imm;
            if (c->priv != RI_M) {
                fault = RI_PRIVILEGE;
                goto trap;
            }
            if (op == RI_CSRR) {
                result = c->csr[csr];
                write = true;
            } else {
                ri_word v = c->r[d.b];
                bool bad = false;
                if (csr == RI_EPC || csr == RI_TVAL || csr == RI_TVEC)
                    bad = v.limb[2] || v.limb[3] || (csr != RI_TVAL && (v.limb[0] & 3));
                else {
                    bad = v.limb[1] || v.limb[2] || v.limb[3];
                    if (csr == RI_SATP)
                        bad = bad || (v.limb[0] & 4094);
                    if (csr == RI_ASID)
                        bad = bad || v.limb[0] > 65535;
                    if (csr == RI_STATUS)
                        bad = bad || (v.limb[0] & ~UINT64_C(31)) || ((v.limb[0] >> 1) & 3) == 3;
                }
                if (bad) {
                    fault = RI_ILLEGAL;
                    goto trap;
                }
                c->csr[csr] = v; /* SATP/ASID changes don't flush: tags isolate contexts; TLBI
                                    publishes edits. */
            }
            break;
        }
        default:
            fault = RI_ILLEGAL;
            goto trap;
        }
    if (write && d.a)
        c->r[d.a] = result;
    memset(&c->r[0], 0, sizeof(c->r[0]));
    c->pc = next;
    c->steps++;
    return RI_OK;
trap:
    ri_exception(c, fault, tval);
    return fault;
}
