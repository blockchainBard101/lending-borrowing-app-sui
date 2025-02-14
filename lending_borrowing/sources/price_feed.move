module lending_borrowing::main {
    use sui::clock::Clock;
    use pyth::price_info;
    use pyth::price_identifier;
    use pyth::price;
    use pyth::pyth;
    use pyth::price_info::PriceInfoObject;
    use std::debug;
    use sui::event;
    use pyth::i64::I64;

    public struct PriceEvent has copy, drop{
        decimal: I64,
        price: I64
    }

    const E_INVALID_ID: u64 = 1;

    public fun use_pyth_price(
        // Other arguments
        clock: &Clock,
        price_info_object: &PriceInfoObject,
    ):  (I64, I64) {
        let max_age = 60;
        // Make sure the price is not older than max_age seconds
        let price_struct = pyth::get_price_no_older_than(price_info_object,clock, max_age);

        // Check the price feed ID
        let price_info = price_info::get_price_info_from_price_info_object(price_info_object);
        let price_id = price_identifier::get_bytes(&price_info::get_price_identifier(&price_info));

        // ETH/USD price feed ID
        // The complete list of feed IDs is available at https://pyth.network/developers/price-feed-ids
        // Note: Sui uses the Pyth price feed ID without the `0x` prefix.
        assert!(price_id!=x"23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744", E_INVALID_ID);

        // Extract the price, decimal, and timestamp from the price struct and use them
        let decimal_i64 = price::get_expo(&price_struct);
        let price_i64 = price::get_price(&price_struct);
        let timestamp_sec = price::get_timestamp(&price_struct);
        debug::print(&decimal_i64);
        debug::print(&price_i64);
        debug::print(&timestamp_sec);

        event::emit(PriceEvent{
            decimal: decimal_i64,
            price: price_i64
        });
        (decimal_i64, price_i64)
    }
}