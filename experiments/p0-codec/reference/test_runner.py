"""Runner trust-boundary checks. No product decoder serves as golden."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

import pydicom

from common import functional_group_transform_presence, metadata, modality_tolerance, save_f64
from fixtures import dataset
from pydicom.dataset import Dataset, FileMetaDataset
from run import enforce_source_invariants, invoke, negative_result, rejection_check, test_case


class RunnerTrustTests(unittest.TestCase):
    def test_unrelated_errors_cannot_pass_malformed_rejection(self):
        for kind in ("unsupported_transfer_syntax", "output_io", "input_io", "panic"):
            self.assertNotEqual(rejection_check({"status": "error", "stage": "whole_decode", "error_kind": kind})["status"], "pass")

    def test_missing_metadata_rejection_needs_independent_bit_evidence_and_metadata_stage(self):
        for stage in ("metadata", "whole_decode", "runner"):
            for invalid_bits in (False, True):
                rust = {"status": "error", "stage": stage, "error_kind": "missing_pixel_metadata"}
                result = rejection_check(rust, independently_invalid_bit_metadata=invalid_bits)
                self.assertEqual(result["status"] == "pass", stage == "metadata" and invalid_bits)

    def test_modality_policy_covers_all_values_scales_and_decoder_allowance(self):
        # The negative extreme drives the relative bound; small/zero arrays use
        # the absolute floor. Decoder allowance applies equally to slope signs.
        for values, arithmetic in ((np.array([0, -1, 100]), 1e-6),
                                   (np.array([10, -2e9, 1e6]), 2.0),
                                   (np.array([]), 1e-6)):
            for tolerance in (0.0, 1.0, 2.0):
                for slope in (-3.5, 0.0, 3.5):
                    actual = modality_tolerance(values, tolerance, slope)
                    self.assertEqual(actual["arithmetic_allowance"], arithmetic)
                    self.assertEqual(actual["decoder_allowance"], tolerance * abs(slope))
                    self.assertEqual(actual["total_allowance"], arithmetic + tolerance * abs(slope))

    def test_functional_group_modality_unavailable_keeps_stored_and_frame_failures(self):
        values = np.array([[[10, 20]], [[30, 40]]], dtype=np.uint16)
        for group_name in ("SharedFunctionalGroupsSequence", "PerFrameFunctionalGroupsSequence"):
            ds = dataset("functional-group-trust-test", values)
            transform = Dataset()
            transform.RescaleSlope = 2
            transform.RescaleIntercept = -1024
            group = Dataset()
            group.PixelValueTransformationSequence = [transform]
            setattr(ds, group_name, [group])
            presence = functional_group_transform_presence(ds)
            self.assertEqual(presence, {"shared": group_name.startswith("Shared"), "per_frame": group_name.startswith("PerFrame")})
            with tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                source = root / "fixture.dcm"
                pydicom.dcmwrite(source, ds, enforce_file_format=True)
                case = {"fixture_id": "test-functional-group", "kind": "public-local-only", "_path": source,
                        "part10": True, "pixel_data_present": True, **metadata(ds)}
                for corrupt_stored in (False, True):
                    def probe(binary, path, prefix, frame=None):
                        prefix.parent.mkdir(parents=True, exist_ok=True)
                        if frame is None:
                            stored = values.copy()
                            if corrupt_stored:
                                stored[0, 0, 0] = 255
                            save_f64(Path(str(prefix) + ".stored.f64le"), stored)
                            save_f64(Path(str(prefix) + ".modality.f64le"), values * 2 - 1024)
                            for index in range(2):
                                save_f64(Path(str(prefix) + f".frame-{index}.f64le"), values[index])
                        else:
                            save_f64(Path(str(prefix) + f".frame-{frame}.f64le"), values[frame])
                        return {"status": "ok", "decoded_photometric": "MONOCHROME2", **metadata(ds)}

                    with patch("run.invoke", side_effect=probe), patch("run.apply_modality_lut", side_effect=AssertionError("top-level oracle must not run for FG")):
                        result = test_case(case, root / "stub", root / "output")
                    self.assertEqual(result["modality"]["status"], "not-run")
                    self.assertEqual(len(result["metadata_checks"]), 9)
                    self.assertEqual(len(result["frame_checks"]), 4)
                    self.assertTrue(all(item["check"]["status"] == "pass" for item in result["frame_checks"]))
                    self.assertEqual(result["stored"]["status"], "fail" if corrupt_stored else "pass")
                    self.assertEqual(result["status"], "fail" if corrupt_stored else "not-run")

    def test_source_change_fails_every_early_status(self):
        for status in ("pass", "not-run", "not-applicable"):
            result = {"status": status, "hash_before": "old", "hash_after": "changed"}
            self.assertEqual(enforce_source_invariants(result, {})["status"], "fail")
        result = {"status": "pass", "hash_before": "same", "hash_after": "same"}
        self.assertEqual(enforce_source_invariants(result, {"inventory_hash_matches": False})["status"], "fail")

    def test_rerun_replaces_only_own_cache_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            binary = root / "stub"
            binary.write_text("#!/bin/sh\npython3 -c 'import json,sys; open(sys.argv[1]+\".stored.f64le\",\"xb\").write(bytes(8)); print(json.dumps({\"status\":\"ok\"}))' \"$2\"\n")
            binary.chmod(0o700)
            prefix = root / "fixture"
            stale = root / "fixture.stored.f64le"
            stale.write_bytes(b"oldold!!")
            untouched = root / "other.stored.f64le"
            untouched.write_bytes(b"golden!!")
            for _ in range(2):
                self.assertEqual(invoke(binary, root / "source", prefix)["status"], "ok")
                self.assertEqual(stale.read_bytes(), bytes(8))
                self.assertEqual(untouched.read_bytes(), b"golden!!")

    def test_whole_error_cannot_hide_selected_frame_acceptance(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "source"
            source.write_bytes(b"synthetic source")
            binary = root / "stub"
            binary.write_text('#!/bin/sh\necho \'{"status":"ok"}\'\n')
            binary.chmod(0o700)
            whole = {"status": "error", "stage": "whole_decode", "error_kind": "unexpected_decoded_length"}
            result = negative_result({"fixture_id": "test", "frames": 2, "malformed_reason": "count mismatch"}, {}, whole, binary, source, root)
            self.assertEqual(result["rejection_checks"][0]["check"]["status"], "pass")
            self.assertEqual(result["status"], "fail")

    def test_arbitrary_metadata_text_is_not_serialized(self):
        ds = Dataset()
        ds.file_meta = FileMetaDataset()
        ds.file_meta.TransferSyntaxUID = "patient-secret"
        ds.SOPClassUID = "patient-secret"
        ds.Modality = "SECRET"
        ds.PhotometricInterpretation = "patient-secret"
        ds.RescaleSlope = None
        ds.RescaleIntercept = None
        result = json.dumps(metadata(ds))
        self.assertNotIn("patient-secret", result)
        self.assertNotIn("SECRET", result)


if __name__ == "__main__":
    unittest.main()
