//! DISPLAY-1 metadata and bounded CPU reference for native frames.
use crate::{PixelError, PixelHandle};
use viewer_core::display as core;

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum VoiFunction {
    Linear,
    LinearExact,
    Sigmoid,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct VoiWindow {
    pub center: f64,
    pub width: f64,
    pub function: VoiFunction,
}
impl From<core::VoiWindow> for VoiWindow {
    fn from(window: core::VoiWindow) -> Self {
        Self {
            center: window.center,
            width: window.width,
            function: match window.function {
                core::VoiFunction::Linear => VoiFunction::Linear,
                core::VoiFunction::LinearExact => VoiFunction::LinearExact,
                core::VoiFunction::Sigmoid => VoiFunction::Sigmoid,
            },
        }
    }
}
impl From<VoiWindow> for core::VoiWindow {
    fn from(window: VoiWindow) -> Self {
        Self {
            center: window.center,
            width: window.width,
            function: match window.function {
                VoiFunction::Linear => core::VoiFunction::Linear,
                VoiFunction::LinearExact => core::VoiFunction::LinearExact,
                VoiFunction::Sigmoid => core::VoiFunction::Sigmoid,
            },
        }
    }
}

#[derive(uniffi::Record)]
pub struct DisplayInfo {
    pub descriptor_revision: u32,
    pub source_revision: String,
    pub frame_index: u32,
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

/// Narrow backend availability; BOOTSTRAP-1 readiness remains independent.
#[uniffi::export]
pub fn native_display_available() -> bool {
    true
}

#[uniffi::export]
impl PixelHandle {
    pub fn display_info(&self) -> Result<DisplayInfo, PixelError> {
        let display = self
            .registered
            .display
            .as_ref()
            .ok_or(PixelError::Unsupported {
                reason: "Display descriptor is unavailable".into(),
            })?;
        Ok(DisplayInfo {
            descriptor_revision: 1,
            source_revision: self.registered.source_revision.clone(),
            frame_index: 0,
            windows: display.windows.iter().cloned().map(Into::into).collect(),
            default_window: display.default_window.clone().map(Into::into),
            automatic_window: display.automatic_window,
            inverted: display.inverted,
            pixel_height_over_width: display.pixel_height_over_width,
            aspect_source: display.aspect_source.clone(),
            aspect_estimated: display.aspect_estimated,
            unit: display.unit.clone(),
            diagnostics: display.diagnostics.clone(),
            can_window: display.can_window,
        })
    }

    /// Test-only CPU reference, limited to 16,384 pixels / 64 KiB. Product display
    /// uses the copy-only pixel contract; this never returns a large frame.
    pub fn reference_rgba(
        &self,
        window: Option<VoiWindow>,
        user_invert: bool,
    ) -> Result<Vec<u8>, PixelError> {
        let display = self
            .registered
            .display
            .as_ref()
            .ok_or(PixelError::Unsupported {
                reason: "Display descriptor is unavailable".into(),
            })?;
        Ok(core::reference_rgba(
            &self.registered.frame,
            display,
            window.map(Into::into),
            user_invert,
        )?)
    }
}
