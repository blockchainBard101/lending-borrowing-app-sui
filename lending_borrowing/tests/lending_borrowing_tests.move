#[test_only]
module lending_borrowing::lending_borrowing_tests{
// uncomment this line to import the module
// use lending_borrowing::lending_borrowing;
    use std::debug;
    const ENotImplemented: u64 = 0;

    #[test]
    fun test_lending_borrowing() {
        let a = 2* 100/4;
        debug::print(&a);

        let b = pow(2, 3);
        debug::print(&b);
    }

    fun pow(base: u64, exp: u64): u64 {
        let mut result = 1;
        let mut i = 0;
        while (i < exp) {
            result = result * base;
            i = i + 1;
        };
        result
    }

    #[test, expected_failure(abort_code = ::lending_borrowing::lending_borrowing_tests::ENotImplemented)]
    fun test_lending_borrowing_fail() {
        abort ENotImplemented
    }
}