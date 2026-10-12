#include "../common/io.h"
#include "../common/ringisa.h"
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *name;
    size_t offset;
} symbol;
typedef struct {
    char *text;
    size_t line, offset;
} source_line;
static bool reg(const char *s, unsigned *out) {
    if (!s || (*s != 'R' && *s != 'r') || !isdigit((unsigned char)s[1]))
        return false;
    char *end;
    errno = 0;
    unsigned long n = strtoul(s + 1, &end, 10);
    if (errno || *end || n > 63)
        return false;
    *out = (unsigned)n;
    return true;
}
static bool integer(const char *s, int64_t *out) {
    if (!s)
        return false;
    char *end;
    errno = 0;
    long long n = strtoll(s, &end, 0);
    if (errno || end == s || *end)
        return false;
    *out = (int64_t)n;
    return true;
}
static char *trim(char *s) {
    while (isspace((unsigned char)*s))
        s++;
    char *end = s + strlen(s);
    while (end > s && isspace((unsigned char)end[-1]))
        *--end = 0;
    return s;
}
static unsigned tokenize(char *s, char **tokens) {
    unsigned n = 0;
    char *t = strtok(s, " ,\t\r");
    while (t) {
        if (n == 6)
            return 7;
        tokens[n++] = t;
        t = strtok(NULL, " ,\t\r");
    }
    return n;
}
static void put32(uint8_t *p, uint32_t w) {
    for (unsigned i = 0; i < 4; i++)
        p[i] = (uint8_t)(w >> (8 * i));
}
static const ri_meta *find(char *name, unsigned *func, bool *force) {
    *func = 5;
    *force = false;
    size_t n = strlen(name);
    if (n > 2 && !strcmp(name + n - 2, ".X")) {
        *force = true;
        name[n - 2] = 0;
    }
    for (size_t i = 0; i < RI_INSTRUCTION_COUNT; i++)
        if (!strcmp(name, ri_instructions[i].name)) {
            if (ri_instructions[i].family == RI_SIMD)
                *func = 3;
            return &ri_instructions[i];
        }
    char *dot = strrchr(name, '.');
    if (!dot)
        return NULL;
    int64_t bits;
    if (!integer(dot + 1, &bits))
        return NULL;
    *dot = 0;
    for (size_t i = 0; i < RI_INSTRUCTION_COUNT; i++)
        if (!strcmp(name, ri_instructions[i].name) && ri_instructions[i].format == 'R') {
            for (unsigned j = 0; j < (ri_instructions[i].family == RI_SCALAR ? 6u : 4u); j++)
                if (bits == (8LL << j)) {
                    *func = j;
                    return &ri_instructions[i];
                }
            return NULL;
        }
    return NULL;
}
int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: ringisa-as input.s output.bin\n");
        return 2;
    }
    size_t size;
    uint8_t *input = ri_read_file(argv[1], &size);
    if (!input) {
        fprintf(stderr, "cannot read source (limit 16 MiB)\n");
        return 1;
    }
    if (memchr(input, 0, size)) {
        fprintf(stderr, "source contains NUL\n");
        free(input);
        return 1;
    }
    source_line *lines = calloc(RI_MAX_LINES, sizeof(*lines));
    symbol *symbols = calloc(RI_MAX_SYMBOLS, sizeof(*symbols));
    uint8_t *output = calloc(RI_MAX_FILE, 1);
    if (!lines || !symbols || !output) {
        fprintf(stderr, "out of memory\n");
        free(input);
        free(lines);
        free(symbols);
        free(output);
        return 1;
    }
    size_t nl = 0, ns = 0, offset = 0, line_number = 0;
    char *cursor = (char *)input;
    bool good = true;
    while (cursor && (size_t)(cursor - (char *)input) < size) {
        char *next = strchr(cursor, '\n');
        if (next)
            *next++ = 0;
        line_number++;
        if (strlen(cursor) > RI_MAX_LINE || nl >= RI_MAX_LINES) {
            good = false;
            break;
        }
        char *comment = strchr(cursor, ';');
        if (comment)
            *comment = 0;
        comment = strchr(cursor, '#');
        if (comment)
            *comment = 0;
        char *s = trim(cursor);
        char *colon = strchr(s, ':');
        if (colon) {
            *colon = 0;
            char *name = trim(s);
            if (!*name || ns >= RI_MAX_SYMBOLS) {
                good = false;
                break;
            }
            for (char *p = name; *p; p++)
                if (!isalnum((unsigned char)*p) && *p != '_') {
                    good = false;
                    break;
                }
            for (size_t i = 0; i < ns; i++)
                if (!strcmp(symbols[i].name, name))
                    good = false;
            if (!good)
                break;
            symbols[ns++] = (symbol){name, offset};
            s = trim(colon + 1);
        }
        if (*s) {
            lines[nl++] = (source_line){s, line_number, offset};
            char copy[RI_MAX_LINE + 1];
            strcpy(copy, s);
            char *t[6];
            unsigned nt = tokenize(copy, t);
            if (!nt || nt > 6) {
                good = false;
                break;
            }
            unsigned func;
            bool force;
            const ri_meta *m = find(t[0], &func, &force);
            size_t len = 4;
            if (!strcmp(t[0], "CONST128"))
                len = 32;
            else if (!strcmp(t[0], "CONST256"))
                len = 64;
            else if (!strcmp(t[0], ".word"))
                len = 4;
            else if (!m) {
                good = false;
                break;
            } else if (m->format == 'X' || force)
                len = 8;
            else if (m->format != 'R' && nt > 1) {
                int64_t imm;
                if (integer(t[nt - 1], &imm)) {
                    if (imm < -512 || imm > 511)
                        len = 8;
                } else if (m->family == RI_BRANCH || m->op == RI_JAL)
                    len = 8;
            }
            if (offset > RI_MAX_FILE - len) {
                good = false;
                break;
            }
            offset += len;
        }
        cursor = next;
    }
    if (!good)
        fprintf(stderr, "%s:%zu: invalid instruction, duplicate label or resource limit\n", argv[1],
                line_number);
    for (size_t i = 0; good && i < nl; i++) {
        source_line l = lines[i];
        char *t[6];
        unsigned nt = tokenize(l.text, t);
        unsigned a = 0, b = 0, c = 0, func = 0;
        bool force = false;
        int64_t imm = 0;
        uint32_t w0 = 0, w1 = 0;
        size_t length = (i + 1 < nl ? lines[i + 1].offset : offset) - l.offset;
        if (!strcmp(t[0], ".word")) {
            ri_word v;
            if (nt != 2 || !ri_parse_word(t[1], &v) || v.limb[0] > UINT32_MAX || v.limb[1] ||
                v.limb[2] || v.limb[3])
                good = false;
            else
                put32(output + l.offset, (uint32_t)v.limb[0]);
            continue;
        }
        if (!strcmp(t[0], "CONST128") || !strcmp(t[0], "CONST256")) {
            ri_word v;
            unsigned chunks = !strcmp(t[0], "CONST128") ? 4 : 8;
            if (nt != 3 || !reg(t[1], &a) || !ri_parse_word(t[2], &v) ||
                (chunks == 4 && (v.limb[2] || v.limb[3])))
                good = false;
            else
                for (unsigned j = 0; j < chunks; j++) {
                    put32(output + l.offset + j * 8, ri_encode_i(RI_CHUNK, a, 0, j, true));
                    put32(output + l.offset + j * 8 + 4,
                          (uint32_t)(v.limb[j / 2] >> ((j % 2) * 32)));
                }
            continue;
        }
        const ri_meta *m = find(t[0], &func, &force);
        if (!m) {
            good = false;
            break;
        }
        if (m->format == 'R') {
            good = nt == 4 && reg(t[1], &a) && reg(t[2], &b) && reg(t[3], &c);
            if (good)
                w0 = ri_encode_r(m->op, a, b, c, func);
        } else if (m->op == RI_CHUNK) {
            ri_word value;
            good = nt == 4 && reg(t[1], &a) && integer(t[2], &imm) && imm >= 0 && imm <= 7 &&
                   ri_parse_word(t[3], &value) && value.limb[0] <= UINT32_MAX && !value.limb[1] &&
                   !value.limb[2] && !value.limb[3];
            if (good) {
                w0 = ri_encode_i(m->op, a, 0, imm, true);
                w1 = (uint32_t)value.limb[0];
            }
        } else {
            const char *operand = NULL;
            if (m->op == RI_ERET || m->op == RI_WFI || m->op == RI_FENCE || m->op == RI_TLBI)
                good = nt == 1;
            else if (m->op == RI_SVC || m->op == RI_BRK) {
                good = nt == 2;
                if (good)
                    operand = t[1];
            } else if (m->op == RI_MOVI || m->op == RI_CSRR) {
                good = nt == 3 && reg(t[1], &a);
                if (good)
                    operand = t[2];
            } else if (m->op == RI_CSRW) {
                good = nt == 3 && reg(t[1], &b);
                if (good)
                    operand = t[2];
            } else {
                good = nt == 4 && reg(t[1], &a) && reg(t[2], &b);
                if (good)
                    operand = t[3];
            }
            if (good && operand && !integer(operand, &imm)) {
                bool found = false;
                if (m->family == RI_BRANCH || m->op == RI_JAL) {
                    for (size_t j = 0; j < ns; j++)
                        if (!strcmp(symbols[j].name, operand)) {
                            int64_t delta = (int64_t)symbols[j].offset - (int64_t)l.offset;
                            imm = delta / 4;
                            found = delta % 4 == 0;
                            break;
                        }
                }
                good = found;
            }
            if (good) {
                bool ext = length == 8;
                good = ext ? (imm >= -(INT64_C(1) << 41) && imm < (INT64_C(1) << 41))
                           : (imm >= -512 && imm <= 511);
                w0 = ri_encode_i(m->op, a, b, imm, ext);
                w1 = (uint32_t)((uint64_t)imm >> 10);
            }
        }
        ri_inst decoded;
        if (good)
            good = ri_decode(w0, w1, &decoded) && decoded.length == length;
        if (good) {
            put32(output + l.offset, w0);
            if (length == 8)
                put32(output + l.offset + 4, w1);
        } else
            fprintf(stderr, "%s:%zu: invalid operands or immediate\n", argv[1], l.line);
    }
    if (!good)
        fprintf(stderr, "assembly failed; previous output preserved\n");
    if (good) {
        good = ri_write_file(argv[2], output, offset);
        if (!good)
            fprintf(stderr, "cannot publish output\n");
    }
    free(output);
    free(symbols);
    free(lines);
    free(input);
    return good ? 0 : 1;
}
