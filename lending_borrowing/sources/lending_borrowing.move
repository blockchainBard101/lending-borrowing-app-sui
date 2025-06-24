module lending_borrowing::lending_borrowing;
// use std::ascii::String as AsciiString;
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
// use pyth::price;

const EZeroCoin : u64= 1;
const EAmountMoreThanBorrowed : u64= 5;
const NotEnoughCollateral : u64= 1;
const NotEnoughLiquidityOnPool : u64= 2;
const EAmountNotEqualBorrowed : u64= 3;

const PERCENT_SCALE: u64 =  100_000;
const PLATFORM_SCALE: u64 = 1_000_000;

public struct Pool<phantom A, phantom B> has key{
    id : UID,
    coin_a: Balance<A>,
    coin_b: Balance<B>,
    fees: Balance<A>,
    borrow_fee: u64,
    url: String,
    ltv: u16, 
    liquidation_threshold: u8
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
    total_amount_borrowed: u64,
    total_amount_payed: u64,
    total_collateral_coin_amount: u64,
    borrows: vector<Borrows>,
    collateral_price_deciaml: u64,
}

public struct Borrows has store, copy, drop{
    amount_borrowed: u64,
    collateral_coin_amount: u64,
    amount_payed: u64,
    collateral_coin_price_at_borrow: u64,
    price_decimals: u64,
    liquidation_price: u128,
    loan_paid: bool,
    date: u64,
}

