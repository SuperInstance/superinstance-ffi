/// Check holonomy: product of all transforms must equal 1 (identity)
/// Each transform is a packed i64 representing a group element.
/// For simplicity, we check if the cumulative XOR-based hash equals 0 or
/// if the product of signed values equals 1.
#[no_mangle]
pub extern "C" fn si_holonomy_check(transforms: *const i64, len: usize) -> bool {
    if transforms.is_null() || len == 0 {
        return true; // trivial loop
    }
    let slice = unsafe { std::slice::from_raw_parts(transforms, len) };
    let product: i64 = slice.iter().product();
    product == 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_holonomy_trivial() {
        assert!(si_holonomy_check(std::ptr::null(), 0));
    }

    #[test]
    fn test_holonomy_identity() {
        let transforms: [i64; 3] = [1, 1, 1];
        assert!(si_holonomy_check(transforms.as_ptr(), 3));
    }

    #[test]
    fn test_holonomy_product_one() {
        // [-1, -1, 1] product = 1
        let transforms: [i64; 3] = [-1, -1, 1];
        assert!(si_holonomy_check(transforms.as_ptr(), 3));
    }

    #[test]
    fn test_holonomy_fail() {
        let transforms: [i64; 2] = [2, 3]; // 6 != 1
        assert!(!si_holonomy_check(transforms.as_ptr(), 2));
    }
}
