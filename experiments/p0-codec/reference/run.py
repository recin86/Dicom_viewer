#!/usr/bin/env python3
"""P0-CODEC all-pixel independent comparison runner.

Exit 0: all applicable expected checks passed. Exit 1: findings (fail/not-run).
Exit 2: setup/argument failure. Structured reports do not contain original paths,
patient attributes, instance UIDs, decoder exception text, or stderr.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
from datetime import datetime, timezone
import json
import logging
from pathlib import Path
import platform
import struct
import subprocess
import sys
import time
import warnings

import numpy as np
import pydicom
from pydicom.encaps import parse_basic_offsets, parse_fragments
from pydicom.pixels import apply_modality_lut, convert_color_space, get_decoder, pixel_array
from pydicom.uid import UID

from common import SCHEMA_VERSION, PHOTOMETRICS, compare, environment, functional_group_transform_presence, metadata, modality_tolerance, safe_enum, safe_uid, sha256
from fixtures import generate, public_entry


# Fixed before observing dicom-rs output. Limits compare decoders for the same
# compressed input, not lossy output against the pre-compression source.
LOSSY_MAX_ABS = 1.0
COLOR_NORMALIZATION_MAX_ABS = 2.0
MAX_REFERENCE_BYTES = 256 * 1024 * 1024
OUTSIDE_INITIAL_PIXEL_SCOPE = (1, 32, 64)
INITIAL_EXCLUDED_TS = {"1.2.840.10008.1.2.4.201", "1.2.840.10008.1.2.4.202", "1.2.840.10008.1.2.4.203"}
SOURCES = {
    "pydicom-package": "https://github.com/pydicom/pydicom/tree/v3.0.2/src/pydicom/data/test_files",
    "pydicom-data": "https://github.com/pydicom/pydicom-data",
    "pydicom-charset": "https://github.com/pydicom/pydicom/tree/v3.0.2/src/pydicom/data/charset_files",
    "dcm-qa-ct": "https://github.com/neurolabusc/dcm_qa_ct",
}
STANDARD_REFERENCES = {
    "encapsulation": "https://dicom.nema.org/medical/dicom/2026d/output/chtml/part05/sect_A.4.html",
    "pydicom_pixel_array": "https://pydicom.github.io/pydicom/stable/reference/generated/pydicom.pixels.pixel_array.html",
    "pydicom_compression": "https://pydicom.github.io/pydicom/stable/tutorials/pixel_data/compressing.html",
}


def read_dataset(path: Path):
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return pydicom.dcmread(path)


def inventory(local_data: Path) -> tuple[list[dict], dict]:
    listings = sorted(local_data.glob("*sample-inventory*.csv"))
    if not listings:
        raise FileNotFoundError("inventory_unavailable")
    listing = listings[-1]
    cases = []
    with listing.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    for index, row in enumerate(rows):
        path = local_data / row["set"] / row["file"]
        category = "dcm-qa-ct" if row["set"].startswith("dcm_qa_ct") else (
            "pydicom-data" if "pydicom-data" in row["set"] else (
                "pydicom-charset" if "charset" in row["set"] else "pydicom-package"))
        digest = sha256(path) if path.is_file() else "unavailable"
        case = {
            "fixture_id": f"public-{index + 1:03d}-{digest[:12]}", "kind": "public-local-only",
            "source": category, "source_url": SOURCES[category],
            "license": "BSD-2-Clause (repository)" if category == "dcm-qa-ct" else "MIT (repository); per-file original redistribution unconfirmed",
            "sha256": digest, "inventory_sha256": row["sha256"],
            "inventory_hash_matches": digest == row["sha256"],
            "expected": "reference all-pixel comparison; malformed public input separately observed",
            "golden_basis": "independent pydicom raw=True; rescale/LUT separately applied once",
            "test_ids": ["T-03", "T-04", "T-05"], "_path": path,
        }
        try:
            ds = read_dataset(path)
            case.update(metadata(ds))
            case["part10"] = bool(getattr(ds.file_meta, "TransferSyntaxUID", None))
            case["pixel_data_present"] = any(name in ds for name in ("PixelData", "FloatPixelData", "DoubleFloatPixelData"))
        except Exception as error:
            case.update(reference_metadata_error=type(error).__name__)
        cases.append(case)
    return cases, {"files": len(rows), "sha256": sha256(listing), "source": "local P0-DATA inventory ver1.1"}


def decoder_plugin(ds) -> str:
    ts = UID(str(ds.file_meta.TransferSyntaxUID))
    if not ts.is_compressed:
        return ""
    decoder = get_decoder(ts)
    available = decoder.available_plugins
    # RLE is an independent pure Python implementation. LS selects libjpeg,
    # different from the synthetic pyjpegls encoder. JPEG/J2K use pylibjpeg.
    for plugin in ("pydicom", "pylibjpeg", "pyjpegls"):
        if plugin in available:
            return plugin
    raise RuntimeError("decoder_unavailable")


def structural_observation(ds) -> dict:
    """Inspect frame/offset evidence without trusting product decoding success."""
    ts = UID(str(ds.file_meta.TransferSyntaxUID))
    try:
        compressed = ts.is_compressed
    except ValueError:
        return {"encapsulated": None, "issues": [], "unknown_transfer_syntax": True}
    result = {"encapsulated": compressed, "issues": []}
    if not compressed or "PixelData" not in ds:
        return result
    pixel_data = ds.PixelData
    try:
        bot = parse_basic_offsets(pixel_data)
        n, offsets = parse_fragments(pixel_data)
        # parse_fragments includes the BOT item; absolute fragment item offsets
        # are normalized to the first real fragment for BOT/EOT comparison.
        bot_end = 8 + struct.unpack_from("<I", pixel_data, 4)[0]
        fragment_offsets = [offset - bot_end for offset in offsets if offset >= bot_end]
        result.update(bot_entries=len(bot), fragments=len(fragment_offsets), eot_present="ExtendedOffsetTable" in ds)
        frame_count = int(getattr(ds, "NumberOfFrames", 1))
        if bot:
            if len(bot) != frame_count:
                result["issues"].append("BOT_frame_count_mismatch")
            if bot[0] != 0 or any(offset not in fragment_offsets for offset in bot) or bot != sorted(set(bot)):
                result["issues"].append("BOT_invalid_fragment_offsets")
        elif "ExtendedOffsetTable" not in ds and str(ts).startswith("1.2.840.10008.1.2.4."):
            # JPEG/JPEG-LS/J2K EOI/EOC (FF D9) provides independent frame-count
            # evidence across fragment splits. This is an observation, not a
            # general codec parser or a product frame extraction algorithm.
            fragments = []
            for relative in fragment_offsets:
                absolute = bot_end + relative
                length = struct.unpack_from("<I", pixel_data, absolute + 4)[0]
                fragments.append(pixel_data[absolute + 8:absolute + 8 + length])
            eoi_count = b"".join(fragments).count(b"\xff\xd9")
            result["codestream_end_markers"] = eoi_count
            # Marker bytes may also occur in APP/COM marker payloads. This
            # count is informational only and never classifies public input as
            # malformed. Synthetic ambiguity is known from its construction.
            result["heuristic_end_marker_count_matches_frames"] = eoi_count == frame_count
        if "ExtendedOffsetTable" in ds:
            if bot:
                result["issues"].append("EOT_requires_empty_BOT")
            eot_bytes = ds.ExtendedOffsetTable
            len_bytes = getattr(ds, "ExtendedOffsetTableLengths", b"")
            if len(eot_bytes) % 8 or len(len_bytes) % 8:
                result["issues"].append("EOT_value_length_invalid")
            else:
                eot = list(struct.unpack("<" + "Q" * (len(eot_bytes) // 8), eot_bytes))
                lengths = list(struct.unpack("<" + "Q" * (len(len_bytes) // 8), len_bytes))
                if len(eot) != frame_count or len(lengths) != frame_count:
                    result["issues"].append("EOT_frame_count_mismatch")
                if not eot or eot[0] != 0 or any(offset not in fragment_offsets for offset in eot) or eot != sorted(set(eot)):
                    result["issues"].append("EOT_invalid_fragment_offsets")
                # EOT is permitted only when each frame occupies one fragment.
                if len(fragment_offsets) != frame_count:
                    result["issues"].append("EOT_requires_one_fragment_per_frame")
                for offset, length in zip(eot, lengths):
                    absolute = bot_end + offset
                    if absolute + 8 <= len(pixel_data):
                        item_length = struct.unpack_from("<I", pixel_data, absolute + 4)[0]
                        # The final codestream may have one pad byte.
                        if length not in (item_length, item_length - 1):
                            result["issues"].append("EOT_frame_length_mismatch")
                            break
    except Exception as error:
        result["issues"].append("encapsulation_parse_" + type(error).__name__)
    return result


def invoke(binary: Path, source: Path, prefix: Path, frame=None) -> dict:
    # CLI uses create_new. Delete only this runner's cache output, never sources
    # or golden arrays, so reruns cannot compare stale partial output.
    for old in prefix.parent.glob(prefix.name + ".*.f64le"):
        old.unlink()
    command = [str(binary), str(source), str(prefix)]
    if frame is not None:
        command += ["--frame", str(frame)]
    started = time.perf_counter()
    try:
        process = subprocess.run(command, capture_output=True, text=True, timeout=60)
        parsed = json.loads(process.stdout.strip().splitlines()[-1])
        if not isinstance(parsed, dict) or parsed.get("status") not in ("ok", "error"):
            raise ValueError("invalid_cli_status")
        # Sanitize upstream details defensively even if future CLI versions add text.
        allowed = {
            "status", "stage", "error_kind", "ts_uid", "rows", "cols", "frames", "samples",
            "bits_allocated", "bits_stored", "high_bit", "pixel_representation", "photometric",
            "decoded_photometric", "planar_configuration", "decoded_planar_configuration", "stored_domain",
            "frame_errors", "frame_results", "selected_frame", "decode_ms", "convert_ms", "stored_bytes",
            "modality_bytes", "decoded_bytes", "stored_convert_ms", "modality_convert_ms",
            "dicom_rs_version", "features", "limits", "modality_domain",
        }
        result = {key: value for key, value in parsed.items() if key in allowed}
        for key in ("photometric", "decoded_photometric"):
            if key in result:
                result[key] = safe_enum(result[key], PHOTOMETRICS)
        if "ts_uid" in result:
            result["ts_uid"] = safe_uid(result["ts_uid"])
        # Nested CLI error payloads can only expose stage/kind/frame, never message.
        result["frame_errors"] = [
            {key: value for key, value in item.items() if key in ("frame", "stage", "error_kind")}
            for item in result.get("frame_errors", [])]
        result["frame_results"] = [
            {key: safe_enum(value, PHOTOMETRICS) if key == "decoded_photometric" else value
             for key, value in item.items() if key in ("frame", "decoded_photometric", "decoded_bytes", "stored_bytes", "decode_ms")}
            for item in result.get("frame_results", [])]
        result["process_exit"] = process.returncode
        result["wall_ms"] = (time.perf_counter() - started) * 1000
        return result
    except subprocess.TimeoutExpired:
        return {"status": "error", "stage": "runner", "error_kind": "timeout", "wall_ms": 60000}
    except Exception as error:
        return {"status": "error", "stage": "runner", "error_kind": type(error).__name__,
                "wall_ms": (time.perf_counter() - started) * 1000}


def output_values(prefix: Path, suffix: str):
    path = Path(str(prefix) + suffix)
    if not path.is_file():
        return None
    if path.stat().st_size % 8:
        return None
    return np.fromfile(path, dtype="<f8")


def same_domain(reference, ds, rust, case) -> tuple[np.ndarray | None, str, float]:
    """Do not compare YBR components with RGB channels under an exact policy."""
    source_pi = safe_enum(ds.PhotometricInterpretation, PHOTOMETRICS)
    actual_pi = str(rust.get("decoded_photometric", ""))
    if actual_pi == source_pi or source_pi == "MONOCHROME1" and actual_pi == "MONOCHROME2":
        return reference, source_pi, 0.0
    if source_pi in ("YBR_FULL", "YBR_FULL_422") and actual_pi == "RGB":
        # raw=True expanded subsampling but deliberately did not convert YBR.
        return convert_color_space(reference, "YBR_FULL", "RGB"), "RGB normalized from YBR", COLOR_NORMALIZATION_MAX_ABS
    if source_pi in ("YBR_RCT", "YBR_ICT") and actual_pi == "RGB":
        # JPEG 2000 decoder reverses RCT/ICT internally even in raw=True mode.
        return reference, "RGB returned by JPEG 2000 reference decoder", 0.0
    return None, f"domain_mismatch:{source_pi}:{actual_pi}", 0.0


def classify_scope(case: dict) -> str | None:
    if case["kind"] == "synthetic":
        return None
    if "reference_metadata_error" in case:
        return "metadata unreadable; public malformed/non-Part10 input"
    if not case.get("part10"):
        return "raw dataset without file meta excluded by docs03"
    if not case.get("pixel_data_present"):
        return "non-image object; no Pixel Data"
    if case.get("bits_allocated") in OUTSIDE_INITIAL_PIXEL_SCOPE:
        return "1bit/32bit/float pixel path outside initial 8/16bit experiment"
    if case.get("ts_uid") in INITIAL_EXCLUDED_TS:
        return "HTJ2K excluded from v0.1 default scope by docs03; decoder observation still recorded"
    return None


def invalid_bit_metadata(case: dict) -> bool:
    allocated, stored = case.get("bits_allocated", 0), case.get("bits_stored", 0)
    return bool(case.get("missing_required_bit_metadata")) or allocated not in (8, 16) or not 0 < stored <= allocated or case.get("high_bit") != stored - 1 or case.get("pixel_representation") not in (0, 1)


def rejection_check(rust: dict, *, independently_invalid_bit_metadata=False) -> dict:
    """A missing codec, I/O failure or panic does not prove malformed rejection."""
    if rust.get("status") == "ok":
        return {"status": "fail", "reason": "malformed_input_accepted"}
    kind = rust.get("error_kind")
    if kind == "unsupported_transfer_syntax":
        return {"status": "not-run", "reason": "decoder_not_enabled_for_malformed_case"}
    if kind == "missing_pixel_metadata" and rust.get("stage") == "metadata" and independently_invalid_bit_metadata:
        return {"status": "pass", "reason": "independently_invalid_or_missing_bit_metadata_rejected"}
    structural_kinds = {"encapsulated_frame_error", "invalid_pixel_data", "unexpected_decoded_length", "invalid_pixel_metadata",
                        "invalid_dimensions", "decoded_size_limit", "decode_error", "parse_error", "frame_out_of_range", "invalid_bit_metadata"}
    if kind in structural_kinds and rust.get("stage") != "runner":
        return {"status": "pass", "reason": "malformed_input_rejected"}
    return {"status": "fail", "reason": "unrelated_or_infrastructure_error_does_not_prove_rejection"}


def negative_result(case, result, rust, binary, path, output_dir):
    invalid_bits = invalid_bit_metadata(case)
    checks = [{"path": "whole", "check": rejection_check(rust, independently_invalid_bit_metadata=invalid_bits)}]
    # A whole-object error cannot hide a direct selected-frame acceptance.
    if case.get("frames", 1) > 1:
        for index in sorted(set((0, case["frames"] - 1))):
            prefix = output_dir / (case["fixture_id"] + f"-negative-selected-{index}")
            selected = invoke(binary, path, prefix, frame=index)
            checks.append({"path": "--frame", "frame_index": index, "rust": selected,
                           "check": rejection_check(selected, independently_invalid_bit_metadata=invalid_bits)})
    statuses = [item["check"]["status"] for item in checks]
    status = "fail" if "fail" in statuses else "not-run" if "not-run" in statuses else "pass"
    return {**result, "status": status, "reason": "malformed_rejection_checks", "rejection_checks": checks,
            "expected_rejection": case.get("malformed_reason", "independent structural validation issues"), "hash_after": sha256(path)}


def test_case(case, binary, output_dir) -> dict:
    path = case["_path"]
    result = {"fixture_id": case["fixture_id"], "ts_uid": case.get("ts_uid", ""),
              "kind": case["kind"], "status": "not-run", "reason": "uninitialized",
              "hash_before": sha256(path) if path.is_file() else "unavailable"}
    if not path.is_file():
        return {**result, "reason": "source_unavailable", "hash_after": "unavailable"}
    try:
        ds = read_dataset(path)
    except Exception as error:
        return {**result, "status": "not-applicable", "reason": "public_metadata_" + type(error).__name__, "hash_after": sha256(path)}
    output_dir.mkdir(parents=True, exist_ok=True)
    prefix = output_dir / case["fixture_id"]
    result["structure"] = structural_observation(ds) if getattr(ds.file_meta, "TransferSyntaxUID", None) else {"issues": ["missing_TS"]}
    estimated_bytes = case.get("rows", 0) * case.get("cols", 0) * case.get("frames", 1) * case.get("samples", 1) * 8
    if estimated_bytes > MAX_REFERENCE_BYTES and not case.get("malformed_reason"):
        return {**result, "reason": "reference_output_over_256MiB_bound", "hash_after": sha256(path)}
    rust = invoke(binary, path, prefix)
    result["rust"] = rust
    if case.get("malformed_reason"):
        return negative_result(case, result, rust, binary, path, output_dir)
    scope_reason = classify_scope(case)
    if scope_reason:
        return {**result, "status": "not-applicable", "reason": scope_reason, "hash_after": sha256(path)}
    if invalid_bit_metadata(case):
        result["structure"]["issues"].append("invalid_bit_metadata")
        return negative_result(case, result, rust, binary, path, output_dir)
    if result["structure"]["issues"]:
        return negative_result(case, result, rust, binary, path, output_dir)
    started = time.perf_counter()
    try:
        plugin = decoder_plugin(ds)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            raw = pixel_array(ds, raw=True, decoding_plugin=plugin)
        result["reference"] = {"status": "ok", "decoder": "pydicom-native" if not plugin else "pydicom/" + plugin,
                               "wall_ms": (time.perf_counter() - started) * 1000,
                               "dtype": str(raw.dtype), "shape": list(raw.shape)}
        if raw.size != case["rows"] * case["cols"] * case["frames"] * case["samples"]:
            return {**result, "status": "not-applicable" if case["kind"] != "synthetic" else "fail",
                    "reason": "reference_output_frame_count_disagrees_with_metadata", "hash_after": sha256(path)}
        if case["kind"] == "synthetic":
            result["reference_vs_explicit_golden"] = compare(raw, case["_expected"])
            if result["reference_vs_explicit_golden"]["status"] != "pass":
                return {**result, "status": "fail", "reason": "synthetic_reference_disagrees_with_explicit_golden", "hash_after": sha256(path)}
            reference_stored = case["_expected"]
        else:
            reference_stored = raw
    except Exception as error:
        return {**result, "status": "not-run", "reason": "independent_decoder_unavailable_or_failed",
                "reference": {"status": "error", "error_kind": type(error).__name__}, "hash_after": sha256(path)}
    if rust["status"] != "ok":
        return {**result, "status": "fail", "reason": "rust_decode_error_reference_success", "hash_after": sha256(path)}
    reference_stored, domain, domain_tolerance = same_domain(reference_stored, ds, rust, case)
    result["comparison_domain"] = domain
    if reference_stored is None:
        return {**result, "status": "not-run", "reason": domain, "hash_after": sha256(path)}
    ts = UID(case["ts_uid"])
    lossy = ts in ("1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.51", "1.2.840.10008.1.2.4.81", "1.2.840.10008.1.2.4.91")
    tolerance = max(domain_tolerance, LOSSY_MAX_ABS if lossy else 0.0)
    functional_group_transform = functional_group_transform_presence(ds)
    unavailable_modality_reference = any(functional_group_transform.values())
    if unavailable_modality_reference:
        # apply_modality_lut sees top-level attributes only. Treating identity
        # as golden would falsely reject a decoder that applies a Shared or
        # Per-frame transform. This experiment does not interpret Enhanced FG.
        reference_modality = None
    elif case["kind"] == "synthetic" and domain_tolerance == 0:
        reference_modality = case["_modality"]
    else:
        reference_modality = apply_modality_lut(np.asarray(reference_stored), ds)
    stored = output_values(prefix, ".stored.f64le")
    modality = output_values(prefix, ".modality.f64le")
    result["stored"] = compare(stored, reference_stored, tolerance) if stored is not None else {"status": "fail", "reason": "missing_stored_output"}
    if not lossy and domain_tolerance > 0:
        result["raw_codec_exact"] = {"status": "not-run", "reason": "source_color_domain_unavailable_after_decoder_RGB_conversion"}
        result["color_normalized"] = dict(result["stored"])
    else:
        result["raw_codec_exact"] = dict(result["stored"]) if not lossy else {"status": "not-applicable", "reason": "lossy_transfer_syntax"}
    if unavailable_modality_reference:
        result["modality"] = {
            "status": "not-run", "reason": "functional_group_pixel_value_transformation_reference_unavailable",
            "reference_domain": "Shared/PerFrame PixelValueTransformationSequence not interpreted by independent oracle",
            "functional_group_pixel_value_transformation": functional_group_transform,
        }
        result["modality_tolerance"] = {"status": "not-run", "reason": "reference_modality_unavailable"}
    else:
        allowances = modality_tolerance(reference_modality, tolerance, float(getattr(ds, "RescaleSlope", 1)))
        result["modality_tolerance"] = allowances
        result["modality"] = compare(modality, reference_modality, allowances["total_allowance"]) if modality is not None else {"status": "fail", "reason": "missing_modality_output"}
    result["metadata_checks"] = []
    for key in ("rows", "cols", "frames", "samples", "bits_allocated", "bits_stored", "high_bit", "pixel_representation", "photometric"):
        result["metadata_checks"].append({"field": key, "expected": case[key], "actual": rust.get(key),
                                          "status": "pass" if case[key] == rust.get(key) else "fail"})
    frame_checks = []
    frames = case["frames"]
    if frames > 1:
        frame_values = np.asarray(reference_stored).reshape(frames, -1)
        for index in range(frames):
            frame_data = output_values(prefix, f".frame-{index}.f64le")
            check = compare(frame_data, frame_values[index], tolerance) if frame_data is not None else {"status": "fail", "reason": "missing_frame_output"}
            frame_checks.append({"frame_index": index, "check": check})
        selected = list(range(frames)) if case["kind"] == "synthetic" else sorted(set((0, frames // 2, frames - 1)))
        for index in selected:
            selected_prefix = output_dir / (case["fixture_id"] + f"-selected-{index}")
            frame_rust = invoke(binary, path, selected_prefix, frame=index)
            frame_data = output_values(selected_prefix, f".frame-{index}.f64le")
            check = compare(frame_data, frame_values[index], tolerance) if frame_rust["status"] == "ok" and frame_data is not None else {"status": "fail", "reason": "selected_frame_error_or_missing_output"}
            frame_checks.append({"frame_index": index, "path": "--frame", "check": check, "rust": frame_rust})
    result["frame_checks"] = frame_checks
    checks = [result["stored"], result["modality"]] + result["metadata_checks"] + [item["check"] for item in frame_checks]
    result["status"] = "fail" if any(item["status"] == "fail" for item in checks) else "not-run" if any(item["status"] == "not-run" for item in checks) else "pass"
    result["reason"] = "all_applicable_checks_match" if result["status"] == "pass" else "pixel_metadata_or_frame_mismatch"
    if result["status"] == "not-run" and unavailable_modality_reference:
        result["reason"] = "functional_group_modality_reference_unavailable_other_checks_match"
    if result["status"] == "pass" and result["raw_codec_exact"]["status"] == "not-run":
        result.update(status="not-run", reason="normalized_color_matches_but_raw_lossless_exactness_unverified")
    result["hash_after"] = sha256(path)
    if result["hash_after"] != result["hash_before"]:
        result.update(status="fail", reason="source_hash_changed")
    return result


def summary(results):
    grouped = defaultdict(Counter)
    for item in results:
        grouped[item.get("ts_uid", "")][item["status"]] += 1
    return {"counts": dict(Counter(item["status"] for item in results)),
            "by_transfer_syntax": {key: dict(value) for key, value in sorted(grouped.items())},
            "source_hashes_unchanged": all(item["hash_before"] == item.get("hash_after") for item in results),
            "inventory_hashes_match": all(item.get("inventory_hash_matches", True) for item in results)}


def enforce_source_invariants(result, case):
    result["inventory_hash_matches"] = case.get("inventory_hash_matches", True)
    if result["hash_before"] != result.get("hash_after"):
        result.update(status="fail", reason="source_hash_changed")
    if not result["inventory_hash_matches"]:
        result.update(status="fail", reason="source_inventory_hash_mismatch")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--work-dir", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--profile", default="baseline")
    parser.add_argument("--local-data", type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--synthetic-only", action="store_true")
    args = parser.parse_args()
    if not args.prepare_only and (not args.binary or not args.binary.is_file()):
        parser.error("--binary must identify a built experiment CLI")
    # Fixture/patient content must not appear in ordinary logs.
    logging.getLogger("pydicom").setLevel(logging.ERROR)
    warnings.filterwarnings("ignore")
    cases = generate(args.work_dir)
    inventory_record = {"files": 0, "reason": "synthetic-only"}
    if not args.synthetic_only and args.local_data:
        public, inventory_record = inventory(args.local_data)
        cases += public
    report = {
        "schema_version": SCHEMA_VERSION, "task_id": "P0-CODEC-REF", "profile": args.profile,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(), "environment": environment(),
        "binary_sha256": sha256(args.binary) if args.binary and args.binary.is_file() else None,
        "source_inventory": inventory_record, "references": STANDARD_REFERENCES,
        "policy": {"lossless": "all-pixel exact in same decoded color domain; normalized-color tolerance alone is not a lossless T03 pass",
                   "lossy_max_abs": LOSSY_MAX_ABS, "lossy_basis": "predeclared decoder-to-decoder difference on same compressed input",
                   "color_normalization_max_abs": COLOR_NORMALIZATION_MAX_ABS,
                   "color_basis": "predeclared YBR-to-RGB integer rounding difference; normalized domain only",
                   "modality_arithmetic_allowance": "docs06 F64: max(1e-6, max(abs(reference_modality))*1e-9)",
                   "modality_decoder_allowance": "stored decoder tolerance * abs(rescale slope)",
                   "modality_total_allowance": "arithmetic allowance + decoder allowance; lossless stored tolerance remains zero",
                   "functional_group_modality_reference": "Shared/PerFrame PixelValueTransformationSequence presence makes Modality not-run; stored, metadata and frame comparisons remain required",
                   "reference_output_bound_bytes": MAX_REFERENCE_BYTES,
                   "selected_frame_policy": "all synthetic frames; public first/middle/last plus all bulk individual-frame outputs",
                   "not_covered": "VOI/display/ROI/GPU/cache lifetime/renderer performance/full T13 are outside this P0 experiment",
                   "synthetic_roundtrip": "readback check only; explicit formulas remain golden; public independent decode is compatibility evidence"},
        "fixture_manifest": [public_entry(case) for case in cases],
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    manifest_path = args.work_dir / "fixture-manifest.json"
    manifest_path.write_text(json.dumps(report["fixture_manifest"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.prepare_only:
        report["results"] = []
        report["summary"] = {"prepared": len(cases), "product_comparison": "not-run: prepare-only"}
        exit_code = 0 if all(case.get("generation_readback", "pass") in ("pass", "not-applicable: intentionally malformed") and case.get("re_read_tags_match", True) for case in cases) else 1
    else:
        results = []
        started = time.perf_counter()
        for number, case in enumerate(cases, 1):
            before = sha256(case["_path"]) if case["_path"].is_file() else "unavailable"
            try:
                result = test_case(case, args.binary, args.work_dir / "product-output" / args.profile)
            except Exception as error:
                # Malformed LUT/transform metadata or a color conversion error
                # is a per-fixture finding; never abort the remaining sweep or
                # print raw decoder messages containing tag data or paths.
                result = {"fixture_id": case["fixture_id"], "ts_uid": case.get("ts_uid", ""),
                          "kind": case["kind"], "status": "not-run", "reason": "reference_runner_" + type(error).__name__,
                          "hash_before": before, "hash_after": sha256(case["_path"]) if case["_path"].is_file() else "unavailable"}
            # Enforce invariants after every return path, including not-run and
            # negative cases. A changed source can never be a passing check.
            result = enforce_source_invariants(result, case)
            results.append(result)
            if number % 25 == 0:
                print(f"{args.profile}: {number}/{len(cases)} fixtures checked", flush=True)
        report["results"] = results
        report["summary"] = summary(results)
        report["summary"]["wall_seconds"] = time.perf_counter() - started
        exit_code = 1 if any(result["status"] in ("fail", "not-run") for result in results) else 0
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"profile": args.profile, "summary": report["summary"], "exit_code": exit_code}), flush=True)
    return exit_code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({"status": "error", "stage": "setup", "error_kind": type(error).__name__, "exit_code": 2}))
        sys.exit(2)
