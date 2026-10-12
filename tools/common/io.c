#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif
#include "io.h"
#include "ringisa.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <io.h>
#include <windows.h>
#else
#include <unistd.h>
#endif
uint8_t *ri_read_file(const char *path, size_t *size) {
    if (!path || !size)
        return NULL;
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    uint8_t *data = malloc(RI_MAX_FILE + 1);
    if (!data) {
        fclose(f);
        return NULL;
    }
    size_t n = fread(data, 1, RI_MAX_FILE + 1, f);
    bool good = !ferror(f) && n <= RI_MAX_FILE;
    if (fclose(f))
        good = false;
    if (!good) {
        free(data);
        return NULL;
    }
    data[n] = 0;
    *size = n;
    return data;
}
bool ri_write_file(const char *path, const void *data, size_t size) {
    if (!path || !data || size > RI_MAX_FILE)
        return false;
    size_t len = strlen(path);
    if (len > 32700)
        return false;
    char *temp = malloc(len + 64);
    if (!temp)
        return false;
    FILE *f = NULL;
    for (unsigned i = 0; i < 100; i++) {
#if defined(_WIN32)
        unsigned long pid = GetCurrentProcessId();
#else
        unsigned long pid = (unsigned long)getpid();
#endif
        (void)snprintf(temp, len + 64, "%s.tmp.%lu.%u", path, pid, i);
        f = fopen(temp, "wbx");
        if (f)
            break;
        if (errno != EEXIST)
            break;
    }
    if (!f) {
        free(temp);
        return false;
    }
    bool good = fwrite(data, 1, size, f) == size;
    if (fflush(f))
        good = false;
#if defined(_WIN32)
    if (_commit(_fileno(f)))
        good = false;
#else
    if (fsync(fileno(f)))
        good = false;
#endif
    if (fclose(f))
        good = false;
    if (good) {
#if defined(_WIN32)
        good = MoveFileExA(temp, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
        good = rename(temp, path) == 0;
#endif
    }
    if (!good)
        remove(temp);
    free(temp);
    return good;
}
