//! P0-only upstream decoding probe. It does not normalize or repair decoded samples.
use dicom_object::{DefaultDicomObject, open_file};
use dicom_pixeldata::{
    ConvertOptions, DecodedPixelData, ModalityLutOption, PixelDecoder, VoiLutOption,
};
use serde_json::{Value, json};
use std::ffi::OsString;
use std::fs::{self, OpenOptions};
use std::io::{BufWriter, Write};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Path, PathBuf};
use std::time::Instant;

#[cfg(all(feature = "openjp2", feature = "openjpeg-sys"))]
compile_error!("Build the two JPEG 2000 backends as separate profiles.");

const MAX_INPUT_BYTES: u64 = 512 * 1024 * 1024;
const MAX_DOMAIN_BYTES: u64 = 256 * 1024 * 1024;
const MAX_FRAMES: u64 = 10_000;

type ProbeResult<T> = Result<T, &'static str>;

struct Args {
    input: PathBuf,
    prefix: PathBuf,
    frame: Option<u32>,
}

fn parse_args(args: impl Iterator<Item = OsString>) -> ProbeResult<Args> {
    let args: Vec<_> = args.collect();
    if args.len() != 2 && args.len() != 4 {
        return Err("invalid_arguments");
    }
    let frame = if args.len() == 4 {
        if args[2] != "--frame" {
            return Err("invalid_arguments");
        }
        Some(
            args[3]
                .to_str()
                .and_then(|x| x.parse::<u32>().ok())
                .ok_or("invalid_frame")?,
        )
    } else {
        None
    };
    Ok(Args {
        input: args[0].clone().into(),
        prefix: args[1].clone().into(),
        frame,
    })
}

fn caught<T>(f: impl FnOnce() -> ProbeResult<T>) -> ProbeResult<T> {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(Err("panic"))
}

fn pixel_error(error: dicom_pixeldata::Error) -> &'static str {
    // Never emit upstream error strings: malformed tags can contain arbitrary text.
    let mut messages = Vec::new();
    let mut current: Option<&dyn std::error::Error> = Some(&error);
    while let Some(error) = current {
        messages.push(error.to_string().to_ascii_lowercase());
        current = error.source();
    }
    let message = messages.join(" ");
    if message.contains("transfersyntax") || message.contains("transfer syntax") {
        "unsupported_transfer_syntax"
    } else if message.contains("planarconfiguration") {
        "unsupported_planar_configuration"
    } else if message.contains("out of range") || message.contains("out of bounds") {
        "frame_out_of_range"
    } else if message.contains("bitsallocated") {
        "unsupported_bits_allocated"
    } else if message.contains("multiplicity") {
        "invalid_transform_metadata"
    } else if message.contains("offset table") || message.contains("fragment") {
        "encapsulated_frame_error"
    } else if message.contains("could not decode pixel data") {
        "decode_error"
    } else if message.contains("pixeldata attribute") {
        "invalid_pixel_data"
    } else {
        "pixel_error"
    }
}

fn integer(obj: &DefaultDicomObject, name: &str) -> ProbeResult<u64> {
    obj.element_by_name(name)
        .map_err(|_| "missing_pixel_metadata")?
        .to_int::<u64>()
        .map_err(|_| "invalid_pixel_metadata")
}

fn safe_pi(value: &str) -> &'static str {
    match value.trim_matches([' ', '\0']) {
        "MONOCHROME1" => "MONOCHROME1",
        "MONOCHROME2" => "MONOCHROME2",
        "RGB" => "RGB",
        "PALETTE COLOR" => "PALETTE COLOR",
        "YBR_FULL" => "YBR_FULL",
        "YBR_FULL_422" => "YBR_FULL_422",
        "YBR_PARTIAL_422" => "YBR_PARTIAL_422",
        "YBR_PARTIAL_420" => "YBR_PARTIAL_420",
        "YBR_ICT" => "YBR_ICT",
        "YBR_RCT" => "YBR_RCT",
        _ => "unknown",
    }
}

