//! Immutable pixel payloads and admission accounting.
//!
//! The budget counts pixels plus mask once for each live frame, including
//! construction and all cache/handle/copy owners. It is not an RSS, parser,
//! allocator-capacity, input, Swift-copy, or GPU memory limit.

use std::fmt;
use std::sync::{Arc, Mutex};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PixelFormat {
    /// Little-endian F32, ModalityApplied; VOI and polarity are not applied.
    GrayF32Le,
    /// Interleaved display R/G/B/A, with alpha 255 and no mask.
    Rgba8,
}

/// Errors expose only static, non-patient diagnostic codes.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum FrameError {
    InvalidArgument(&'static str),
    ResourceLimit(&'static str),
    Unsupported(&'static str),
    DecodeFailed(&'static str),
    Io,
}

impl fmt::Display for FrameError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidArgument(code) => write!(f, "invalid argument: {code}"),
            Self::ResourceLimit(code) => write!(f, "resource limit: {code}"),
            Self::Unsupported(code) => write!(f, "unsupported: {code}"),
            Self::DecodeFailed(code) => write!(f, "decode failed: {code}"),
            Self::Io => f.write_str("input I/O failed"),
        }
    }
}

impl std::error::Error for FrameError {}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct BudgetSnapshot {
    pub live_bytes: u64,
    pub peak_bytes: u64,
    pub max_live_bytes: u64,
    pub max_frame_bytes: u64,
}

#[derive(Debug)]
struct BudgetState {
    live_bytes: u64,
    peak_bytes: u64,
}

/// Shared accounting for every live payload, not just cached payloads.
#[derive(Debug)]
pub struct FrameBudget {
    state: Mutex<BudgetState>,
    max_live_bytes: u64,
    max_frame_bytes: u64,
}

impl FrameBudget {
    pub fn new(max_live_bytes: u64, max_frame_bytes: u64) -> Result<Arc<Self>, FrameError> {
        if max_live_bytes == 0 || max_frame_bytes == 0 {
            return Err(FrameError::InvalidArgument("zero_budget"));
        }
        Ok(Arc::new(Self {
            state: Mutex::new(BudgetState {
                live_bytes: 0,
                peak_bytes: 0,
            }),
            max_live_bytes,
            max_frame_bytes,
        }))
    }

    pub fn snapshot(&self) -> BudgetSnapshot {
        let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        BudgetSnapshot {
            live_bytes: state.live_bytes,
            peak_bytes: state.peak_bytes,
            max_live_bytes: self.max_live_bytes,
            max_frame_bytes: self.max_frame_bytes,
        }
    }

    fn reserve(self: &Arc<Self>, bytes: u64) -> Result<BudgetLease, FrameError> {
        if bytes == 0 {
            return Err(FrameError::InvalidArgument("zero_payload"));
        }
        if bytes > self.max_frame_bytes {
            return Err(FrameError::ResourceLimit("frame_bytes"));
        }
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        let next = state
            .live_bytes
            .checked_add(bytes)
            .filter(|&next| next <= self.max_live_bytes)
            .ok_or(FrameError::ResourceLimit("live_bytes"))?;
        state.live_bytes = next;
        state.peak_bytes = state.peak_bytes.max(next);
        Ok(BudgetLease {
            budget: Arc::clone(self),
            bytes,
        })
    }
}

#[derive(Debug)]
struct BudgetLease {
    budget: Arc<FrameBudget>,
    bytes: u64,
}

impl Drop for BudgetLease {
    fn drop(&mut self) {
        let mut state = self.budget.state.lock().unwrap_or_else(|e| e.into_inner());
        state.live_bytes -= self.bytes;
    }
}

/// An immutable, tightly packed payload. Clone the Arc rather than the storage.
///
/// F32 display values do not replace the future F64 measurement path.
#[derive(Debug)]
pub struct FrameData {
    width: u32,
    height: u32,
    pixel_format: PixelFormat,
    pixels: Vec<u8>,
    mask: Option<Vec<u8>>,
    // Dropped after the storage so its charge covers the entire payload life.
    lease: BudgetLease,
}

