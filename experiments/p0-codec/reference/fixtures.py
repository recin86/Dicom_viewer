"""Deterministic DICOM fixtures; golden comes from explicit values/formulas.

Generated DICOM and golden arrays belong in the external work cache, never Git.
The encoder is not a compatibility oracle: the explicit array is the oracle.
"""

from __future__ import annotations

import copy
import hashlib
import struct
from pathlib import Path

import numpy as np
import pydicom
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.encaps import encapsulate, encapsulate_extended
from pydicom.pixels import get_encoder, pixel_array
from pydicom.uid import (
    DeflatedExplicitVRLittleEndian, ExplicitVRBigEndian, ExplicitVRLittleEndian,
    ImplicitVRLittleEndian, JPEG2000Lossless, JPEGLSLossless, RLELossless,
    SecondaryCaptureImageStorage, MultiFrameGrayscaleWordSecondaryCaptureImageStorage,
)

from common import metadata, save_f64, sha256, versions


def deterministic_uid(label: str) -> str:
    return "2.25." + str(int.from_bytes(hashlib.sha256(label.encode()).digest()[:16], "big"))


def dataset(label, values, *, bits=16, stored=None, signed=False, ts=ExplicitVRLittleEndian,
            slope=1.0, intercept=0.0, photometric="MONOCHROME2", planar=0):
    file_meta = FileMetaDataset()
    file_meta.TransferSyntaxUID = ts
    file_meta.MediaStorageSOPClassUID = SecondaryCaptureImageStorage
    file_meta.MediaStorageSOPInstanceUID = deterministic_uid(label)
    file_meta.ImplementationClassUID = deterministic_uid("P0-CODEC-REF-v1")
    ds = FileDataset(None, {}, file_meta=file_meta, preamble=b"\0" * 128)
    ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
    ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
    ds.Modality = "OT"
    ds.Rows, ds.Columns = values.shape[-3:-1] if photometric in ("RGB", "YBR_FULL") else values.shape[-2:]
    ds.SamplesPerPixel = 3 if photometric in ("RGB", "YBR_FULL") else 1
    frames = values.shape[0] if (values.ndim == 3 and ds.SamplesPerPixel == 1) or values.ndim == 4 else 1
    if frames > 1:
        ds.NumberOfFrames = frames
        if ds.SamplesPerPixel == 1 and bits == 16:
            ds.SOPClassUID = MultiFrameGrayscaleWordSecondaryCaptureImageStorage
            ds.file_meta.MediaStorageSOPClassUID = ds.SOPClassUID
    ds.PhotometricInterpretation = photometric
    if ds.SamplesPerPixel > 1:
        ds.PlanarConfiguration = planar
    ds.BitsAllocated = bits
    ds.BitsStored = stored or bits
    ds.HighBit = ds.BitsStored - 1
    ds.PixelRepresentation = int(signed)
    ds.RescaleSlope = str(slope)
    ds.RescaleIntercept = str(intercept)
    ds.LossyImageCompression = "00"
    byteorder = ">" if ts == ExplicitVRBigEndian else "<"
    dtype = byteorder + ("i" if signed else "u") + str(bits // 8)
    encoded = np.asarray(values, dtype=dtype)
    if ds.BitsStored < bits:
        # Stored signed values use BitsStored two's-complement. Unused high
        # bits are zero here, deliberately exposing incorrect i16-container
        # interpretation instead of relying on accidental sign extension.
        encoded = (encoded.astype(np.int64) & ((1 << ds.BitsStored) - 1)).astype(byteorder + "u" + str(bits // 8))
    if planar == 1 and ds.SamplesPerPixel == 3:
        encoded = np.moveaxis(encoded, -1, -3)
    ds.PixelData = encoded.tobytes()
    ds["PixelData"].VR = "OB" if bits == 8 else "OW"
    return ds


def generate(work_dir: Path) -> list[dict]:
    fixture_dir = work_dir / "synthetic"
    golden_dir = work_dir / "golden"
    fixture_dir.mkdir(parents=True, exist_ok=True)
    golden_dir.mkdir(parents=True, exist_ok=True)
    cases = []

    def add(label, ds, expected, basis, *, condition="native", malformed=None, encoder="none"):
        ds = copy.deepcopy(ds)
        ds.SOPInstanceUID = deterministic_uid(label)
        ds.file_meta.MediaStorageSOPInstanceUID = ds.SOPInstanceUID
        path = fixture_dir / (label + ".dcm")
        # Pixel bytes above already use the declared byte order. dcmwrite permits
        # explicit BE serialization without save_as's dataset-conversion guard.
        pydicom.dcmwrite(path, ds, enforce_file_format=True)
        reread = pydicom.dcmread(path)
        entry = {
            "fixture_id": "synth-" + label, "kind": "synthetic", "source": "P0-CODEC-REF explicit arrays",
            "license": "project-generated; no patient content", "sha256": sha256(path),
            **metadata(reread), "condition": condition,
            "expected": "reject" if malformed else "all-pixel-exact",
            "malformed_reason": malformed, "golden_basis": basis,
            "encoder": encoder, "generator_versions": versions(),
            "spatial_dimension": "none", "time_dimension": "ordered synthetic frames; no acquisition time",
            "test_ids": ["T-03", "T-04"] + (["T-05"] if int(ds.SamplesPerPixel) > 1 else []),
            "re_read_tags_match": metadata(ds) == metadata(reread),
        }
        expected = np.asarray(expected, dtype=np.float64)
        modality = expected * float(ds.RescaleSlope) + float(ds.RescaleIntercept)
        save_f64(golden_dir / (label + ".stored.f64le"), expected)
        save_f64(golden_dir / (label + ".modality.f64le"), modality)
        # Private fields never enter the report, and golden cannot be overwritten by product output.
        entry.update(_path=path, _expected=expected, _modality=modality)
        cases.append(entry)

    u8 = np.array([[0, 1, 127, 128], [129, 200, 254, 255]], dtype=np.uint8)
    s8 = np.array([[-128, -127, -1, 0], [1, 63, 126, 127]], dtype=np.int8)
    u12 = np.array([[0, 1, 24, 1024], [2024, 2047, 2048, 4095]], dtype=np.uint16)
    s12 = np.array([[-2048, -1024, -1, 0], [1, 24, 1024, 2047]], dtype=np.int16)
    s16 = np.array([[-32768, -2048, -1, 0], [1, 1024, 16384, 32767]], dtype=np.int16)
    u16 = np.array([[0, 1, 255, 256], [1024, 32767, 32768, 65535]], dtype=np.uint16)
    for name, arr, bits, stored, signed in (
        ("u8", u8, 8, 8, False), ("s8", s8, 8, 8, True),
        ("u12", u12, 16, 12, False), ("s12", s12, 16, 12, True),
        ("u16", u16, 16, 16, False), ("s16", s16, 16, 16, True),
    ):
        for ts_name, ts in (("explicit-le", ExplicitVRLittleEndian), ("implicit-le", ImplicitVRLittleEndian),
                            ("explicit-be", ExplicitVRBigEndian), ("deflate", DeflatedExplicitVRLittleEndian)):
            label = name + "-" + ts_name
            ds = dataset(label, arr, bits=bits, stored=stored, signed=signed, ts=ts,
                         slope=2.5, intercept=-1024.5)
            add(label, ds, arr, "literal integer array; modality = stored*2.5-1024.5")

    padding = np.array([[0, 24, 1024, 2024]], dtype=np.uint16)
    ds = dataset("padding", padding, slope=1, intercept=-1024)
    ds.PixelPaddingValue = 0
    add("padding", ds, padding, "docs06 literal [0,24,1024,2024]; modality [-1024,-1000,0,1000]; padding retained here")
    ds = dataset("u12-unused-high-bits", u12, stored=12, slope=2.5, intercept=-1024.5)
    ds.PixelData = (u12 | 0xF000).astype("<u2").tobytes()
    add("u12-unused-high-bits", ds, u12, "literal u12 array; bits12..15 contain ones and must be ignored")
    ds = dataset("bad-native-pixel-length", u16)
    ds.PixelData = ds.PixelData[:-2]
    add("bad-native-pixel-length", ds, u16, "literal u16 array", malformed="payload is one 16bit sample short", condition="malformed native length")
    ds = dataset("declared-output-over-limit", u16)
    ds.Rows = 65535
    ds.Columns = 65535
    add("declared-output-over-limit", ds, u16, "declared 65535*65535*16bit output over 8GiB; tiny payload",
        malformed="declared output exceeds experiment resource bound (also payload length inconsistent)", condition="resource bound", )
    ds = dataset("bad-bits-stored", u16)
    ds.BitsStored = 32
    ds.HighBit = 31
    add("bad-bits-stored", ds, u16, "16bit container cannot contain 32 stored bits; reference decode intentionally not executed",
        malformed="BitsStored=32 exceeds BitsAllocated=16", condition="malformed bit metadata")
    rgb = np.array([[[255, 0, 0], [0, 255, 0], [0, 0, 255]], [[0, 0, 0], [255, 255, 255], [12, 34, 56]]], dtype=np.uint8)
    for planar in (0, 1):
        add(f"rgb-planar{planar}", dataset("rgb", rgb, bits=8, photometric="RGB", planar=planar),
            rgb, "literal RGB patches; expected row-major interleaved regardless disk planar layout")
    ybr = np.array([[[0, 128, 128], [255, 128, 128], [76, 85, 255]], [[150, 44, 21], [29, 255, 107], [128, 128, 128]]], dtype=np.uint8)
    add("ybr-full", dataset("ybr", ybr, bits=8, photometric="YBR_FULL"), ybr,
        "literal YBR_FULL patches; stored domain stays YBR (RGB is separately normalized in runner)")

    # 32x32 is the small valid size required by the reference JPEG 2000 encoder.
    multi = np.fromfunction(lambda f, r, c: (f * 1009 + r * 97 + c * 17) % 4096,
                            (3, 32, 32), dtype=int).astype(np.uint16)
    basis = "independent formula: sample[f,r,c]=(1009*f+97*r+17*c)%4096; modality=stored*2.5-1024.5"
    codecs = (("rle", RLELossless, "pydicom"), ("jls", JPEGLSLossless, "pyjpegls"),
              ("j2k", JPEG2000Lossless, "pylibjpeg"))
    for codec, ts, plugin in codecs:
        ds = dataset(codec, multi, stored=12, slope=2.5, intercept=-1024.5)
        encoder = get_encoder(ts)
        frames = [encoder.encode(ds, index=i, encoding_plugin=plugin) for i in range(3)]
        ds.file_meta.TransferSyntaxUID = ts
        ds["PixelData"].VR = "OB"
        ds["PixelData"].is_undefined_length = True
        variants = [("bot", encapsulate(frames)), ("empty-bot", encapsulate(frames, has_bot=False))]
        if codec != "rle":
            variants += [("multifragment-bot", encapsulate(frames, fragments_per_frame=3)),
                         ("multifragment-empty-bot", encapsulate(frames, fragments_per_frame=3, has_bot=False))]
        eot_data, eot, lengths = encapsulate_extended(frames)
        for variant, pixel_data in variants:
            candidate = copy.deepcopy(ds)
            candidate.PixelData = pixel_data
            add(codec + "-" + variant, candidate, multi, basis, condition=variant,
                encoder=f"pydicom {pydicom.__version__} / {plugin}; explicit arrays are golden")
        candidate = copy.deepcopy(ds)
        candidate.PixelData = eot_data
        candidate.ExtendedOffsetTable = eot
        candidate.ExtendedOffsetTableLengths = lengths
        add(codec + "-eot", candidate, multi, basis, condition="empty BOT + EOT; one fragment/frame", encoder=plugin)

        # These are boundary rejection cases, not reference decoder success cases.
        if codec == "jls":
            bad = copy.deepcopy(ds)
            pixel = bytearray(encapsulate(frames))
            struct.pack_into("<I", pixel, 12, 0xFFFFFF00)
            bad.PixelData = bytes(pixel)
            add("bad-bot-offset", bad, multi, basis, malformed="BOT offset outside item stream", condition="malformed BOT")
            bad = copy.deepcopy(ds)
            bad.PixelData = encapsulate(frames)
            bad.NumberOfFrames = 2
            add("bad-frame-count", bad, multi[:2], basis, malformed="3 codestream frames versus declared 2", condition="malformed NumberOfFrames")
            bad = copy.deepcopy(ds)
            bad.PixelData = encapsulate(frames, fragments_per_frame=3, has_bot=False)
            bad.NumberOfFrames = 4
            add("ambiguous-empty-bot", bad, multi, basis, malformed="9 fragments with 3 EOI markers but declared 4 frames", condition="ambiguous empty BOT")
            bad = copy.deepcopy(candidate)
            bad.ExtendedOffsetTable = struct.pack("<QQQ", 0, 1, 2)
            add("bad-eot-offset", bad, multi, basis, malformed="EOT offsets point inside items", condition="malformed EOT")
            bad = copy.deepcopy(candidate)
            bad.ExtendedOffsetTableLengths = struct.pack("<QQQ", 1, 1, 1)
            add("bad-eot-length", bad, multi, basis, malformed="EOT lengths disagree with compressed frame sizes", condition="malformed EOT")

    # Validate generated good fixtures with a decoder as an additional readback check.
    # This round-trip is explicitly NOT the external codec compatibility evidence.
    for case in cases:
        if case["malformed_reason"]:
            case["generation_readback"] = "not-applicable: intentionally malformed"
            continue
        try:
            # Full dcmread first also handles Deflated Explicit VR LE; the
            # pydicom 3.0.2 path-optimized pixel_array parser cannot read it.
            actual = pixel_array(pydicom.dcmread(case["_path"]), raw=True)
            case["generation_readback"] = "pass" if np.array_equal(actual, case["_expected"]) else "fail"
        except Exception as error:
            case["generation_readback"] = "not-run:" + type(error).__name__
    return cases


def public_entry(case: dict) -> dict:
    return {key: value for key, value in case.items() if not key.startswith("_")}
