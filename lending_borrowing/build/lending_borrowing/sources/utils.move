module lending_borrowing::utils{
    public fun pow(base: u64, exp: u64): u64 {
        let mut result = 1;
        let mut i = 0;
        while (i < exp) {
            result = result * base;
            i = i + 1;
        };
        result
    }
    
}