//! P0-FFI-CONTRACT experiment (docs/implementation/P0-closeout.md).
//!
//! P0-only code, not product API. It checks one candidate pixel path:
//! Rust keeps an immutable decoded frame; metadata/control goes through UniFFI;
//! pixels and the valid mask are copied exactly once into a Swift-owned buffer
//! through a small typed C function keyed by an opaque ticket (never an address).
//! See `../include/p0_contract_copy.h` for the caller obligations.

use std::alloc::{GlobalAlloc, Layout, System};
use std::collections::HashMap;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock, Weak};

uniffi::setup_scaffolding!();

// ---------------------------------------------------------------------------
// Counting allocator: lets the Swift checks assert that a copy allocates nothing
// on the Rust side and that released frames return their bytes.
// ---------------------------------------------------------------------------

struct CountingAlloc;
static LIVE_BYTES: AtomicU64 = AtomicU64::new(0);
static ALLOCS: AtomicU64 = AtomicU64::new(0);

unsafe impl GlobalAlloc for CountingAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // SAFETY: forwarded unchanged to the system allocator.
        let p = unsafe { System.alloc(layout) };
        if !p.is_null() {
            ALLOCS.fetch_add(1, Ordering::Relaxed);
            LIVE_BYTES.fetch_add(layout.size() as u64, Ordering::Relaxed);
        }
        p
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // SAFETY: forwarded unchanged to the system allocator.
        let p = unsafe { System.alloc_zeroed(layout) };
        if !p.is_null() {
            ALLOCS.fetch_add(1, Ordering::Relaxed);
            LIVE_BYTES.fetch_add(layout.size() as u64, Ordering::Relaxed);
        }
        p
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        // SAFETY: forwarded unchanged to the system allocator.
        unsafe { System.dealloc(ptr, layout) };
        LIVE_BYTES.fetch_sub(layout.size() as u64, Ordering::Relaxed);
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        // SAFETY: forwarded unchanged to the system allocator.
        let q = unsafe { System.realloc(ptr, layout, new_size) };
        if !q.is_null() {
            ALLOCS.fetch_add(1, Ordering::Relaxed);
            LIVE_BYTES.fetch_add(new_size as u64, Ordering::Relaxed);
            LIVE_BYTES.fetch_sub(layout.size() as u64, Ordering::Relaxed);
        }
        q
    }
}

#[global_allocator]
static GLOBAL: CountingAlloc = CountingAlloc;

#[derive(Debug, Clone, uniffi::Record)]
pub struct AllocStats {
    pub live_bytes: u64,
    pub allocs: u64,
}

#[uniffi::export]
pub fn alloc_stats() -> AllocStats {
    AllocStats {
        live_bytes: LIVE_BYTES.load(Ordering::Relaxed),
        allocs: ALLOCS.load(Ordering::Relaxed),
    }
}

#[uniffi::export]
pub fn core_info() -> String {
    format!(
        "p0contract {} | uniffi 0.32.2 | profile {} | target {}-{}",
        env!("CARGO_PKG_VERSION"),
        if cfg!(debug_assertions) {
            "debug"
        } else {
            "release"
        },
        std::env::consts::ARCH,
        std::env::consts::OS
    )
}

// ---------------------------------------------------------------------------
// Public (UniFFI) model
// ---------------------------------------------------------------------------

/// Experimental single-frame limit (512 MiB of pixel bytes).
const MAX_FRAME_BYTES: u64 = 512 * 1024 * 1024;

/// Changes whenever the synthetic fill/normalisation policy changes.
pub const PAYLOAD_REVISION: u64 = 1;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ContractError {
    #[error("invalid argument: {detail}")]
    InvalidArgument { detail: String },
    #[error("resource limit: {detail}")]
    ResourceLimit { detail: String },
    #[error("session closed")]
    SessionClosed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PixelFormat {
    GrayF32Le,
    Rgba8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ValueDomain {
    ModalityApplied,
    DisplayColor,
}

/// Synthetic mask policy. `Padding` marks pixels with (3x + y) % 11 == 0 invalid.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum MaskMode {
    AllValid,
    Padding,
}

/// Immutable decoded frame. Shared by the session cache and every PreparedFrame.
struct FrameData {
    ticket: u64,
    width: u32,
    height: u32,
    format: PixelFormat,
    pixels: Vec<u8>,
    mask: Option<Vec<u8>>,
    checksum: u64,
}

impl Drop for FrameData {
    fn drop(&mut self) {
        // The registry lock is never held while a FrameData is dropped by a copy
        // (the strong reference is released after unlocking), so this cannot deadlock.
        if let Ok(mut map) = registry().lock() {
            map.remove(&self.ticket);
        }
    }
}

/// Ticket registry: opaque IDs -> weak frame references. IDs are never reused.
fn registry() -> &'static Mutex<HashMap<u64, Weak<FrameData>>> {
    static REGISTRY: OnceLock<Mutex<HashMap<u64, Weak<FrameData>>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}
