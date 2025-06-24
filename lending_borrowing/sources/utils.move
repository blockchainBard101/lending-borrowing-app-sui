module lending_borrowing::utils;

public fun pow(base: u64, exp: u64): u64 {
    let mut result = 1;
    let mut i = 0;
    while (i < exp) {
        result = result * base;
        i = i + 1;
    };
    result
}
    

public fun normalize_price(price: u64, oracle_decimals: u64): u64 {
    if (oracle_decimals > 6) {
        price / (pow(10,(oracle_decimals - 6) as u64))
    } else {
        price * (pow(10, (6 - oracle_decimals) as u64))
    }
}