impl FrameData {
    pub fn width(&self) -> u32 {
        self.width
    }

    pub fn height(&self) -> u32 {
        self.height
    }

    pub fn pixel_format(&self) -> PixelFormat {
        self.pixel_format
    }

    pub fn pixels(&self) -> &[u8] {
        &self.pixels
    }

    pub fn mask(&self) -> Option<&[u8]> {
        self.mask.as_deref()
    }

    pub fn accounted_bytes(&self) -> u64 {
        self.lease.bytes
    }

    /// Streams normalized ModalityApplied F64 samples in row-major order.
    ///
    /// None is padding/invalid and requires a mask. Its F32 bytes are +0.0.
    /// Non-finite values and finite F64 values overflowing F32 are explicitly
    /// unsupported; they are never silently clamped or converted to padding.
    pub fn gray_from_fn(
        width: u32,
        height: u32,
        budget: Arc<FrameBudget>,
        has_mask: bool,
        sample: impl FnMut(usize) -> Result<Option<f64>, FrameError>,
    ) -> Result<Arc<Self>, FrameError> {
        Self::gray_with_allocator(width, height, budget, has_mask, sample, allocate_bytes)
    }

    fn gray_with_allocator(
        width: u32,
        height: u32,
        budget: Arc<FrameBudget>,
        has_mask: bool,
        mut sample: impl FnMut(usize) -> Result<Option<f64>, FrameError>,
        mut allocate: impl FnMut(usize) -> Result<Vec<u8>, FrameError>,
    ) -> Result<Arc<Self>, FrameError> {
        let shape = PayloadShape::new(width, height, has_mask)?;
        // Reserve pixels AND mask before either allocation or sample callback.
        let lease = budget.reserve(shape.total_bytes)?;
        let mut pixels = allocate(shape.pixel_bytes)?;
        let mut mask = if has_mask {
            Some(allocate(shape.samples)?)
        } else {
            None
        };
        for i in 0..shape.samples {
            match sample(i)? {
                Some(value) => {
                    if !value.is_finite() {
                        return Err(FrameError::Unsupported("non_finite_modality_value"));
                    }
                    let display = value as f32;
                    if !display.is_finite() {
                        return Err(FrameError::Unsupported("f32_overflow"));
                    }
                    pixels[i * 4..i * 4 + 4].copy_from_slice(&display.to_le_bytes());
                    if let Some(mask) = mask.as_mut() {
                        mask[i] = 1;
                    }
                }
                None => {
                    if mask.is_none() {
                        return Err(FrameError::InvalidArgument("invalid_sample_without_mask"));
                    }
                    // Zero-filled bytes are the IEEE 754 positive zero.
                }
            }
        }
        Ok(Arc::new(Self {
            width,
            height,
            pixel_format: PixelFormat::GrayF32Le,
            pixels,
            mask,
            lease,
        }))
    }

    /// Streams RGB display bytes in row-major order; the builder adds alpha 255.
    pub fn rgba_from_fn(
        width: u32,
        height: u32,
        budget: Arc<FrameBudget>,
        mut sample: impl FnMut(usize) -> Result<[u8; 3], FrameError>,
    ) -> Result<Arc<Self>, FrameError> {
        let shape = PayloadShape::new(width, height, false)?;
        let lease = budget.reserve(shape.total_bytes)?;
        let mut pixels = allocate_bytes(shape.pixel_bytes)?;
        for i in 0..shape.samples {
            let rgb = sample(i)?;
            pixels[i * 4..i * 4 + 3].copy_from_slice(&rgb);
            pixels[i * 4 + 3] = 255;
        }
        Ok(Arc::new(Self {
            width,
            height,
            pixel_format: PixelFormat::Rgba8,
            pixels,
            mask: None,
            lease,
        }))
    }
}

struct PayloadShape {
    samples: usize,
    pixel_bytes: usize,
    total_bytes: u64,
}

