module lending_borrowing::lending_borrowing{
    use std::ascii::String as AsciiString;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use std::type_name;
    use sui::table::{Table, new};
    use sui::clock::Clock;
    use std::string::{Self,String};
    use sui::dynamic_object_field as dof;
    use sui::dynamic_field as df;

    use pyth::price_info::PriceInfoObject;

    const NotEnoughCollateral : u64= 1;
    const NotEnoughLiquidityOnPool : u64= 2;


    public struct Pool<phantom A, phantom B> has key{
        id : UID,
        coin_a: Balance<A>,
        coin_b: Balance<B>,
        url: String,
        ltv: u8, 
        interest_rate: u8,
    }

    public struct LiquidityProviders has store{
        id: ID,
        liquidity_providers: Table<address, u64>,
        borrowers: Table<address, Borrower>,
    }

    public struct Borrower has store{
        amount_borrowed: u64,
        amount_payed: u64,
        collateral_coin_price: u64,
        date: u64,
        intrest_rate: u8,
    }
    
    public fun create_lending_pool<A, B>(ltv: u8, interest_rate: u8, ctx: &mut TxContext) {
        let mut pool = Pool {
            id: object::new(ctx),
            coin_a: balance::zero<A>(),
            coin_b: balance::zero<B>(),
            url: string::utf8(b""),
            ltv,
            interest_rate,
        };
        
        let liquidity_providers = LiquidityProviders {
            id: *pool.id.uid_as_inner(),
            liquidity_providers: new<address, u64>(ctx),
            borrowers: new<address, Borrower>(ctx),
        };
        df::add(&mut pool.id, b"providers", liquidity_providers);
        transfer::share_object(pool);
    }

    public fun add_liquidity<A, B>(pool: &mut Pool<A, B>,liquidity_coin: Coin<A>, ctx: &mut TxContext) {
        let providers: &mut LiquidityProviders = df::borrow_mut(&mut pool.id, b"providers");
        let amount = liquidity_coin.value();
        if(providers.liquidity_providers.contains(ctx.sender())) {
            let liquidty = providers.liquidity_providers.borrow_mut(ctx.sender());
            *liquidty = *liquidty + amount;
        } else{
            providers.liquidity_providers.add(ctx.sender(), amount);
        };
        let coin_balance : Balance<A> = liquidity_coin.into_balance();
        balance::join(&mut pool.coin_a, coin_balance);
    }

    // public fun borrow<A, B>(pool: &mut Pool<A, B>, borrow_amount: u64, collateral_coin: Coin<B>,clock: &Clock, ctx: &mut TxContext) {
    //     let coin_amount = collateral_coin.value();
    //     let ltv = pool.ltv;
    //     let max_borrow = coin_amount * collateral_coin_price / 100 * (ltv as u64);
    //     let loan_liquidity = balance::value(&pool.coin_a);

    //     assert!(borrow_amount <= max_borrow, NotEnoughCollateral);
    //     assert!(borrow_amount <= loan_liquidity, NotEnoughLiquidityOnPool);
    //     let lps: &mut LiquidityProviders = df::borrow_mut(&mut pool.id, b"providers");
    //     if(lps.borrowers.contains(ctx.sender())) {
    //         let borrower = lps.borrowers.borrow_mut(ctx.sender());
    //         let previous_amount = borrower.amount_borrowed;
    //         borrower.amount_borrowed = previous_amount + borrow_amount;
    //     } else{
    //         let borrower = Borrower{
    //             amount_borrowed: borrow_amount,
    //             amount_payed: 0,
    //             collateral_coin_price,
    //             date: clock.timestamp_ms(),
    //             intrest_rate: pool.interest_rate,
    //         };
    //         lps.borrowers.add(ctx.sender(), borrower);
    //     };
    //     balance::join(&mut pool.coin_b, collateral_coin.into_balance());
    //     let lend_coin = coin::take(&mut pool.coin_a, borrow_amount, ctx);
    //     transfer::public_transfer(lend_coin, ctx.sender());
    // }
}