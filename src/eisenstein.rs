/// Eisenstein integer norm: a² - ab + b²
#[no_mangle]
pub extern "C" fn si_eisenstein_norm(a: i32, b: i32) -> i64 {
    let a = a as i64;
    let b = b as i64;
    a * a - a * b + b * b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_eisenstein_unit() {
        // Eisenstein integer (1, 0) has norm 1: 1² - 1*0 + 0² = 1
        assert_eq!(si_eisenstein_norm(1, 0), 1);
        // Also (0, 1) has norm 1
        assert_eq!(si_eisenstein_norm(0, 1), 1);
    }

    #[test]
    fn test_eisenstein_zero() {
        assert_eq!(si_eisenstein_norm(0, 0), 0);
    }

    #[test]
    fn test_eisenstein_symmetric() {
        // (a,b) and (b,a) give same norm
        assert_eq!(si_eisenstein_norm(3, 5), si_eisenstein_norm(5, 3));
    }

    #[test]
    fn test_eisenstein_known() {
        // 3² - 3*7 + 7² = 9 - 21 + 49 = 37
        assert_eq!(si_eisenstein_norm(3, 7), 37);
    }
}
