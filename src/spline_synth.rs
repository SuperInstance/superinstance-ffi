//! Spline Wavetable Synthesizer — Eisenstein lattice control points for audio.
//!
//! Reconstructs wavetables from a handful of control points via IDW² interpolation
//! on a hexagonal (Eisenstein) lattice. No external dependencies.

/// A control point on the Eisenstein lattice.
#[derive(Debug, Clone, Copy)]
pub struct ControlPoint {
    pub x: f64,
    pub y: f64,
    pub value: f64,
}

/// Spline wavetable synthesizer using Eisenstein lattice control points.
///
/// Stores K control points instead of N waveform samples, achieving
/// compression ratios of ~128× (16 control points for a 2048-sample wavetable).
#[derive(Debug, Clone)]
pub struct SplineWavetable {
    control_points: Vec<ControlPoint>,
    table: Vec<f64>,
    table_size: usize,
    interp_matrix: Vec<f64>, // table_size × n_points, row-major
}

const SQRT3_HALF: f64 = 0.86602540378443864676;
const PI: f64 = std::f64::consts::PI;

impl SplineWavetable {
    /// Create a new wavetable with the given size and number of control points.
    pub fn new(table_size: usize, n_control_points: usize) -> Self {
        assert!(table_size >= 4, "table_size must be >= 4");
        assert!(n_control_points >= 2, "need >= 2 control points");

        let control_points = build_lattice(n_control_points);
        let interp_matrix = build_interp_matrix(&control_points, table_size);
        let table = vec![0.0; table_size];

        SplineWavetable {
            control_points,
            table,
            table_size,
            interp_matrix,
        }
    }

    /// Number of control points.
    pub fn n_points(&self) -> usize {
        self.control_points.len()
    }

    /// Table size.
    pub fn table_size(&self) -> usize {
        self.table_size
    }

    /// Get the reconstructed wavetable.
    pub fn table(&self) -> &[f64] {
        &self.table
    }

    /// Get the control points.
    pub fn control_points(&self) -> &[ControlPoint] {
        &self.control_points
    }

    /// Set control point values directly.
    pub fn set_values(&mut self, values: &[f64]) {
        assert_eq!(values.len(), self.control_points.len());
        for (i, &v) in values.iter().enumerate() {
            self.control_points[i].value = v;
        }
    }

    /// Reconstruct the full wavetable from control points via IDW² interpolation.
    pub fn reconstruct(&mut self) {
        let n_pts = self.control_points.len();
        for i in 0..self.table_size {
            let mut s = 0.0;
            for j in 0..n_pts {
                s += self.interp_matrix[i * n_pts + j] * self.control_points[j].value;
            }
            self.table[i] = s;
        }
    }

    /// Sample the wavetable at phase ∈ [0, 1) with linear interpolation.
    pub fn sample(&self, phase: f64) -> f64 {
        let pos = phase * self.table_size as f64;
        let idx = pos as usize % self.table_size;
        let frac = pos - pos.floor();
        let idx_next = (idx + 1) % self.table_size;
        self.table[idx] * (1.0 - frac) + self.table[idx_next] * frac
    }

    /// Morph between two wavetables' control points at parameter t.
    /// t=0 → pure a, t=1 → pure b.
    pub fn morph(a: &Self, b: &Self, t: f64) -> Self {
        assert_eq!(a.table_size, b.table_size);
        let n = a.control_points.len().min(b.control_points.len());
        let mut out = Self::new(a.table_size, a.control_points.len());
        for i in 0..n {
            out.control_points[i].value =
                (1.0 - t) * a.control_points[i].value + t * b.control_points[i].value;
        }
        out.reconstruct();
        out
    }

    /// Preset: sine wave.
    pub fn preset_sine(table_size: usize, n_cp: usize) -> Self {
        let mut swt = Self::new(table_size, n_cp);
        let target: Vec<f64> = (0..table_size)
            .map(|i| (2.0 * PI * i as f64 / table_size as f64).sin())
            .collect();
        fit_preset(&mut swt, &target);
        swt
    }

    /// Preset: sawtooth wave.
    pub fn preset_saw(table_size: usize, n_cp: usize) -> Self {
        let mut swt = Self::new(table_size, n_cp);
        let target: Vec<f64> = (0..table_size)
            .map(|i| 2.0 * i as f64 / table_size as f64 - 1.0)
            .collect();
        fit_preset(&mut swt, &target);
        swt
    }

