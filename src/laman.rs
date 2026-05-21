/// Laman graph edge count: 2v - 3
#[no_mangle]
pub extern "C" fn si_laman_edges(v: i32) -> i32 {
    2 * v - 3
}

/// Check if a graph with v vertices and e edges is rigid (Laman condition)
#[no_mangle]
pub extern "C" fn si_is_rigid(v: i32, e: i32) -> bool {
    e >= 2 * v - 3
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_laman_edges_min() {
        assert_eq!(si_laman_edges(2), 1);
    }

    #[test]
    fn test_laman_edges_triangle() {
        assert_eq!(si_laman_edges(3), 3);
    }

    #[test]
    fn test_is_rigid_true() {
        assert!(si_is_rigid(4, 5)); // 2*4-3 = 5
    }

    #[test]
    fn test_is_rigid_false() {
        assert!(!si_is_rigid(4, 4)); // 2*4-3 = 5, 4 < 5
    }

    #[test]
    fn test_is_rigid_exactly() {
        assert!(si_is_rigid(5, 7)); // 2*5-3 = 7
    }
}
