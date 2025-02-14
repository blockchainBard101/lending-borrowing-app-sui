module lending_borrowing::lending_borrowing_main{
    // use std::string::String;
    use std::ascii::String as AsciiString;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use std::type_name;
    use sui::table::{Table, new};
    use sui::clock::Clock;

    const NotEnoughLiquidity : u64= 1;
    const NotEnoughLiquidityOnPool : u64= 2;
    const LoanPayed : u64= 3;
    const NotCollateral : u64= 4;
    const AmountMoreThanBorrowed : u64= 5;

    public struct Lender has store, copy, drop{
        amount: u64,
        reward: u64,
    }

    public struct Borrows has store{
        amounts_borrowed: Table<AsciiString, u64>,
    }


    public struct Borrower has key{
        id : UID,
        borrower: address,
        amount: u64,
        amount_payed: u64,
        collateral_coin: AsciiString,
        collateral_coin_price: u64,
        date: u64,
        intrest_rate: u64,
        loan_payed : bool,
    }

    public struct LendingPool<phantom T, phantom C> has key{
        id : UID,
        total_liquidity: Balance<T>, // Balance of stablecoins in the pool
        total_collateral: Table<AsciiString, Balance<C>>,
        liquidity_providers: Table<address, Lender>,
        borrowers: Table<address, Borrows>,
        ltv: u64,
        liquidation_threshold: u64,
        interest_rate: u64,
        decimals: u64,   
    }

    public fun init_pool<T, C>(ltv : u64, decimals: u64, liquidation_threshold: u64, interest_rate: u64, ctx: &mut TxContext){
        let pool : LendingPool< T, C> = LendingPool<T, C> {
            id: object::new(ctx),
            total_liquidity: balance::zero<T>(),
            total_collateral: new<AsciiString, Balance<C>>(ctx),
            liquidity_providers: new<address, Lender>(ctx),
            borrowers: new<address, Borrows>(ctx),
            ltv,
            liquidation_threshold,
            interest_rate,
            decimals,
        };
        transfer::transfer(pool, ctx.sender())
    }

    public fun add_liquidity<T, C>(
        pool: &mut LendingPool<T, C>,
        liquidity_coin: Coin<T>,
        ctx: &mut TxContext)
        {
        // let coin_type = type_name::get<T>();
        let amount = liquidity_coin.value();
        if (pool.liquidity_providers.contains(ctx.sender())) {
            let lender = *pool.liquidity_providers.borrow_mut(ctx.sender());
            let previous_liquidity  = lender.amount;
            pool.liquidity_providers.borrow_mut(ctx.sender()).amount = previous_liquidity + amount;
        } else {
            let lender = Lender {
                amount: amount,
                reward: 0
            };
            pool.liquidity_providers.add(ctx.sender(), lender);
        };
        let coin_balance : Balance<T> = liquidity_coin.into_balance();
        balance::join(&mut pool.total_liquidity, coin_balance);
    }

    #[allow(lint(self_transfer))]
    public fun borrow<T, C>(
        pool: &mut LendingPool<T, C>,
        borrow_amount: u64,
        collateral_coin: Coin<C>,
        collateral_coin_price: u64,
        clock: &Clock,
        ctx: &mut TxContext)
        {
        let coin_type = type_name::get<C>();
        let amount = collateral_coin.value();

        let ltv = pool.ltv / pool.decimals;
        let max_borrow = amount * collateral_coin_price / 100 * (ltv as u64);
        let loan_liquidity = balance::value(&pool.total_liquidity);
        assert!(borrow_amount <= max_borrow, NotEnoughLiquidity);
        assert!(borrow_amount <= loan_liquidity, NotEnoughLiquidityOnPool);

        if(pool.borrowers.contains(ctx.sender())) {
            let borrower = pool.borrowers.borrow_mut(ctx.sender());
            if (borrower.amounts_borrowed.contains(coin_type.into_string())) {
                let previous_amount = borrower.amounts_borrowed.borrow_mut(coin_type.into_string());
                *borrower.amounts_borrowed.borrow_mut(coin_type.into_string()) = *previous_amount + borrow_amount;
            } else{
                borrower.amounts_borrowed.add(coin_type.into_string(), borrow_amount);
            };
        } else {
            let mut borrower = Borrows{
                amounts_borrowed: new<AsciiString, u64>(ctx),
            };
            borrower.amounts_borrowed.add(coin_type.into_string(), borrow_amount);
            pool.borrowers.add(ctx.sender(), borrower);
        };
        let coin_balance : Balance<C> = collateral_coin.into_balance();

        let collateral_exists = pool.total_collateral.contains(coin_type.into_string());
        if (collateral_exists) {
            
            let previous_collateral = pool.total_collateral.borrow_mut(coin_type.into_string());
            balance::join(previous_collateral, coin_balance);
        } else {
            pool.total_collateral.add(coin_type.into_string(), coin_balance);
        };
        let lend_balance = coin::take(&mut pool.total_liquidity, borrow_amount, ctx);

        let borrower = Borrower{
            id: object::new(ctx),
            borrower: ctx.sender(),
            amount: borrow_amount,
            amount_payed: 0,
            collateral_coin: coin_type.into_string(),
            collateral_coin_price: collateral_coin_price,
            date: clock.timestamp_ms(),
            intrest_rate: pool.interest_rate,
            loan_payed : false,
        };
        transfer::transfer(borrower, ctx.sender());
        transfer::public_transfer(lend_balance, ctx.sender());
    }

    #[allow(lint(self_transfer))]
    public fun repay<T, C>(
        pool: &mut LendingPool<T, C>,
        borrower: &mut Borrower,
        liquidity_coin: Coin<T>,
        collateral_coin_price: u64,
        clock: &Clock,
        ctx: &mut TxContext)
        {
        assert!(borrower.loan_payed == false, LoanPayed);
        let b_coin_type = type_name::get<T>();
        let c_coin_type = type_name::get<C>();
        assert!(b_coin_type.into_string() == borrower.collateral_coin, NotCollateral);
        let amount = liquidity_coin.value();
        let loan_days = (clock.timestamp_ms() - borrower.date)/86_400_000;
        let dec = pow(10, pool.decimals);
        let repayment_amount = ((borrower.amount - borrower.amount_payed)  * (pool.interest_rate  / (100 * dec)) * ((loan_days * dec)/(365 * dec))) + (borrower.amount - borrower.amount_payed);
        assert!(amount > repayment_amount, AmountMoreThanBorrowed);
        let coin_balance  = coin::into_balance(liquidity_coin);//liquidity_coin.into_balance();
        let collateral_value = pool.total_collateral.borrow_mut(c_coin_type.into_string()).value();
        if (amount == repayment_amount) {
            balance::join(&mut pool.total_liquidity, coin_balance);
            let collateral_coin = coin::take(pool.total_collateral.borrow_mut(c_coin_type.into_string()), collateral_value, ctx);
            transfer::public_transfer(collateral_coin, ctx.sender());

            borrower.amount_payed = borrower.amount;
            borrower.loan_payed = true;
        } else{
            balance::join(&mut pool.total_liquidity, coin_balance);
            let per = amount*dec/(borrower.amount - borrower.amount_payed) * 100;
            let amt = ((per / 100) * collateral_value)/dec;
            let collateral_coin = coin::take(pool.total_collateral.borrow_mut(c_coin_type.into_string()), amt, ctx);
            transfer::public_transfer(collateral_coin, ctx.sender());

            borrower.amount_payed = borrower.amount_payed + amount;
        }
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
}