    /// Preset: square wave.
    pub fn preset_square(table_size: usize, n_cp: usize) -> Self {
        let mut swt = Self::new(table_size, n_cp);
        let target: Vec<f64> = (0..table_size)
            .map(|i| if (i as f64 / table_size as f64) < 0.5 { 1.0 } else { -1.0 })
            .collect();
        fit_preset(&mut swt, &target);
        swt
    }

    /// Preset: triangle wave.
    pub fn preset_triangle(table_size: usize, n_cp: usize) -> Self {
        let mut swt = Self::new(table_size, n_cp);
        let target: Vec<f64> = (0..table_size)
            .map(|i| {
                let t = i as f64 / table_size as f64;
                4.0 * (t - 0.5).abs() - 1.0
            })
            .collect();
        fit_preset(&mut swt, &target);
        swt
    }

    /// Render audio at the given frequency, duration, and sample rate.
    pub fn render(&self, frequency: f64, duration: f64, sample_rate: usize) -> Vec<f64> {
        let n_samples = (sample_rate as f64 * duration) as usize;
        let mut output = vec![0.0; n_samples];
        let phase_inc = frequency * self.table_size as f64 / sample_rate as f64;
        let mut phase: f64 = 0.0;

        for i in 0..n_samples {
            let idx = phase as usize % self.table_size;
            let frac = phase - phase.floor();
            let idx_next = (idx + 1) % self.table_size;
            output[i] = self.table[idx] * (1.0 - frac) + self.table[idx_next] * frac;
            phase += phase_inc;
        }
        output
    }

    /// Compression ratio: table_size / n_control_points.
    pub fn compression_ratio(&self) -> f64 {
        self.table_size as f64 / self.control_points.len() as f64
    }

    /// RMSE between reconstructed table and a target waveform.
    pub fn reconstruction_error(&self, target: &[f64]) -> f64 {
        let n = self.table_size.min(target.len());
        let sum: f64 = (0..n).map(|i| (self.table[i] - target[i]).powi(2)).sum();
        (sum / n as f64).sqrt()
    }
}

// ---- Internal helpers ----

fn build_lattice(n: usize) -> Vec<ControlPoint> {
    let r = ((n as f64 / 3.0).sqrt().ceil() as usize) + 2;
    let r = r.max(3);

    let mut cands: Vec<(f64, f64, f64)> = Vec::with_capacity((2 * r + 1).pow(2));
    for a in -(r as i32)..=(r as i32) {
        for b in -(r as i32)..=(r as i32) {
            let x = a as f64 - b as f64 * 0.5;
            let y = b as f64 * SQRT3_HALF;
            let d = x * x + y * y;
            cands.push((x, y, d));
        }
    }
    cands.sort_by(|a, b| {
        let da = (a.2 * 1e9).round() as i64;
        let db = (b.2 * 1e9).round() as i64;
        da.cmp(&db).then(a.0.partial_cmp(&b.0).unwrap()).then(a.1.partial_cmp(&b.1).unwrap())
    });

    let max_dist: f64 = (0..n.min(cands.len()))
        .map(|i| cands[i].2.sqrt())
        .fold(0.0_f64, f64::max)
        .max(1e-12);

    (0..n.min(cands.len()))
        .map(|i| ControlPoint {
            x: cands[i].0 / max_dist,
            y: cands[i].1 / max_dist,
            value: 0.0,
        })
        .collect()
}

fn build_interp_matrix(pts: &[ControlPoint], table_size: usize) -> Vec<f64> {
    let n_pts = pts.len();
    let eps = 1e-6;
    let mut mat = vec![0.0; table_size * n_pts];

    for i in 0..table_size {
        let qx = -1.0 + 2.0 * i as f64 / table_size as f64;
        let mut sum = 0.0;
        let mut weights = vec![0.0; n_pts];

        for j in 0..n_pts {
            let dx = qx - pts[j].x;
            let dy = 0.0 - pts[j].y; // query y = 0
            let d2 = dx * dx + dy * dy;
            weights[j] = 1.0 / (d2 + eps);
            sum += weights[j];
        }
        for j in 0..n_pts {
            mat[i * n_pts + j] = weights[j] / sum;
        }
    }
    mat
}

