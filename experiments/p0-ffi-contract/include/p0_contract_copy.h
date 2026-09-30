#ifndef P0_CONTRACT_COPY_H
#define P0_CONTRACT_COPY_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum P0ContractCopyStatus {
    P0_CONTRACT_COPY_OK = 0,
    P0_CONTRACT_COPY_INVALID_TICKET = 1,
    P0_CONTRACT_COPY_NULL_DESTINATION = 2,
    P0_CONTRACT_COPY_LENGTH_MISMATCH = 3,
    P0_CONTRACT_COPY_PANIC = 4,
    P0_CONTRACT_COPY_NO_MASK = 5
};

/* P0-only bridge, not a production ABI.
 * ticket is an opaque ID from PreparedFrame.copyTicket(), never an address.
 * The source is upgraded to a strong reference for the duration of a copy.
 * A ticket expires when the last owning PreparedFrame is released (including
 * any session cache owner). Session close/eviction does not expire a ticket
 * while the caller still owns its PreparedFrame. Tickets are never reused.
 *
 * CALLER OBLIGATION: dst must point to a live, writable allocation of exactly
 * dst_len bytes, exclusive to this call. It must not overlap Rust's source
 * storage. The bridge checks ticket, null, mask presence and exact length
 * before writing; it cannot validate an arbitrary nonnull pointer's allocation
 * or lifetime. The destination is never retained and no Rust source pointer is
 * returned. Separate writable buffers may be copied concurrently using one
 * ticket. Errors 1/2/3/5 do not write destination bytes; panic status is
 * containment, not a guarantee that all possible panic sites leave a buffer
 * unchanged. Check order: ticket (1), null (2), mask presence (5), length (3).
 *
 * Swift code must not call these directly; the P0 wrapper keeps the
 * PreparedFrame alive (withExtendedLifetime) and owns an exactly-sized buffer.
 */
int32_t p0_contract_copy_pixels(uint64_t ticket, uint8_t *dst, size_t dst_len);
int32_t p0_contract_copy_mask(uint64_t ticket, uint8_t *dst, size_t dst_len);

/* Experiment-only probe: panics inside the bridge and must return
 * P0_CONTRACT_COPY_PANIC instead of unwinding into the caller. */
int32_t p0_contract_selftest_panic(void);

#ifdef __cplusplus
}
#endif
#endif
