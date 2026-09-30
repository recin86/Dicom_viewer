#!/usr/bin/env python3
"""P0-DATA-CLOSE fixture preparation, independent metadata golden and gap audit.

This invokes no product implementation. Original public files are read only;
generated DICOM and golden live outside the repository. Exit 0 means fixture
preparation/readback passed, not product support or a complete IOD validation.
"""

from __future__ import annotations

import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import logging
from pathlib import Path
import platform
import sys
import time
import warnings

import numpy as np
import pydicom
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.encaps import encapsulate, parse_basic_offsets
from pydicom.pixels import get_encoder, iter_pixels, pixel_array
from pydicom.tag import Tag
from pydicom.uid import (
    CTImageStorage, DigitalXRayImageStorageForPresentation, ExplicitVRLittleEndian,
    RLELossless, UltrasoundMultiFrameImageStorage,
)


TASK_ID = "P0-DATA-CLOSE"
BASE_COMMIT = "ea7e2b351fad35a1e8871e6e21bf226739913d67"
ROOT = Path(__file__).resolve().parents[2]
CACHE = Path.home() / "Library/Caches/dicom-viewer/p0-data"
SOURCES = {
    "image_plane": "https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.2.html",
    "dx_image": "https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.8.11.3.html",
    "cine": "https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.5.html",
    "standard_version_observed": "PS3.3 2026d (current pages consulted 2026-09-30)",
}


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def uid(label):
    return "2.25." + str(int.from_bytes(hashlib.sha256(label.encode()).digest()[:16], "big"))


def numeric(values):
    return [float(value) for value in values]


def at_values(value):
    # pydicom returns a single-valued AT element as one tag, multi-valued as a list.
    return [int(tag) for tag in (value if isinstance(value, (list, tuple, pydicom.multival.MultiValue)) else [value])]


def new_dataset(label, sop, modality, rows, cols, *, bits=16, stored=16, signed=False, series="series"):
    meta = FileMetaDataset()
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    meta.MediaStorageSOPClassUID = sop
    meta.MediaStorageSOPInstanceUID = uid(label)
    meta.ImplementationClassUID = uid("P0-DATA-CLOSE-generator-v1")
    ds = FileDataset(None, {}, file_meta=meta, preamble=b"\0" * 128)
    ds.SOPClassUID = sop
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.StudyInstanceUID = uid("P0-DATA-study")
    ds.SeriesInstanceUID = uid(series)
    ds.PatientName = ""
    ds.PatientID = ""
    ds.PatientBirthDate = ""
    ds.PatientSex = ""
    ds.StudyDate = "20000101"
    ds.StudyTime = "120000"
    ds.AccessionNumber = ""
    ds.StudyID = ""
    ds.SeriesNumber = 1
    ds.InstanceNumber = 1
    ds.Manufacturer = "PROJECT SYNTHETIC"
    ds.Modality = modality
    ds.Rows, ds.Columns = rows, cols
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.BitsAllocated, ds.BitsStored = bits, stored
    ds.HighBit = stored - 1
    ds.PixelRepresentation = int(signed)
    ds.LossyImageCompression = "00"
    ds.BurnedInAnnotation = "NO"
    ds.ImageType = ["ORIGINAL", "PRIMARY", ""]
    return ds


def pixel_metadata(ds):
    # This helper is used only for our deterministic synthetic attributes.
    return {"sop_class_uid": str(ds.SOPClassUID), "ts_uid": str(ds.file_meta.TransferSyntaxUID),
            "modality": str(ds.Modality), "rows": int(ds.Rows), "cols": int(ds.Columns),
            "frames": int(getattr(ds, "NumberOfFrames", 1)), "samples": int(ds.SamplesPerPixel),
            "bits_allocated": int(ds.BitsAllocated), "bits_stored": int(ds.BitsStored),
            "high_bit": int(ds.HighBit), "pixel_representation": int(ds.PixelRepresentation),
            "photometric": str(ds.PhotometricInterpretation), "lossy": str(ds.LossyImageCompression)}


def ct_values(index):
    rows = np.arange(512, dtype=np.int32)[:, None]
    cols = np.arange(512, dtype=np.int32)[None, :]
    return ((37 * index + 3 * rows + 5 * cols) % 4096 - 1024).astype("<i2")