impl PayloadShape {
    fn new(width: u32, height: u32, has_mask: bool) -> Result<Self, FrameError> {
        if width == 0 || height == 0 {
            return Err(FrameError::InvalidArgument("zero_dimensions"));
        }
        let samples = u64::from(width) * u64::from(height);
        let pixel_bytes = samples
            .checked_mul(4)
            .ok_or(FrameError::ResourceLimit("payload_size_overflow"))?;
        let total_bytes = pixel_bytes
            .checked_add(if has_mask { samples } else { 0 })
            .ok_or(FrameError::ResourceLimit("payload_size_overflow"))?;
        Ok(Self {
            samples: usize::try_from(samples)
                .map_err(|_| FrameError::ResourceLimit("addressable_size"))?,
            pixel_bytes: usize::try_from(pixel_bytes)
                .map_err(|_| FrameError::ResourceLimit("addressable_size"))?,
            total_bytes,
        })
    }
}

fn allocate_bytes(bytes: usize) -> Result<Vec<u8>, FrameError> {
    let mut storage = Vec::new();
    storage
        .try_reserve_exact(bytes)
        .map_err(|_| FrameError::ResourceLimit("allocation"))?;
    storage.resize(bytes, 0);
    Ok(storage)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Barrier;
    use std::thread;

    #[test]
    fn little_endian_values_mask_and_last_owner_charge() {
        let budget = FrameBudget::new(20, 20).unwrap();
        let cache = FrameData::gray_from_fn(2, 2, Arc::clone(&budget), true, |i| {
            Ok([Some(-12.0), None, Some(0.5), Some(4084.0)][i])
        })
        .unwrap();
        assert_eq!(
            cache.pixels(),
            &[0, 0, 64, 193, 0, 0, 0, 0, 0, 0, 0, 63, 0, 64, 127, 69]
        );
        assert_eq!(cache.mask(), Some([1, 0, 1, 1].as_slice()));
        assert_eq!(cache.accounted_bytes(), 20);
        let handle = Arc::clone(&cache);
        let in_flight_copy = Arc::clone(&handle);
        drop(cache);
        drop(handle);
        assert_eq!(budget.snapshot().live_bytes, 20);
        assert_eq!(in_flight_copy.pixels()[4..8], [0, 0, 0, 0]);
        assert!(matches!(
            FrameData::rgba_from_fn(1, 1, Arc::clone(&budget), |_| Ok([1, 2, 3])),
            Err(FrameError::ResourceLimit("live_bytes"))
        ));
        drop(in_flight_copy);
        assert_eq!(budget.snapshot().live_bytes, 0);
        assert_eq!(budget.snapshot().peak_bytes, 20);
    }

    #[test]
    fn rgb_order_and_alpha_are_independent_bytes() {
        let budget = FrameBudget::new(8, 8).unwrap();
        let frame = FrameData::rgba_from_fn(2, 1, Arc::clone(&budget), |i| {
            Ok([[255, 0, 0], [17, 34, 51]][i])
        })
        .unwrap();
        assert_eq!(frame.pixels(), &[255, 0, 0, 255, 17, 34, 51, 255]);
        assert_eq!(frame.pixel_format(), PixelFormat::Rgba8);
        assert_eq!(frame.mask(), None);
        assert_eq!(budget.snapshot().live_bytes, 8);
    }

    #[test]
    fn dimensions_and_total_mask_bytes_are_checked_before_callback() {
        let budget = FrameBudget::new(u64::MAX, 4).unwrap();
        assert!(FrameBudget::new(0, 4).is_err());
        assert!(FrameBudget::new(4, 0).is_err());
        assert!(matches!(
            FrameData::gray_from_fn(0, 1, Arc::clone(&budget), false, |_| panic!("called")),
            Err(FrameError::InvalidArgument("zero_dimensions"))
        ));
        assert!(matches!(
            FrameData::gray_from_fn(u32::MAX, u32::MAX, Arc::clone(&budget), true, |_| panic!(
                "called"
            )),
            Err(FrameError::ResourceLimit("payload_size_overflow"))
        ));
        assert!(matches!(
            FrameData::gray_from_fn(1, 1, Arc::clone(&budget), true, |_| panic!("called")),
            Err(FrameError::ResourceLimit("frame_bytes"))
        ));
        assert_eq!(budget.snapshot().live_bytes, 0);
        assert_eq!(budget.snapshot().peak_bytes, 0);
    }

    #[test]
    fn allocation_failure_and_sample_failure_return_the_entire_reservation() {
        let budget = FrameBudget::new(10, 10).unwrap();
        let mut allocation = 0;
        let result = FrameData::gray_with_allocator(
            2,
            1,
            Arc::clone(&budget),
            true,
            |_| panic!("sample before allocation"),
            |bytes| {
                allocation += 1;
                // Exercise a real try_reserve CapacityOverflow after pixels succeeded.
                allocate_bytes(if allocation == 2 { usize::MAX } else { bytes })
            },
        );
        assert_eq!(result.unwrap_err(), FrameError::ResourceLimit("allocation"));
        assert_eq!(allocation, 2);
        assert_eq!(budget.snapshot().live_bytes, 0);
        assert_eq!(budget.snapshot().peak_bytes, 10);
        assert!(
            FrameData::gray_from_fn(2, 1, Arc::clone(&budget), true, |i| {
                if i == 1 {
                    Err(FrameError::DecodeFailed("sample"))
                } else {
                    Ok(Some(1.0))
                }
            })
            .is_err()
        );
        assert_eq!(budget.snapshot().live_bytes, 0);
    }

    #[test]
    fn finite_f64_overflow_and_non_finite_are_not_masked() {
        let budget = FrameBudget::new(5, 5).unwrap();
        for value in [f64::MAX, -f64::MAX] {
            assert_eq!(
                FrameData::gray_from_fn(1, 1, Arc::clone(&budget), true, |_| Ok(Some(value)))
                    .unwrap_err(),
                FrameError::Unsupported("f32_overflow")
            );
            assert_eq!(budget.snapshot().live_bytes, 0);
        }
        for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            assert_eq!(
                FrameData::gray_from_fn(1, 1, Arc::clone(&budget), true, |_| Ok(Some(value)))
                    .unwrap_err(),
                FrameError::Unsupported("non_finite_modality_value")
            );
            assert_eq!(budget.snapshot().live_bytes, 0);
        }
        assert_eq!(
            FrameData::gray_from_fn(1, 1, Arc::clone(&budget), false, |_| Ok(None)).unwrap_err(),
            FrameError::InvalidArgument("invalid_sample_without_mask")
        );
        assert_eq!(budget.snapshot().live_bytes, 0);
    }

    #[test]
    fn concurrent_admission_is_atomic_and_counts_final_owner() {
        let budget = FrameBudget::new(8, 8).unwrap();
        let admitted = Arc::new(Barrier::new(9));
        let release = Arc::new(Barrier::new(9));
        let mut threads = Vec::new();
        for _ in 0..8 {
            let budget = Arc::clone(&budget);
            let admitted = Arc::clone(&admitted);
            let release = Arc::clone(&release);
            threads.push(thread::spawn(move || {
                let frame = FrameData::rgba_from_fn(1, 1, budget, |_| Ok([1, 2, 3]));
                admitted.wait();
                release.wait();
                frame.is_ok()
            }));
        }
        admitted.wait();
        assert_eq!(budget.snapshot().live_bytes, 8);
        assert_eq!(budget.snapshot().peak_bytes, 8);
        release.wait();
        let successes = threads
            .into_iter()
            .map(|t| t.join().unwrap())
            .filter(|success| *success)
            .count();
        assert_eq!(successes, 2);
        assert_eq!(budget.snapshot().live_bytes, 0);
    }

    #[test]
    fn panic_during_construction_also_returns_the_lease() {
        let budget = FrameBudget::new(5, 5).unwrap();
        let result = std::panic::catch_unwind(|| {
            let _ = FrameData::gray_from_fn(1, 1, Arc::clone(&budget), true, |_| panic!("sample"));
        });
        assert!(result.is_err());
        assert_eq!(budget.snapshot().live_bytes, 0);
    }
}
