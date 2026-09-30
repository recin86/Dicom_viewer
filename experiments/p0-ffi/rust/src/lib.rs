//! P0-FFI experiment (docs/implementation/P0-tech-data.md).
//! Throwaway code for measuring the UniFFI Rust <-> Swift boundary.
//! Do not move this into crates/ as product API.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

uniffi::setup_scaffolding!();

/// Upper bound for a single experimental frame (512 MiB).
const MAX_FRAME_BYTES: u64 = 512 * 1024 * 1024;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum P0Error {
    #[error("invalid argument: {detail}")]
    InvalidArgument { detail: String },
    #[error("resource limit: {detail}")]
    ResourceLimit { detail: String },
    #[error("cancelled")]
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PixelFormat {
    GrayF32Le,
    Rgba8,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FramePayload {
    pub width: u32,
    pub height: u32,
    pub pixel_format: PixelFormat,
    pub row_stride_bytes: u32,
    /// Time spent filling the buffer inside Rust (ns), excluding FFI lowering.
    pub rust_fill_ns: u64,
    /// Wrapping sum of little-endian u64 words (tail bytes added individually).
    pub checksum: u64,
    /// Time spent computing `checksum` inside Rust (ns).
    pub rust_checksum_ns: u64,
    pub bytes: Vec<u8>,
}

/// Build/runtime information for the report.
#[uniffi::export]
pub fn core_info() -> String {
    format!(
        "p0ffi {} | uniffi 0.32.2 | profile {} | target {}-{}",
        env!("CARGO_PKG_VERSION"),
        if cfg!(debug_assertions) { "debug" } else { "release" },
        std::env::consts::ARCH,
        std::env::consts::OS
    )
}

fn frame_len(width: u32, height: u32) -> Result<usize, P0Error> {
    if width == 0 || height == 0 {
        return Err(P0Error::InvalidArgument {
            detail: format!("width and height must be positive ({width}x{height})"),
        });
    }
    let n = (width as u64)
        .checked_mul(height as u64)
        .and_then(|v| v.checked_mul(4))
        .ok_or_else(|| P0Error::ResourceLimit { detail: "size overflow".into() })?;
    if n > MAX_FRAME_BYTES {
        return Err(P0Error::ResourceLimit {
            detail: format!("{n} bytes exceeds limit {MAX_FRAME_BYTES}"),
        });
    }
    Ok(n as usize)
}

/// Deterministic test pattern.
/// GrayF32Le: value(x, y) = x - 0.5*y - 1024 (so (3,2) = -1022.0).
/// Rgba8: (x mod 256, y mod 256, (x xor y) mod 256, 255).
fn fill(width: u32, height: u32, format: PixelFormat, len: usize) -> Vec<u8> {
    let mut v = Vec::with_capacity(len);
    match format {
        PixelFormat::GrayF32Le => {
            for y in 0..height {
                let row_base = -(y as f32) * 0.5 - 1024.0;
                for x in 0..width {
                    v.extend_from_slice(&((x as f32) + row_base).to_le_bytes());
                }
            }
        }
        PixelFormat::Rgba8 => {
            for y in 0..height {
                for x in 0..width {
                    v.extend_from_slice(&[x as u8, y as u8, (x ^ y) as u8, 255]);
                }
            }
        }
    }
    debug_assert_eq!(v.len(), len);
    v
}

fn checksum_of(bytes: &[u8]) -> u64 {
    let mut sum: u64 = 0;
    let mut chunks = bytes.chunks_exact(8);
    for c in &mut chunks {
        sum = sum.wrapping_add(u64::from_le_bytes(c.try_into().unwrap()));
    }
    for &b in chunks.remainder() {
        sum = sum.wrapping_add(b as u64);
    }
    sum
}

fn build_frame(width: u32, height: u32, format: PixelFormat) -> Result<FramePayload, P0Error> {
    let len = frame_len(width, height)?;
    let t = Instant::now();
    let bytes = fill(width, height, format, len);
    let rust_fill_ns = t.elapsed().as_nanos() as u64;
    let t = Instant::now();
    let checksum = checksum_of(&bytes);
    let rust_checksum_ns = t.elapsed().as_nanos() as u64;
    Ok(FramePayload {
        width,
        height,
        pixel_format: format,
        row_stride_bytes: width * 4,
        rust_fill_ns,
        checksum,
        rust_checksum_ns,
        bytes,
    })
}

/// Rust -> Swift: owned bytes returned inside a record.
#[uniffi::export]
pub fn make_frame(width: u32, height: u32, format: PixelFormat) -> Result<FramePayload, P0Error> {
    build_frame(width, height, format)
}

/// Rust -> Swift: bare Vec<u8> return (no record), for comparing the lift path.
#[uniffi::export]
pub fn make_frame_bytes(width: u32, height: u32, format: PixelFormat) -> Result<Vec<u8>, P0Error> {
    let len = frame_len(width, height)?;
    Ok(fill(width, height, format, len))
}

/// Rust-only cost of building the same frame, for separating FFI cost.
#[uniffi::export]
pub fn fill_only_ns(width: u32, height: u32, format: PixelFormat) -> Result<u64, P0Error> {
    let len = frame_len(width, height)?;
    let t = Instant::now();
    let bytes = fill(width, height, format, len);
    let ns = t.elapsed().as_nanos() as u64;
    std::hint::black_box(&bytes);
    Ok(ns)
}

/// Swift -> Rust, owned (copied into a RustBuffer).
#[uniffi::export]
pub fn checksum_owned(bytes: Vec<u8>) -> u64 {
    checksum_of(&bytes)
}

/// Swift -> Rust, borrowed (&[u8], zero-copy since UniFFI 0.32, sync only).
#[uniffi::export]
pub fn checksum_borrowed(bytes: &[u8]) -> u64 {
    checksum_of(bytes)
}

/// Structured errors: 1 = InvalidArgument, 2 = ResourceLimit, 3 = Cancelled, other = Ok.
#[uniffi::export]
pub fn fail_with(kind: u32) -> Result<(), P0Error> {
    match kind {
        1 => Err(P0Error::InvalidArgument { detail: "requested by test".into() }),
        2 => Err(P0Error::ResourceLimit { detail: "requested by test".into() }),
        3 => Err(P0Error::Cancelled),
        _ => Ok(()),
    }
}

/// Intentional panic inside a Result-returning function.
/// Expectation: UniFFI catches it and Swift receives a thrown internal error, not a crash.
#[uniffi::export]
pub fn panic_in_result() -> Result<u32, P0Error> {
    panic!("intentional P0 panic (expected)");
}

/// Synchronous blocking call: blocks whichever Swift thread calls it.
#[uniffi::export]
pub fn blocking_sleep_ms(ms: u64) -> u64 {
    let t = Instant::now();
    std::thread::sleep(Duration::from_millis(ms));
    t.elapsed().as_millis() as u64
}

/// Async call: work runs on a Rust thread; the Swift caller is suspended, not blocked.
#[uniffi::export]
pub async fn async_sleep_ms(ms: u64) -> u64 {
    let (tx, rx) = futures_channel::oneshot::channel();
    std::thread::spawn(move || {
        let t = Instant::now();
        std::thread::sleep(Duration::from_millis(ms));
        let _ = tx.send(t.elapsed().as_millis() as u64);
    });
    rx.await.unwrap_or(0)
}

/// Explicit cancellation token shared between Swift and Rust.
#[derive(uniffi::Object, Default)]
pub struct CancelToken {
    flag: AtomicBool,
}

#[uniffi::export]
impl CancelToken {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }
    pub fn cancel(&self) {
        self.flag.store(true, Ordering::SeqCst);
    }
    pub fn is_cancelled(&self) -> bool {
        self.flag.load(Ordering::SeqCst)
    }
}

/// Long async task that checks the token between steps.
/// Returns the number of completed steps, or Cancelled.
#[uniffi::export]
pub async fn long_task(token: Arc<CancelToken>, steps: u32, step_ms: u64) -> Result<u32, P0Error> {
    let (tx, rx) = futures_channel::oneshot::channel();
    std::thread::spawn(move || {
        let mut done = 0u32;
        let result = loop {
            if token.is_cancelled() {
                break Err(P0Error::Cancelled);
            }
            if done >= steps {
                break Ok(done);
            }
            std::thread::sleep(Duration::from_millis(step_ms));
            done += 1;
        };
        let _ = tx.send(result);
    });
    rx.await.unwrap_or(Err(P0Error::Cancelled))
}

/// Minimal cache to check that returned payloads outlive Rust-side eviction.
#[derive(uniffi::Object, Default)]
pub struct FrameCache {
    frames: Mutex<HashMap<String, FramePayload>>,
}

#[uniffi::export]
impl FrameCache {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }
    pub fn put(&self, key: String, width: u32, height: u32, format: PixelFormat) -> Result<(), P0Error> {
        let f = build_frame(width, height, format)?;
        self.frames.lock().unwrap().insert(key, f);
        Ok(())
    }
    pub fn get(&self, key: String) -> Result<FramePayload, P0Error> {
        self.frames
            .lock()
            .unwrap()
            .get(&key)
            .cloned()
            .ok_or(P0Error::InvalidArgument { detail: format!("no frame for key {key}") })
    }
    pub fn clear(&self) {
        self.frames.lock().unwrap().clear();
    }
    pub fn len(&self) -> u32 {
        self.frames.lock().unwrap().len() as u32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pattern_and_checksum() {
        let f = build_frame(4, 3, PixelFormat::GrayF32Le).unwrap();
        assert_eq!(f.bytes.len(), 4 * 3 * 4);
        let i = (2 * 4 + 3) * 4; // (x=3, y=2)
        let v = f32::from_le_bytes(f.bytes[i..i + 4].try_into().unwrap());
        assert_eq!(v, -1022.0);
        assert_eq!(f.checksum, checksum_of(&f.bytes));
    }

    #[test]
    fn size_limits() {
        assert!(matches!(frame_len(0, 1), Err(P0Error::InvalidArgument { .. })));
        assert!(matches!(frame_len(100_000, 100_000), Err(P0Error::ResourceLimit { .. })));
        assert!(matches!(frame_len(u32::MAX, u32::MAX), Err(P0Error::ResourceLimit { .. })));
    }
}
