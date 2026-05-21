/// Count how many constraint bounds are violated.
/// vals[i] must be <= bounds[i] for satisfaction.
/// Returns count of violations.
#[no_mangle]
pub extern "C" fn si_constraint_check(vals: *const f64, bounds: *const f64, n: usize) -> u8 {
    if vals.is_null() || bounds.is_null() || n == 0 {
        return 0;
    }
    let sv = unsafe { std::slice::from_raw_parts(vals, n) };
    let sb = unsafe { std::slice::from_raw_parts(bounds, n) };
    sv.iter().zip(sb.iter()).filter(|(v, b)| v > b).count() as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_constraint_all_satisfied() {
        let vals = [1.0, 2.0, 3.0];
        let bounds = [2.0, 3.0, 4.0];
        assert_eq!(si_constraint_check(vals.as_ptr(), bounds.as_ptr(), 3), 0);
    }

    #[test]
    fn test_constraint_all_violated() {
        let vals = [3.0, 4.0, 5.0];
        let bounds = [1.0, 2.0, 3.0];
        assert_eq!(si_constraint_check(vals.as_ptr(), bounds.as_ptr(), 3), 3);
    }

    #[test]
    fn test_constraint_mixed() {
        let vals = [1.0, 5.0, 2.0];
        let bounds = [2.0, 3.0, 2.0]; // 1<=2 ok, 5>3 fail, 2<=2 ok
        assert_eq!(si_constraint_check(vals.as_ptr(), bounds.as_ptr(), 3), 1);
    }

    #[test]
    fn test_constraint_null() {
        assert_eq!(si_constraint_check(std::ptr::null(), std::ptr::null(), 0), 0);
    }
}