static NEXT_TICKET: AtomicU64 = AtomicU64::new(1);

fn pixel_len(width: u32, height: u32) -> Result<usize, ContractError> {
    if width == 0 || height == 0 {
        return Err(ContractError::InvalidArgument {
            detail: format!("width and height must be positive ({width}x{height})"),
        });
    }
    let n = (width as u64)
        .checked_mul(height as u64)
        .and_then(|v| v.checked_mul(4))
        .ok_or_else(|| ContractError::ResourceLimit {
            detail: "size overflow".into(),
        })?;
    if n > MAX_FRAME_BYTES {
        return Err(ContractError::ResourceLimit {
            detail: format!("{n} bytes exceeds limit {MAX_FRAME_BYTES}"),
        });
    }
    Ok(n as usize)
}

fn is_padding(x: u32, y: u32) -> bool {
    (3 * x as u64 + y as u64).is_multiple_of(11)
}

/// GrayF32Le: value(x, y) = x - 0.5*y - 1024, invalid (masked) positions hold +0.0.
/// Rgba8: (x mod 256, y mod 256, (x xor y) mod 256, 255).
fn fill(
    width: u32,
    height: u32,
    format: PixelFormat,
    mask_mode: MaskMode,
) -> (Vec<u8>, Option<Vec<u8>>) {
    let len = width as usize * height as usize * 4;
    let mut pixels = Vec::with_capacity(len);
    let mut mask = match (format, mask_mode) {
        (PixelFormat::GrayF32Le, MaskMode::Padding) => {
            Some(Vec::with_capacity(width as usize * height as usize))
        }
        _ => None,
    };
    for y in 0..height {
        for x in 0..width {
            match format {
                PixelFormat::GrayF32Le => {
                    let invalid = mask.is_some() && is_padding(x, y);
                    let value = if invalid {
                        0.0f32
                    } else {
                        x as f32 - 0.5 * y as f32 - 1024.0
                    };
                    pixels.extend_from_slice(&value.to_le_bytes());
                    if let Some(m) = mask.as_mut() {
                        m.push(u8::from(!invalid));
                    }
                }
                PixelFormat::Rgba8 => {
                    pixels.extend_from_slice(&[x as u8, y as u8, (x ^ y) as u8, 255])
                }
            }
        }
    }
    (pixels, mask)
}

fn checksum_of(bytes: &[u8]) -> u64 {
    let mut sum: u64 = 0;
    let (words, tail) = bytes.as_chunks::<8>();
    for w in words {
        sum = sum.wrapping_add(u64::from_le_bytes(*w));
    }
    for &b in tail {
        sum = sum.wrapping_add(b as u64);
    }
    sum
}

fn build(
    width: u32,
    height: u32,
    format: PixelFormat,
    mask_mode: MaskMode,
) -> Result<Arc<FrameData>, ContractError> {
    pixel_len(width, height)?;
    if format == PixelFormat::Rgba8 && mask_mode == MaskMode::Padding {
        return Err(ContractError::InvalidArgument {
            detail: "valid mask is defined for GrayF32Le only".into(),
        });
    }
    let (pixels, mask) = fill(width, height, format, mask_mode);
    let checksum = checksum_of(&pixels);
    let ticket = NEXT_TICKET.fetch_add(1, Ordering::Relaxed);
    let data = Arc::new(FrameData {
        ticket,
        width,
        height,
        format,
        pixels,
        mask,
        checksum,
    });
    registry()
        .lock()
        .map_err(|_| ContractError::ResourceLimit {
            detail: "registry poisoned".into(),
        })?
        .insert(ticket, Arc::downgrade(&data));
    Ok(data)
}

