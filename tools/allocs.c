// LD_PRELOAD heap-allocation counter: prints "allocs N" to stderr at exit. N counts every
// malloc/calloc/realloc/memalign-family call and every Mojo KGEN_CompilerRT_AlignedAlloc, so a run of K more calls that adds 0 proves zero allocation.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
extern void *__libc_malloc(size_t), *__libc_calloc(size_t, size_t), *__libc_realloc(void *, size_t), *__libc_memalign(size_t, size_t);
static volatile unsigned long n;
void *malloc(size_t s) { __atomic_add_fetch(&n, 1, __ATOMIC_RELAXED); return __libc_malloc(s); }
void *calloc(size_t a, size_t b) { __atomic_add_fetch(&n, 1, __ATOMIC_RELAXED); return __libc_calloc(a, b); }
void *realloc(void *p, size_t s) { __atomic_add_fetch(&n, 1, __ATOMIC_RELAXED); return __libc_realloc(p, s); }
void *memalign(size_t a, size_t s) { __atomic_add_fetch(&n, 1, __ATOMIC_RELAXED); return __libc_memalign(a, s); }
void *aligned_alloc(size_t a, size_t s) { __atomic_add_fetch(&n, 1, __ATOMIC_RELAXED); return __libc_memalign(a, s); }
int posix_memalign(void **r, size_t a, size_t s) { __atomic_add_fetch(&n, 1, __ATOMIC_RELAXED); void *p = __libc_memalign(a, s); if (!p) return 12; *r = p; return 0; }
void *KGEN_CompilerRT_AlignedAlloc(size_t a, size_t s) {  // Mojo's allocator entry
    static void *(*real)(size_t, size_t);
    if (!real) real = dlsym(RTLD_NEXT, "KGEN_CompilerRT_AlignedAlloc");
    __atomic_add_fetch(&n, 1, __ATOMIC_RELAXED);
    return real(a, s);
}
__attribute__((destructor)) static void report(void) { fprintf(stderr, "allocs %lu\n", n); }
