//! Native grayscale display interpretation and a bounded CPU test reference.
//!
//! The pipeline is ModalityApplied F32 -> one selected VOI -> one resolved
//! polarity -> user inversion -> half-up 8-bit quantization. Padding is always
//! black. Display aspect never grants geometry or measurement calibration.

use dicom_object::{DefaultDicomObject, Tag};

use crate::frame::{FrameData, FrameError, PixelFormat};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum VoiFunction {
    Linear,
    LinearExact,
    Sigmoid,
}

#[derive(Clone, Debug, PartialEq)]
pub struct VoiWindow {
    pub center: f64,
    pub width: f64,
    pub function: VoiFunction,
}

impl VoiWindow {
    /// Checks a caller-provided window; file errors are classified separately.
    pub fn validate(&self) -> Result<(), FrameError> {
        let width_valid = match self.function {
            VoiFunction::Linear => self.width >= 1.0,
            VoiFunction::LinearExact | VoiFunction::Sigmoid => self.width > 0.0,
        };
        if !self.center.is_finite() || !self.width.is_finite() || !width_valid {
            return Err(FrameError::InvalidArgument("voi_window"));
        }
        Ok(())
    }

    fn normalized(&self, value: f64) -> f64 {
        match self.function {
            VoiFunction::Linear => {
                let midpoint = self.center - 0.5;
                if self.width == 1.0 {
                    if value <= midpoint { 0.0 } else { 1.0 }
                } else {
                    ((value - midpoint) / (self.width - 1.0) + 0.5).clamp(0.0, 1.0)
                }
            }
            VoiFunction::LinearExact => ((value - self.center) / self.width + 0.5).clamp(0.0, 1.0),
            VoiFunction::Sigmoid => {
                // Divide first so finite large widths do not create overflow
                // in an intermediate 4*(value-center). Stable logistic avoids
                // overflow in exp for very narrow windows.
                let t = (value - self.center) / self.width * 4.0;
                if t >= 0.0 {
                    1.0 / (1.0 + (-t).exp())
                } else {
                    let e = t.exp();
                    e / (1.0 + e)
                }
            }
        }
    }
}

#[derive(Clone, Debug)]
pub struct DisplayDescriptor {
    pub windows: Vec<VoiWindow>,
    pub default_window: Option<VoiWindow>,
    pub automatic_window: bool,
    pub inverted: bool,
    pub pixel_height_over_width: f64,
    pub aspect_source: String,
    pub aspect_estimated: bool,
    pub unit: String,
    pub diagnostics: Vec<String>,
    pub can_window: bool,
}

/// CPU nearest-pixel reference, intended only for small contract/golden tests.
///
/// At most 16,384 pixels / 64 KiB are returned. RGBA input is passed through
/// with alpha 255; grayscale VOI/polarity/user inversion do not affect color.
pub fn reference_rgba(
    frame: &FrameData,
    display: &DisplayDescriptor,
    window: Option<VoiWindow>,
    user_invert: bool,
) -> Result<Vec<u8>, FrameError> {
    if let Some(window) = &window {
        window.validate()?;
    }
    let count = u64::from(frame.width()) * u64::from(frame.height());
    if count > 16_384 {
        return Err(FrameError::ResourceLimit("reference_pixels"));
    }
    let length =
        usize::try_from(count * 4).map_err(|_| FrameError::ResourceLimit("reference_bytes"))?;
    let mut output = Vec::new();
    output
        .try_reserve_exact(length)
        .map_err(|_| FrameError::ResourceLimit("reference_allocation"))?;
    output.resize(length, 0);
    if frame.pixel_format() == PixelFormat::Rgba8 {
        output.copy_from_slice(frame.pixels());
        for pixel in output.as_chunks_mut::<4>().0 {
            pixel[3] = 255;
        }
        return Ok(output);
    }
    let window = window.or_else(|| display.default_window.clone());
    if let Some(window) = &window {
        window.validate()?;
    }
    let inverted = display.inverted ^ user_invert;
    for (i, (source, target)) in frame
        .pixels()
        .as_chunks::<4>()
        .0
        .iter()
        .zip(output.as_chunks_mut::<4>().0)
        .enumerate()
    {
        target[3] = 255;
        if frame.mask().is_some_and(|mask| mask[i] == 0) {
            continue;
        }
        let value = f64::from(f32::from_le_bytes(*source));
        let window = window
            .as_ref()
            .ok_or(FrameError::InvalidArgument("missing_voi_window"))?;
        let value = window.normalized(value);
        let value = if inverted { 1.0 - value } else { value };
        let byte = (value * 255.0 + 0.5).floor() as u8;
        target[..3].fill(byte);
    }
    Ok(output)
}