/// Least-squares solve: (A^T A + λI) x = A^T y via Gauss-Jordan.
fn lstsq(a: &[f64], y: &[f64], rows: usize, cols: usize, lambda: f64) -> Vec<f64> {
    // Build ATA = A^T A + λI
    let mut ata = vec![0.0; cols * cols];
    let mut aty = vec![0.0; cols];

    for i in 0..cols {
        for j in 0..cols {
            let mut s = 0.0;
            for k in 0..rows {
                s += a[k * cols + i] * a[k * cols + j];
            }
            ata[i * cols + j] = s;
        }
        ata[i * cols + i] += lambda;
        let mut s = 0.0;
        for k in 0..rows {
            s += a[k * cols + i] * y[k];
        }
        aty[i] = s;
    }

    // Gauss-Jordan
    for col in 0..cols {
        // Find pivot
        let mut max_row = col;
        let mut max_val = ata[col * cols + col].abs();
        for row in (col + 1)..cols {
            let v = ata[row * cols + col].abs();
            if v > max_val {
                max_val = v;
                max_row = row;
            }
        }
        // Swap rows
        if max_row != col {
            for j in 0..cols {
                ata.swap(col * cols + j, max_row * cols + j);
            }
            aty.swap(col, max_row);
        }
        let pivot = ata[col * cols + col];
        let pivot = if pivot.abs() < 1e-15 { 1e-15 } else { pivot };
        for j in 0..cols {
            ata[col * cols + j] /= pivot;
        }
        aty[col] /= pivot;
        for row in 0..cols {
            if row == col {
                continue;
            }
            let factor = ata[row * cols + col];
            for j in 0..cols {
                ata[row * cols + j] -= factor * ata[col * cols + j];
            }
            aty[row] -= factor * aty[col];
        }
    }
    aty
}

fn fit_preset(swt: &mut SplineWavetable, target: &[f64]) {
    let n_pts = swt.n_points();
    let values = lstsq(&swt.interp_matrix, target, swt.table_size, n_pts, 1e-4);
    swt.set_values(&values);
    swt.reconstruct();
}

// ---- FFI exports ----

#[no_mangle]
pub extern "C" fn si_spline_wavetable_init(table_size: usize, n_cp: usize) -> *mut SplineWavetable {
    let swt = Box::new(SplineWavetable::new(table_size, n_cp));
    Box::into_raw(swt)
}

#[no_mangle]
pub unsafe extern "C" fn si_spline_wavetable_free(swt: *mut SplineWavetable) {
    if !swt.is_null() {
        drop(Box::from_raw(swt));
    }
}

#[no_mangle]
pub unsafe extern "C" fn si_spline_wavetable_reconstruct(swt: *mut SplineWavetable) {
    (*swt).reconstruct();
}

#[no_mangle]
pub unsafe extern "C" fn si_spline_wavetable_sample(swt: *const SplineWavetable, phase: f64) -> f64 {
    (*swt).sample(phase)
}

#[no_mangle]
pub unsafe extern "C" fn si_spline_wavetable_preset_sine(table_size: usize, n_cp: usize) -> *mut SplineWavetable {
    let swt = Box::new(SplineWavetable::preset_sine(table_size, n_cp));
    Box::into_raw(swt)
}

#[no_mangle]
pub unsafe extern "C" fn si_spline_wavetable_preset_saw(table_size: usize, n_cp: usize) -> *mut SplineWavetable {
    let swt = Box::new(SplineWavetable::preset_saw(table_size, n_cp));
    Box::into_raw(swt)
}

#[no_mangle]
pub unsafe extern "C" fn si_spline_wavetable_preset_square(table_size: usize, n_cp: usize) -> *mut SplineWavetable {
    let swt = Box::new(SplineWavetable::preset_square(table_size, n_cp));
    Box::into_raw(swt)
}

