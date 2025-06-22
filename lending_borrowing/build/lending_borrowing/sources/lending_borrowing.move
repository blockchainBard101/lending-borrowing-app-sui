module lending_borrowing::lending_borrowing;
use std::ascii::String as AsciiString;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::table::{Table, new};
use sui::clock::Clock;
use std::string::{Self,String};
use sui::dynamic_object_field as dof;
use sui::dynamic_field as df;
use std::type_name::{Self, TypeName};

use lending_borrowing::main;
use lending_borrowing::utils;

use pyth::price_info::PriceInfoObject;

const NotEnoughCollateral : u64= 1;
const NotEnoughLiquidityOnPool : u64= 2;

public struct Pool<phantom A, phantom B> has key{
    id : UID,
    coin_a: Balance<A>,
    coin_b: Balance<B>,
    fees: Balance<A>,
    borrow_fee: u64,
    url: String,
    ltv: u8, 
}

public struct LiquidityProviders has store{
    id: ID,
    liquidity_providers: Table<address, u64>,
    borrowers: Table<address, Borrower>,
}

public struct BorrowNft<phantom A, phantom B> has key{
    id: UID,
    pool_id: ID,
    borrower: Borrower
}

public struct LendingNft<phantom A, phantom B> has key{
    id: UID,
    lend_coin: TypeName,
    pool_id: ID,
    amount: u64,
    url: String,
}

public struct Borrower has store, copy, drop{
    total_amount_borrowed: u128,
    total_amount_payed: u64,
    borrows: vector<Borrows>,
    collateral_price_deciaml: u64,
    decimals: u64,
}

public struct Borrows has store, copy, drop{
    amount_borrowed: u128,
    amount_payed: u64,
    collateral_coin_price_at_borrow: u64,
    date: u64,
}

public fun create_lending_pool<A, B>(ltv: u8, borrow_fee: u64, ctx: &mut TxContext) {
    let mut pool = Pool {
        id: object::new(ctx),
        coin_a: balance::zero<A>(),
        coin_b: balance::zero<B>(),
        fees: balance::zero<A>(),
        borrow_fee,
        url: string::utf8(b""),
        ltv,  //1% == 100
    };
    
    let liquidity_providers = LiquidityProviders {
        id: *pool.id.uid_as_inner(),
        liquidity_providers: new<address, u64>(ctx),
        borrowers: new<address, Borrower>(ctx),
    };
    df::add(&mut pool.id, b"providers", liquidity_providers);
    transfer::share_object(pool);
}

public fun add_liquidity<A, B>(pool: &mut Pool<A, B>, lending_nft: &mut Option<LendingNft<A, B>>,liquidity_coin: Coin<A>, ctx: &mut TxContext) {
    let lending_coin_type = type_name::get<A>() ;
    let providers: &mut LiquidityProviders = df::borrow_mut(&mut pool.id, b"providers");
    let amount = liquidity_coin.value();
    if(providers.liquidity_providers.contains(ctx.sender()) && lending_nft.is_some()) {
        let liquidty = providers.liquidity_providers.borrow_mut(ctx.sender());
        *liquidty = *liquidty + amount;

        let lend_nft = option::borrow_mut(lending_nft);
        lend_nft.amount = lend_nft.amount + amount;
    } else{
        providers.liquidity_providers.add(ctx.sender(), amount);
        let lend_nft = LendingNft<A,B>{
            id: object::new(ctx),
            pool_id: *pool.id.uid_as_inner(),
            lend_coin: lending_coin_type,
            amount: amount,
            url: string::utf8(b""),
        };
        transfer::transfer(lend_nft, ctx.sender());
    };
    let coin_balance : Balance<A> = liquidity_coin.into_balance();
    balance::join(&mut pool.coin_a, coin_balance);
}

#[allow(lint(self_transfer))]
public fun borrow<A, B>(pool: &mut Pool<A, B>, borrow_nft: &mut Option<BorrowNft<A, B>>, borrow_amount: u64, collateral_coin: Coin<B>,clock: &Clock,price_info_object: &PriceInfoObject, ctx: &mut TxContext) {
    let collateral_coin_amount = collateral_coin.value();
    let ltv = pool.ltv;
    let usdc_decimals = 6;
    let (decimals_i64, price_i64) = main::use_pyth_price(clock, price_info_object);
    let price_decimals = decimals_i64.get_magnitude_if_negative();
    let decimals = price_decimals + 9 + 3;  //pyth price decimals + sui decimals + ltv decimals
    let collateral_coin_price = price_i64.get_magnitude_if_positive();
    let max_borrow = (collateral_coin_amount as u128) * (collateral_coin_price as u128) * (ltv as u128);
    let loan_liquidity = (balance::value(&pool.coin_a) as u128) * (utils::pow(10, decimals - usdc_decimals ) as u128); //total decimals - usdc decimals
    let borrow_amount_rounded = (borrow_amount as u128) * (utils::pow(10, decimals - usdc_decimals) as u128); 

    assert!(borrow_amount_rounded <= max_borrow, NotEnoughCollateral);
    assert!(borrow_amount_rounded <= loan_liquidity, NotEnoughLiquidityOnPool);
    let borrow =  Borrows{
        amount_borrowed: borrow_amount_rounded,
        amount_payed: 0,
        collateral_coin_price_at_borrow: collateral_coin_price,
        date: clock.timestamp_ms()
    };
    let lps: &mut LiquidityProviders = df::borrow_mut(&mut pool.id, b"providers");
    if(lps.borrowers.contains(ctx.sender()) && borrow_nft.is_some()) {
        let mut borrower = lps.borrowers.borrow_mut(ctx.sender());
        // let total_borrow_amount = borrower.total_amount_borrowed;
        borrower.total_amount_borrowed = borrower.total_amount_borrowed  + borrow_amount_rounded;
        vector::push_back(&mut borrower.borrows, borrow);
        let b_nft = option::borrow_mut(borrow_nft);
        b_nft.borrower = *borrower;
    } else{
        let mut borrower = Borrower{
            total_amount_borrowed: borrow_amount_rounded,
            total_amount_payed: 0,
            borrows: vector::empty<Borrows>(),
            collateral_price_deciaml: price_decimals,
            decimals: decimals,
        };
        vector::push_back(&mut borrower.borrows, borrow);
        lps.borrowers.add(ctx.sender(), borrower);
        let b_nft = BorrowNft<A,B>{
            id: object::new(ctx),
            pool_id: *pool.id.uid_as_inner(),
            borrower: borrower,
        };
        transfer::transfer(b_nft, ctx.sender());
    };
    balance::join(&mut pool.coin_b, collateral_coin.into_balance());
    let lend_coin = coin::take(&mut pool.coin_a, borrow_amount, ctx);
    transfer::public_transfer(lend_coin, ctx.sender());
}

public fun repay(){

}