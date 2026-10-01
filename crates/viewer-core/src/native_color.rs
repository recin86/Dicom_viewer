//! Private native unsigned-8 color normalization, before RGBA8 publication.
//!
//! SC eligibility, bit metadata, source length and required transforms are
//! checked by the caller. This module never invokes a codec or uses a decoded
//! RGB buffer as YBR input. Dense palettes and odd-width 4:2:2 are excluded.

use std::sync::Arc;

use crate::frame::{FrameBudget, FrameData, FrameError};

#[derive(Clone, Copy)]
pub(crate) enum NativeColorLayout {
    RgbInterleaved,
    RgbPlanar,
    YbrFullInterleaved,
    YbrFullPlanar,
    YbrFull422,
}

impl NativeColorLayout {
    pub(crate) fn new(photometric: &str, planar: u16, width: u32) -> Result<Self, FrameError> {
        match (photometric, planar) {
            ("RGB", 0) => Ok(Self::RgbInterleaved),
            ("RGB", 1) => Ok(Self::RgbPlanar),
            ("YBR_FULL", 0) => Ok(Self::YbrFullInterleaved),
            ("YBR_FULL", 1) => Ok(Self::YbrFullPlanar),
            ("YBR_FULL_422", 0) if width.is_multiple_of(2) => Ok(Self::YbrFull422),
            ("YBR_FULL_422", 0) => Err(FrameError::Unsupported("odd_width_ybr422")),
            _ => Err(FrameError::Unsupported("native_color_layout")),
        }
    }

    pub(crate) fn encoded_bytes(self, pixel_count: usize) -> Result<usize, FrameError> {
        // DICOM PS3.3 C.7.6.3: native 422 has nominal spp=3, but two
        // chroma samples shared by two Y samples, hence two bytes per pixel.
        let bytes_per_pixel = if matches!(self, Self::YbrFull422) {
            2
        } else {
            3
        };
        pixel_count
            .checked_mul(bytes_per_pixel)
            .ok_or(FrameError::ResourceLimit("pixel_size_overflow"))
    }

    pub(crate) fn into_frame(
        self,
        width: u32,
        height: u32,
        budget: Arc<FrameBudget>,
        mut sample: impl FnMut(usize) -> u8,
    ) -> Result<Arc<FrameData>, FrameError> {
        let count = usize::try_from(u64::from(width) * u64::from(height))
            .map_err(|_| FrameError::ResourceLimit("addressable_size"))?;
        // The existing builder reserves all RGBA bytes before allocation or
        // this callback. Conversion is streamed without a temporary RGB Vec.
        FrameData::rgba_from_fn(width, height, budget, |i| {
            let channels = match self {
                Self::RgbInterleaved | Self::YbrFullInterleaved => {
                    [sample(i * 3), sample(i * 3 + 1), sample(i * 3 + 2)]
                }
                Self::RgbPlanar | Self::YbrFullPlanar => {
                    [sample(i), sample(count + i), sample(count * 2 + i)]
                }
                Self::YbrFull422 => {
                    let columns = width as usize;
                    let row = i / columns;
                    let column = i % columns;
                    // Each row begins a fresh Y1,Y2,Cb,Cr pair sequence.
                    let pair = row * columns * 2 + (column / 2) * 4;
                    [
                        sample(pair + column % 2),
                        sample(pair + 2),
                        sample(pair + 3),
                    ]
                }
            };
            Ok(match self {
                Self::RgbInterleaved | Self::RgbPlanar => channels,
                _ => ybr_full_to_rgb(channels),
            })
        })
    }
}

