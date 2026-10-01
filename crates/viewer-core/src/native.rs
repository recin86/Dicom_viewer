//! Limited native Part 10 adapter with immutable pixels and display metadata.
//!
//! Accepts legacy single-frame gray CT/MR/Secondary Capture and unsigned-8
//! RGB/YBR_FULL/even-width YBR_FULL_422 Secondary Capture, in native LE/BE
//! syntax (8-bit BE OW is explicitly excluded). Color is normalized once to
//! row-major RGBA8, with no ICC-based color-match claim.
//! Gray samples are normalized stored integers, then simple rescale is applied
//! once in F64 before F32LE output. The image API resolves VOI/polarity/aspect
//! and hashes the same input snapshot; spatial geometry and F64 measurements
//! remain outside this API. Pixel-only preparation preserves PIXEL-1 behavior.
//! Parser allocations are not covered by the payload budget or a hostile-input
//! memory guarantee. Input is capped on the same opened handle before parsing.

use std::fs::OpenOptions;
use std::io::{Cursor, Read};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::sync::Arc;

use dicom_object::{DefaultDicomObject, FileMetaTable, OpenFileOptions, Tag, file::ReadPreamble};
use sha2::{Digest, Sha256};

use crate::display::{DisplayDescriptor, from_native_object};
use crate::frame::{FrameBudget, FrameData, FrameError};
use crate::native_color::NativeColorLayout;

const MAX_INPUT_BYTES: u64 = 32 * 1024 * 1024;
const IMPLICIT_LE: &str = "1.2.840.10008.1.2";
const EXPLICIT_LE: &str = "1.2.840.10008.1.2.1";
const EXPLICIT_BE: &str = "1.2.840.10008.1.2.2";
const CT: &str = "1.2.840.10008.5.1.4.1.1.2";
const MR: &str = "1.2.840.10008.5.1.4.1.1.4";
const SC: &str = "1.2.840.10008.5.1.4.1.1.7";
const PIXEL_DATA: Tag = Tag(0x7fe0, 0x0010);

#[derive(Debug)]
pub struct PreparedImage {
    pub frame: Arc<FrameData>,
    pub display: DisplayDescriptor,
    /// Lowercase SHA-256 hex of the bounded bytes read on the opened handle.
    /// This identifies the input snapshot, not a promise the file stays fixed.
    pub source_revision: String,
}

/// Prepares one immutable pixel buffer from a bounded, opened native file.
///
/// Only frame index zero is accepted. No path or tag value is included in errors.
pub fn prepare_native_frame(
    path: &Path,
    frame_index: u32,
    budget: Arc<FrameBudget>,
) -> Result<Arc<FrameData>, FrameError> {
    let bytes = read_native_input(path, frame_index)?;
    prepare_bytes(&bytes, budget)
}

/// Prepares native display metadata and the pixels from one opened snapshot.
pub fn prepare_native_image(
    path: &Path,
    frame_index: u32,
    budget: Arc<FrameBudget>,
) -> Result<PreparedImage, FrameError> {
    let bytes = read_native_input(path, frame_index)?;
    prepare_image_bytes(&bytes, budget)
}

fn read_native_input(path: &Path, frame_index: u32) -> Result<Vec<u8>, FrameError> {
    if frame_index != 0 {
        return Err(FrameError::InvalidArgument("frame_index"));
    }
    // O_NONBLOCK prevents a FIFO from blocking in open before fstat can reject
    // it. The regular-file check and bounded read use this same handle.
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(path)
        .map_err(|_| FrameError::Io)?;
    let metadata = file.metadata().map_err(|_| FrameError::Io)?;
    if !metadata.is_file() {
        return Err(FrameError::InvalidArgument("input_not_regular_file"));
    }
    read_bounded(file, metadata.len())
}

fn read_bounded(reader: impl Read, observed_length: u64) -> Result<Vec<u8>, FrameError> {
    if observed_length > MAX_INPUT_BYTES {
        return Err(FrameError::ResourceLimit("input_bytes"));
    }
    // Metadata is only an early check. A file growing after that check is still
    // read through this fixed limit on its already-open handle.
    let mut reader = reader.take(MAX_INPUT_BYTES + 1);
    let mut bytes = Vec::new();
    let mut chunk = [0; 8192];
    loop {
        let count = reader.read(&mut chunk).map_err(|_| FrameError::Io)?;
        if count == 0 {
            break;
        }
        if bytes.len() as u64 + count as u64 > MAX_INPUT_BYTES {
            return Err(FrameError::ResourceLimit("input_bytes"));
        }
        bytes
            .try_reserve(count)
            .map_err(|_| FrameError::ResourceLimit("input_allocation"))?;
        bytes.extend_from_slice(&chunk[..count]);
    }
    Ok(bytes)
}

fn prepare_bytes(bytes: &[u8], budget: Arc<FrameBudget>) -> Result<Arc<FrameData>, FrameError> {
    let object = parse_object(bytes)?;
    frame_from_object(&object, budget)
}

fn prepare_image_bytes(
    bytes: &[u8],
    budget: Arc<FrameBudget>,
) -> Result<PreparedImage, FrameError> {
    let object = parse_object(bytes)?;
    let frame = frame_from_object(&object, budget)?;
    let display = from_native_object(&object, &frame)?;
    Ok(PreparedImage {
        frame,
        display,
        source_revision: source_revision(bytes),
    })
}

