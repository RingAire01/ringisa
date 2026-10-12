#ifndef RI_IO_H
#define RI_IO_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
enum {
    RI_MAX_FILE = 16 * 1024 * 1024,
    RI_MAX_LINES = 131072,
    RI_MAX_LINE = 4096,
    RI_MAX_SYMBOLS = 4096
};
uint8_t *ri_read_file(const char *path, size_t *size);
bool ri_write_file(const char *path, const void *data, size_t size);
#endif
