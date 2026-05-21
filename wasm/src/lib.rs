use wasm_bindgen::prelude::*;

// Export all core math functions for JavaScript
#[wasm_bindgen]
pub fn si_eisenstein_norm(a: i32, b: i32) -> i64 {
    (a as i64 * a as i64 - a as i64 * b as i64 + b as i64 * b as i64)
}

#[wasm_bindgen]
pub fn si_laman_edges(v: i32) -> i32 {
    2 * v - 3
}

#[wasm_bindgen]
pub fn si_is_rigid(v: i32, e: i32) -> bool {
    e >= 2 * v - 3
}

#[wasm_bindgen]
pub fn si_deadband_filter(val: f64, center: f64, band: f64) -> f64 {
    if (val - center).abs() > band { val } else { center }
}

#[wasm_bindgen]
pub fn si_manhattan_distance(a: &[i32], b: &[i32]) -> i64 {
    a.iter().zip(b.iter()).map(|(x, y)| (x - y).abs() as i64).sum()
}

#[wasm_bindgen]
pub fn si_pythagorean48_encode(x: f64, y: f64) -> u8 {
    // Quantize direction to one of 48
    let angle = y.atan2(x);
    let sector = ((angle + std::f64::consts::PI) / (2.0 * std::f64::consts::PI) * 48.0) as u8;
    sector.min(47)
}