/// Swift-visible handle. Holding it keeps the ticket valid.
#[derive(uniffi::Object)]
pub struct PreparedFrame {
    data: Arc<FrameData>,
}

#[uniffi::export]
impl PreparedFrame {
    /// Standalone frame without a session (the handle is the only owner).
    #[uniffi::constructor]
    pub fn prepare(
        width: u32,
        height: u32,
        format: PixelFormat,
        mask_mode: MaskMode,
    ) -> Result<Arc<Self>, ContractError> {
        Ok(Arc::new(Self {
            data: build(width, height, format, mask_mode)?,
        }))
    }
    pub fn width(&self) -> u32 {
        self.data.width
    }
    pub fn height(&self) -> u32 {
        self.data.height
    }
    pub fn pixel_format(&self) -> PixelFormat {
        self.data.format
    }
    pub fn value_domain(&self) -> ValueDomain {
        match self.data.format {
            PixelFormat::GrayF32Le => ValueDomain::ModalityApplied,
            PixelFormat::Rgba8 => ValueDomain::DisplayColor,
        }
    }
    pub fn payload_revision(&self) -> u64 {
        PAYLOAD_REVISION
    }
    pub fn row_stride_bytes(&self) -> u32 {
        self.data.width * 4
    }
    pub fn byte_len(&self) -> u64 {
        self.data.pixels.len() as u64
    }
    /// 0 means "no mask: all pixels valid" (docs/04 allows omitting an all-valid mask).
    pub fn mask_len(&self) -> u64 {
        self.data.mask.as_ref().map_or(0, |m| m.len() as u64)
    }
    pub fn checksum(&self) -> u64 {
        self.data.checksum
    }
    /// Opaque, never-reused ID for the C copy functions. Not an address.
    pub fn copy_ticket(&self) -> u64 {
        self.data.ticket
    }
}

/// Minimal session: a cache that co-owns frames, eviction and close.
#[derive(uniffi::Object, Default)]
pub struct ContractSession {
    cache: Mutex<HashMap<String, Arc<FrameData>>>,
    closed: AtomicBool,
}

#[uniffi::export]
impl ContractSession {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }
    pub fn prepare(
        &self,
        key: String,
        width: u32,
        height: u32,
        format: PixelFormat,
        mask_mode: MaskMode,
    ) -> Result<Arc<PreparedFrame>, ContractError> {
        if self.closed.load(Ordering::SeqCst) {
            return Err(ContractError::SessionClosed);
        }
        let data = build(width, height, format, mask_mode)?;
        let mut cache = self
            .cache
            .lock()
            .map_err(|_| ContractError::ResourceLimit {
                detail: "cache poisoned".into(),
            })?;
        if self.closed.load(Ordering::SeqCst) {
            return Err(ContractError::SessionClosed);
        }
        cache.insert(key, data.clone());
        Ok(Arc::new(PreparedFrame { data }))
    }
    pub fn evict(&self, key: String) -> bool {
        self.cache
            .lock()
            .map(|mut c| c.remove(&key).is_some())
            .unwrap_or(false)
    }
    pub fn cached_count(&self) -> u32 {
        self.cache.lock().map(|c| c.len() as u32).unwrap_or(0)
    }
    /// Rejects new work and drops the cache. Already returned PreparedFrames stay valid.
    pub fn close(&self) {
        self.closed.store(true, Ordering::SeqCst);
        if let Ok(mut c) = self.cache.lock() {
            c.clear();
        }
    }
}

// ---------------------------------------------------------------------------
// C copy bridge (see include/p0_contract_copy.h)
// ---------------------------------------------------------------------------

pub const STATUS_OK: i32 = 0;
pub const STATUS_INVALID_TICKET: i32 = 1;
pub const STATUS_NULL_DESTINATION: i32 = 2;
pub const STATUS_LENGTH_MISMATCH: i32 = 3;
pub const STATUS_PANIC: i32 = 4;
pub const STATUS_NO_MASK: i32 = 5;

#[derive(Clone, Copy)]
enum Plane {
    Pixels,
    Mask,
}