#[no_mangle]
pub unsafe extern "C" fn si_spline_wavetable_preset_triangle(table_size: usize, n_cp: usize) -> *mut SplineWavetable {
    let swt = Box::new(SplineWavetable::preset_triangle(table_size, n_cp));
    Box::into_raw(swt)
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_basic() {
        let swt = SplineWavetable::new(2048, 16);
        assert_eq!(swt.table_size(), 2048);
        assert_eq!(swt.n_points(), 16);
    }

    #[test]
    fn test_lattice_first_point_origin() {
        let swt = SplineWavetable::new(512, 7);
        let pts = swt.control_points();
        assert!(pts[0].x.abs() < 1e-9);
        assert!(pts[0].y.abs() < 1e-9);
    }

    #[test]
    fn test_lattice_normalized() {
        let swt = SplineWavetable::new(256, 32);
        let max_dist: f64 = swt.control_points().iter()
            .map(|p| (p.x * p.x + p.y * p.y).sqrt())
            .fold(0.0_f64, f64::max);
        assert!((max_dist - 1.0).abs() < 0.01, "max_dist = {max_dist}");
    }

    #[test]
    fn test_interp_matrix_rows_sum_to_one() {
        let swt = SplineWavetable::new(256, 16);
        let n_pts = swt.n_points();
        for i in 0..swt.table_size() {
            let sum: f64 = (0..n_pts).map(|j| swt.interp_matrix[i * n_pts + j]).sum();
            assert!((sum - 1.0).abs() < 1e-9, "row {i} sum = {sum}");
        }
    }

    #[test]
    fn test_interp_matrix_all_positive() {
        let swt = SplineWavetable::new(512, 16);
        for &w in &swt.interp_matrix {
            assert!(w >= 0.0);
        }
    }

    #[test]
    fn test_reconstruct_zero_values() {
        let mut swt = SplineWavetable::new(512, 16);
        swt.set_values(&vec![0.0; 16]);
        swt.reconstruct();
        for &v in swt.table() {
            assert!(v.abs() < 1e-12, "v = {v}");
        }
    }

    #[test]
    fn test_reconstruct_uniform_values() {
        let mut swt = SplineWavetable::new(512, 16);
        swt.set_values(&vec![1.0; 16]);
        swt.reconstruct();
        for &v in swt.table() {
            assert!((v - 1.0).abs() < 1e-9, "v = {v}");
        }
    }

    #[test]
    fn test_sample_phase_range() {
        let mut swt = SplineWavetable::new(2048, 32);
        swt.set_values(&vec![1.0; 32]);
        swt.reconstruct();
        for i in 0..100 {
            let phase = i as f64 / 100.0;
            let s = swt.sample(phase);
            assert!((s - 1.0).abs() < 0.01, "phase={phase} sample={s}");
        }
    }

    #[test]
    fn test_preset_sine() {
        let swt = SplineWavetable::preset_sine(2048, 32);
        let target: Vec<f64> = (0..2048).map(|i| (2.0 * PI * i as f64 / 2048.0).sin()).collect();
        let rmse = swt.reconstruction_error(&target);
        assert!(rmse < 0.05, "sine RMSE = {rmse}");
    }

    #[test]
    fn test_preset_saw() {
        let swt = SplineWavetable::preset_saw(2048, 64);
        let has_pos = swt.table().iter().any(|&v| v > 0.5);
        let has_neg = swt.table().iter().any(|&v| v < -0.5);
        assert!(has_pos && has_neg);
    }

    #[test]
    fn test_preset_square() {
        let swt = SplineWavetable::preset_square(2048, 64);
        let near_pos = swt.table().iter().filter(|&&v| v > 0.5).count();
        let near_neg = swt.table().iter().filter(|&&v| v < -0.5).count();
        assert!(near_pos > 2048 / 4);
        assert!(near_neg > 2048 / 4);
    }

    #[test]
    fn test_preset_triangle() {
        let swt = SplineWavetable::preset_triangle(2048, 32);
        let target: Vec<f64> = (0..2048)
            .map(|i| 4.0 * ((i as f64 / 2048.0) - 0.5).abs() - 1.0)
            .collect();
        let rmse = swt.reconstruction_error(&target);
        assert!(rmse < 0.05, "triangle RMSE = {rmse}");
    }

    #[test]
    fn test_morph_midpoint() {
        let a = SplineWavetable::preset_sine(512, 16);
        let b = SplineWavetable::preset_saw(512, 16);
        let m = SplineWavetable::morph(&a, &b, 0.5);
        let nonzero = m.table().iter().filter(|&&v| v.abs() > 1e-6).count();
        assert!(nonzero > 100);
        for &v in m.table() {
            assert!(v >= -2.0 && v <= 2.0, "v = {v}");
        }
    }

    #[test]
    fn test_morph_t_zero_is_a() {
        let a = SplineWavetable::preset_sine(512, 16);
        let b = SplineWavetable::preset_saw(512, 16);
        let m = SplineWavetable::morph(&a, &b, 0.0);
        for i in 0..16 {
            let diff = (m.control_points()[i].value - a.control_points()[i].value).abs();
            assert!(diff < 1e-12, "cp[{i}] diff = {diff}");
        }
    }

    #[test]
    fn test_morph_t_one_is_b() {
        let a = SplineWavetable::preset_sine(512, 16);
        let b = SplineWavetable::preset_saw(512, 16);
        let m = SplineWavetable::morph(&a, &b, 1.0);
        for i in 0..16 {
            let diff = (m.control_points()[i].value - b.control_points()[i].value).abs();
            assert!(diff < 1e-12, "cp[{i}] diff = {diff}");
        }
    }

    #[test]
    fn test_render_length() {
        let swt = SplineWavetable::preset_sine(2048, 16);
        let audio = swt.render(440.0, 0.5, 44100);
        assert_eq!(audio.len(), 22050);
    }

    #[test]
    fn test_render_bounded() {
        let swt = SplineWavetable::preset_sine(2048, 16);
        let audio = swt.render(440.0, 0.1, 44100);
        for &v in &audio {
            assert!(v >= -2.0 && v <= 2.0, "v = {v}");
        }
    }

    #[test]
    fn test_render_nonzero() {
        let swt = SplineWavetable::preset_sine(2048, 16);
        let audio = swt.render(440.0, 0.1, 44100);
        let nonzero = audio.iter().filter(|&&v| v.abs() > 1e-6).count();
        assert!(nonzero > audio.len() / 2);
    }

    #[test]
    fn test_sine_differs_from_saw() {
        let s1 = SplineWavetable::preset_sine(2048, 32);
        let s2 = SplineWavetable::preset_saw(2048, 32);
        let a1 = s1.render(440.0, 0.01, 44100);
        let a2 = s2.render(440.0, 0.01, 44100);
        let diff: f64 = a1.iter().zip(&a2).map(|(a, b)| (a - b).powi(2)).sum::<f64>() / a1.len() as f64;
        let diff = diff.sqrt();
        assert!(diff > 0.01, "RMSE = {diff}");
    }

    #[test]
    fn test_compression_ratio() {
        let swt = SplineWavetable::new(2048, 16);
        let ratio = swt.compression_ratio();
        assert!((ratio - 128.0).abs() < 0.01, "ratio = {ratio}");
    }

    #[test]
    fn test_reconstruction_error_self() {
        let mut swt = SplineWavetable::new(1024, 32);
        swt.set_values(&vec![1.0; 32]);
        swt.reconstruct();
        let err = swt.reconstruction_error(swt.table());
        assert!(err.abs() < 1e-12, "err = {err}");
    }

    #[test]
    fn test_multiple_presets_differ() {
        let sine = SplineWavetable::preset_sine(1024, 32);
        let saw = SplineWavetable::preset_saw(1024, 32);
        let sine_energy: f64 = sine.table().iter().map(|v| v.abs()).sum();
        let saw_energy: f64 = saw.table().iter().map(|v| v.abs()).sum();
        assert!((sine_energy - saw_energy).abs() > 1.0);
    }

    #[test]
    fn test_large_table() {
        let swt = SplineWavetable::preset_sine(4096, 64);
        assert_eq!(swt.table_size(), 4096);
        let nonzero = swt.table().iter().filter(|&&v| v.abs() > 1e-6).count();
        assert!(nonzero > 2048);
    }

    #[test]
    fn test_few_control_points() {
        let swt = SplineWavetable::preset_sine(256, 4);
        let nonzero = swt.table().iter().filter(|&&v| v.abs() > 1e-6).count();
        assert!(nonzero > 50);
    }

    #[test]
    fn test_set_values_reconstruct() {
        let mut swt = SplineWavetable::new(256, 8);
        swt.set_values(&[0.0, 1.0, 0.0, -1.0, 0.0, 1.0, 0.0, -1.0]);
        swt.reconstruct();
        let nonzero = swt.table().iter().filter(|&&v| v.abs() > 1e-6).count();
        assert!(nonzero > 50);
    }

    #[test]
    #[should_panic(expected = "table_size must be >= 4")]
    fn test_rejects_small_table() {
        let _ = SplineWavetable::new(2, 16);
    }

    #[test]
    #[should_panic(expected = "need >= 2 control points")]
    fn test_rejects_one_cp() {
        let _ = SplineWavetable::new(1024, 1);
    }
}