fn source_revision(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn parse_object(bytes: &[u8]) -> Result<DefaultDicomObject, FrameError> {
    if bytes.len() < 132 || &bytes[128..132] != b"DICM" {
        return Err(FrameError::DecodeFailed("part10_header"));
    }
    // Check syntax before the dataset reader can invoke a deflate/codec path.
    let meta = FileMetaTable::from_reader(Cursor::new(&bytes[128..]))
        .map_err(|_| FrameError::DecodeFailed("file_meta"))?;
    match meta.transfer_syntax() {
        IMPLICIT_LE | EXPLICIT_LE | EXPLICIT_BE => {}
        _ => return Err(FrameError::Unsupported("transfer_syntax")),
    }
    if !matches!(meta.media_storage_sop_class_uid(), CT | MR | SC) {
        return Err(FrameError::Unsupported("sop_class"));
    }
    let object = OpenFileOptions::new()
        .read_preamble(ReadPreamble::Always)
        .from_reader(Cursor::new(bytes))
        .map_err(|_| FrameError::DecodeFailed("dataset"))?;
    let sop = text(&object, Tag(0x0008, 0x0016))?;
    let instance = text(&object, Tag(0x0008, 0x0018))?;
    if sop != object.meta().media_storage_sop_class_uid()
        || instance != object.meta().media_storage_sop_instance_uid()
    {
        return Err(FrameError::DecodeFailed("sop_identity_mismatch"));
    }
    if optional_i32(&object, Tag(0x0028, 0x0008))?.unwrap_or(1) != 1 {
        return Err(FrameError::Unsupported("multi_frame"));
    }
    // These carry transforms/dimensions that this adapter cannot preserve.
    for tag in [
        Tag(0x5200, 0x9229), // Shared Functional Groups
        Tag(0x5200, 0x9230), // Per-frame Functional Groups
        Tag(0x0028, 0x3000), // Modality LUT
        Tag(0x0028, 0x3010), // VOI LUT
        Tag(0x2050, 0x0010), // Presentation LUT
        Tag(0x0040, 0x9096), // Real World Value Mapping
        Tag(0x0028, 0x2000), // ICC Profile
        Tag(0x0028, 0x2002), // Color Space
        Tag(0x0028, 0x7fe0), // Pixel Data Provider URL
        Tag(0x7fe0, 0x0008), // Float Pixel Data
        Tag(0x7fe0, 0x0009), // Double Float Pixel Data
    ] {
        if object.get(tag).is_some() {
            return Err(FrameError::Unsupported("pixel_transform_or_dimension"));
        }
    }
    Ok(object)
}

fn frame_from_object(
    object: &DefaultDicomObject,
    budget: Arc<FrameBudget>,
) -> Result<Arc<FrameData>, FrameError> {
    let big_endian = object.meta().transfer_syntax() == EXPLICIT_BE;
    let sop = text(object, Tag(0x0008, 0x0016))?;
    let height = u32::from(required_u16(object, Tag(0x0028, 0x0010))?);
    let width = u32::from(required_u16(object, Tag(0x0028, 0x0011))?);
    if width == 0 || height == 0 {
        return Err(FrameError::DecodeFailed("zero_dimensions"));
    }
    let samples = required_u16(object, Tag(0x0028, 0x0002))?;
    let allocated = required_u16(object, Tag(0x0028, 0x0100))?;
    let stored = required_u16(object, Tag(0x0028, 0x0101))?;
    let high_bit = required_u16(object, Tag(0x0028, 0x0102))?;
    let representation = required_u16(object, Tag(0x0028, 0x0103))?;
    if !matches!(allocated, 8 | 16) {
        return Err(FrameError::Unsupported("bits_allocated"));
    }
    if stored == 0
        || stored > allocated
        || high_bit >= allocated
        || high_bit + 1 < stored
        || representation > 1
    {
        return Err(FrameError::DecodeFailed("pixel_bit_metadata"));
    }
    let count = usize::try_from(u64::from(width) * u64::from(height))
        .map_err(|_| FrameError::ResourceLimit("addressable_size"))?;
    let photometric = text(object, Tag(0x0028, 0x0004))?;
    let color_layout =
        if samples == 3 && matches!(photometric.as_str(), "RGB" | "YBR_FULL" | "YBR_FULL_422") {
            if sop != SC {
                return Err(FrameError::Unsupported("rgb_sop_class"));
            }
            if allocated != 8 || stored != 8 || high_bit != 7 || representation != 0 {
                return Err(FrameError::Unsupported("rgb_layout"));
            }
            if [
                Tag(0x0028, 0x1052),
                Tag(0x0028, 0x1053),
                Tag(0x0028, 0x0120),
                Tag(0x0028, 0x0121),
            ]
            .iter()
            .any(|&tag| object.get(tag).is_some())
            {
                return Err(FrameError::Unsupported("rgb_transform"));
            }
            Some(NativeColorLayout::new(
                &photometric,
                required_u16(object, Tag(0x0028, 0x0006))?,
                width,
            )?)
        } else {
            None
        };
    let expected = if let Some(layout) = color_layout {
        layout.encoded_bytes(count)?
    } else {
        count
            .checked_mul(usize::from(samples))
            .and_then(|n| n.checked_mul(usize::from(allocated / 8)))
            .ok_or(FrameError::ResourceLimit("pixel_size_overflow"))?
    };
    let source = PixelSource::from_object(object, allocated, big_endian, expected)?;
    if samples == 1 && matches!(photometric.as_str(), "MONOCHROME1" | "MONOCHROME2") {
        let slope = optional_f64(object, Tag(0x0028, 0x1053))?;
        let intercept = optional_f64(object, Tag(0x0028, 0x1052))?;
        let (slope, intercept) = match (slope, intercept) {
            (None, None) => (1.0, 0.0),
            (Some(slope), Some(intercept))
                if slope.is_finite() && intercept.is_finite() && slope != 0.0 =>
            {
                (slope, intercept)
            }
            _ => return Err(FrameError::Unsupported("rescale_metadata")),
        };
        let padding = optional_i32(object, Tag(0x0028, 0x0120))?;
        let limit = optional_i32(object, Tag(0x0028, 0x0121))?;
        let padding = padding_range(padding, limit, stored, representation == 1)?;
        FrameData::gray_from_fn(width, height, budget, padding.is_some(), |i| {
            let value = normalize(source.sample(i), stored, high_bit, representation == 1);
            if padding.is_some_and(|(low, high)| low <= value && value <= high) {
                Ok(None)
            } else {
                Ok(Some(f64::from(value) * slope + intercept))
            }
        })
    } else if let Some(layout) = color_layout {
        layout.into_frame(width, height, budget, |i| source.sample(i) as u8)
    } else {
        Err(FrameError::Unsupported("photometric_or_samples"))
    }
}

/// OW values have already been endian-decoded to u16 by dicom-rs 0.10's
/// StatefulDecoder::read_value_us. OB remains bytes. Do not reinterpret OW's
/// to_bytes() as transfer-syntax bytes: those are native-memory bytes.
enum PixelSource<'a> {
    Words16(&'a [u16]),
    Bytes8(&'a [u8]),
    Words8(&'a [u16]),
}

impl<'a> PixelSource<'a> {
    fn from_object(
        object: &'a DefaultDicomObject,
        allocated: u16,
        big_endian: bool,
        expected: usize,
    ) -> Result<Self, FrameError> {
        let element = object
            .get(PIXEL_DATA)
            .ok_or(FrameError::DecodeFailed("missing_pixel_data"))?;
        let primitive = element
            .value()
            .primitive()
            .ok_or(FrameError::Unsupported("encapsulated_pixels"))?;
        let encoded_length = element
            .header()
            .len
            .get()
            .ok_or(FrameError::DecodeFailed("pixel_length"))? as usize;
        let padded = expected
            .checked_add(expected % 2)
            .ok_or(FrameError::ResourceLimit("pixel_size_overflow"))?;
        if encoded_length != padded {
            return Err(FrameError::DecodeFailed("pixel_length"));
        }
        if allocated == 16 {
            let words = primitive
                .uint16_slice()
                .map_err(|_| FrameError::Unsupported("native_16bit_vr"))?;
            if words.len() * 2 != expected {
                return Err(FrameError::DecodeFailed("pixel_length"));
            }
            Ok(Self::Words16(words))
        } else if let Ok(bytes) = primitive.uint8_slice() {
            if bytes.len() != padded || (!expected.is_multiple_of(2) && bytes[expected] != 0) {
                return Err(FrameError::DecodeFailed("pixel_length_or_padding"));
            }
            Ok(Self::Bytes8(bytes))
        } else if let Ok(words) = primitive.uint16_slice() {
            if big_endian {
                // 8-bit OW's BE word/byte ordering awaits a separate oracle.
                return Err(FrameError::Unsupported("big_endian_8bit_ow"));
            }
            if words.len() * 2 != padded
                || (!expected.is_multiple_of(2) && words[expected / 2] >> 8 != 0)
            {
                return Err(FrameError::DecodeFailed("pixel_length_or_padding"));
            }
            Ok(Self::Words8(words))
        } else {
            Err(FrameError::Unsupported("native_pixel_vr"))
        }
    }

    fn sample(&self, i: usize) -> u16 {
        match self {
            Self::Words16(words) => words[i],
            Self::Bytes8(bytes) => u16::from(bytes[i]),
            Self::Words8(words) => (words[i / 2] >> ((i % 2) * 8)) & 0xff,
        }
    }
}

fn normalize(word: u16, stored: u16, high_bit: u16, signed: bool) -> i32 {
    let mask = (1_u32 << stored) - 1;
    let value = (u32::from(word) >> (high_bit + 1 - stored)) & mask;
    if signed && value & (1 << (stored - 1)) != 0 {
        value as i32 - (1_i32 << stored)
    } else {
        value as i32
    }
}

fn padding_range(
    padding: Option<i32>,
    limit: Option<i32>,
    stored: u16,
    signed: bool,
) -> Result<Option<(i32, i32)>, FrameError> {
    match (padding, limit) {
        (None, None) => Ok(None),
        (None, Some(_)) => Err(FrameError::DecodeFailed("padding_limit_without_value")),
        (Some(value), limit) => {
            let limit = limit.unwrap_or(value);
            let (min, max) = if signed {
                (-(1_i32 << (stored - 1)), (1_i32 << (stored - 1)) - 1)
            } else {
                (0, (1_i32 << stored) - 1)
            };
            if value < min || value > max || limit < min || limit > max {
                return Err(FrameError::DecodeFailed("padding_range"));
            }
            Ok(Some((value.min(limit), value.max(limit))))
        }
    }
}

fn required_u16(object: &DefaultDicomObject, tag: Tag) -> Result<u16, FrameError> {
    let element = object
        .get(tag)
        .ok_or(FrameError::DecodeFailed("missing_metadata"))?;
    if element
        .value()
        .primitive()
        .is_none_or(|p| p.multiplicity() != 1)
    {
        return Err(FrameError::DecodeFailed("metadata_multiplicity"));
    }
    element
        .to_int()
        .map_err(|_| FrameError::DecodeFailed("integer_metadata"))
}

fn optional_i32(object: &DefaultDicomObject, tag: Tag) -> Result<Option<i32>, FrameError> {
    object
        .get(tag)
        .map(|element| {
            if element
                .value()
                .primitive()
                .is_none_or(|p| p.multiplicity() != 1)
            {
                return Err(FrameError::DecodeFailed("metadata_multiplicity"));
            }
            element
                .to_int()
                .map_err(|_| FrameError::DecodeFailed("integer_metadata"))
        })
        .transpose()
}

fn optional_f64(object: &DefaultDicomObject, tag: Tag) -> Result<Option<f64>, FrameError> {
    object
        .get(tag)
        .map(|element| {
            if element
                .value()
                .primitive()
                .is_none_or(|p| p.multiplicity() != 1)
            {
                return Err(FrameError::DecodeFailed("metadata_multiplicity"));
            }
            element
                .to_float64()
                .map_err(|_| FrameError::DecodeFailed("decimal_metadata"))
        })
        .transpose()
}

fn text(object: &DefaultDicomObject, tag: Tag) -> Result<String, FrameError> {
    let element = object
        .get(tag)
        .ok_or(FrameError::DecodeFailed("missing_metadata"))?;
    if element
        .value()
        .primitive()
        .is_none_or(|p| p.multiplicity() != 1)
    {
        return Err(FrameError::DecodeFailed("metadata_multiplicity"));
    }
    let value = element
        .to_str()
        .map_err(|_| FrameError::DecodeFailed("text_metadata"))?;
    let value = value.trim_end_matches(|c: char| c.is_whitespace() || c == '\0');
    if value.is_empty() {
        return Err(FrameError::DecodeFailed("empty_metadata"));
    }
    Ok(value.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn budget() -> Arc<FrameBudget> {
        FrameBudget::new(1024, 1024).unwrap()
    }

    #[test]
    fn stored_bits_shift_sign_and_padding_have_literal_expectations() {
        // Dirty unused upper/lower bits must not become value or sign bits.
        assert_eq!(normalize(0xa800, 12, 11, true), -2048);
        assert_eq!(normalize(0xafff, 12, 11, true), -1);
        assert_eq!(normalize(0xa7ff, 12, 11, true), 2047);
        assert_eq!(normalize(0xfff9, 8, 11, true), -1);
        assert_eq!(normalize(0x801f, 8, 11, false), 1);
        assert_eq!(normalize(0xffff, 16, 15, false), 65535);
        assert_eq!(normalize(0x8000, 16, 15, true), -32768);
        assert_eq!(
            padding_range(Some(-1), Some(-3), 12, true).unwrap(),
            Some((-3, -1))
        );
        assert!(padding_range(None, Some(1), 8, false).is_err());
        assert!(padding_range(Some(256), None, 8, false).is_err());
    }

    #[test]
    fn bounded_read_checks_actual_bytes_even_after_a_small_metadata_observation() {
        struct RepeatedBytes(u64);
        impl Read for RepeatedBytes {
            fn read(&mut self, target: &mut [u8]) -> std::io::Result<usize> {
                let count = target.len().min(self.0 as usize);
                target[..count].fill(0);
                self.0 -= count as u64;
                Ok(count)
            }
        }
        assert_eq!(
            read_bounded(RepeatedBytes(MAX_INPUT_BYTES + 100), 0).unwrap_err(),
            FrameError::ResourceLimit("input_bytes")
        );
        assert_eq!(
            read_bounded(Cursor::new([]), MAX_INPUT_BYTES + 1).unwrap_err(),
            FrameError::ResourceLimit("input_bytes")
        );
    }

    // Independent byte writer: these tests do not serialize through dicom-rs.
    fn element(tag: Tag, vr: &[u8; 2], value: &[u8], be: bool, implicit: bool) -> Vec<u8> {
        let mut out = Vec::new();
        for n in [tag.0, tag.1] {
            out.extend_from_slice(&if be { n.to_be_bytes() } else { n.to_le_bytes() });
        }
        let length = (value.len() + value.len() % 2) as u32;
        if implicit {
            out.extend_from_slice(&length.to_le_bytes());
        } else {
            out.extend_from_slice(vr);
            if matches!(vr, b"OB" | b"OW" | b"SQ") {
                out.extend_from_slice(&[0, 0]);
                out.extend_from_slice(&if be {
                    length.to_be_bytes()
                } else {
                    length.to_le_bytes()
                });
            } else {
                out.extend_from_slice(&if be {
                    (length as u16).to_be_bytes()
                } else {
                    (length as u16).to_le_bytes()
                });
            }
        }
        out.extend_from_slice(value);
        if !value.len().is_multiple_of(2) {
            out.push(if vr == b"UI" || vr == b"OB" || vr == b"OW" {
                0
            } else {
                b' '
            });
        }
        out
    }

    fn part10(syntax: &str, color: bool, extras: &[(Tag, &[u8; 2], Vec<u8>)]) -> Vec<u8> {
        part10_with_sop(syntax, color, extras, None)
    }

    fn part10_with_sop(
        syntax: &str,
        color: bool,
        extras: &[(Tag, &[u8; 2], Vec<u8>)],
        sop: Option<&str>,
    ) -> Vec<u8> {
        let be = syntax == EXPLICIT_BE;
        let implicit = syntax == IMPLICIT_LE;
        let sop = sop.unwrap_or(if color { SC } else { CT });
        let uid = "1.2.826.0.1.3680043.10.543.999";
        let mut meta = Vec::new();
        for (tag, value) in [
            (Tag(2, 2), sop),
            (Tag(2, 3), uid),
            (Tag(2, 0x10), syntax),
            (Tag(2, 0x12), uid),
        ] {
            meta.extend(element(tag, b"UI", value.as_bytes(), false, false));
        }
        let mut output = vec![0; 128];
        output.extend(b"DICM");
        output.extend(element(
            Tag(2, 0),
            b"UL",
            &(meta.len() as u32).to_le_bytes(),
            false,
            false,
        ));
        output.extend(meta);
        let mut tags: Vec<(Tag, &[u8; 2], Vec<u8>)> = vec![
            (Tag(8, 0x16), b"UI", sop.as_bytes().to_vec()),
            (Tag(8, 0x18), b"UI", uid.as_bytes().to_vec()),
            (
                Tag(0x28, 4),
                b"CS",
                if color {
                    b"RGB".to_vec()
                } else {
                    b"MONOCHROME2".to_vec()
                },
            ),
        ];
        for (tag, value) in [
            (2, if color { 3_u16 } else { 1 }),
            (0x10, 1),
            (0x11, if color { 2 } else { 6 }),
            (0x100, if color { 8 } else { 16 }),
            (0x101, if color { 8 } else { 12 }),
            (0x102, if color { 7 } else { 11 }),
            (0x103, if color { 0 } else { 1 }),
        ] {
            tags.push((
                Tag(0x28, tag),
                b"US",
                if be {
                    value.to_be_bytes().to_vec()
                } else {
                    value.to_le_bytes().to_vec()
                },
            ));
        }
        if color {
            tags.push((Tag(0x28, 6), b"US", vec![0, 0]));
            tags.push((PIXEL_DATA, b"OB", vec![255, 0, 0, 17, 34, 51]));
        } else {
            tags.push((
                Tag(0x28, 0x120),
                b"SS",
                if be {
                    (-2048_i16).to_be_bytes().to_vec()
                } else {
                    (-2048_i16).to_le_bytes().to_vec()
                },
            ));
            tags.push((Tag(0x28, 0x1052), b"DS", b"-10".to_vec()));
            tags.push((Tag(0x28, 0x1053), b"DS", b"2".to_vec()));
            let mut pixels = Vec::new();
            for word in [0xa800_u16, 0xafff, 0xa000, 0xa001, 0xa400, 0xa7ff] {
                pixels.extend_from_slice(&if be {
                    word.to_be_bytes()
                } else {
                    word.to_le_bytes()
                });
            }
            tags.push((PIXEL_DATA, b"OW", pixels));
        }
        for (tag, vr, value) in extras {
            tags.retain(|(existing, _, _)| existing != tag);
            tags.push((*tag, *vr, value.clone()));
        }
        tags.sort_by_key(|(tag, _, _)| *tag);
        for (tag, vr, value) in tags {
            output.extend(element(tag, vr, &value, be, implicit));
        }
        output
    }

    #[test]
    fn native_part10_le_be_implicit_have_the_same_independent_modality_golden() {
        for syntax in [EXPLICIT_LE, EXPLICIT_BE, IMPLICIT_LE] {
            let budget = budget();
            let frame = prepare_bytes(&part10(syntax, false, &[]), Arc::clone(&budget)).unwrap();
            let actual: Vec<f32> = frame
                .pixels()
                .as_chunks::<4>()
                .0
                .iter()
                .map(|&b| f32::from_le_bytes(b))
                .collect();
            assert_eq!(actual, [0.0, -12.0, -10.0, -8.0, 2038.0, 4084.0]);
            assert_eq!(frame.mask(), Some([0, 1, 1, 1, 1, 1].as_slice()));
            assert_eq!(frame.accounted_bytes(), 30);
            drop(frame);
            assert_eq!(budget.snapshot().live_bytes, 0);
        }
    }

    #[test]
    fn native_rgb_ob_and_implicit_ow_preserve_channel_order() {
        for syntax in [EXPLICIT_LE, EXPLICIT_BE, IMPLICIT_LE] {
            let frame = prepare_bytes(&part10(syntax, true, &[]), budget()).unwrap();
            assert_eq!(frame.pixels(), &[255, 0, 0, 255, 17, 34, 51, 255]);
            assert_eq!(frame.mask(), None);
        }
    }

    #[test]
    fn sc_native_color_layouts_parse_to_independent_literal_rgba() {
        let rgb = vec![
            255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 17, 34, 51,
        ];
        let planar = vec![
            255, 0, 0, 0, 255, 17, 0, 255, 0, 0, 255, 34, 0, 0, 255, 0, 255, 51,
        ];
        let rgb_golden = vec![
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255, 17,
            34, 51, 255,
        ];
        let ybr_golden = vec![
            254, 0, 0, 255, 0, 255, 1, 255, 0, 0, 254, 255, 0, 0, 0, 255, 255, 255, 255, 255, 128,
            128, 128, 255,
        ];
        for (syntax, photometric, planar_value, width, pixels, golden) in [
            (EXPLICIT_LE, "RGB", 0, 3, rgb.clone(), rgb_golden.clone()),
            (EXPLICIT_LE, "RGB", 1, 3, planar.clone(), rgb_golden.clone()),
            (IMPLICIT_LE, "RGB", 1, 3, planar, rgb_golden.clone()),
            (EXPLICIT_BE, "RGB", 0, 3, rgb, rgb_golden),
            (
                EXPLICIT_LE,
                "YBR_FULL",
                0,
                3,
                vec![
                    76, 85, 255, 150, 44, 21, 29, 255, 107, 0, 128, 128, 255, 128, 128, 128, 128,
                    128,
                ],
                ybr_golden.clone(),
            ),
            (
                EXPLICIT_LE,
                "YBR_FULL",
                1,
                3,
                vec![
                    76, 150, 29, 0, 255, 128, 85, 44, 255, 128, 128, 128, 255, 21, 107, 128, 128,
                    128,
                ],
                ybr_golden,
            ),
            (
                EXPLICIT_LE,
                "YBR_FULL_422",
                0,
                4,
                vec![
                    76, 100, 85, 255, 29, 60, 255, 107, 0, 255, 128, 128, 128, 64, 128, 128,
                ],
                vec![
                    254, 0, 0, 255, 255, 24, 24, 255, 0, 0, 254, 255, 31, 31, 255, 255, 0, 0, 0,
                    255, 255, 255, 255, 255, 128, 128, 128, 255, 64, 64, 64, 255,
                ],
            ),
        ] {
            let us = |n: u16| {
                if syntax == EXPLICIT_BE {
                    n.to_be_bytes().to_vec()
                } else {
                    n.to_le_bytes().to_vec()
                }
            };
            let bytes = part10(
                syntax,
                true,
                &[
                    (Tag(0x28, 4), b"CS", photometric.as_bytes().to_vec()),
                    (Tag(0x28, 6), b"US", us(planar_value)),
                    (Tag(0x28, 0x10), b"US", us(2)),
                    (Tag(0x28, 0x11), b"US", us(width)),
                    (PIXEL_DATA, b"OB", pixels),
                ],
            );
            let budget = FrameBudget::new(golden.len() as u64, golden.len() as u64).unwrap();
            let image = prepare_image_bytes(&bytes, Arc::clone(&budget)).unwrap();
            assert_eq!(image.frame.pixels(), golden);
            assert_eq!(image.frame.pixel_format(), crate::frame::PixelFormat::Rgba8);
            assert_eq!(image.frame.mask(), None);
            assert_eq!(image.frame.width(), u32::from(width));
            assert_eq!(image.frame.height(), 2);
            assert!(!image.display.can_window);
            assert!(!image.display.inverted);
            assert!(!image.display.automatic_window);
            assert!(image.display.windows.is_empty());
            assert!(image.display.default_window.is_none());
            assert_eq!(image.display.unit, "unknown");
            assert_eq!(image.source_revision, source_revision(&bytes));
            assert_eq!(
                crate::display::reference_rgba(&image.frame, &image.display, None, true).unwrap(),
                golden
            );
            assert_eq!(budget.snapshot().live_bytes, golden.len() as u64);
            let owner = Arc::clone(&image.frame);
            drop(image);
            assert_eq!(budget.snapshot().live_bytes, golden.len() as u64);
            assert_eq!(owner.pixels(), golden);
            drop(owner);
            assert_eq!(budget.snapshot().live_bytes, 0);
        }
    }

    #[test]
    fn sc_color_layout_transform_and_length_errors_have_safe_categories() {
        for (extras, expected) in [
            (
                vec![(Tag(0x28, 6), b"US", 2_u16.to_le_bytes().to_vec())],
                FrameError::Unsupported("native_color_layout"),
            ),
            (
                vec![(Tag(0x28, 0x103), b"US", 1_u16.to_le_bytes().to_vec())],
                FrameError::Unsupported("rgb_layout"),
            ),
            (
                vec![(Tag(0x28, 0x1053), b"DS", b"2".to_vec())],
                FrameError::Unsupported("rgb_transform"),
            ),
            (
                vec![(Tag(0x28, 0x120), b"US", 0_u16.to_le_bytes().to_vec())],
                FrameError::Unsupported("rgb_transform"),
            ),
            (
                vec![(Tag(0x28, 0x100), b"US", 16_u16.to_le_bytes().to_vec())],
                FrameError::Unsupported("rgb_layout"),
            ),
            (
                vec![(PIXEL_DATA, b"OB", vec![0; 4])],
                FrameError::DecodeFailed("pixel_length"),
            ),
            (
                vec![(PIXEL_DATA, b"OB", vec![0; 8])],
                FrameError::DecodeFailed("pixel_length"),
            ),
            (
                vec![
                    (Tag(0x28, 4), b"CS", b"YBR_FULL_422".to_vec()),
                    (Tag(0x28, 6), b"US", 1_u16.to_le_bytes().to_vec()),
                ],
                FrameError::Unsupported("native_color_layout"),
            ),
            (
                vec![
                    (Tag(0x28, 4), b"CS", b"YBR_FULL_422".to_vec()),
                    (Tag(0x28, 0x11), b"US", 3_u16.to_le_bytes().to_vec()),
                ],
                FrameError::Unsupported("odd_width_ybr422"),
            ),
            (
                vec![
                    (Tag(0x28, 4), b"CS", b"YBR_FULL_422".to_vec()),
                    (PIXEL_DATA, b"OB", vec![0; 2]),
                ],
                FrameError::DecodeFailed("pixel_length"),
            ),
        ] {
            let budget = budget();
            let actual =
                prepare_image_bytes(&part10(EXPLICIT_LE, true, &extras), Arc::clone(&budget))
                    .err()
                    .unwrap();
            assert_eq!(actual, expected);
            assert_eq!(budget.snapshot().live_bytes, 0);
            assert_eq!(budget.snapshot().peak_bytes, 0);
        }
        let error = prepare_image_bytes(
            &part10(
                EXPLICIT_BE,
                true,
                &[(PIXEL_DATA, b"OW", vec![255, 0, 0, 17, 34, 51])],
            ),
            budget(),
        )
        .err()
        .unwrap();
        assert_eq!(error, FrameError::Unsupported("big_endian_8bit_ow"));
    }

    #[test]
    fn color_image_presentation_rejection_releases_its_reserved_payload() {
        for (tag, vr, value) in [
            (Tag(0x28, 0x1050), b"DS", b"0".to_vec()),
            (Tag(0x28, 0x1051), b"DS", b"1".to_vec()),
            (Tag(0x28, 0x1056), b"CS", b"LINEAR".to_vec()),
            (Tag(0x2050, 0x20), b"CS", b"INVERSE".to_vec()),
        ] {
            let budget = FrameBudget::new(8, 8).unwrap();
            let error = prepare_image_bytes(
                &part10(EXPLICIT_LE, true, &[(tag, vr, value)]),
                Arc::clone(&budget),
            )
            .err()
            .unwrap();
            assert_eq!(error, FrameError::Unsupported("rgb_presentation_transform"));
            assert_eq!(budget.snapshot().peak_bytes, 8);
            assert_eq!(budget.snapshot().live_bytes, 0);
        }
    }

    #[test]
    fn unsupported_color_sop_palette_profile_and_bit_depth_remain_explicit() {
        let us = "1.2.840.10008.5.1.4.1.1.6.1";
        let budget = budget();
        let error = prepare_image_bytes(
            &part10_with_sop(EXPLICIT_LE, true, &[], Some(us)),
            Arc::clone(&budget),
        )
        .err()
        .unwrap();
        assert_eq!(error, FrameError::Unsupported("sop_class"));
        for extras in [
            vec![
                (Tag(0x28, 4), b"CS", b"PALETTE COLOR".to_vec()),
                (Tag(0x28, 2), b"US", 1_u16.to_le_bytes().to_vec()),
                (PIXEL_DATA, b"OB", vec![0, 1]),
            ],
            vec![(Tag(0x28, 0x2000), b"OB", vec![0, 0])],
            vec![(Tag(0x28, 0x2002), b"CS", b"SRGB".to_vec())],
            vec![(Tag(0x28, 0x101), b"US", 7_u16.to_le_bytes().to_vec())],
            vec![
                (Tag(0x28, 0x100), b"US", 16_u16.to_le_bytes().to_vec()),
                (Tag(0x28, 0x101), b"US", 16_u16.to_le_bytes().to_vec()),
                (Tag(0x28, 0x102), b"US", 15_u16.to_le_bytes().to_vec()),
            ],
        ] {
            let error =
                prepare_image_bytes(&part10(EXPLICIT_LE, true, &extras), Arc::clone(&budget))
                    .err()
                    .unwrap();
            assert!(matches!(error, FrameError::Unsupported(_)));
            assert_eq!(budget.snapshot().live_bytes, 0);
            assert_eq!(budget.snapshot().peak_bytes, 0);
        }
    }

    #[test]
    fn color_payload_limits_reject_before_allocation_and_allow_recovery() {
        let budget = FrameBudget::new(8, 8).unwrap();
        let small =
            prepare_image_bytes(&part10(EXPLICIT_LE, true, &[]), Arc::clone(&budget)).unwrap();
        let blocked = prepare_image_bytes(&part10(EXPLICIT_LE, true, &[]), Arc::clone(&budget))
            .err()
            .unwrap();
        assert!(matches!(blocked, FrameError::ResourceLimit(_)));
        assert_eq!(budget.snapshot().live_bytes, 8);
        drop(small);
        assert_eq!(budget.snapshot().live_bytes, 0);
        let recovered =
            prepare_image_bytes(&part10(EXPLICIT_LE, true, &[]), Arc::clone(&budget)).unwrap();
        assert_eq!(recovered.frame.pixels(), [255, 0, 0, 255, 17, 34, 51, 255]);
        drop(recovered);
        assert_eq!(budget.snapshot().live_bytes, 0);
    }

    #[test]
    fn rgb_ct_and_mr_do_not_inherit_secondary_capture_support() {
        for sop in [CT, MR] {
            assert_eq!(
                prepare_bytes(
                    &part10_with_sop(EXPLICIT_LE, true, &[], Some(sop)),
                    budget()
                )
                .unwrap_err(),
                FrameError::Unsupported("rgb_sop_class")
            );
        }
    }

    #[test]
    fn native_unsigned_8bit_ob_and_implicit_ow_use_stored_bits_and_padding_range() {
        for syntax in [EXPLICIT_LE, IMPLICIT_LE] {
            let bytes = part10(
                syntax,
                false,
                &[
                    (Tag(0x28, 0x11), b"US", 3_u16.to_le_bytes().to_vec()),
                    (Tag(0x28, 0x100), b"US", 8_u16.to_le_bytes().to_vec()),
                    (Tag(0x28, 0x101), b"US", 6_u16.to_le_bytes().to_vec()),
                    (Tag(0x28, 0x102), b"US", 7_u16.to_le_bytes().to_vec()),
                    (Tag(0x28, 0x103), b"US", 0_u16.to_le_bytes().to_vec()),
                    (Tag(0x28, 0x120), b"US", 1_u16.to_le_bytes().to_vec()),
                    (Tag(0x28, 0x121), b"US", 2_u16.to_le_bytes().to_vec()),
                    (PIXEL_DATA, b"OB", vec![7, 11, 255]),
                ],
            );
            let frame = prepare_bytes(&bytes, budget()).unwrap();
            let values: Vec<f32> = frame
                .pixels()
                .as_chunks::<4>()
                .0
                .iter()
                .map(|&b| f32::from_le_bytes(b))
                .collect();
            assert_eq!(values, [0.0, 0.0, 116.0]);
            assert_eq!(frame.mask(), Some([0, 0, 1].as_slice()));
            assert_eq!(frame.accounted_bytes(), 15);
        }
    }

    struct TemporaryInput {
        directory: std::path::PathBuf,
        path: std::path::PathBuf,
    }

    impl TemporaryInput {
        fn new() -> Self {
            use std::sync::atomic::{AtomicU64, Ordering};
            static SEQUENCE: AtomicU64 = AtomicU64::new(0);
            let directory = std::env::temp_dir().join(format!(
                "viewer-core-pixel-{}-{}",
                std::process::id(),
                SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            std::fs::create_dir(&directory).unwrap();
            let path = directory.join("synthetic-input");
            Self { directory, path }
        }
    }

    impl Drop for TemporaryInput {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.path);
            let _ = std::fs::remove_dir(&self.directory);
        }
    }

    #[test]
    fn file_entrypoint_uses_actual_part10_and_safe_frame_index_errors() {
        let input = TemporaryInput::new();
        std::fs::write(&input.path, part10(EXPLICIT_LE, false, &[])).unwrap();
        let frame = prepare_native_frame(&input.path, 0, budget()).unwrap();
        assert_eq!(frame.width(), 6);
        assert_eq!(frame.height(), 1);
        assert_eq!(frame.mask(), Some([0, 1, 1, 1, 1, 1].as_slice()));
        assert_eq!(
            prepare_native_frame(&input.path, 1, budget()).unwrap_err(),
            FrameError::InvalidArgument("frame_index")
        );
        let missing = input.directory.join("missing-private-path");
        let error = prepare_native_frame(&missing, 0, budget()).unwrap_err();
        assert_eq!(error, FrameError::Io);
        assert!(!error.to_string().contains("private-path"));
    }

    #[test]
    fn fifo_is_rejected_without_waiting_for_a_writer() {
        use std::ffi::CString;
        use std::os::unix::ffi::OsStrExt;
        use std::sync::mpsc;
        use std::time::Duration;
        let input = TemporaryInput::new();
        let path = CString::new(input.path.as_os_str().as_bytes()).unwrap();
        // SAFETY: the CString is NUL-terminated and lives through this call.
        assert_eq!(unsafe { libc::mkfifo(path.as_ptr(), 0o600) }, 0);
        let (sender, receiver) = mpsc::channel();
        let worker_path = input.path.clone();
        let worker = std::thread::spawn(move || {
            sender
                .send(prepare_native_frame(&worker_path, 0, budget()))
                .unwrap();
        });
        let result = receiver.recv_timeout(Duration::from_secs(2));
        // If a regression blocked open, release it so the test never leaves a
        // permanently blocked thread. A prompt result is still required.
        let unblock = if result.is_err() {
            Some(
                OpenOptions::new()
                    .read(true)
                    .write(true)
                    .custom_flags(libc::O_NONBLOCK)
                    .open(&input.path)
                    .unwrap(),
            )
        } else {
            None
        };
        worker.join().unwrap();
        drop(unblock);
        assert_eq!(
            result.expect("FIFO open blocked").unwrap_err(),
            FrameError::InvalidArgument("input_not_regular_file")
        );
    }

    fn gray_display_bytes(image: &PreparedImage, user_invert: bool) -> Vec<u8> {
        crate::display::reference_rgba(&image.frame, &image.display, None, user_invert)
            .unwrap()
            .as_chunks::<4>()
            .0
            .iter()
            .map(|pixel| pixel[0])
            .collect()
    }

    #[test]
    fn file_voi_is_applied_once_after_signed_bits_and_rescale() {
        for (function, expected) in [
            ("LINEAR", [0, 0, 170, 255, 255, 255]),
            ("LINEAR_EXACT", [0, 0, 128, 255, 255, 255]),
            ("SIGMOID", [0, 30, 128, 225, 255, 255]),
        ] {
            let image = prepare_image_bytes(
                &part10(
                    EXPLICIT_LE,
                    false,
                    &[
                        (Tag(0x28, 0x1050), b"DS", b"-10".to_vec()),
                        (Tag(0x28, 0x1051), b"DS", b"4".to_vec()),
                        (Tag(0x28, 0x1056), b"CS", function.as_bytes().to_vec()),
                    ],
                ),
                budget(),
            )
            .unwrap();
            assert_eq!(gray_display_bytes(&image, false), expected);
            assert!(!image.display.automatic_window);
            assert!(image.display.can_window);
            assert_eq!(image.display.windows.len(), 1);
            let modality_values: Vec<f32> = image
                .frame
                .pixels()
                .as_chunks::<4>()
                .0
                .iter()
                .map(|&bytes| f32::from_le_bytes(bytes))
                .collect();
            assert_eq!(modality_values, [0.0, -12.0, -10.0, -8.0, 2038.0, 4084.0]);
        }
        let image = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[
                    (Tag(0x28, 0x1050), b"DS", b"-10\\2036".to_vec()),
                    (Tag(0x28, 0x1051), b"DS", b"4\\4096".to_vec()),
                ],
            ),
            budget(),
        )
        .unwrap();
        assert_eq!(image.display.windows.len(), 2);
        assert_eq!(image.display.default_window.as_ref().unwrap().center, -10.0);
        assert_eq!(
            image.display.default_window.as_ref().unwrap().function,
            crate::display::VoiFunction::Linear
        );
        assert_eq!(image.display.windows[1].center, 2036.0);
        assert_eq!(image.display.windows[1].width, 4096.0);
    }

    #[test]
    fn native_automatic_uniform_all_padding_and_polarity_have_independent_expected_outputs() {
        let image = prepare_image_bytes(&part10(EXPLICIT_LE, false, &[]), budget()).unwrap();
        assert!(image.display.automatic_window);
        assert_eq!(
            image.display.default_window.as_ref().unwrap().center,
            2036.0
        );
        assert_eq!(image.display.default_window.as_ref().unwrap().width, 4096.0);
        let uniform = prepare_image_bytes(
            &part10(EXPLICIT_LE, false, &[(PIXEL_DATA, b"OW", vec![0; 12])]),
            budget(),
        )
        .unwrap();
        assert_eq!(
            uniform.display.default_window.as_ref().unwrap().center,
            -10.0
        );
        assert_eq!(uniform.display.default_window.as_ref().unwrap().width, 1.0);
        assert_eq!(gray_display_bytes(&uniform, false), [128; 6]);
        let all_padding = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[(PIXEL_DATA, b"OW", [0x00, 0xa8].repeat(6))],
            ),
            budget(),
        )
        .unwrap();
        assert!(all_padding.display.default_window.is_none());
        assert!(!all_padding.display.can_window);
        assert!(
            all_padding
                .display
                .diagnostics
                .iter()
                .any(|d| d == "no_valid_pixels")
        );
        assert_eq!(gray_display_bytes(&all_padding, false), [0; 6]);
        assert_eq!(gray_display_bytes(&all_padding, true), [0; 6]);
        let m1 = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[
                    (Tag(0x28, 4), b"CS", b"MONOCHROME1".to_vec()),
                    (Tag(0x2050, 0x20), b"CS", b"INVERSE".to_vec()),
                    (Tag(0x28, 0x1050), b"DS", b"-10".to_vec()),
                    (Tag(0x28, 0x1051), b"DS", b"4".to_vec()),
                    (Tag(0x28, 0x1056), b"CS", b"LINEAR_EXACT".to_vec()),
                ],
            ),
            budget(),
        )
        .unwrap();
        assert!(m1.display.inverted);
        assert_eq!(gray_display_bytes(&m1, false), [0, 255, 128, 0, 0, 0]);
        assert_eq!(gray_display_bytes(&m1, true), [0, 0, 128, 255, 255, 255]);
    }

    #[test]
    fn invalid_file_voi_has_no_auto_fallback_and_returns_the_payload_charge() {
        let cases = [
            vec![(Tag(0x28, 0x1050), b"DS", b"-10".to_vec())],
            vec![
                (Tag(0x28, 0x1050), b"DS", b"-10\\0".to_vec()),
                (Tag(0x28, 0x1051), b"DS", b"4".to_vec()),
            ],
            vec![
                (Tag(0x28, 0x1050), b"DS", b"-10".to_vec()),
                (Tag(0x28, 0x1051), b"DS", b"0".to_vec()),
            ],
            vec![
                (Tag(0x28, 0x1050), b"DS", b"NaN".to_vec()),
                (Tag(0x28, 0x1051), b"DS", b"4".to_vec()),
            ],
            vec![(
                Tag(0x28, 0x1056),
                b"CS",
                b"UNSUPPORTED_PRIVATE_FUNCTION".to_vec(),
            )],
            vec![(Tag(0x2050, 0x20), b"CS", b"INVERSE".to_vec())],
        ];
        for extra in cases {
            let bytes = part10(EXPLICIT_LE, false, &extra);
            let budget = budget();
            let error = prepare_image_bytes(&bytes, Arc::clone(&budget)).unwrap_err();
            assert!(matches!(error, FrameError::Unsupported(_)));
            assert!(!error.to_string().contains("PRIVATE_FUNCTION"));
            assert_eq!(budget.snapshot().live_bytes, 0);
            // PIXEL-1 remains a pixel-only contract, independent of file VOI.
            let frame = prepare_bytes(&bytes, Arc::clone(&budget)).unwrap();
            assert_eq!(frame.accounted_bytes(), 30);
            drop(frame);
            assert_eq!(budget.snapshot().live_bytes, 0);
        }
    }

    #[test]
    fn aspect_priority_invalid_fallback_conflicts_and_safe_units_are_preserved() {
        let image = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[
                    (Tag(0x28, 0x30), b"DS", b"2\\1".to_vec()),
                    (Tag(0x18, 0x1164), b"DS", b"1\\1".to_vec()),
                    (Tag(0x28, 0x1054), b"LO", b"HU".to_vec()),
                ],
            ),
            budget(),
        )
        .unwrap();
        assert_eq!(image.display.pixel_height_over_width, 2.0);
        assert_eq!(image.display.aspect_source, "pixel_spacing");
        assert!(!image.display.aspect_estimated);
        assert_eq!(image.display.unit, "HU");
        assert!(
            image
                .display
                .diagnostics
                .iter()
                .any(|d| d == "display_aspect_conflict")
        );
        let fallback = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[
                    (Tag(0x28, 0x30), b"DS", b"private-invalid-value\\0".to_vec()),
                    (Tag(0x18, 0x1164), b"DS", b"3\\2".to_vec()),
                    (Tag(0x28, 0x1054), b"LO", b"private-unit-value".to_vec()),
                ],
            ),
            budget(),
        )
        .unwrap();
        assert_eq!(fallback.display.pixel_height_over_width, 1.5);
        assert_eq!(fallback.display.aspect_source, "imager_pixel_spacing");
        assert_eq!(fallback.display.unit, "unknown");
        assert!(
            fallback
                .display
                .diagnostics
                .iter()
                .any(|d| d == "invalid_pixel_spacing")
        );
        assert!(!format!("{:?}", fallback.display).contains("private-"));
        let nominal = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[
                    (Tag(0x18, 0x1164), b"DS", b"-1\\1".to_vec()),
                    (Tag(0x18, 0x2010), b"DS", b"0.8\\0.4".to_vec()),
                    (Tag(0x28, 0x34), b"IS", b"3\\2".to_vec()),
                ],
            ),
            budget(),
        )
        .unwrap();
        assert_eq!(nominal.display.pixel_height_over_width, 2.0);
        assert_eq!(
            nominal.display.aspect_source,
            "nominal_scanned_pixel_spacing"
        );
        let aspect_only = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[(Tag(0x28, 0x34), b"IS", b"3\\2".to_vec())],
            ),
            budget(),
        )
        .unwrap();
        assert_eq!(aspect_only.display.pixel_height_over_width, 1.5);
        assert_eq!(aspect_only.display.aspect_source, "pixel_aspect_ratio");
        assert!(!aspect_only.display.aspect_estimated);
        let invalid = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[
                    (Tag(0x28, 0x30), b"DS", b"NaN\\1".to_vec()),
                    (Tag(0x28, 0x34), b"IS", b"0\\1".to_vec()),
                ],
            ),
            budget(),
        )
        .unwrap();
        assert_eq!(invalid.display.pixel_height_over_width, 1.0);
        assert_eq!(invalid.display.aspect_source, "assumed_square");
        assert!(invalid.display.aspect_estimated);
        let mr = prepare_image_bytes(
            &part10_with_sop(
                EXPLICIT_LE,
                false,
                &[(Tag(0x28, 0x1054), b"LO", b"HU".to_vec())],
                Some(MR),
            ),
            budget(),
        )
        .unwrap();
        assert_eq!(mr.display.unit, "unknown");
    }

    #[test]
    fn unapplied_overlay_and_shutter_are_reported_without_original_text() {
        let image = prepare_image_bytes(
            &part10(
                EXPLICIT_LE,
                false,
                &[
                    (Tag(0x6000, 0x3000), b"OW", vec![0, 0]),
                    (
                        Tag(0x6000, 0x22),
                        b"LO",
                        b"private-overlay-description".to_vec(),
                    ),
                    (Tag(0x18, 0x1600), b"CS", b"RECTANGULAR".to_vec()),
                ],
            ),
            budget(),
        )
        .unwrap();
        assert!(
            image
                .display
                .diagnostics
                .iter()
                .any(|d| d == "overlay_not_applied")
        );
        assert!(
            image
                .display
                .diagnostics
                .iter()
                .any(|d| d == "shutter_not_applied")
        );
        assert!(!format!("{:?}", image.display).contains("private-overlay"));
    }

    #[test]
    fn source_hash_matches_the_standard_vector_and_the_opened_snapshot() {
        assert_eq!(
            source_revision(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        let input = TemporaryInput::new();
        let bytes = part10(EXPLICIT_LE, false, &[]);
        std::fs::write(&input.path, &bytes).unwrap();
        let budget = FrameBudget::new(60, 30).unwrap();
        let first = prepare_native_image(&input.path, 0, Arc::clone(&budget)).unwrap();
        let expected = source_revision(&bytes);
        assert_eq!(first.source_revision, expected);
        assert_eq!(first.source_revision.len(), 64);
        let mut changed_bytes = bytes.clone();
        changed_bytes[0] = 1;
        std::fs::write(&input.path, &changed_bytes).unwrap();
        let second = prepare_native_image(&input.path, 0, Arc::clone(&budget)).unwrap();
        assert_ne!(first.source_revision, second.source_revision);
        assert_eq!(first.source_revision, expected);
        assert_eq!(first.frame.pixels(), second.frame.pixels());
        assert_eq!(budget.snapshot().live_bytes, 60);
        drop(second);
        assert_eq!(budget.snapshot().live_bytes, 30);
        drop(first);
        assert_eq!(budget.snapshot().live_bytes, 0);
    }

    #[test]
    fn unsupported_syntax_dimensions_transform_and_malformed_length_are_explicit() {
        assert_eq!(
            prepare_bytes(&part10("1.2.840.10008.1.2.4.50", false, &[]), budget()).unwrap_err(),
            FrameError::Unsupported("transfer_syntax")
        );
        for (tag, vr, value) in [
            (Tag(0x28, 8), b"IS", b"2".to_vec()),
            (Tag(0x28, 0x3000), b"SQ", vec![]),
            (Tag(0x5200, 0x9229), b"SQ", vec![]),
        ] {
            assert!(matches!(
                prepare_bytes(&part10(EXPLICIT_LE, false, &[(tag, vr, value)]), budget()),
                Err(FrameError::Unsupported(_))
            ));
        }
        assert_eq!(
            prepare_bytes(
                &part10(EXPLICIT_LE, false, &[(PIXEL_DATA, b"OW", vec![0, 0])]),
                budget()
            )
            .unwrap_err(),
            FrameError::DecodeFailed("pixel_length")
        );
        let budget = budget();
        assert_eq!(
            prepare_bytes(
                &part10(
                    EXPLICIT_LE,
                    false,
                    &[(Tag(0x28, 0x1052), b"DS", b"1e100".to_vec())]
                ),
                Arc::clone(&budget)
            )
            .unwrap_err(),
            FrameError::Unsupported("f32_overflow")
        );
        assert_eq!(budget.snapshot().live_bytes, 0);
        assert_eq!(
            prepare_bytes(b"not DICOM", budget).unwrap_err(),
            FrameError::DecodeFailed("part10_header")
        );
    }
}