fn lookup(ticket: u64) -> Option<Arc<FrameData>> {
    // Upgrade under the lock, release the lock before copying.
    let map = registry().lock().ok()?;
    map.get(&ticket).and_then(Weak::upgrade)
}

/// Checks run in a fixed order so that no destination byte is written on errors 1/2/3/5.
fn copy_plane(ticket: u64, dst: *mut u8, dst_len: usize, plane: Plane) -> i32 {
    let Some(frame) = lookup(ticket) else {
        return STATUS_INVALID_TICKET;
    };
    if dst.is_null() {
        return STATUS_NULL_DESTINATION;
    }
    let src: &[u8] = match plane {
        Plane::Pixels => &frame.pixels,
        Plane::Mask => match frame.mask.as_deref() {
            Some(m) => m,
            None => return STATUS_NO_MASK,
        },
    };
    if src.len() != dst_len {
        return STATUS_LENGTH_MISMATCH;
    }
    // SAFETY: the caller guarantees (header contract) that `dst` is a live, writable,
    // exclusive allocation of exactly `dst_len` bytes that does not overlap Rust's
    // storage; `src` is kept alive by the strong reference `frame` for the whole copy.
    unsafe { std::ptr::copy_nonoverlapping(src.as_ptr(), dst, dst_len) };
    STATUS_OK
    // `frame` is dropped here, after the registry lock was released.
}

fn contained(f: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(STATUS_PANIC)
}

/// # Safety
/// See `p0_contract_copy.h`: `dst` must be a live writable allocation of exactly
/// `dst_len` bytes, exclusive to this call and not overlapping Rust storage.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn p0_contract_copy_pixels(ticket: u64, dst: *mut u8, dst_len: usize) -> i32 {
    contained(|| copy_plane(ticket, dst, dst_len, Plane::Pixels))
}

/// # Safety
/// Same obligations as [`p0_contract_copy_pixels`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn p0_contract_copy_mask(ticket: u64, dst: *mut u8, dst_len: usize) -> i32 {
    contained(|| copy_plane(ticket, dst, dst_len, Plane::Mask))
}

