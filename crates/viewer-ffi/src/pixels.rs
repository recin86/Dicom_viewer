//! Owned immutable frames and copy-only C boundary. No source pointer crosses FFI.

use std::{
    collections::HashMap,
    fmt,
    path::Path,
    sync::{
        Arc, Mutex, MutexGuard, OnceLock, Weak,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};
use viewer_core::frame::{FrameBudget, FrameData, FrameError};

#[derive(Debug, uniffi::Error)]
pub enum PixelError {
    InvalidArgument { reason: String },
    ResourceLimit { reason: String },
    Unsupported { reason: String },
    DecodeFailed { reason: String },
    SessionClosed,
    Busy,
}

impl fmt::Display for PixelError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidArgument { reason }
            | Self::ResourceLimit { reason }
            | Self::Unsupported { reason }
            | Self::DecodeFailed { reason } => f.write_str(reason),
            Self::SessionClosed => f.write_str("Pixel session is closed"),
            Self::Busy => f.write_str("One frame is already being prepared"),
        }
    }
}
impl std::error::Error for PixelError {}
impl From<FrameError> for PixelError {
    fn from(error: FrameError) -> Self {
        match error {
            FrameError::InvalidArgument(reason) => Self::InvalidArgument {
                reason: reason.into(),
            },
            FrameError::ResourceLimit(reason) => Self::ResourceLimit {
                reason: reason.into(),
            },
            FrameError::Unsupported(reason) => Self::Unsupported {
                reason: reason.into(),
            },
            FrameError::DecodeFailed(reason) => Self::DecodeFailed {
                reason: reason.into(),
            },
            FrameError::Io => Self::DecodeFailed {
                reason: "Input could not be read".into(),
            },
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum PixelFormat {
    GrayF32Le,
    Rgba8,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum ValueDomain {
    ModalityApplied,
    DisplayColor,
}

/// Tight row-major pixels. Lengths/stride are bytes; frame index is zero based.
#[derive(Debug, uniffi::Record)]
pub struct PixelBufferInfo {
    pub width: u32,
    pub height: u32,
    pub row_stride_bytes: u64,
    pub byte_len: u64,
    pub mask_len: u64,
    pub pixel_format: PixelFormat,
    pub value_domain: ValueDomain,
    pub contract_revision: u32,
    pub payload_revision: u64,
}

/// Payload accounting only: excludes parser, input, allocator overhead and GPU.
#[derive(Debug, uniffi::Record)]
pub struct MemorySnapshot {
    pub live_bytes: u64,
    pub peak_bytes: u64,
    pub max_live_bytes: u64,
    pub max_frame_bytes: u64,
    pub cached_frames: u32,
    pub active_preparations: u32,
}

type Registry = HashMap<u64, Weak<RegisteredFrame>>;
static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();
static NEXT_TICKET: AtomicU64 = AtomicU64::new(1);
fn registry() -> &'static Mutex<Registry> {
    REGISTRY.get_or_init(Mutex::default)
}
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    // No partially mutated payload exists: frames are immutable, maps are atomic
    // entries. Recover poisoned bookkeeping so Drop never panics during unwind.
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

struct RegisteredFrame {
    ticket: u64,
    frame: Arc<FrameData>,
}
impl RegisteredFrame {
    fn new(frame: Arc<FrameData>) -> Result<Arc<Self>, PixelError> {
        let ticket = NEXT_TICKET
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
                value.checked_add(1)
            })
            .map_err(|_| PixelError::ResourceLimit {
                reason: "Pixel ticket space exhausted".into(),
            })?;
        let registered = Arc::new(Self { ticket, frame });
        lock(registry()).insert(ticket, Arc::downgrade(&registered));
        Ok(registered)
    }
}
impl Drop for RegisteredFrame {
    fn drop(&mut self) {
        lock(registry()).remove(&self.ticket);
    }
}
fn copy_source(ticket: u64) -> Option<Arc<RegisteredFrame>> {
    // Release the registry lock before copying/dropping the strong reference.
    lock(registry()).get(&ticket).and_then(Weak::upgrade)
}

#[derive(uniffi::Object)]
pub struct PixelHandle {
    registered: Arc<RegisteredFrame>,
}
#[uniffi::export]
impl PixelHandle {
    pub fn info(&self) -> PixelBufferInfo {
        let frame = &self.registered.frame;
        let (pixel_format, value_domain) = match frame.pixel_format() {
            viewer_core::frame::PixelFormat::GrayF32Le => {
                (PixelFormat::GrayF32Le, ValueDomain::ModalityApplied)
            }
            viewer_core::frame::PixelFormat::Rgba8 => {
                (PixelFormat::Rgba8, ValueDomain::DisplayColor)
            }
        };
        PixelBufferInfo {
            width: frame.width(),
            height: frame.height(),
            row_stride_bytes: u64::from(frame.width()) * 4,
            byte_len: frame.pixels().len() as u64,
            mask_len: frame.mask().map_or(0, |mask| mask.len() as u64),
            pixel_format,
            value_domain,
            contract_revision: 1,
            payload_revision: 1,
        }
    }
    /// Internal to ViewerBridge in Swift. Never a pointer; never reused.
    pub fn copy_ticket(&self) -> u64 {
        self.registered.ticket
    }
}

#[derive(Default)]
struct SessionState {
    closed: bool,
    cache: HashMap<u64, Arc<RegisteredFrame>>,
}
#[derive(uniffi::Object)]
pub struct PixelSession {
    budget: Arc<FrameBudget>,
    state: Mutex<SessionState>,
    preparing: AtomicBool,
}
struct Preparation<'a>(&'a AtomicBool);
impl Drop for Preparation<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}
impl PixelSession {
    fn begin(&self) -> Result<Preparation<'_>, PixelError> {
        if lock(&self.state).closed {
            return Err(PixelError::SessionClosed);
        }
        self.preparing
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| PixelError::Busy)?;
        Ok(Preparation(&self.preparing))
    }
    fn publish(&self, frame: Arc<FrameData>) -> Result<Arc<PixelHandle>, PixelError> {
        let registered = RegisteredFrame::new(frame)?;
        let mut state = lock(&self.state);
        if state.closed {
            return Err(PixelError::SessionClosed);
        }
        state
            .cache
            .insert(registered.ticket, Arc::clone(&registered));
        Ok(Arc::new(PixelHandle { registered }))
    }
}
#[uniffi::export]
impl PixelSession {
    #[uniffi::constructor]
    pub fn new(max_live_bytes: u64, max_frame_bytes: u64) -> Result<Arc<Self>, PixelError> {
        Ok(Arc::new(Self {
            budget: FrameBudget::new(max_live_bytes, max_frame_bytes)?,
            state: Mutex::default(),
            preparing: AtomicBool::new(false),
        }))
    }
    /// Synchronous Rust call. Swift wrapper dispatches it on Task.detached.
    /// One preparation per session; input is bounded by the narrow core adapter.
    pub fn prepare_native_frame(
        &self,
        path: String,
        frame_index: u32,
    ) -> Result<Arc<PixelHandle>, PixelError> {
        let _preparation = self.begin()?;
        let frame = viewer_core::native::prepare_native_frame(
            Path::new(&path),
            frame_index,
            Arc::clone(&self.budget),
        )?;
        self.publish(frame)
    }
    pub fn evict_all(&self) -> u32 {
        let mut state = lock(&self.state);
        let count = state.cache.len() as u32;
        state.cache.clear();
        count
    }
    /// Idempotent. Already returned handles and running copies stay valid.
    pub fn close(&self) {
        let mut state = lock(&self.state);
        state.closed = true;
        state.cache.clear();
    }
    pub fn memory_snapshot(&self) -> MemorySnapshot {
        let cached_frames = lock(&self.state).cache.len() as u32;
        let snapshot = self.budget.snapshot();
        MemorySnapshot {
            live_bytes: snapshot.live_bytes,
            peak_bytes: snapshot.peak_bytes,
            max_live_bytes: snapshot.max_live_bytes,
            max_frame_bytes: snapshot.max_frame_bytes,
            cached_frames,
            active_preparations: u32::from(self.preparing.load(Ordering::Acquire)),
        }
    }
}

