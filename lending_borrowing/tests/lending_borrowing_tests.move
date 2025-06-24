#[test_only]
module lending_borrowing::lending_borrowing_tests{
// uncomment this line to import the module
// use lending_borrowing::lending_borrowing;
    use std::debug;
    const ENotImplemented: u64 = 0;

    use sui::clock::Clock;
    use pyth::price_info;
    use pyth::price_identifier;
    use pyth::price;
    use pyth::pyth;
    use pyth::price_info::PriceInfoObject;

    const E_INVALID_ID: u64 = 1;

    #[test]
    fun test_lending_borrowing() {
        // let max_age = 60;
        // // Make sure the price is not older than max_age seconds
        // let price_struct = pyth::get_price_no_older_than(price_info_object,clock, max_age);
        // let price_info = price_info::get_price_info_from_price_info_object(price_info_object);
        // let price_id = price_identifier::get_bytes(&price_info::get_price_identifier(&price_info));
    }

    #[test, expected_failure(abort_code = ::lending_borrowing::lending_borrowing_tests::ENotImplemented)]
    fun test_lending_borrowing_fail() {
        abort ENotImplemented
    }
}