/// Experiment-only probe: proves that a panic inside the bridge returns
/// STATUS_PANIC instead of unwinding into Swift. Not part of any product ABI.
#[unsafe(no_mangle)]
pub extern "C" fn p0_contract_selftest_panic() -> i32 {
    contained(|| {
        let v: Vec<i32> = Vec::new();
        std::hint::black_box(&v);
        panic!("intentional P0 contract panic probe (expected)")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gray_value(x: u32, y: u32) -> f32 {
        x as f32 - 0.5 * y as f32 - 1024.0
    }

    #[test]
    fn copies_exact_pixels_and_mask() {
        let f = PreparedFrame::prepare(13, 7, PixelFormat::GrayF32Le, MaskMode::Padding).unwrap();
        let mut px = vec![0xAAu8; f.byte_len() as usize];
        let mut mask = vec![0xAAu8; f.mask_len() as usize];
        assert_eq!(
            unsafe { p0_contract_copy_pixels(f.copy_ticket(), px.as_mut_ptr(), px.len()) },
            STATUS_OK
        );
        assert_eq!(
            unsafe { p0_contract_copy_mask(f.copy_ticket(), mask.as_mut_ptr(), mask.len()) },
            STATUS_OK
        );
        for y in 0..7 {
            for x in 0..13 {
                let i = (y * 13 + x) as usize;
                let v = f32::from_le_bytes(px[i * 4..i * 4 + 4].try_into().unwrap());
                let valid = (3 * x + y) % 11 != 0;
                assert_eq!(mask[i], u8::from(valid));
                assert_eq!(
                    v.to_bits(),
                    if valid { gray_value(x, y) } else { 0.0 }.to_bits()
                );
            }
        }
    }

    #[test]
    fn errors_do_not_write() {
        let f = PreparedFrame::prepare(4, 4, PixelFormat::Rgba8, MaskMode::AllValid).unwrap();
        let t = f.copy_ticket();
        let n = f.byte_len() as usize;
        for len in [n - 1, n + 1, 0] {
            let mut buf = vec![0x5Au8; n + 1];
            assert_eq!(
                unsafe { p0_contract_copy_pixels(t, buf.as_mut_ptr(), len) },
                STATUS_LENGTH_MISMATCH
            );
            assert!(buf.iter().all(|&b| b == 0x5A));
        }
        let mut buf = vec![0x5Au8; n];
        assert_eq!(
            unsafe { p0_contract_copy_pixels(t, std::ptr::null_mut(), n) },
            STATUS_NULL_DESTINATION
        );
        assert_eq!(
            unsafe { p0_contract_copy_mask(t, buf.as_mut_ptr(), 16) },
            STATUS_NO_MASK
        );
        assert_eq!(
            unsafe { p0_contract_copy_pixels(0, buf.as_mut_ptr(), n) },
            STATUS_INVALID_TICKET
        );
        assert!(buf.iter().all(|&b| b == 0x5A));
        assert!(PreparedFrame::prepare(4, 4, PixelFormat::Rgba8, MaskMode::Padding).is_err());
        assert!(PreparedFrame::prepare(0, 4, PixelFormat::Rgba8, MaskMode::AllValid).is_err());
        assert!(
            PreparedFrame::prepare(u32::MAX, u32::MAX, PixelFormat::Rgba8, MaskMode::AllValid)
                .is_err()
        );
    }

    #[test]
    fn ticket_lifetime_follows_owners() {
        let s = ContractSession::new();
        let f = s
            .prepare("a".into(), 8, 8, PixelFormat::GrayF32Le, MaskMode::AllValid)
            .unwrap();
        let t = f.copy_ticket();
        let mut buf = vec![0u8; f.byte_len() as usize];
        assert!(s.evict("a".into()));
        assert_eq!(
            unsafe { p0_contract_copy_pixels(t, buf.as_mut_ptr(), buf.len()) },
            STATUS_OK
        );
        s.close();
        assert!(matches!(
            s.prepare("b".into(), 8, 8, PixelFormat::GrayF32Le, MaskMode::AllValid),
            Err(ContractError::SessionClosed)
        ));
        assert_eq!(
            unsafe { p0_contract_copy_pixels(t, buf.as_mut_ptr(), buf.len()) },
            STATUS_OK
        );
        drop(f);
        assert_eq!(
            unsafe { p0_contract_copy_pixels(t, buf.as_mut_ptr(), buf.len()) },
            STATUS_INVALID_TICKET
        );
        // A cache-only owner keeps the ticket valid; tickets are never reused.
        let s2 = ContractSession::new();
        let g = s2
            .prepare("c".into(), 8, 8, PixelFormat::GrayF32Le, MaskMode::AllValid)
            .unwrap();
        let t2 = g.copy_ticket();
        assert_ne!(t, t2);
        drop(g);
        assert_eq!(
            unsafe { p0_contract_copy_pixels(t2, buf.as_mut_ptr(), buf.len()) },
            STATUS_OK
        );
        s2.close();
        assert_eq!(
            unsafe { p0_contract_copy_pixels(t2, buf.as_mut_ptr(), buf.len()) },
            STATUS_INVALID_TICKET
        );
    }

    #[test]
    fn concurrent_copies_and_release_race() {
        for _ in 0..50 {
            let f =
                PreparedFrame::prepare(64, 64, PixelFormat::GrayF32Le, MaskMode::AllValid).unwrap();
            let t = f.copy_ticket();
            let n = f.byte_len() as usize;
            let expected = f.checksum();
            let handles: Vec<_> = (0..4)
                .map(|_| {
                    std::thread::spawn(move || {
                        let mut out = Vec::new();
                        for _ in 0..20 {
                            let mut buf = vec![0u8; n];
                            let s = unsafe { p0_contract_copy_pixels(t, buf.as_mut_ptr(), n) };
                            out.push((s, checksum_of(&buf)));
                        }
                        out
                    })
                })
                .collect();
            drop(f);
            for h in handles {
                let mut expired = false;
                for (s, c) in h.join().unwrap() {
                    match s {
                        STATUS_OK => {
                            assert!(!expired, "a ticket must not revive after expiring");
                            assert_eq!(c, expected);
                        }
                        STATUS_INVALID_TICKET => expired = true,
                        other => panic!("unexpected status {other}"),
                    }
                }
            }
            assert!(lookup(t).is_none());
        }
    }

    #[test]
    fn panic_is_contained() {
        assert_eq!(p0_contract_selftest_panic(), STATUS_PANIC);
    }
}
