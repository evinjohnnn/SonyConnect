//! Model profiles and capability status.
//!
//! Every claim is tagged. Only entries with `VerifiedOnHardware` have been
//! exercised against a real headphone by this project; everything else is
//! either implemented-and-unit-tested against the protocol tables or entirely
//! unknown. The UI must not render unknown capability as if it worked.

use crate::protocol::ncasma_type;

/// How much we actually know about a model.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Confidence {
    /// Exercised against this project on real hardware.
    VerifiedOnHardware,
    /// Code path exists and is covered by deterministic tests.
    ImplementedAndUnitTested,
    /// Model appears in upstream projects but is untested here.
    SupportedUpstreamOnly,
    Partial,
    Unsupported,
}

/// One controllable feature family for a model.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Capability {
    pub battery: Confidence,
    pub noise_control: Confidence,
    pub equalizer: Confidence,
    /// `NcAsmInquiredType` the model is expected to speak, when known.
    pub ncasma_type: Option<u8>,
}

/// A model profile.
#[derive(Debug, Clone)]
pub struct Model {
    /// Sony marketing name.
    pub name: String,
    /// Bluetooth product id observed in SDP/OS data where available.
    pub product_id: Option<u16>,
    pub capabilities: Capability,
    /// Free-form caveats surfaced verbatim in the device inspector.
    pub notes: &'static str,
}

const fn cap(
    battery: Confidence,
    noise_control: Confidence,
    equalizer: Confidence,
    ncasma_type: Option<u8>,
) -> Capability {
    Capability { battery, noise_control, equalizer, ncasma_type }
}

/// Built-in profiles.
///
/// Only `WH-1000XM6` is treated as a first-class target: it is the unit paired
/// to the development host. Its capability flags are promoted to
/// `VerifiedOnHardware` only after the live harness passes.
pub fn builtin_models() -> Vec<Model> {
    use Confidence::*;
    vec![
        Model {
            name: "WH-1000XM6".into(),
            product_id: Some(0x0F8A),
            capabilities: cap(
                ImplementedAndUnitTested,
                ImplementedAndUnitTested,
                SupportedUpstreamOnly,
                Some(ncasma_type::MODE_NC_ASM_DUAL_NC_MODE_SWITCH_AND_ASM_SEAMLESS),
            ),
            notes: "Primary development target. Protocol V2 table 1.",
        },
        Model {
            name: "WH-1000XM5".into(),
            product_id: None,
            capabilities: cap(SupportedUpstreamOnly, SupportedUpstreamOnly, Partial, None),
            notes: "Present in upstream projects; unverified here.",
        },
        Model {
            name: "WF-1000XM5".into(),
            product_id: None,
            capabilities: cap(Partial, Partial, Partial, None),
            notes: "Buds: battery shape is left/right, not single. Unverified here.",
        },
    ]
}

/// Look up a profile by Sony product id.
pub fn by_product_id(id: u16) -> Option<Model> {
    builtin_models().into_iter().find(|m| m.product_id == Some(id))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xm6_profile_exists_and_is_honest() {
        let m = by_product_id(0x0F8A).expect("XM6 profile");
        assert_eq!(m.name, "WH-1000XM6");
        assert_ne!(
            m.capabilities.noise_control,
            Confidence::VerifiedOnHardware,
            "must not claim hardware verification before the live harness runs"
        );
    }

    #[test]
    fn unknown_product_is_none() {
        assert!(by_product_id(0x1234).is_none());
    }
}