fn domain_bytes(rows: u64, cols: u64, frames: u64, samples: u64) -> ProbeResult<u64> {
    if rows == 0 || cols == 0 || frames == 0 || samples == 0 || frames > MAX_FRAMES {
        return Err("invalid_dimensions");
    }
    [rows, cols, frames, samples, 8]
        .into_iter()
        .try_fold(1_u64, |n, factor| n.checked_mul(factor))
        .filter(|&bytes| bytes <= MAX_DOMAIN_BYTES)
        .ok_or("decoded_size_limit")
}

fn validate_bit_metadata(
    bits_allocated: u64,
    bits_stored: u64,
    high_bit: u64,
    pixel_representation: u64,
) -> ProbeResult<()> {
    // Conversion can allocate a LUT indexed by BitsStored. Reject inconsistent
    // bit fields before any upstream decoding or conversion call.
    if !matches!(bits_allocated, 8 | 16) {
        return Err("unsupported_bits_allocated");
    }
    if bits_stored == 0
        || bits_stored > bits_allocated
        || high_bit != bits_stored - 1
        || pixel_representation > 1
    {
        return Err("invalid_pixel_metadata");
    }
    Ok(())
}

fn metadata(obj: &DefaultDicomObject, report: &mut Value, frame: Option<u32>) -> ProbeResult<u64> {
    let uid = obj.meta().transfer_syntax().trim_matches([' ', '\0']);
    if uid.is_empty() || uid.len() > 64 || !uid.bytes().all(|b| b.is_ascii_digit() || b == b'.') {
        return Err("invalid_transfer_syntax_uid");
    }
    report["ts_uid"] = json!(uid);
    for (field, tag) in [
        ("rows", "Rows"),
        ("cols", "Columns"),
        ("samples", "SamplesPerPixel"),
        ("bits_allocated", "BitsAllocated"),
        ("bits_stored", "BitsStored"),
        ("high_bit", "HighBit"),
        ("pixel_representation", "PixelRepresentation"),
    ] {
        report[field] = json!(integer(obj, tag)?);
    }
    validate_bit_metadata(
        report["bits_allocated"].as_u64().unwrap(),
        report["bits_stored"].as_u64().unwrap(),
        report["high_bit"].as_u64().unwrap(),
        report["pixel_representation"].as_u64().unwrap(),
    )?;
    let frames = match obj.element_by_name("NumberOfFrames") {
        Ok(value) => value
            .to_int::<u64>()
            .map_err(|_| "invalid_pixel_metadata")?,
        Err(_) => 1,
    };
    report["frames"] = json!(frames);
    report["planar_configuration"] = json!(integer(obj, "PlanarConfiguration").ok());
    let pi = obj
        .element_by_name("PhotometricInterpretation")
        .map_err(|_| "missing_pixel_metadata")?
        .to_str()
        .map_err(|_| "invalid_pixel_metadata")?;
    report["photometric"] = json!(safe_pi(&pi));
    if frames == 0 || frames > MAX_FRAMES {
        return Err("invalid_dimensions");
    }
    if frame.is_some_and(|index| u64::from(index) >= frames) {
        return Err("frame_out_of_range");
    }
    domain_bytes(
        report["rows"].as_u64().unwrap(),
        report["cols"].as_u64().unwrap(),
        if frame.is_some() { 1 } else { frames },
        report["samples"].as_u64().unwrap(),
    )
}

fn with_suffix(prefix: &Path, suffix: &str) -> PathBuf {
    let mut name = prefix.as_os_str().to_os_string();
    name.push(suffix);
    name.into()
}

fn write_values(path: &Path, values: &[f64], expected_bytes: u64) -> ProbeResult<()> {
    if (values.len() as u64).checked_mul(8) != Some(expected_bytes) {
        return Err("unexpected_decoded_length");
    }
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|_| "output_io")?;
    let result = (|| {
        let mut writer = BufWriter::new(file);
        for value in values {
            writer
                .write_all(&value.to_le_bytes())
                .map_err(|_| "output_io")?;
        }
        writer.flush().map_err(|_| "output_io")
    })();
    if result.is_err() {
        let _ = fs::remove_file(path);
    }
    result
}

fn options(modality: ModalityLutOption) -> ConvertOptions {
    ConvertOptions::new()
        .with_modality_lut(modality)
        .with_voi_lut(VoiLutOption::Identity)
}

