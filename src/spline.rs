/// Linear interpolation along a polyline defined by control points.
/// `pts` is a flat array of 2*n doubles (x0,y0, x1,y1, ...).
/// `t` is in [0, 1], mapping to the full arc length.
/// For simplicity, this does uniform-parameter linear interpolation between segments.
#[no_mangle]
pub extern "C" fn si_spline_interpolate(pts: *const f64, t: f64, n: usize) -> f64 {
    if pts.is_null() || n < 2 {
        return 0.0;
    }
    let s = unsafe { std::slice::from_raw_parts(pts, 2 * n) };
    if n == 2 {
        // simple lerp between two points, return x coordinate
        let x0 = s[0];
        let x1 = s[2];
        return x0 + t * (x1 - x0);
    }
    // Multi-segment: distribute t across segments
    let num_segs = n - 1;
    let seg_t = t * num_segs as f64;
    let seg_idx = (seg_t.floor() as usize).min(num_segs - 1);
    let local_t = seg_t - seg_idx as f64;
    let x0 = s[seg_idx * 2];
    let x1 = s[(seg_idx + 1) * 2];
    x0 + local_t * (x1 - x0)
}

/// Deadband filter: if val is within `band` of `center`, return center.
/// Otherwise return val (pass through).
#[no_mangle]
pub extern "C" fn si_deadband_filter(val: f64, center: f64, band: f64) -> f64 {
    if (val - center).abs() <= band {
        center
    } else {
        val
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spline_two_points() {
        let pts = [0.0, 0.0, 10.0, 10.0];
        let result = si_spline_interpolate(pts.as_ptr(), 0.5, 2);
        assert!((result - 5.0).abs() < 1e-10);
    }

    #[test]
    fn test_spline_start() {
        let pts = [0.0, 0.0, 10.0, 0.0];
        let result = si_spline_interpolate(pts.as_ptr(), 0.0, 2);
        assert!((result - 0.0).abs() < 1e-10);
    }

    #[test]
    fn test_spline_end() {
        let pts = [0.0, 0.0, 10.0, 0.0];
        let result = si_spline_interpolate(pts.as_ptr(), 1.0, 2);
        assert!((result - 10.0).abs() < 1e-10);
    }

    #[test]
    fn test_deadband_inside() {
        assert_eq!(si_deadband_filter(5.1, 5.0, 0.2), 5.0);
    }

    #[test]
    fn test_deadband_outside() {
        assert_eq!(si_deadband_filter(5.5, 5.0, 0.2), 5.5);
    }

    #[test]
    fn test_deadband_edge() {
        // Clearly inside the band
        assert_eq!(si_deadband_filter(5.1, 5.0, 0.2), 5.0);
        // Clearly outside
        assert_eq!(si_deadband_filter(5.3, 5.0, 0.2), 5.3);
    }
}
