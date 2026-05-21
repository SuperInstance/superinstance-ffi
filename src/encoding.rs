/// Quantize a 2D direction to one of 48 evenly-spaced angles (7.5° increments).
/// Returns a u8 in [0, 47].
#[no_mangle]
pub extern "C" fn si_pythagorean48_encode(x: f64, y: f64) -> u8 {
    let angle = y.atan2(x); // [-π, π]
    let normalized = if angle < 0.0 { angle + 2.0 * std::f64::consts::PI } else { angle };
    let index = (normalized / (2.0 * std::f64::consts::PI) * 48.0).round() as u8;
    index % 48
}

/// Manhattan distance between two integer vectors.
#[no_mangle]
pub extern "C" fn si_manhattan_distance(a: *const i32, b: *const i32, len: usize) -> i64 {
    if a.is_null() || b.is_null() || len == 0 {
        return 0;
    }
    let sa = unsafe { std::slice::from_raw_parts(a, len) };
    let sb = unsafe { std::slice::from_raw_parts(b, len) };
    sa.iter().zip(sb.iter()).map(|(x, y)| (x - y).abs() as i64).sum()
}

/// Cascade matching: count matching bytes between query and a single codebook entry.
/// Returns number of matching positions.
#[no_mangle]
pub extern "C" fn si_cascade_match(query: *const u8, codebook: *const u8, len: usize) -> i32 {
    if query.is_null() || codebook.is_null() || len == 0 {
        return 0;
    }
    let sq = unsafe { std::slice::from_raw_parts(query, len) };
    let sc = unsafe { std::slice::from_raw_parts(codebook, len) };
    sq.iter().zip(sc.iter()).filter(|(a, b)| a == b).count() as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pythagorean48_zero() {
        assert_eq!(si_pythagorean48_encode(1.0, 0.0), 0);
    }

    #[test]
    fn test_pythagorean48_up() {
        let idx = si_pythagorean48_encode(0.0, 1.0);
        assert_eq!(idx, 12); // 90° = 12 * 7.5°
    }

    #[test]
    fn test_manhattan_basic() {
        let a = [1, 2, 3];
        let b = [4, 0, 3];
        assert_eq!(si_manhattan_distance(a.as_ptr(), b.as_ptr(), 3), 3 + 2 + 0);
    }

    #[test]
    fn test_manhattan_null() {
        assert_eq!(si_manhattan_distance(std::ptr::null(), std::ptr::null(), 0), 0);
    }

    #[test]
    fn test_cascade_match_all() {
        let q = [1u8, 2, 3, 4];
        let c = [1u8, 2, 3, 4];
        assert_eq!(si_cascade_match(q.as_ptr(), c.as_ptr(), 4), 4);
    }

    #[test]
    fn test_cascade_match_none() {
        let q = [1u8, 2, 3, 4];
        let c = [5u8, 6, 7, 8];
        assert_eq!(si_cascade_match(q.as_ptr(), c.as_ptr(), 4), 0);
    }

    #[test]
    fn test_cascade_match_partial() {
        let q = [1u8, 2, 3, 4];
        let c = [1u8, 9, 3, 9];
        assert_eq!(si_cascade_match(q.as_ptr(), c.as_ptr(), 4), 2);
    }
}