pub(crate) fn from_native_object(
    object: &DefaultDicomObject,
    frame: &FrameData,
) -> Result<DisplayDescriptor, FrameError> {
    let mut diagnostics = Vec::new();
    let (ratio, source, estimated) = display_aspect(object, &mut diagnostics);
    unused_presentation_diagnostics(object, &mut diagnostics);
    if frame.pixel_format() == PixelFormat::Rgba8 {
        // These are meaningful only on monochrome images. Reject them in this
        // narrow RGB adapter rather than implying they were applied.
        if [
            Tag(0x0028, 0x1050),
            Tag(0x0028, 0x1051),
            Tag(0x0028, 0x1056),
            Tag(0x2050, 0x0020),
        ]
        .iter()
        .any(|&tag| object.get(tag).is_some())
        {
            return Err(FrameError::Unsupported("rgb_presentation_transform"));
        }
        diagnostics.push("unprofiled_rgb".to_owned());
        return Ok(DisplayDescriptor {
            windows: Vec::new(),
            default_window: None,
            automatic_window: false,
            inverted: false,
            pixel_height_over_width: ratio,
            aspect_source: source,
            aspect_estimated: estimated,
            unit: "unknown".to_owned(),
            diagnostics,
            can_window: false,
        });
    }
    let windows = file_windows(object)?;
    let automatic_window = windows.is_empty();
    let range = valid_range(frame);
    let default_window = if range.is_none() {
        diagnostics.push("no_valid_pixels".to_owned());
        None
    } else if let Some(first) = windows.first() {
        Some(first.clone())
    } else {
        diagnostics.push("automatic_voi_from_display_range".to_owned());
        automatic_window_for_range(range)
    };
    let photometric = safe_text(object, Tag(0x0028, 0x0004))?;
    let shape = optional_safe_text(object, Tag(0x2050, 0x0020))?;
    let inverted = resolve_polarity(&photometric, shape.as_deref())?;
    let unit = trusted_unit(object, &mut diagnostics)?;
    Ok(DisplayDescriptor {
        windows,
        default_window,
        automatic_window,
        inverted,
        pixel_height_over_width: ratio,
        aspect_source: source,
        aspect_estimated: estimated,
        unit,
        diagnostics,
        can_window: range.is_some(),
    })
}

fn file_windows(object: &DefaultDicomObject) -> Result<Vec<VoiWindow>, FrameError> {
    let center = object.get(Tag(0x0028, 0x1050));
    let width = object.get(Tag(0x0028, 0x1051));
    let function = optional_safe_text(object, Tag(0x0028, 0x1056))?;
    let function = match function.as_deref() {
        None | Some("LINEAR") => VoiFunction::Linear,
        Some("LINEAR_EXACT") => VoiFunction::LinearExact,
        Some("SIGMOID") => VoiFunction::Sigmoid,
        _ => return Err(FrameError::Unsupported("voi_function")),
    };
    let (center, width) = match (center, width) {
        (None, None) if object.get(Tag(0x0028, 0x1056)).is_none() => return Ok(Vec::new()),
        (Some(center), Some(width)) => (center, width),
        _ => return Err(FrameError::Unsupported("voi_window_pair")),
    };
    let center_count = center
        .value()
        .primitive()
        .map(|p| p.multiplicity())
        .unwrap_or(0);
    let width_count = width
        .value()
        .primitive()
        .map(|p| p.multiplicity())
        .unwrap_or(0);
    if center_count == 0 || center_count != width_count {
        return Err(FrameError::Unsupported("voi_window_multiplicity"));
    }
    let centers = center
        .to_multi_float64()
        .map_err(|_| FrameError::Unsupported("voi_window"))?;
    let widths = width
        .to_multi_float64()
        .map_err(|_| FrameError::Unsupported("voi_window"))?;
    let mut windows = Vec::new();
    windows
        .try_reserve_exact(centers.len())
        .map_err(|_| FrameError::ResourceLimit("voi_allocation"))?;
    for (center, width) in centers.into_iter().zip(widths) {
        let window = VoiWindow {
            center,
            width,
            function,
        };
        window
            .validate()
            .map_err(|_| FrameError::Unsupported("voi_window"))?;
        windows.push(window);
    }
    Ok(windows)
}

fn valid_range(frame: &FrameData) -> Option<(f64, f64)> {
    let mut range: Option<(f64, f64)> = None;
    for (i, bytes) in frame.pixels().as_chunks::<4>().0.iter().enumerate() {
        if frame.mask().is_some_and(|mask| mask[i] == 0) {
            continue;
        }
        let value = f64::from(f32::from_le_bytes(*bytes));
        range = Some(match range {
            None => (value, value),
            Some((low, high)) => (low.min(value), high.max(value)),
        });
    }
    range
}