public fun create_lending_pool<A, B>(ltv: u16, liquidation_threshold: u8, borrow_fee: u64, ctx: &mut TxContext) {
    let mut pool = Pool {
        id: object::new(ctx),
        coin_a: balance::zero<A>(),
        coin_b: balance::zero<B>(),
        fees: balance::zero<A>(),
        borrow_fee,
        url: string::utf8(b""),
        ltv,  //1% == 100
        liquidation_threshold,
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
    let coin_b_decimals = 9;
    let usdc_decimals = 6;

    let ltv = pool.ltv;

    let (decimals_i64, price_i64) = main::use_pyth_price(clock, price_info_object);
    let price_decimals = decimals_i64.get_magnitude_if_negative();
    let collateral_coin_price = price_i64.get_magnitude_if_positive();

    let mut liquidation_price;
    // let mut division_dec = 0;

    if(coin_b_decimals > usdc_decimals){
        let division_dec = coin_b_decimals - usdc_decimals;
        liquidation_price = ((borrow_amount as u128) * (utils::pow(10, division_dec) as u128)  * (utils::pow(10, price_decimals) as u128)) / (((collateral_coin_amount as u128) * (pool.liquidation_threshold as u128)) / (100 * PERCENT_SCALE as u128 ));

    } else{
        if(coin_b_decimals == usdc_decimals){
            liquidation_price = ((borrow_amount as u128)  * (utils::pow(10, price_decimals) as u128)) / (((collateral_coin_amount as u128) * (pool.liquidation_threshold as u128)) / (100 * PERCENT_SCALE as u128 ));
        } else{
            let division_dec = usdc_decimals - coin_b_decimals;
            liquidation_price = ((borrow_amount as u128)  * (utils::pow(10, price_decimals) as u128)) / (((collateral_coin_amount as u128)* (utils::pow(10, division_dec) as u128) * (pool.liquidation_threshold as u128)) / (100 * PERCENT_SCALE as u128 ));
        }
    };

    let b_value_price_a = ((collateral_coin_amount as u128) * (collateral_coin_price as u128)) / (utils::pow(10, coin_b_decimals + price_decimals ) as u128);
    let max_borrow_value = b_value_price_a * (ltv as u128) / (100 * PERCENT_SCALE as u128);

    // let decimals = price_decimals + 9 + 2;  //pyth price decimals + sui decimals + ltv decimals
    // let uf = utils::pow(10, decimals - usdc_decimals) as u128;
    // let max_borrow = (collateral_coin_amount as u128) * (collateral_coin_price as u128) * (ltv as u128); // 8×10 ^ 16
    // let loan_liquidity = (balance::value(&pool.coin_a) as u128) * uf; //total decimals - usdc decimals 1.5×10¹⁹
    // let borrow_amount_rounded = (borrow_amount as u128) * uf; //1.5×10¹⁶

    // assert!(borrow_amount_rounded <= max_borrow, NotEnoughCollateral);
    // assert!(borrow_amount_rounded <= loan_liquidity, NotEnoughLiquidityOnPool);
    
    assert!(borrow_amount as u128 <= max_borrow_value, NotEnoughCollateral);
    assert!(borrow_amount as u128 <= (balance::value(&pool.coin_a) as u128), NotEnoughLiquidityOnPool);
    let borrow =  Borrows{
        amount_borrowed: borrow_amount,
        amount_payed: 0,
        collateral_coin_amount: collateral_coin_amount,
        collateral_coin_price_at_borrow: collateral_coin_price,
        price_decimals,
        liquidation_price,
        loan_paid: false,
        date: clock.timestamp_ms()
    };
    let lps: &mut LiquidityProviders = df::borrow_mut(&mut pool.id, b"providers");
    if(lps.borrowers.contains(ctx.sender()) && borrow_nft.is_some()) {
        let mut borrower = lps.borrowers.borrow_mut(ctx.sender());
        borrower.total_amount_borrowed = borrower.total_amount_borrowed  + borrow_amount;
        vector::push_back(&mut borrower.borrows, borrow);
        borrower.total_collateral_coin_amount = borrower.total_collateral_coin_amount + collateral_coin_amount;
        let b_nft = option::borrow_mut(borrow_nft);
        b_nft.borrower = *borrower;
    } else{
        let mut borrower = Borrower{
            total_amount_borrowed: borrow_amount,
            total_amount_payed: 0,
            borrows: vector::empty<Borrows>(),
            total_collateral_coin_amount: collateral_coin_amount,
            collateral_price_deciaml: price_decimals,
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

#[allow(lint(self_transfer))]
public fun repay<A, B>(
    pool: &mut Pool<A, B>, 
    borrow_nft: &mut BorrowNft<A, B>, 
    borrowed_coin: Coin<A>, 
    loan_to_repay_idx: Option<u64>,
    price_info_object: &PriceInfoObject,
    clock: &Clock, 
    ctx: &mut TxContext) 
    {
    assert!(borrowed_coin.value() == 0, EZeroCoin);
    let amount = borrowed_coin.value();
    let mut borrower = borrow_nft.borrower;
    assert!((amount <= borrower.total_amount_borrowed && loan_to_repay_idx.is_none()) || (loan_to_repay_idx.is_some() && (amount <= vector::borrow_mut(&mut borrower.borrows, *loan_to_repay_idx.borrow()).amount_borrowed)), EAmountMoreThanBorrowed);
    assert!((amount == borrower.total_amount_borrowed && loan_to_repay_idx.is_none()) || (loan_to_repay_idx.is_some() && (amount <= vector::borrow_mut(&mut borrower.borrows, *loan_to_repay_idx.borrow()).amount_borrowed)), EAmountNotEqualBorrowed);
    let (decimals_i64, price_i64) = main::use_pyth_price(clock, price_info_object);
    let price_decimals = decimals_i64.get_magnitude_if_negative();
    let collateral_coin_price = price_i64.get_magnitude_if_positive();

    let lps: &mut LiquidityProviders = df::borrow_mut(&mut pool.id, b"providers");

    let coin_balance  = coin::into_balance(borrowed_coin); 
    
    if (loan_to_repay_idx.is_none()) {
        pool.coin_a.join(coin_balance);
        borrower.total_amount_payed = borrower.total_amount_borrowed;
        borrower.borrows = pay_all_borrowed(borrower.borrows);
        let collateral_coin = coin::take(&mut pool.coin_b, borrower.total_collateral_coin_amount, ctx);
        borrower.total_collateral_coin_amount = 0;
        transfer::public_transfer(collateral_coin, ctx.sender());
    } else{
        let loan_to_repay_idx_val = *loan_to_repay_idx.borrow();
        let loan_to_repay_ref = vector::borrow_mut(&mut borrower.borrows, loan_to_repay_idx_val);
        if (amount == loan_to_repay_ref.amount_borrowed) {
            pool.coin_a.join(coin_balance);
            let collateral_amount = loan_to_repay_ref.collateral_coin_amount;
            loan_to_repay_ref.amount_borrowed = 0;
            loan_to_repay_ref.collateral_coin_amount = 0;
            loan_to_repay_ref.loan_paid = true;
            let collateral_coin = coin::take(&mut pool.coin_b, collateral_amount, ctx);
            transfer::public_transfer(collateral_coin, ctx.sender());

            borrower.total_amount_payed = borrower.total_amount_payed + amount;
            borrower.total_collateral_coin_amount = borrower.total_collateral_coin_amount - collateral_amount;
        } else{
            pool.coin_a.join(coin_balance);
            let repayment_percent = get_repayment_percentage(amount, loan_to_repay_ref.amount_borrowed);
            let collateral_to_return = get_collateral_to_return(repayment_percent, loan_to_repay_ref.collateral_coin_amount);
            loan_to_repay_ref.amount_borrowed = loan_to_repay_ref.amount_borrowed - amount;
            loan_to_repay_ref.collateral_coin_amount = loan_to_repay_ref.collateral_coin_amount - collateral_to_return;
            let collateral_coin = coin::take(&mut pool.coin_b, collateral_to_return, ctx);
            transfer::public_transfer(collateral_coin, ctx.sender());

            borrower.total_amount_payed = borrower.total_amount_payed + amount;
            borrower.total_collateral_coin_amount = borrower.total_collateral_coin_amount - collateral_to_return;
        };
    };

    let lps_borrower = lps.borrowers.borrow_mut(ctx.sender());
    *lps_borrower = borrower;
}

// fun get_borrow_risk(borrow: &Borrows, raw_oracle_price: u64, oracle_decimals: u64, liquidation_threshold: u8 ): u64 {
//     let normalized_price = utils::normalize_price(raw_oracle_price, oracle_decimals);
//     let collateral_value = borrow.collateral_coin_amount * normalized_price;
//     let current_ltv = (borrow.amount_borrowed * PLATFORM_SCALE) / collateral_value;
//     let ltv_progress = (current_ltv * PERCENT_SCALE) / (liquidation_threshold as u64);
//     ltv_progress
// }


// fun get_borrows_with_highest_liquidation_risk_idx(borrows:vector<Borrows>, raw_oracle_price: u64, oracle_decimals: u64, liquidation_threshold: u8, clock: &Clock) : u64 {
//     let mut i = 0;
//     let mut max_ltv_progress = 0;
//     let mut max_ltv_index = 0;
//     while(i <= vector::length(borrows)) {
//         let ltv_progress = get_borrow_risk(vector::borrow(borrows, i), raw_oracle_price, oracle_decimals, liquidation_threshold);
//         if (ltv_progress > max_ltv_progress) {
//             max_ltv_progress = ltv_progress;
//             max_ltv_index = i;
//         }
//     };
//     return max_ltv_index
// }

fun pay_all_borrowed(mut borrows: vector<Borrows>) : vector<Borrows> {
    let mut i = 0;
    while(i <= vector::length(&borrows)) {
        let borrow = vector::borrow_mut(&mut borrows, i);
        borrow.amount_payed = borrow.amount_borrowed;
        i = i + 1;
    };
    return borrows
}

fun get_repayment_percentage(repay_amount: u64, total_borrowed: u64): u64 {
    assert!(total_borrowed > 0, 0);
    repay_amount * PLATFORM_SCALE / total_borrowed
}

fun get_collateral_to_return(repayment_percent: u64, total_collateral: u64): u64 {
    total_collateral * repayment_percent / PLATFORM_SCALE
}