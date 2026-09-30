#ifndef VIEWER_PIXEL_COPY_H
#define VIEWER_PIXEL_COPY_H
#include <stddef.h>
#include <stdint.h>

/* PIXEL-1: tickets are opaque IDs, never source pointers. A live PixelHandle
 * must be retained throughout copying. Exact lengths come from its info().
 *
 * Destination must be a live, exclusively writable allocation of that exact
 * size until return, with no alias to the source or concurrent/GPU use. Null
 * and length checks cannot validate arbitrary non-null pointers. All validation
 * completes before a write; rejected calls leave destination unchanged.
 *
 * 0 success, 1 expired/invalid ticket, 2 null destination, 3 wrong length,
 * 4 contained Rust panic, 5 no mask. A successful copy owns its bytes in the
 * caller's allocator; Rust never frees or retains the destination pointer.
 * This module is internal to ViewerBridge, not an app-facing unsafe API.
 */
int32_t viewer_copy_pixels(uint64_t ticket, uint8_t *destination, size_t length);
int32_t viewer_copy_mask(uint64_t ticket, uint8_t *destination, size_t length);
#endif
