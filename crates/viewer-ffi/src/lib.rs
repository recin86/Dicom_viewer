//! Product boundary. PIXEL-1 is a bounded native-frame contract, not UI readiness.

mod pixels;
pub use pixels::*;

uniffi::setup_scaffolding!();

/// BOOTSTRAP-1 identity and readiness, not a DICOM codec support declaration.
#[derive(uniffi::Record)]
pub struct BootstrapInfo {
    pub api_revision: u32,
    pub core_version: String,
    pub dicom_rs_version: String,
    pub frame_decode_implemented: bool,
}

/// A short synchronous call with no file I/O, decoding, or patient metadata.
#[uniffi::export]
pub fn bootstrap_info() -> BootstrapInfo {
    let info = viewer_core::build_info();
    BootstrapInfo {
        api_revision: 1,
        core_version: info.core_version.into(),
        dicom_rs_version: info.dicom_rs_version.into(),
        frame_decode_implemented: info.frame_decode_implemented,
    }
}