def us_values(index):
    rows = np.arange(480, dtype=np.int32)[:, None]
    cols = np.arange(640, dtype=np.int32)[None, :]
    return ((13 * index + 7 * (rows // 16) + 3 * (cols // 64)) % 256).astype(np.uint8)


def selected_pixels(frame, index, formula):
    points = ((0, 0), (3, 2), (frame.shape[0] - 1, frame.shape[1] - 1))
    return [{"frame_index": index, "dicom_frame_number": index + 1, "row": row, "col": col,
             "expected_stored": formula(index, row, col)} for row, col in points]


def compare_pixels(actual, expected):
    return {"status": "pass" if actual.shape == expected.shape and np.array_equal(actual, expected) else "fail",
            "expected_values": int(expected.size), "actual_values": int(actual.size)}


def checks_status(checks):
    return "pass" if all(check["status"] == "pass" for check in checks) else "fail"


def generate(work):
    generated = work / "generated"
    golden_dir = work / "golden"
    generated.mkdir(parents=True, exist_ok=True)
    golden_dir.mkdir(parents=True, exist_ok=True)
    fixtures, results = [], []

    def finish(fixture_id, ds, golden, condition, path, expected_frames, extra_checks):
        before_metadata = pixel_metadata(ds)
        pydicom.dcmwrite(path, ds, enforce_file_format=True)
        before = digest(path)
        reread = pydicom.dcmread(path)
        checks = [{"name": "pixel_metadata_readback", "status": "pass" if pixel_metadata(reread) == before_metadata else "fail"}]
        checks.extend(extra_checks(reread))
        pixel_count = 0
        frames = 0
        for index, frame in enumerate(iter_pixels(reread, raw=True, decoding_plugin="pydicom" if reread.file_meta.TransferSyntaxUID == RLELossless else "")):
            expected = expected_frames(index)
            check = compare_pixels(frame, expected)
            checks.append({"name": "frame_all_pixel_readback", "frame_index": index, **check})
            pixel_count += int(frame.size)
            frames += 1
        checks.append({"name": "frame_count_readback", "status": "pass" if frames == before_metadata["frames"] else "fail"})
        after = digest(path)
        checks.append({"name": "source_hash_unchanged", "status": "pass" if before == after else "fail"})
        golden_path = golden_dir / (fixture_id + ".json")
        golden_path.write_text(json.dumps(golden, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        fixtures.append({"fixture_id": fixture_id, "kind": "project-generated synthetic",
                         "source": "P0-DATA-CLOSE literal parameters and independent formulas", "license": "project-generated; no patient content",
                         "sha256": before, "bytes": path.stat().st_size, **before_metadata,
                         "condition": condition, "golden": golden, "golden_sha256": digest(golden_path),
                         "expected_preparation": "readback all pixels/metadata/frame count exactly match generated inputs",
                         "product_tests": "not-run: no product implementation invoked",
                         "iod_validation": "not-run: pixel/geometry/timing fixture; no complete IOD conformance validator",
                         "requirements": ["FR-03", "FR-04", "QR-01", "QR-04"], "test_ids": golden["test_ids"]})
        results.append({"fixture_id": fixture_id, "status": checks_status(checks), "checks": checks,
                        "frames_decoded": frames, "pixels_compared": pixel_count,
                        "hash_before": before, "hash_after": after})

    for index in range(32):
        fixture_id = f"data-ct-{index:03d}"
        ds = new_dataset(fixture_id, CTImageStorage, "CT", 512, 512, signed=True, series="regular-CT-stack")
        ds.FrameOfReferenceUID = uid("regular-CT-frame-of-reference")
        ds.ImageType = ["ORIGINAL", "PRIMARY", "AXIAL"]
        ds.ImagePositionPatient = [10, 20, 30 + 1.5 * index]
        ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
        ds.PixelSpacing = [0.7, 0.4]
        ds.SliceThickness = 1.5
        ds.SpacingBetweenSlices = 1.5
        ds.GantryDetectorTilt = 0
        ds.RescaleSlope, ds.RescaleIntercept, ds.RescaleType = "1.5", "-1024", "HU"
        ds.InstanceNumber = 32 - index
        ds.PixelData = ct_values(index).tobytes()
        ds["PixelData"].VR = "OW"
        rank = (13 * index + 7) % 32
        golden = {"test_ids": ["T-03", "T-04", "T-06", "T-07", "T-09"],
                  "spatial_dimension": "regular axial patient-LPS stack; not acquisition cine", "time_dimension": "none",
                  "slice_index": index, "filename_sort_rank": rank, "instance_number": 32 - index,
                  "origin_lps_mm": [10, 20, 30 + 1.5 * index], "row_direction": [1, 0, 0], "column_direction": [0, 1, 0],
                  "normal": [0, 0, 1], "slice_projection_mm": 30 + 1.5 * index,
                  "pixel_spacing_row_col_mm": [0.7, 0.4], "regular_slice_step_mm": 1.5,
                  "pixel_row3_col2_lps_mm": [10.8, 22.1, 30 + 1.5 * index], "calibration": "PatientPlane",
                  "pixel_formula": "stored[k,r,c]=((37*k+3*r+5*c)%4096)-1024; Modality=stored*1.5-1024",
                  "rescale": {"slope": 1.5, "intercept": -1024, "unit": "HU"},
                  "selected_pixels": selected_pixels(ct_values(index), 0, lambda _, r, c: (37 * index + 3 * r + 5 * c) % 4096 - 1024)}
        def ct_checks(read, k=index):
            actual = {"origin": numeric(read.ImagePositionPatient), "orientation": numeric(read.ImageOrientationPatient),
                      "spacing": numeric(read.PixelSpacing), "instance": int(read.InstanceNumber),
                      "tilt": float(read.GantryDetectorTilt), "slope": float(read.RescaleSlope), "intercept": float(read.RescaleIntercept)}
            expected = {"origin": [10, 20, 30 + 1.5 * k], "orientation": [1, 0, 0, 0, 1, 0],
                        "spacing": [0.7, 0.4], "instance": 32 - k, "tilt": 0, "slope": 1.5, "intercept": -1024}
            return [{"name": "geometry_rescale_readback", "status": "pass" if actual == expected else "fail"}]
        finish(fixture_id, ds, golden, "regular no-tilt CT; filename and InstanceNumber order disagree with geometry",
               generated / f"ct-slot-{rank:03d}.dcm", lambda _, k=index: ct_values(k), ct_checks)

    dx_values = (np.arange(256, dtype=np.uint16).reshape(16, 16) * 16).astype("<u2")
    for name, photometric, shape, pixel_spacing, imager, state in (
        ("calibrated", "MONOCHROME2", "IDENTITY", [0.2, 0.15], [0.4, 0.3], "CalibratedProjection"),
        ("detector", "MONOCHROME1", "INVERSE", None, [0.4, 0.3], "DetectorPlane"),
        ("unverified", "MONOCHROME2", "IDENTITY", [0.2, 0.15], None, "ProjectionUnverified"),
    ):
        fixture_id = "data-dx-" + name
        ds = new_dataset(fixture_id, DigitalXRayImageStorageForPresentation, "DX", 16, 16, stored=12, series=fixture_id)
        ds.PresentationIntentType = "FOR PRESENTATION"
        ds.PhotometricInterpretation, ds.PresentationLUTShape = photometric, shape
        ds.PixelIntensityRelationship = "LIN"
        ds.PixelIntensityRelationshipSign = 1
        ds.RescaleSlope, ds.RescaleIntercept, ds.RescaleType = "1", "0", "US"
        ds.WindowCenter, ds.WindowWidth, ds.VOILUTFunction = 2048, 4096, "LINEAR_EXACT"
        ds.PatientOrientation = ["L", "F"]
        if pixel_spacing is not None:
            ds.PixelSpacing = pixel_spacing
        if imager is not None:
            ds.ImagerPixelSpacing = imager
        if name == "calibrated":
            ds.PixelSpacingCalibrationType = "GEOMETRY"
        ds.PixelData = dx_values.tobytes()
        ds["PixelData"].VR = "OW"
        expected_spacing = pixel_spacing or imager
        golden = {"test_ids": ["T-03", "T-04", "T-09"], "spatial_dimension": "single projection; no patient-LPS plane",
                  "time_dimension": "none", "required_pixel_representation": 0, "pixel_formula": "stored[r,c]=16*(16*r+c); Modality identity",
                  "photometric": photometric, "presentation_lut_shape": shape,
                  "normalized_voi_0_1_after_default_polarity": [1, 0] if shape == "INVERSE" else [0, 1],
                  "pixel_intensity_relationship_sign": "+1; does not independently invert display",
                  "pixel_spacing_row_col_mm": pixel_spacing, "imager_pixel_spacing_row_col_mm": imager,
                  "calibration": state, "measurement_spacing_row_col_mm": expected_spacing,
                  "one_row_one_col_distance_mm": float(np.hypot(*expected_spacing)),
                  "physical_scope": "calibrated projection plane" if state == "CalibratedProjection" else "detector plane" if state == "DetectorPlane" else "calibration unverified",
                  "selected_pixels": selected_pixels(dx_values, 0, lambda _, r, c: 16 * (16 * r + c))}
        def dx_checks(read, pi=photometric, lut=shape, ps=pixel_spacing, ips=imager):
            actual = {"signedness": int(read.PixelRepresentation), "pi": str(read.PhotometricInterpretation),
                      "lut": str(read.PresentationLUTShape), "slope": float(read.RescaleSlope), "intercept": float(read.RescaleIntercept),
                      "pixel_spacing": numeric(read.PixelSpacing) if "PixelSpacing" in read else None,
                      "imager_spacing": numeric(read.ImagerPixelSpacing) if "ImagerPixelSpacing" in read else None}
            expected = {"signedness": 0, "pi": pi, "lut": lut, "slope": 1, "intercept": 0, "pixel_spacing": ps, "imager_spacing": ips}
            return [{"name": "DX_polarity_identity_calibration_tags", "status": "pass" if actual == expected else "fail"}]
        condition = state + "; unsigned DX for Presentation"
        if imager is None:
            condition += "; intentional nonconformance: DX Detector Module Type 1 ImagerPixelSpacing omitted to exercise unverified calibration"
        finish(fixture_id, ds, golden, condition, generated / (fixture_id + ".dcm"), lambda _: dx_values, dx_checks)

    encoder = get_encoder(RLELossless)
    for name, count in (("fixed-long", 300), ("variable", 3), ("missing-time", 3)):
        fixture_id = "data-us-" + name
        ds = new_dataset(fixture_id, UltrasoundMultiFrameImageStorage, "US", 480, 640, bits=8, stored=8, series=fixture_id)
        ds.NumberOfFrames = count
        ds.StartTrim, ds.StopTrim = (2, 3) if name == "variable" else (1, count)
        ds.PreferredPlaybackSequencing = 1 if name == "variable" else 0
        ds.FrameDelay = 17
        if name == "fixed-long":
            ds.FrameTime = 40
            ds.FrameIncrementPointer = [Tag(0x00181063)]
            relative = [40 * i for i in range(count)]
            timing_source = "FrameTime: explicit 40ms increments; UI-relative first-frame zero"
        elif name == "variable":
            ds.FrameTimeVector = [0, 40, 60]
            ds.FrameIncrementPointer = [Tag(0x00181065)]
            relative = [0, 40, 100]
            timing_source = "FrameTimeVector: increments [0,40,60]ms; independent cumulative times [0,40,100]"
        else:
            relative = None
            timing_source = "missing timing: no acquisition-relative time may be asserted"
        compressed = []
        for index in range(count):
            compressed.append(encoder.encode(us_values(index), encoding_plugin="pydicom", rows=480, columns=640,
                                             number_of_frames=1, samples_per_pixel=1, bits_allocated=8, bits_stored=8,
                                             pixel_representation=0, photometric_interpretation="MONOCHROME2", planar_configuration=0))
            if count == 300 and (index + 1) % 100 == 0:
                print(f"synthetic US encoding: {index + 1}/{count} frames", flush=True)
        ds.file_meta.TransferSyntaxUID = RLELossless
        ds.PixelData = encapsulate(compressed)
        ds["PixelData"].VR = "OB"
        ds["PixelData"].is_undefined_length = True
        chosen = sorted(set((0, count // 2, count - 1)))
        golden = {"test_ids": ["T-03", "T-07", "T-08", "T-09"], "spatial_dimension": "none; no physical US calibration regions",
                  "time_dimension": "cine" if relative is not None else "ordered frames with unavailable acquisition timing",
                  "pixel_formula": "stored[f,r,c]=(13*f+7*(r//16)+3*(c//64))%256", "calibration": "PixelOnly",
                  "frame_index_range": [0, count - 1], "dicom_frame_number_range": [1, count],
                  "relative_acquisition_times_ms": relative, "timing_source": timing_source,
                  "frame_delay_ms": 17, "frame_delay_added_to_UI_elapsed": False,
                  "trim_dicom_frame_numbers": [int(ds.StartTrim), int(ds.StopTrim)],
                  "trimmed_source_frame_indices": [int(ds.StartTrim) - 1, int(ds.StopTrim) - 1],
                  "trimmed_playback_elapsed_ms": [0, 60] if name == "variable" else relative,
                  "fallback_playback_if_timing_missing": {"source": "explicit test user-default policy, not acquisition", "fps": 30,
                                                           "elapsed_ms": [0, 1000 / 30, 2000 / 30]} if relative is None else None,
                  "selected_pixels": [sample for index in chosen for sample in selected_pixels(us_values(index), index,
                                      lambda f, r, c: (13 * f + 7 * (r // 16) + 3 * (c // 64)) % 256)],
                  "encoding": "RLE pydicom encoder; one fragment/frame with BOT; readback is fixture preparation, not external compatibility proof"}
        def us_checks(read, kind=name, n=count):
            checks = [{"name": "BOT_frame_count", "status": "pass" if len(parse_basic_offsets(read.PixelData)) == n else "fail"},
                      {"name": "trim_readback", "status": "pass" if [int(read.StartTrim), int(read.StopTrim)] == ([2, 3] if kind == "variable" else [1, n]) else "fail"}]
            if kind == "fixed-long":
                timing_ok = float(read.FrameTime) == 40 and at_values(read.FrameIncrementPointer) == [0x00181063]
            elif kind == "variable":
                timing_ok = numeric(read.FrameTimeVector) == [0, 40, 60] and at_values(read.FrameIncrementPointer) == [0x00181065]
            else:
                timing_ok = "FrameTime" not in read and "FrameTimeVector" not in read and "FrameIncrementPointer" not in read
            checks.append({"name": "timing_tags_readback", "status": "pass" if timing_ok else "fail"})
            return checks
        condition = timing_source
        if relative is None:
            condition += "; intentional nonconformance: Multi-frame Module Type 1 FrameIncrementPointer omitted to exercise missing timing"
        finish(fixture_id, ds, golden, condition, generated / (fixture_id + ".dcm"), us_values, us_checks)
    stack_golden = {"fixture_id": "data-ct-stack-32", "test_ids": ["T-06", "T-07", "T-09"],
                    "expected_spatial_order": [f"data-ct-{i:03d}" for i in range(32)],
                    "expected_filename_order": [f"data-ct-{(5 * rank - 35) % 32:03d}" for rank in range(32)],
                    "expected_instance_number_ascending_order": [f"data-ct-{i:03d}" for i in reversed(range(32))],
                    "expected_slice_projections_mm": [30 + 1.5 * i for i in range(32)],
                    "sort_direction_note": "ascending slice projection along the normal is this golden's convention; docs/03 does not fix the display direction",
                    "spacing_regular": True, "gantry_tilt_deg": 0, "full_IOD_conformance": "not-run"}
    (golden_dir / "ct-stack.json").write_text(json.dumps(stack_golden, indent=2) + "\n", encoding="utf-8")
    return fixtures, results, stack_golden


def source_audit(codec_report, inventory_path, local_data):
    codec_before = digest(codec_report)
    inventory_before = digest(inventory_path)
    manifest = json.loads(codec_report.read_text(encoding="utf-8"))["fixture_manifest"]
    if len(manifest) != 381:
        raise ValueError("expected_frozen_CODEC_manifest381")
    public = [item for item in manifest if item["kind"] == "public-local-only"]
    if len(public) != 331:
        raise ValueError("expected_public331")
    with inventory_path.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != len(public):
        raise ValueError("inventory_count_mismatch")
    hash_results, source_paths = [], []
    for row, fixture in zip(rows, public):
        path = local_data / row["set"] / row["file"]
        content = digest(path)
        hash_results.append({"fixture_id": fixture["fixture_id"], "expected_sha256": fixture["sha256"], "sha256": content,
                             "status": "pass" if content == fixture["sha256"] == row["sha256"] else "fail"})
        source_paths.append((path, content, fixture["fixture_id"]))
    def distribution(items, key):
        return dict(sorted(Counter(str(item.get(key, "unavailable")) for item in items).items()))
    enhanced_ct = "1.2.840.10008.5.1.4.1.1.2.1"
    enhanced_mr = "1.2.840.10008.5.1.4.1.1.4.1"
    distributions = {"public_files": len(public), "public_unique_sha256": len(set(item["sha256"] for item in public)),
                     "codec_synthetic_files": len(manifest) - len(public), "transfer_syntax": distribution(public, "ts_uid"),
                     "sop_class": distribution(public, "sop_class_uid"), "modality": distribution(public, "modality"),
                     "enhanced": {"CT": sum(item.get("sop_class_uid") == enhanced_ct for item in public),
                                  "MR": sum(item.get("sop_class_uid") == enhanced_mr for item in public)},
                     "sample_bias": "curated codec/QA corpus; file counts are not clinical usage frequency; duplicates retained for source audit"}
    safe_keys = ("fixture_id", "kind", "source", "source_url", "license", "sha256", "sop_class_uid", "ts_uid", "modality",
                 "rows", "cols", "frames", "samples", "bits_allocated", "bits_stored", "high_bit", "pixel_representation",
                 "photometric", "lossy_declared", "rescale_slope", "rescale_intercept", "modality_lut_present",
                 "functional_group_pixel_value_transformation", "golden_basis", "expected", "condition", "test_ids")
    safe_manifest = [{key: item[key] for key in safe_keys if key in item} for item in manifest]
    record = {"codec_report": "experiments/p0-codec/results/combined-c.json", "codec_report_sha256": codec_before,
              "inventory_revision": "P0-DATA public sample inventory ver1.1", "inventory_sha256": inventory_before,
              "existing_manifest": safe_manifest, "distributions": distributions, "public_hash_checks": hash_results}
    return record, source_paths, (codec_before, inventory_before)


def coverage():
    return [
        {"family": "CT", "prepared": "public tilt/irregular stacks, CODEC signedness/rescale; new regular32 axial synthetic",
         "remaining": "manufacturer no-tilt regular CT series; independent product T06 sorting/coordinates/stack acceptance",
         "needed_by": "P2 exploration and P5 release compatibility"},
        {"family": "MR", "prepared": "public standard/Enhanced MR and codec fixtures",
         "remaining": "controlled same-position echo/time, different FrameOfReference, incomplete geometry golden; Enhanced product rejection/limitation tests",
         "needed_by": "P2 grouping; Enhanced remains v0.2 candidate pending dedicated interpretation"},
        {"family": "X-ray", "prepared": "public CR; new3 unsigned DXforPresentation with MONO1/2, calibrated/detector/unverified spacing",
         "remaining": "manufacturer DX and calibration provenance, PixelSpacing equal to ImagerPixelSpacing without calibration type (DetectorPlane rule), detector spacing conflicts, DX-specific VOI LUT10..16bit, invalid signed DX rejection",
         "needed_by": "P1 display/T04 and P3 measurement/T09; manufacturer coverage before P5"},
        {"family": "US", "prepared": "public RGB/YBR/Palette/short cine; new640x480 fixed300/variable3/missing3 grayscale RLE",
         "remaining": "manufacturer long cine with reliable fixed/variable acquisition timing, calibration regions with different axis units, 640x480 color 300-frame performance case (docs/06); actual app playback",
         "needed_by": "P2 cine/T08 and P5 manufacturer compatibility; physical US measurement later scope"},
        {"family": "codec", "prepared": "CODEC50 synthetic+public331 manifest with BOT/EOT/fragment/rescale/color findings preserved",
         "remaining": "existing CODEC failures and unavailable references; generation readback does not prove external codec compatibility",
         "needed_by": "P1 adapter and subsequent supported profile validation"},
        {"family": "metadata/recovery/display boundaries", "prepared": "public charset and CODEC padding; deterministic source hashes",
         "remaining": "UID collision/missing/changed source; deep sequences/resource bounds; access/move/delete; pixel aspect/invalid spacing; all product behavior not-run",
         "needed_by": "P2/P4/P5 applicable tests; not required to fabricate real acquisition coverage at P0"},
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, default=CACHE)
    parser.add_argument("--codec-report", type=Path, default=ROOT / "experiments/p0-codec/results/combined-c.json")
    parser.add_argument("--inventory", type=Path, default=ROOT / "local-data/20260930_DicomViewer_sample-inventory_ver1.1_KMJ.csv")
    parser.add_argument("--local-data", type=Path, default=ROOT / "local-data")
    parser.add_argument("--report", type=Path, default=ROOT / "experiments/p0-data/results/preparation.json")
    args = parser.parse_args()
    # Never allow accidental DICOM/golden generation in the source repository.
    work = args.work_dir.expanduser().resolve()
    if work == ROOT or ROOT in work.parents:
        raise ValueError("generated_artifacts_must_be_outside_repository")
    if pydicom.__version__ != "3.0.2" or platform.python_version() != "3.12.13":
        raise RuntimeError("requires_pinned_CODEC_venv_Python3.12.13_pydicom3.0.2")
    logging.getLogger("pydicom").setLevel(logging.ERROR)
    warnings.filterwarnings("ignore")
    started = time.perf_counter()
    source, paths, source_hashes = source_audit(args.codec_report, args.inventory, args.local_data)
    work.mkdir(parents=True, exist_ok=True)
    fixtures, results, stack = generate(work)
    source_unchanged = []
    for path, before, fixture_id in paths:
        after = digest(path)
        source_unchanged.append({"fixture_id": fixture_id, "hash_before": before, "hash_after": after,
                                 "status": "pass" if before == after else "fail"})
    audit_unchanged = digest(args.codec_report) == source_hashes[0] and digest(args.inventory) == source_hashes[1]
    all_pass = all(item["status"] == "pass" for item in results + source_unchanged + source["public_hash_checks"]) and audit_unchanged
    versions = {name: importlib.metadata.version(name) for name in ("pydicom", "numpy")}
    report = {"schema_version": 1, "task_id": TASK_ID, "base_commit": BASE_COMMIT,
              "timestamp_utc": datetime.now(timezone.utc).isoformat(),
              "environment": {"system": platform.system(), "macos": platform.mac_ver()[0], "machine": platform.machine(),
                              "python": platform.python_version(), "generator_versions": versions,
                              "reference_decoder": "pydicom3.0.2 native/RLE Python implementation"},
              "script_sha256": digest(Path(__file__)), "standards": SOURCES,
              "existing_source": source, "synthetic_fixture_manifest": fixtures, "stack_golden": stack,
              "results": results, "public_source_invariants": source_unchanged, "coverage_and_gaps": coverage(),
              "summary": {"preparation_status": "pass" if all_pass else "fail", "synthetic_files": len(fixtures),
                          "CT": 32, "DX": 3, "US": 3, "synthetic_frames": sum(item["frames_decoded"] for item in results),
                          "all_pixels_compared": sum(item["pixels_compared"] for item in results),
                          "synthetic_bytes": sum(item["bytes"] for item in fixtures),
                          "public_source_hashes_unchanged": all(item["status"] == "pass" for item in source_unchanged),
                          "CODEC_and_inventory_unchanged": audit_unchanged, "wall_seconds": time.perf_counter() - started,
                          "product_T03_T09": "not-run: fixture preparation only", "manufacturer_compatibility": "not-run: synthetic cannot replace real manufacturer gaps",
                          "full_IOD_conformance": "not-run: no independent complete IOD validator"}}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], ensure_ascii=False), flush=True)
    return 0 if all_pass else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({"status": "error", "stage": "fixture_preparation", "error_kind": type(error).__name__, "exit_code": 2}))
        sys.exit(2)
