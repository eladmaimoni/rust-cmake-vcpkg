#[cxx::bridge(namespace = "by2")]
mod ffi {
    unsafe extern "C++" {
        include!("ccore/ccore.hpp");

        // ccore_add is defined in the C++ library `ccore`
        fn ccore_add(a: i32, b: i32) -> i32;
    }
}

pub fn ccore_add(a: i32, b: i32) -> i32 {
    ffi::ccore_add(a, b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ccore_add() {
        let r = ccore_add(2, 3);
        assert_eq!(r, 5);
    }
}