fn ybr_full_to_rgb([y, cb, cr]: [u8; 3]) -> [u8; 3] {
    // Full-range 8-bit CCIR 601 conversion, as used by DICOM PS3.3
    // C.7.6.3.1.2. Neutral chroma is 128. Inverse matrix coefficients
    // operate in F64; clamp each result and round half up once to RGB8.
    let y = f64::from(y);
    let cb = f64::from(cb) - 128.0;
    let cr = f64::from(cr) - 128.0;
    let quantize = |value: f64| (value.clamp(0.0, 255.0) + 0.5).floor() as u8;
    [
        quantize(y + 1.402 * cr),
        quantize(y - (0.114 * 1.772 / 0.587) * cb - (0.299 * 1.402 / 0.587) * cr),
        quantize(y + 1.772 * cb),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    const RGB: [u8; 18] = [
        255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 17, 34, 51,
    ];
    const RGB_PLANAR: [u8; 18] = [
        255, 0, 0, 0, 255, 17, 0, 255, 0, 0, 255, 34, 0, 0, 255, 0, 255, 51,
    ];
    const RGBA: [u8; 24] = [
        255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255, 17, 34,
        51, 255,
    ];

    #[test]
    fn rgb_disk_layouts_have_one_literal_row_major_output() {
        for (layout, source) in [
            (NativeColorLayout::RgbInterleaved, RGB),
            (NativeColorLayout::RgbPlanar, RGB_PLANAR),
        ] {
            let budget = FrameBudget::new(24, 24).unwrap();
            let frame = layout
                .into_frame(3, 2, Arc::clone(&budget), |i| source[i])
                .unwrap();
            assert_eq!(frame.pixels(), RGBA);
            assert_eq!(frame.mask(), None);
            assert_eq!(frame.accounted_bytes(), 24);
            assert_eq!(budget.snapshot().live_bytes, 24);
            drop(frame);
            assert_eq!(budget.snapshot().live_bytes, 0);
        }
    }

    #[test]
    fn ybr_full_neutral_clipping_and_patches_have_literal_rgb_expectations() {
        for (source, expected) in [
            ([0, 128, 128], [0, 0, 0]),
            ([1, 128, 128], [1, 1, 1]),
            ([128, 128, 128], [128, 128, 128]),
            ([255, 128, 128], [255, 255, 255]),
            ([76, 85, 255], [254, 0, 0]),
            ([150, 44, 21], [0, 255, 1]),
            ([29, 255, 107], [0, 0, 254]),
            ([0, 0, 0], [0, 135, 0]),
            ([255, 255, 255], [255, 121, 255]),
        ] {
            assert_eq!(ybr_full_to_rgb(source), expected);
        }
    }

    #[test]
    fn ybr_full_planar_and_interleaved_have_literal_output() {
        let expected = [
            254, 0, 0, 255, 0, 255, 1, 255, 0, 0, 254, 255, 128, 128, 128, 255,
        ];
        for (layout, source) in [
            (
                NativeColorLayout::YbrFullInterleaved,
                [76, 85, 255, 150, 44, 21, 29, 255, 107, 128, 128, 128],
            ),
            (
                NativeColorLayout::YbrFullPlanar,
                [76, 150, 29, 128, 85, 44, 255, 128, 255, 21, 107, 128],
            ),
        ] {
            let frame = layout
                .into_frame(2, 2, FrameBudget::new(16, 16).unwrap(), |i| source[i])
                .unwrap();
            assert_eq!(frame.pixels(), expected);
        }
    }

    #[test]
    fn ybr422_shared_chroma_and_row_boundaries_have_literal_output() {
        let source = [
            76, 100, 85, 255, 29, 60, 255, 107, 0, 255, 128, 128, 128, 64, 128, 128,
        ];
        let expected = [
            254, 0, 0, 255, 255, 24, 24, 255, 0, 0, 254, 255, 31, 31, 255, 255, 0, 0, 0, 255, 255,
            255, 255, 255, 128, 128, 128, 255, 64, 64, 64, 255,
        ];
        let layout = NativeColorLayout::new("YBR_FULL_422", 0, 4).unwrap();
        assert_eq!(layout.encoded_bytes(8).unwrap(), 16);
        let frame = layout
            .into_frame(4, 2, FrameBudget::new(32, 32).unwrap(), |i| source[i])
            .unwrap();
        assert_eq!(frame.pixels(), expected);
    }

    #[test]
    fn layout_and_size_limits_are_checked_before_source_sampling() {
        assert!(matches!(
            NativeColorLayout::new("RGB", 2, 2),
            Err(FrameError::Unsupported(_))
        ));
        assert!(matches!(
            NativeColorLayout::new("YBR_FULL_422", 1, 2),
            Err(FrameError::Unsupported(_))
        ));
        assert!(matches!(
            NativeColorLayout::new("YBR_FULL_422", 0, 3),
            Err(FrameError::Unsupported(_))
        ));
        assert_eq!(
            NativeColorLayout::RgbPlanar
                .encoded_bytes(usize::MAX)
                .unwrap_err(),
            FrameError::ResourceLimit("pixel_size_overflow")
        );
        let budget = FrameBudget::new(23, 23).unwrap();
        let error = NativeColorLayout::RgbPlanar
            .into_frame(3, 2, Arc::clone(&budget), |_| {
                panic!("unreserved source sample")
            })
            .unwrap_err();
        assert!(matches!(error, FrameError::ResourceLimit(_)));
        assert_eq!(budget.snapshot().live_bytes, 0);
        assert_eq!(budget.snapshot().peak_bytes, 0);
    }
}
