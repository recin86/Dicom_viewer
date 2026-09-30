"""P0-CODEC independent fixture/report helpers; no product code imports."""

from __future__ import annotations

import hashlib
import importlib.metadata
import math
import platform
import re
from pathlib import Path

import numpy as np


SCHEMA_VERSION = 1
PACKAGES = (
    "pydicom", "numpy", "pylibjpeg", "pylibjpeg-libjpeg",
    "pylibjpeg-openjpeg", "pyjpegls",
)
PHOTOMETRICS = {"MONOCHROME1", "MONOCHROME2", "PALETTE COLOR", "RGB", "HSV", "ARGB", "CMYK",
               "YBR_FULL", "YBR_FULL_422", "YBR_PARTIAL_422", "YBR_PARTIAL_420", "YBR_ICT", "YBR_RCT"}
MODALITIES = {"CT", "MR", "CR", "DX", "US", "OT", "SC", "SEG", "PT", "NM", "RTIMAGE", "RTDOSE",
              "RTSTRUCT", "SR", "PR", "MG", "XA", "RF", "IO", "PX", "XC", "ES", "SM", "GM", "HC", "DOC"}


def safe_uid(value) -> str:
    value = str(value)
    return value if len(value) <= 64 and re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", value) else "unrecognized"


def safe_number(value):
    try:
        number = float(value)
        return number if math.isfinite(number) else None
    except (ValueError, TypeError):
        return None


def safe_enum(value, allowed) -> str:
    value = str(value)
    return value if value in allowed else "unrecognized"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def versions() -> dict:
    result = {}
    for package in PACKAGES:
        try:
            result[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            result[package] = "unavailable"
    return result


def environment() -> dict:
    return {
        "system": platform.system(), "release": platform.release(),
        "machine": platform.machine(), "python": platform.python_version(),
        "reference_versions": versions(),
    }


def save_f64(path: Path, values: np.ndarray) -> None:
    np.asarray(values, dtype="<f8").ravel(order="C").tofile(path)


def functional_group_transform_presence(ds) -> dict:
    """Observe transform macros without interpreting Enhanced frame semantics."""
    return {
        "shared": any("PixelValueTransformationSequence" in item for item in getattr(ds, "SharedFunctionalGroupsSequence", [])),
        "per_frame": any("PixelValueTransformationSequence" in item for item in getattr(ds, "PerFrameFunctionalGroupsSequence", [])),
    }


def metadata(ds) -> dict:
    """Only nonidentifying pixel/conformance metadata enters durable reports."""
    def integer(name, default=0):
        try:
            return int(getattr(ds, name, default))
        except (TypeError, ValueError):
            return default

    return {
        "sop_class_uid": safe_uid(getattr(ds, "SOPClassUID", "")),
        "ts_uid": safe_uid(getattr(getattr(ds, "file_meta", None), "TransferSyntaxUID", "")),
        "modality": safe_enum(getattr(ds, "Modality", ""), MODALITIES),
        "rows": integer("Rows"), "cols": integer("Columns"),
        "frames": integer("NumberOfFrames", 1),
        "samples": integer("SamplesPerPixel", 1),
        "bits_allocated": integer("BitsAllocated"),
        "bits_stored": integer("BitsStored"), "high_bit": integer("HighBit"),
        "pixel_representation": integer("PixelRepresentation"),
        "missing_required_bit_metadata": [name for name in ("BitsAllocated", "BitsStored", "HighBit", "PixelRepresentation") if name not in ds],
        "photometric": safe_enum(getattr(ds, "PhotometricInterpretation", ""), PHOTOMETRICS),
        "planar_configuration": integer("PlanarConfiguration"),
        "lossy_declared": safe_enum(getattr(ds, "LossyImageCompression", ""), {"00", "01", ""}),
        "rescale_slope": safe_number(getattr(ds, "RescaleSlope", 1)),
        "rescale_intercept": safe_number(getattr(ds, "RescaleIntercept", 0)),
        "modality_lut_present": "ModalityLUTSequence" in ds,
        "functional_group_pixel_value_transformation": functional_group_transform_presence(ds),
        "padding_value": integer("PixelPaddingValue") if "PixelPaddingValue" in ds else None,
        "pixel_spacing_present": "PixelSpacing" in ds,
        "time_metadata_present": "FrameTime" in ds or "FrameTimeVector" in ds,
    }


def compare(actual: np.ndarray, expected: np.ndarray, max_abs: float = 0.0) -> dict:
    actual = np.asarray(actual, dtype=np.float64).ravel()
    expected = np.asarray(expected, dtype=np.float64).ravel()
    result = {"expected_values": int(expected.size), "actual_values": int(actual.size),
              "tolerance_max_abs": max_abs}
    if actual.size != expected.size:
        return {**result, "status": "fail", "reason": "length_mismatch"}
    if not np.isfinite(actual).all() or not np.isfinite(expected).all():
        return {**result, "status": "fail", "reason": "nonfinite_value"}
    errors = np.abs(actual - expected)
    max_error = float(errors.max(initial=0))
    return {**result, "status": "pass" if max_error <= max_abs else "fail",
            "max_abs_error": max_error, "mean_abs_error": float(errors.mean()) if errors.size else 0.0,
            "unequal_values": int(np.count_nonzero(errors)),
            "over_tolerance_values": int(np.count_nonzero(errors > max_abs))}


def modality_tolerance(expected: np.ndarray, decoder_tolerance: float, slope: float) -> dict:
    """docs06 F64 arithmetic bound plus independently fixed decoder allowance."""
    values = np.asarray(expected, dtype=np.float64)
    arithmetic = max(1e-6, float(np.abs(values).max(initial=0)) * 1e-9)
    decoder = decoder_tolerance * abs(slope)
    return {"arithmetic_allowance": arithmetic, "decoder_allowance": decoder,
            "total_allowance": arithmetic + decoder}
