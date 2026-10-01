//! P1 foundation for the Rust DICOM core.
//!
//! A limited native adapter prepares immutable pixel buffers and display
//! descriptors. The general decoder and measurement path are not implemented.
//! Pinned dependencies do not establish DICOM support.

pub mod display;
pub mod frame;
pub mod native;
mod native_color;

/// Build identity and implementation readiness for the bootstrap connection.
///
/// This record is not a per-file or per-codec capability assessment.
pub struct BuildInfo {
    /// Version of the product core crate built into the application.
    pub core_version: &'static str,
    /// Pinned dicom-rs baseline; this is not a decoder support result.
    pub dicom_rs_version: &'static str,
    /// Whether the product is ready for general UI frame decoding.
    ///
    /// This legacy bootstrap flag is unchanged; native display readiness is
    /// provided by the separate display contract rather than this global flag.
    pub frame_decode_implemented: bool,
}

/// Returns build information without reading DICOM files or patient metadata.
pub fn build_info() -> BuildInfo {
    BuildInfo {
        core_version: env!("CARGO_PKG_VERSION"),
        dicom_rs_version: "0.10.0",
        frame_decode_implemented: false,
    }
}