fn automatic_window_for_range(range: Option<(f64, f64)>) -> Option<VoiWindow> {
    range.map(|(low, high)| VoiWindow {
        center: low / 2.0 + high / 2.0,
        width: if low < high { high - low } else { 1.0 },
        function: VoiFunction::LinearExact,
    })
}

/// Shape is interpreted once, never XORed with MONOCHROME1. Only the natural
/// M1/INVERSE and M2/IDENTITY combinations are supported for this adapter.
fn resolve_polarity(photometric: &str, shape: Option<&str>) -> Result<bool, FrameError> {
    match (photometric, shape) {
        ("MONOCHROME1", None | Some("INVERSE")) => Ok(true),
        ("MONOCHROME2", None | Some("IDENTITY")) => Ok(false),
        ("MONOCHROME1", Some("IDENTITY")) | ("MONOCHROME2", Some("INVERSE")) => {
            Err(FrameError::Unsupported("presentation_polarity_conflict"))
        }
        _ => Err(FrameError::Unsupported("presentation_lut_shape")),
    }
}

fn display_aspect(
    object: &DefaultDicomObject,
    diagnostics: &mut Vec<String>,
) -> (f64, String, bool) {
    let candidates = [
        (
            Tag(0x0028, 0x0030),
            "pixel_spacing",
            "invalid_pixel_spacing",
        ),
        (
            Tag(0x0018, 0x1164),
            "imager_pixel_spacing",
            "invalid_imager_pixel_spacing",
        ),
        (
            Tag(0x0018, 0x2010),
            "nominal_scanned_pixel_spacing",
            "invalid_nominal_scanned_pixel_spacing",
        ),
        (
            Tag(0x0028, 0x0034),
            "pixel_aspect_ratio",
            "invalid_pixel_aspect_ratio",
        ),
    ];
    let mut selected: Option<(f64, &'static str)> = None;
    for (tag, source, invalid) in candidates {
        let Some(element) = object.get(tag) else {
            continue;
        };
        let ratio = if element
            .value()
            .primitive()
            .is_some_and(|p| p.multiplicity() == 2)
        {
            element.to_multi_float64().ok().and_then(|values| {
                let row = values[0];
                let column = values[1];
                let ratio = row / column;
                if row.is_finite()
                    && column.is_finite()
                    && row > 0.0
                    && column > 0.0
                    && ratio.is_finite()
                    && ratio > 0.0
                    && (source != "pixel_aspect_ratio"
                        || (row.fract() == 0.0 && column.fract() == 0.0))
                {
                    Some(ratio)
                } else {
                    None
                }
            })
        } else {
            None
        };
        match ratio {
            None => diagnostics.push(invalid.to_owned()),
            Some(ratio) => match selected {
                None => selected = Some((ratio, source)),
                Some((chosen, _))
                    if (ratio - chosen).abs() > 1e-6 * ratio.abs().max(chosen.abs()) =>
                {
                    diagnostics.push("display_aspect_conflict".to_owned());
                }
                _ => {}
            },
        }
    }
    match selected {
        Some((ratio, source)) => (ratio, source.to_owned(), false),
        None => {
            diagnostics.push("display_aspect_assumed_square".to_owned());
            (1.0, "assumed_square".to_owned(), true)
        }
    }
}

fn trusted_unit(
    object: &DefaultDicomObject,
    diagnostics: &mut Vec<String>,
) -> Result<String, FrameError> {
    let sop = safe_text(object, Tag(0x0008, 0x0016))?;
    let rescale_type = optional_safe_text(object, Tag(0x0028, 0x1054))?;
    // Conservative evidence: CT SOP + explicitly declared HU + the rescale
    // pair validated and applied by the native adapter. Never echo raw units.
    if sop == "1.2.840.10008.5.1.4.1.1.2"
        && rescale_type.as_deref() == Some("HU")
        && object.get(Tag(0x0028, 0x1052)).is_some()
        && object.get(Tag(0x0028, 0x1053)).is_some()
    {
        Ok("HU".to_owned())
    } else {
        diagnostics.push("unit_unknown".to_owned());
        Ok("unknown".to_owned())
    }
}

fn unused_presentation_diagnostics(object: &DefaultDicomObject, diagnostics: &mut Vec<String>) {
    if object.iter().any(|element| {
        (0x6000..=0x601e).contains(&element.header().tag.0)
            && element.header().tag.0.is_multiple_of(2)
    }) {
        diagnostics.push("overlay_not_applied".to_owned());
    }
    if [
        0x1600, 0x1602, 0x1604, 0x1606, 0x1608, 0x1610, 0x1620, 0x1622, 0x1623, 0x1624,
    ]
    .iter()
    .any(|&element| object.get(Tag(0x0018, element)).is_some())
    {
        diagnostics.push("shutter_not_applied".to_owned());
    }
}

fn optional_safe_text(object: &DefaultDicomObject, tag: Tag) -> Result<Option<String>, FrameError> {
    if object.get(tag).is_none() {
        return Ok(None);
    }
    safe_text(object, tag).map(Some)
}

fn safe_text(object: &DefaultDicomObject, tag: Tag) -> Result<String, FrameError> {
    let element = object
        .get(tag)
        .ok_or(FrameError::Unsupported("display_metadata"))?;
    if element
        .value()
        .primitive()
        .is_none_or(|p| p.multiplicity() != 1)
    {
        return Err(FrameError::Unsupported("display_metadata"));
    }
    let value = element
        .to_str()
        .map_err(|_| FrameError::Unsupported("display_metadata"))?;
    let value = value.trim_end_matches(|c: char| c.is_whitespace() || c == '\0');
    if value.is_empty() {
        return Err(FrameError::Unsupported("display_metadata"));
    }
    Ok(value.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::FrameBudget;

    fn frame(values: &[Option<f64>]) -> std::sync::Arc<FrameData> {
        let budget = FrameBudget::new(1024 * 1024, 1024 * 1024).unwrap();
        FrameData::gray_from_fn(values.len() as u32, 1, budget, true, |i| Ok(values[i])).unwrap()
    }

    fn descriptor(window: Option<VoiWindow>) -> DisplayDescriptor {
        DisplayDescriptor {
            windows: Vec::new(),
            default_window: window,
            automatic_window: false,
            inverted: false,
            pixel_height_over_width: 1.0,
            aspect_source: "assumed_square".to_owned(),
            aspect_estimated: true,
            unit: "unknown".to_owned(),
            diagnostics: Vec::new(),
            can_window: true,
        }
    }

    fn bytes(values: &[Option<f64>], center: f64, width: f64, function: VoiFunction) -> Vec<u8> {
        let frame = frame(values);
        let display = descriptor(Some(VoiWindow {
            center,
            width,
            function,
        }));
        reference_rgba(&frame, &display, None, false)
            .unwrap()
            .as_chunks::<4>()
            .0
            .iter()
            .map(|pixel| pixel[0])
            .collect()
    }

    #[test]
    fn linear_definition_boundaries_and_width_one_threshold_are_literal() {
        assert_eq!(
            bytes(
                &[
                    Some(-2.0),
                    Some(-1.5),
                    Some(-1.0),
                    Some(-0.5),
                    Some(0.0),
                    Some(0.5),
                    Some(1.0)
                ],
                0.0,
                3.0,
                VoiFunction::Linear
            ),
            [0, 0, 64, 128, 191, 255, 255]
        );
        assert_eq!(
            bytes(
                &[Some(-1.0), Some(-0.5), Some(0.0)],
                0.0,
                1.0,
                VoiFunction::Linear
            ),
            [0, 0, 255]
        );
        // A standard 8-bit identity window maps each integer to itself.
        assert_eq!(
            bytes(
                &[Some(0.0), Some(1.0), Some(127.0), Some(128.0), Some(255.0)],
                128.0,
                256.0,
                VoiFunction::Linear
            ),
            [0, 1, 127, 128, 255]
        );
    }

    #[test]
    fn exact_and_sigmoid_are_distinct_and_round_half_up() {
        let values = [Some(-2.0), Some(-1.0), Some(0.0), Some(1.0), Some(2.0)];
        assert_eq!(
            bytes(&values, 0.0, 4.0, VoiFunction::LinearExact),
            [0, 64, 128, 191, 255]
        );
        assert_eq!(
            bytes(&values, 0.0, 4.0, VoiFunction::Sigmoid),
            [30, 69, 128, 186, 225]
        );
        assert_eq!(
            bytes(
                &[Some(-1.0), Some(0.0), Some(1.0)],
                0.0,
                f64::MIN_POSITIVE,
                VoiFunction::Sigmoid
            ),
            [0, 128, 255]
        );
        assert_eq!(
            bytes(&[Some(0.0)], f64::MAX, f64::MAX, VoiFunction::Sigmoid),
            [5]
        );
    }

    #[test]
    fn caller_voi_definition_errors_are_invalid_arguments_even_for_padding() {
        let frame = frame(&[None]);
        let display = descriptor(None);
        for (function, width) in [
            (VoiFunction::Linear, 0.5),
            (VoiFunction::LinearExact, 0.0),
            (VoiFunction::Sigmoid, -1.0),
            (VoiFunction::LinearExact, f64::INFINITY),
        ] {
            assert_eq!(
                reference_rgba(
                    &frame,
                    &display,
                    Some(VoiWindow {
                        center: 0.0,
                        width,
                        function
                    }),
                    false
                )
                .unwrap_err(),
                FrameError::InvalidArgument("voi_window")
            );
        }
        assert_eq!(
            reference_rgba(
                &frame,
                &display,
                Some(VoiWindow {
                    center: f64::NAN,
                    width: 1.0,
                    function: VoiFunction::Linear
                }),
                false
            )
            .unwrap_err(),
            FrameError::InvalidArgument("voi_window")
        );
    }

    #[test]
    fn automatic_range_excludes_padding_and_uniform_is_midgray() {
        let input = frame(&[None, Some(-12.0), Some(4084.0)]);
        let window = automatic_window_for_range(valid_range(&input)).unwrap();
        assert_eq!(
            window,
            VoiWindow {
                center: 2036.0,
                width: 4096.0,
                function: VoiFunction::LinearExact
            }
        );
        assert_eq!(
            reference_rgba(&input, &descriptor(Some(window)), None, false).unwrap(),
            [0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255, 255]
        );
        let uniform = frame(&[Some(37.0), Some(37.0)]);
        let window = automatic_window_for_range(valid_range(&uniform)).unwrap();
        assert_eq!(window.center, 37.0);
        assert_eq!(window.width, 1.0);
        assert_eq!(
            reference_rgba(&uniform, &descriptor(Some(window)), None, false).unwrap(),
            [128, 128, 128, 255, 128, 128, 128, 255]
        );
        let padding = frame(&[None, None]);
        assert_eq!(automatic_window_for_range(valid_range(&padding)), None);
        let mut display = descriptor(None);
        display.inverted = true;
        assert_eq!(
            reference_rgba(&padding, &display, None, false).unwrap(),
            [0, 0, 0, 255, 0, 0, 0, 255]
        );
        assert_eq!(
            reference_rgba(&padding, &display, None, true).unwrap(),
            [0, 0, 0, 255, 0, 0, 0, 255]
        );
    }

    #[test]
    fn natural_polarity_is_applied_once_before_user_inversion() {
        assert!(resolve_polarity("MONOCHROME1", None).unwrap());
        assert!(resolve_polarity("MONOCHROME1", Some("INVERSE")).unwrap());
        assert!(!resolve_polarity("MONOCHROME2", Some("IDENTITY")).unwrap());
        assert!(resolve_polarity("MONOCHROME1", Some("IDENTITY")).is_err());
        assert!(resolve_polarity("MONOCHROME2", Some("INVERSE")).is_err());
        assert!(resolve_polarity("MONOCHROME2", Some("LIN OD")).is_err());
        let input = frame(&[None, Some(0.0), Some(0.5), Some(1.0)]);
        let mut display = descriptor(Some(VoiWindow {
            center: 0.5,
            width: 1.0,
            function: VoiFunction::LinearExact,
        }));
        display.inverted = resolve_polarity("MONOCHROME1", Some("INVERSE")).unwrap();
        assert_eq!(
            reference_rgba(&input, &display, None, false).unwrap(),
            [
                0, 0, 0, 255, 255, 255, 255, 255, 128, 128, 128, 255, 0, 0, 0, 255
            ]
        );
        assert_eq!(
            reference_rgba(&input, &display, None, true).unwrap(),
            [
                0, 0, 0, 255, 0, 0, 0, 255, 128, 128, 128, 255, 255, 255, 255, 255
            ]
        );
    }

    #[test]
    fn rgb_is_byte_exact_and_large_reference_is_rejected_before_allocation() {
        let budget = FrameBudget::new(1024 * 1024, 1024 * 1024).unwrap();
        let rgb =
            FrameData::rgba_from_fn(2, 1, budget.clone(), |i| Ok([[255, 0, 0], [17, 34, 51]][i]))
                .unwrap();
        assert_eq!(
            reference_rgba(&rgb, &descriptor(None), None, true).unwrap(),
            [255, 0, 0, 255, 17, 34, 51, 255]
        );
        let large = FrameData::rgba_from_fn(16_385, 1, budget, |_| Ok([1, 2, 3])).unwrap();
        assert_eq!(
            reference_rgba(&large, &descriptor(None), None, false).unwrap_err(),
            FrameError::ResourceLimit("reference_pixels")
        );
    }
}