fn describe_decoded(decoded: &DecodedPixelData<'_>, report: &mut Value) {
    report["decoded_photometric"] = json!(safe_pi(decoded.photometric_interpretation().as_ref()));
    report["decoded_planar_configuration"] = json!(decoded.planar_configuration().to_string());
    report["decoded_bytes"] = json!(decoded.data().len());
}

fn frame_probe(
    obj: &DefaultDicomObject,
    args: &Args,
    frame: u32,
    bytes: u64,
) -> ProbeResult<Value> {
    let start = Instant::now();
    let decoded = obj.decode_pixel_data_frame(frame).map_err(pixel_error)?;
    let decode_ms = start.elapsed().as_secs_f64() * 1000.0;
    let mut info = json!({"frame": frame, "decode_ms": decode_ms});
    describe_decoded(&decoded, &mut info);
    let start = Instant::now();
    let stored = decoded
        .to_vec_with_options::<f64>(&options(ModalityLutOption::None))
        .map_err(pixel_error)?;
    info["convert_ms"] = json!(start.elapsed().as_secs_f64() * 1000.0);
    write_values(
        &with_suffix(&args.prefix, &format!(".frame-{frame}.f64le")),
        &stored,
        bytes,
    )?;
    info["stored_bytes"] = json!(stored.len() * 8);
    Ok(info)
}

fn probe(args: &Args, report: &mut Value) -> ProbeResult<()> {
    report["stage"] = json!("input");
    let input = fs::metadata(&args.input).map_err(|_| "input_io")?;
    if !input.is_file() || input.len() > MAX_INPUT_BYTES {
        return Err("input_size_limit");
    }
    report["stage"] = json!("parse");
    let obj = open_file(&args.input).map_err(|_| "parse_error")?;
    report["stage"] = json!("metadata");
    let expected_bytes = metadata(&obj, report, args.frame)?;
    let frames = report["frames"].as_u64().unwrap() as u32;
    if let Some(frame) = args.frame {
        report["stage"] = json!("single_frame");
        let info = caught(|| frame_probe(&obj, args, frame, expected_bytes))?;
        report["frame_results"] = json!([info]);
        return Ok(());
    }
    report["stage"] = json!("whole_decode");
    let whole = caught(|| {
        let start = Instant::now();
        let decoded = obj.decode_pixel_data().map_err(pixel_error)?;
        report["decode_ms"] = json!(start.elapsed().as_secs_f64() * 1000.0);
        describe_decoded(&decoded, report);
        report["stage"] = json!("stored_convert");
        let start = Instant::now();
        let stored = decoded
            .to_vec_with_options::<f64>(&options(ModalityLutOption::None))
            .map_err(pixel_error)?;
        let stored_convert_ms = start.elapsed().as_secs_f64() * 1000.0;
        report["stored_convert_ms"] = json!(stored_convert_ms);
        report["stored_bytes"] = json!(stored.len() * 8);
        report["stage"] = json!("stored_output");
        write_values(
            &with_suffix(&args.prefix, ".stored.f64le"),
            &stored,
            expected_bytes,
        )?;
        drop(stored);
        report["stage"] = json!("modality_convert");
        let start = Instant::now();
        let modality = decoded
            .to_vec_with_options::<f64>(&options(ModalityLutOption::Default))
            .map_err(pixel_error)?;
        let modality_convert_ms = start.elapsed().as_secs_f64() * 1000.0;
        report["modality_convert_ms"] = json!(modality_convert_ms);
        report["modality_bytes"] = json!(modality.len() * 8);
        report["convert_ms"] = json!(stored_convert_ms + modality_convert_ms);
        report["stage"] = json!("modality_output");
        write_values(
            &with_suffix(&args.prefix, ".modality.f64le"),
            &modality,
            expected_bytes,
        )
    });
    let whole_stage = report["stage"].clone();
    if frames > 1 {
        let mut results = Vec::new();
        let mut errors = Vec::new();
        for frame in 0..frames {
            match caught(|| frame_probe(&obj, args, frame, expected_bytes / u64::from(frames))) {
                Ok(info) => results.push(info),
                Err(kind) => errors
                    .push(json!({"frame": frame, "stage": "single_frame", "error_kind": kind})),
            }
        }
        report["frame_results"] = json!(results);
        report["frame_errors"] = json!(errors);
    }
    report["stage"] = whole_stage;
    whole?;
    if !report["frame_errors"].as_array().unwrap().is_empty() {
        report["stage"] = json!("single_frame");
        return Err("frame_errors");
    }
    Ok(())
}