pub const COPY_OK: i32 = 0;
pub const COPY_INVALID_TICKET: i32 = 1;
pub const COPY_NULL_DESTINATION: i32 = 2;
pub const COPY_WRONG_LENGTH: i32 = 3;
pub const COPY_PANIC: i32 = 4;
pub const COPY_NO_MASK: i32 = 5;

fn contained(operation: impl FnOnce() -> i32) -> i32 {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(operation)).unwrap_or(COPY_PANIC)
}
unsafe fn copy(ticket: u64, destination: *mut u8, length: usize, mask: bool) -> i32 {
    let Some(source) = copy_source(ticket) else {
        return COPY_INVALID_TICKET;
    };
    if destination.is_null() {
        return COPY_NULL_DESTINATION;
    }
    let bytes = if mask {
        let Some(mask) = source.frame.mask() else {
            return COPY_NO_MASK;
        };
        mask
    } else {
        source.frame.pixels()
    };
    if bytes.len() != length {
        return COPY_WRONG_LENGTH;
    }
    // All fallible work is before this write. The strong source lease remains
    // alive until the copy ends, including concurrent eviction/close/drop.
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, length);
    }
    COPY_OK
}

/// Copy an immutable frame into caller-owned, exclusive writable memory.
///
/// # Safety
/// For a valid ticket and exact length, destination must reference a live
/// allocation of that length, not overlap the source, and have exclusive write
/// access until return. Null/length checks cannot validate arbitrary pointers.
/// Never pass a buffer currently in use by the GPU. Use ViewerBridge in Swift.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn viewer_copy_pixels(
    ticket: u64,
    destination: *mut u8,
    length: usize,
) -> i32 {
    contained(|| unsafe { copy(ticket, destination, length, false) })
}
/// Copy a mask with the same caller memory obligations as `viewer_copy_pixels`.
///
/// # Safety
/// See `viewer_copy_pixels`. Missing masks return COPY_NO_MASK, without writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn viewer_copy_mask(ticket: u64, destination: *mut u8, length: usize) -> i32 {
    contained(|| unsafe { copy(ticket, destination, length, true) })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn gray(session: &PixelSession) -> Arc<FrameData> {
        FrameData::gray_from_fn(2, 1, Arc::clone(&session.budget), true, |i| {
            Ok(if i == 0 { Some(-12.0) } else { None })
        })
        .unwrap()
    }
    #[test]
    fn metadata_exact_copy_and_failures_do_not_write() {
        let session = PixelSession::new(100, 100).unwrap();
        let handle = session.publish(gray(&session)).unwrap();
        let info = handle.info();
        assert_eq!(
            (
                info.width,
                info.height,
                info.row_stride_bytes,
                info.byte_len,
                info.mask_len
            ),
            (2, 1, 8, 8, 2)
        );
        assert_eq!(
            (info.pixel_format, info.value_domain),
            (PixelFormat::GrayF32Le, ValueDomain::ModalityApplied)
        );
        assert_eq!((info.contract_revision, info.payload_revision), (1, 1));
        let ticket = handle.copy_ticket();
        let mut out = [0xa5; 9];
        unsafe {
            assert_eq!(
                viewer_copy_pixels(0, out.as_mut_ptr(), 8),
                COPY_INVALID_TICKET
            );
            assert_eq!(
                viewer_copy_pixels(ticket, std::ptr::null_mut(), 8),
                COPY_NULL_DESTINATION
            );
            assert_eq!(
                viewer_copy_pixels(ticket, out.as_mut_ptr(), 7),
                COPY_WRONG_LENGTH
            );
            assert_eq!(
                viewer_copy_pixels(ticket, out.as_mut_ptr(), 9),
                COPY_WRONG_LENGTH
            );
            assert_eq!(out, [0xa5; 9]);
            assert_eq!(viewer_copy_pixels(ticket, out.as_mut_ptr(), 8), COPY_OK);
        }
        assert_eq!(&out[..8], &[0, 0, 64, 193, 0, 0, 0, 0]);
        assert_eq!(out[8], 0xa5);
        let mut mask = [0xa5; 3];
        unsafe {
            assert_eq!(
                viewer_copy_mask(ticket, mask.as_mut_ptr(), 3),
                COPY_WRONG_LENGTH
            );
            assert_eq!(mask, [0xa5; 3]);
            assert_eq!(viewer_copy_mask(ticket, mask.as_mut_ptr(), 2), COPY_OK);
        }
        assert_eq!(mask, [1, 0, 0xa5]);
    }
    #[test]
    fn color_no_mask_and_ticket_never_reused() {
        let session = PixelSession::new(100, 100).unwrap();
        let frame =
            FrameData::rgba_from_fn(1, 1, Arc::clone(&session.budget), |_| Ok([17, 34, 51]))
                .unwrap();
        let handle = session.publish(frame).unwrap();
        assert_eq!(handle.info().value_domain, ValueDomain::DisplayColor);
        let ticket = handle.copy_ticket();
        let mut out = [0xa5; 4];
        unsafe {
            assert_eq!(viewer_copy_mask(ticket, out.as_mut_ptr(), 0), COPY_NO_MASK);
            assert_eq!(out, [0xa5; 4]);
            assert_eq!(viewer_copy_pixels(ticket, out.as_mut_ptr(), 4), COPY_OK);
        }
        assert_eq!(out, [17, 34, 51, 255]);
        session.evict_all();
        drop(handle);
        let next = session.publish(gray(&session)).unwrap();
        assert_ne!(next.copy_ticket(), ticket);
        unsafe {
            assert_eq!(
                viewer_copy_pixels(ticket, out.as_mut_ptr(), 4),
                COPY_INVALID_TICKET
            );
        }
    }
    #[test]
    fn eviction_close_and_copy_lease_keep_live_charge() {
        let session = PixelSession::new(10, 10).unwrap();
        let handle = session.publish(gray(&session)).unwrap();
        let ticket = handle.copy_ticket();
        assert_eq!(session.evict_all(), 1);
        session.close();
        session.close();
        assert_eq!(session.memory_snapshot().live_bytes, 10);
        let mut out = [0; 8];
        unsafe {
            assert_eq!(viewer_copy_pixels(ticket, out.as_mut_ptr(), 8), COPY_OK);
        }
        // Exactly the strong lease used by the C copy function. A last handle
        // drop on another thread cannot free its source allocation.
        let source = copy_source(ticket).unwrap();
        std::thread::spawn(move || drop(handle)).join().unwrap();
        assert_eq!(session.memory_snapshot().live_bytes, 10);
        drop(source);
        assert_eq!(session.memory_snapshot().live_bytes, 0);
        assert!(copy_source(ticket).is_none());
        assert!(matches!(session.begin(), Err(PixelError::SessionClosed)));
    }
    #[test]
    fn cache_owns_once_and_budget_rolls_back_on_closed_publish() {
        let session = PixelSession::new(10, 10).unwrap();
        let handle = session.publish(gray(&session)).unwrap();
        drop(handle);
        assert_eq!(session.memory_snapshot().live_bytes, 10);
        assert!(
            FrameData::gray_from_fn(1, 1, Arc::clone(&session.budget), false, |_| Ok(Some(1.0)))
                .is_err()
        );
        session.evict_all();
        let frame = gray(&session);
        session.close();
        assert!(matches!(
            session.publish(frame),
            Err(PixelError::SessionClosed)
        ));
        assert_eq!(session.memory_snapshot().live_bytes, 0);
    }
    #[test]
    fn preparation_is_single_and_guard_recovers_after_unwind() {
        let session = PixelSession::new(10, 10).unwrap();
        let preparation = session.begin().unwrap();
        assert_eq!(session.memory_snapshot().active_preparations, 1);
        assert!(matches!(session.begin(), Err(PixelError::Busy)));
        drop(preparation);
        assert_eq!(
            contained(|| {
                let _guard = session.begin().unwrap();
                panic!("synthetic panic");
            }),
            COPY_PANIC
        );
        assert_eq!(session.memory_snapshot().active_preparations, 0);
        assert!(session.begin().is_ok());
    }
    #[test]
    fn concurrent_copies_with_last_owner_drop() {
        for _ in 0..100 {
            let session = PixelSession::new(10, 10).unwrap();
            let handle = session.publish(gray(&session)).unwrap();
            let ticket = handle.copy_ticket();
            let barrier = Arc::new(std::sync::Barrier::new(2));
            let copy_barrier = Arc::clone(&barrier);
            let copy = std::thread::spawn(move || {
                let mut out = [0xa5; 8];
                copy_barrier.wait();
                let status = unsafe { viewer_copy_pixels(ticket, out.as_mut_ptr(), 8) };
                match status {
                    COPY_OK => assert_eq!(out, [0, 0, 64, 193, 0, 0, 0, 0]),
                    COPY_INVALID_TICKET => assert_eq!(out, [0xa5; 8]),
                    other => panic!("unexpected copy status {other}"),
                }
            });
            barrier.wait();
            session.close();
            drop(handle);
            copy.join().unwrap();
            assert_eq!(session.memory_snapshot().live_bytes, 0);
        }
    }
}
