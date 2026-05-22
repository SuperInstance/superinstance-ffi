#![allow(clippy::not_unsafe_ptr_arg_deref)]
mod eisenstein;
mod laman;
mod holonomy;
mod encoding;
mod constraint;
mod spline;

// Re-export all FFI functions at crate root
pub use eisenstein::si_eisenstein_norm;
pub use laman::{si_laman_edges, si_is_rigid};
pub use holonomy::si_holonomy_check;
pub use encoding::{si_pythagorean48_encode, si_manhattan_distance, si_cascade_match};
pub use constraint::si_constraint_check;
pub use spline::{si_spline_interpolate, si_deadband_filter};