fn main() {
    // Prevent the default panic hook from logging paths or malformed tag contents.
    std::panic::set_hook(Box::new(|_| {}));
    let mut report = json!({
        "status": "error", "stage": "arguments", "frame_errors": [], "frame_results": [],
        "stored_domain": "upstream_no_modality", "modality_domain": "upstream_default_rescale_no_voi",
        "limits": {"input_bytes": MAX_INPUT_BYTES, "domain_bytes": MAX_DOMAIN_BYTES, "frames": MAX_FRAMES},
        "dicom_rs_version": "0.10.0",
        "features": {"baseline": cfg!(feature="baseline"), "charls": cfg!(feature="charls"),
                     "openjp2": cfg!(feature="openjp2"), "openjpeg-sys": cfg!(feature="openjpeg-sys")}
    });
    let result = caught(|| {
        let args = parse_args(std::env::args_os().skip(1))?;
        if let Some(frame) = args.frame {
            report["selected_frame"] = json!(frame);
        }
        probe(&args, &mut report)
    });
    let code = match result {
        Ok(()) => {
            report["status"] = json!("ok");
            report["stage"] = json!("complete");
            0
        }
        Err(kind) => {
            report["error_kind"] = json!(kind);
            1
        }
    };
    println!("{report}");
    std::process::exit(code);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bit_metadata_is_rejected_without_constructing_an_upstream_lut() {
        assert_eq!(
            validate_bit_metadata(16, 32, 31, 0),
            Err("invalid_pixel_metadata")
        );
        assert_eq!(
            validate_bit_metadata(16, 0, 0, 0),
            Err("invalid_pixel_metadata")
        );
        assert_eq!(
            validate_bit_metadata(8, 9, 8, 0),
            Err("invalid_pixel_metadata")
        );
        assert_eq!(
            validate_bit_metadata(16, 12, 15, 1),
            Err("invalid_pixel_metadata")
        );
        assert_eq!(
            validate_bit_metadata(16, 16, 15, 2),
            Err("invalid_pixel_metadata")
        );
        assert_eq!(
            validate_bit_metadata(16, u64::MAX, u64::MAX, 0),
            Err("invalid_pixel_metadata")
        );
        for bits_allocated in [0, 1, 32, 64, u64::MAX] {
            assert_eq!(
                validate_bit_metadata(bits_allocated, 1, 0, 0),
                Err("unsupported_bits_allocated")
            );
        }
        for bits_allocated in [8, 16] {
            for bits_stored in 1..=bits_allocated {
                for pixel_representation in [0, 1] {
                    assert_eq!(
                        validate_bit_metadata(
                            bits_allocated,
                            bits_stored,
                            bits_stored - 1,
                            pixel_representation
                        ),
                        Ok(())
                    );
                }
            }
        }
    }

    #[test]
    fn limits_reject_invalid_and_overflow_dimensions_before_decode() {
        assert_eq!(domain_bytes(0, 4, 1, 1), Err("invalid_dimensions"));
        assert_eq!(
            domain_bytes(1, 1, MAX_FRAMES + 1, 1),
            Err("invalid_dimensions")
        );
        assert_eq!(domain_bytes(u64::MAX, 2, 1, 1), Err("decoded_size_limit"));
        assert_eq!(domain_bytes(4096, 4096, 2, 1), Ok(MAX_DOMAIN_BYTES));
        assert_eq!(domain_bytes(4096, 4096, 3, 1), Err("decoded_size_limit"));
    }

    #[test]
    fn malformed_photometric_cannot_be_echoed_as_identifying_text() {
        assert_eq!(safe_pi("PATIENT EXAMPLE"), "unknown");
        assert_eq!(safe_pi("RGB\0 "), "RGB");
        assert_eq!(caught::<()>(|| panic!("private text")), Err("panic"));
    }
}
