#include "../common/ringisa.h"
#include <stdlib.h>
#include <string.h>

static ri_page *page(ri_memory *m, uint64_t address) {
    uint64_t n = address >> 12;
    size_t lo = 0, hi = m->count;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (m->pages[mid].number < n)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo < m->count && m->pages[lo].number == n ? &m->pages[lo] : NULL;
}
static int compare_page(const void *a, const void *b) {
    const ri_page *x = a, *y = b;
    return x->number < y->number ? -1 : x->number > y->number ? 1 : 0;
}
bool ri_memory_map(ri_memory *m, uint64_t base, size_t length, bool writable, bool device) {
    if (!m || !length || (base & 4095) || (length & 4095) || length - 1 > UINT64_MAX - base)
        return false;
    size_t count = length / RI_PAGE_SIZE;
    if (count > RI_MAX_PAGES - m->count)
        return false;
    for (size_t i = 0; i < count; i++)
        if (page(m, base + (uint64_t)i * RI_PAGE_SIZE))
            return false;
    size_t needed = m->count + count;
    if (needed > m->capacity) {
        ri_page *p = realloc(m->pages, needed * sizeof(*p));
        if (!p)
            return false;
        m->pages = p;
        m->capacity = needed;
    }
    size_t old = m->count;
    for (size_t i = 0; i < count; i++) {
        uint8_t *data = calloc(RI_PAGE_SIZE, 1);
        if (!data) {
            while (m->count > old)
                free(m->pages[--m->count].data);
            return false;
        }
        m->pages[m->count++] = (ri_page){(base >> 12) + i, data, writable, device};
    }
    qsort(m->pages, m->count, sizeof(*m->pages), compare_page);
    return true;
}
static bool physical(ri_memory *m, uint64_t address, void *data, size_t length, bool write) {
    if (!m || !data || !length || length > 32 || length - 1 > UINT64_MAX - address)
        return false;
    for (size_t i = 0; i < length; i++) {
        ri_page *p = page(m, address + i);
        if (!p || (write && !p->writable))
            return false;
    }
    for (size_t i = 0; i < length; i++) {
        ri_page *p = page(m, address + i);
        if (write)
            p->data[(address + i) & 4095] = ((const uint8_t *)data)[i];
        else
            ((uint8_t *)data)[i] = p->data[(address + i) & 4095];
    }
    return true;
}
bool ri_phys_read(ri_memory *m, uint64_t a, void *d, size_t n) {
    return physical(m, a, d, n, false);
}
bool ri_phys_write(ri_memory *m, uint64_t a, const void *d, size_t n) {
    return physical(m, a, (void *)d, n, true);
}
void ri_cpu_init(ri_cpu *c) {
    if (!c)
        return;
    memset(c, 0, sizeof(*c));
    c->priv = RI_M;
}
void ri_cpu_destroy(ri_cpu *c) {
    if (!c)
        return;
    for (size_t i = 0; i < c->memory.count; i++)
        free(c->memory.pages[i].data);
    free(c->memory.pages);
    memset(c, 0, sizeof(*c));
}
void ri_tlbi(ri_cpu *c) {
    if (!c)
        return;
    memset(c->itlb, 0, sizeof(c->itlb));
    memset(c->dtlb, 0, sizeof(c->dtlb));
    memset(c->l2, 0, sizeof(c->l2));
    memset(c->pwc, 0, sizeof(c->pwc));
}
static ri_addr vpn(ri_addr a) {
    return (ri_addr){(a.lo >> 12) | (a.hi << 52), a.hi >> 12};
}
static unsigned index_at(ri_addr a, unsigned level) {
    unsigned shift = 12 + 8 * level;
    uint64_t x;
    if (shift >= 64)
        x = a.hi >> (shift - 64);
    else {
        x = a.lo >> shift;
        if (shift)
            x |= a.hi << (64 - shift);
    }
    return (unsigned)(x & (level == 14 ? 15 : 255));
}
static bool permitted(ri_cpu *c, unsigned flags, ri_access access) {
    if (c->priv == RI_U && !(flags & RI_PTE_U))
        return false;
    if (c->priv == RI_S && (flags & RI_PTE_U))
        return false;
    return (flags & (access == RI_FETCH  ? RI_PTE_X
                     : access == RI_READ ? RI_PTE_R
                                         : RI_PTE_W)) != 0 &&
           (flags & RI_PTE_A) && (access != RI_WRITE || (flags & RI_PTE_D));
}
static ri_tlb_entry *lookup(ri_cpu *c, ri_tlb_entry *table, size_t n, ri_addr tag, uint64_t root) {
    uint16_t asid = (uint16_t)c->csr[RI_ASID].limb[0];
    for (size_t i = 0; i < n; i++) {
        ri_tlb_entry *e = &table[i];
        if (e->valid && ri_addr_equal(e->vpn, tag) && e->root == root &&
            (e->global || e->asid == asid))
            return e;
    }
    return NULL;
}
ri_fault ri_translate(ri_cpu *c, ri_addr va, ri_access access, uint64_t *pa) {
    if (!c || !pa || access > RI_WRITE || c->priv > RI_M)
        return RI_ILLEGAL;
    uint64_t satp = c->csr[RI_SATP].limb[0], root = satp & ~UINT64_C(4095);
    c->translation_device = false;
    if (c->priv == RI_M || !(satp & 1)) {
        if (va.hi)
            return RI_PHYSICAL;
        *pa = va.lo;
        return RI_OK;
    }
    ri_addr tag = vpn(va);
    ri_tlb_entry *local = access == RI_FETCH ? c->itlb : c->dtlb;
    size_t count = access == RI_FETCH ? RI_ITLB_SIZE : RI_DTLB_SIZE;
    ri_tlb_entry *hit = lookup(c, local, count, tag, root);
    if (!hit)
        hit = lookup(c, c->l2, RI_L2_SIZE, tag, root);
    if (hit) {
        if (!permitted(c, hit->flags, access))
            return RI_PERMISSION;
        *pa = (hit->ppn << 12) | (va.lo & 4095);
        c->translation_device = hit->device;
        c->hits++;
        return RI_OK;
    }
    c->walks++;
    uint64_t table = root;
    unsigned flags = 0;
    uint64_t ppn = 0;
    bool global = false;
    for (int level = 14; level >= 0; level--) {
        uint64_t off = (uint64_t)index_at(va, (unsigned)level) * 16;
        if (table > UINT64_MAX - off)
            return RI_PHYSICAL;
        uint64_t address = table + off;
        /* Cache only table entries. OS updates require TLBI; cache tags include root/ASID. */
        ri_addr pte = {0, 0};
        bool cached = false;
        uint16_t asid = (uint16_t)c->csr[RI_ASID].limb[0];
        for (unsigned i = 0; i < RI_PWC_SIZE; i++) {
            ri_pwc_entry *e = &c->pwc[i];
            if (e->valid && e->address == address && e->root == root && e->asid == asid) {
                pte = e->pte;
                cached = true;
                break;
            }
        }
        if (!cached) {
            uint8_t raw[16];
            if (!ri_phys_read(&c->memory, address, raw, 16))
                return RI_PHYSICAL;
            for (unsigned i = 0; i < 8; i++) {
                pte.lo |= (uint64_t)raw[i] << (i * 8);
                pte.hi |= (uint64_t)raw[i + 8] << (i * 8);
            }
        }
        if (pte.hi >> 32)
            return RI_PTE_RESERVED;
        flags = (unsigned)(pte.lo & 4095);
        unsigned attr = (unsigned)((pte.lo >> 12) & 65535);
        if (!(flags & RI_PTE_V))
            return RI_PTE_INVALID;
        if ((flags & ~511u) || attr > 1 || (flags & RI_PTE_W && !(flags & RI_PTE_R)))
            return RI_PTE_RESERVED;
        ppn = (pte.lo >> 44) | ((pte.hi & UINT64_C(0xffffffff)) << 20);
        global = global || (flags & RI_PTE_G) != 0;
        if (flags & RI_PTE_T) {
            if (!level ||
                (flags & (RI_PTE_R | RI_PTE_W | RI_PTE_X | RI_PTE_U | RI_PTE_A | RI_PTE_D)) || attr)
                return RI_PTE_RESERVED;
            c->pwc[c->next_pwc++ % RI_PWC_SIZE] =
                (ri_pwc_entry){true, address, root, (uint16_t)c->csr[RI_ASID].limb[0], pte};
            table = ppn << 12;
            continue;
        }
        if (level)
            return RI_PTE_RESERVED;
        if (!permitted(c, flags, access))
            return RI_PERMISSION;
        /* Software-managed A/D: missing A or D faults, never updates guest tables. */
        if (!(flags & RI_PTE_A) || (access == RI_WRITE && !(flags & RI_PTE_D)))
            return RI_PERMISSION;
        ri_tlb_entry entry = {
            true, global,   tag, ppn, (uint16_t)c->csr[RI_ASID].limb[0], (uint16_t)flags,
            root, attr == 1};
        c->l2[c->next_l2++ % RI_L2_SIZE] = entry;
        unsigned slot =
            access == RI_FETCH ? c->next_i++ % RI_ITLB_SIZE : c->next_d++ % RI_DTLB_SIZE;
        local[slot] = entry;
        c->translation_device = attr == 1;
        *pa = (ppn << 12) | (va.lo & 4095);
        return RI_OK;
    }
    return RI_PTE_INVALID;
}
static ri_fault virtual_access(ri_cpu *c, ri_addr va, void *data, size_t n, ri_access access) {
    if (!c || !data || !n || n > 32 || access > RI_WRITE)
        return RI_ILLEGAL;
    uint64_t physical_addresses[32];
    ri_addr current = va;
    for (size_t i = 0; i < n; i++) {
        if (i && !ri_addr_add(va, (int64_t)i, &current)) {
            c->fault_address = va;
            return RI_OVERFLOW;
        }
        ri_fault fault = ri_translate(c, current, access, &physical_addresses[i]);
        if (fault) {
            c->fault_address = current;
            return fault;
        }
        ri_page *p = page(&c->memory, physical_addresses[i]);
        if (!p || (access == RI_WRITE && !p->writable)) {
            c->fault_address = current;
            return RI_PHYSICAL;
        }
        /* Device RAM is a deterministic stand-in bus region, never callbacks: aligned one-page
         * transactions. */
        if ((p->device || c->translation_device) && ((va.lo % n) || ((va.lo & 4095) + n > 4096))) {
            c->fault_address = va;
            return RI_ALIGN;
        }
    }
    for (size_t i = 0; i < n; i++) {
        ri_page *p = page(&c->memory, physical_addresses[i]);
        if (access == RI_WRITE)
            p->data[physical_addresses[i] & 4095] = ((uint8_t *)data)[i];
        else
            ((uint8_t *)data)[i] = p->data[physical_addresses[i] & 4095];
    }
    return RI_OK;
}
ri_fault ri_load(ri_cpu *c, ri_addr a, void *d, size_t n, ri_access access) {
    return virtual_access(c, a, d, n, access);
}
ri_fault ri_store(ri_cpu *c, ri_addr a, const void *d, size_t n) {
    return virtual_access(c, a, (void *)d, n, RI_WRITE);
}
