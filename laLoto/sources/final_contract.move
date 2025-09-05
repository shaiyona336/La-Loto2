module final_contract::no_rake_lotto {
    use sui::bcs;
    use std::hash::{sha2_256};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::dynamic_field;
    use sui::event;
    use sui::clock::{Self, Clock};  // Import Clock
    
    //Structs
    //lottery ticket players buy
    public struct Ticket has key, store {
        id: UID,
        lottery_id: ID,
        round: u64,
        start_number: u64,
        end_number: u64,
    }
    
    //when lottery ends, create recipt so winning ticket can claim prize
    public struct LotteryReceipt has key, store {
        id: UID,
        lottery_id: ID,
        round: u64,
        prize_pool: Balance<SUI>,
        winning_number: u64,
        prize_claimed: bool,
        was_canceled: bool,
    }
    
    //current lottery
    public struct Lottery has key {
        id: UID,
        current_pool: Balance<SUI>,
        current_round: u64,
        round_start_timestamp: u64,
        randomness_commitment: vector<u8>,
        pause: bool,
        admin_commission: u64,
        ///the time admin has to draw a winner before the round can be canceled by anyone.
        when_can_end: u64,
        when_can_cancel: u64,
    }

    //object for admin privileges
    public struct AdminCap has key, store {
        id: UID
    }
    
    //Events
    public struct RoundCompleted has copy, drop { round: u64, winning_number: u64, prize_pool: u64 }
    public struct RoundCanceled has copy, drop { round: u64, prize_pool: u64 }
    public struct PrizeClaimed has copy, drop { winner: address, prize: u64, round: u64 }
    public struct RefundClaimed has copy, drop { player: address, amount: u64, round: u64 }
    
    //Errors
    const E_LOTTERY_IS_EMPTY: u64 = 0;
    const E_ROUND_NOT_CLOSABLE_YET: u64 = 1;
    const E_NOT_WINNING_TICKET: u64 = 3;
    const E_PRIZE_ALREADY_CLAIMED: u64 = 4;
    const E_WRONG_LOTTERY_ROUND: u64 = 5;
    const E_INVALID_COMMITMENT: u64 = 7;
    const E_ROUND_NOT_STARTED: u64 = 9;
    const E_ROUND_ALREADY_STARTED: u64 = 10;
    const E_ROUND_EXPIRED: u64 = 11;
    const E_ROUND_NOT_CANCELLABLE_YET: u64 = 12;
    const E_ROUND_NOT_CANCELED: u64 = 13;
    const E_POOL_TOO_SMALL_FOR_COMMISSION: u64 = 14;
    const E_COMMISSION_NOT_SET: u64 = 15;

    //Functions
    //functions to potentially set variables in the future
    entry fun set_admin_commission(
        _cap: &AdminCap,
        lottery: &mut Lottery, 
        new_commission: u64
    ) {
        lottery.admin_commission = new_commission;
    }

    entry fun set_when_can_end(
        _cap: &AdminCap,
        lottery: &mut Lottery, 
        when_can_end: u64
    ) {
        lottery.when_can_end = when_can_end;
    }

    entry fun set_when_can_cancel(
        _cap: &AdminCap,
        lottery: &mut Lottery, 
        when_can_cancel: u64
    ) {
        lottery.when_can_cancel = when_can_cancel;
    }
    //functions to initialize smart contract
    //seperated create_lottery from init to allow test to create lottery
    fun create_lottery(ctx: &mut TxContext) {
        //the one that created the lottery has admin privileges
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        //create lottery
        let lottery = Lottery {
            id: object::new(ctx),
            current_pool: balance::zero(),
            current_round: 0,
            round_start_timestamp: 0,
            randomness_commitment: vector[],
            pause: true,
            admin_commission: 2_000_000, //default 0.002 SUI
            when_can_end: 60_000, //minute
            when_can_cancel: 43_200_000 //12 hours
        };
        transfer::share_object(lottery);
    }
    
    fun init(ctx: &mut TxContext) {
        create_lottery(ctx);
    }

    public(package) fun test_init(ctx: &mut TxContext) {
        create_lottery(ctx);
    }

    entry fun start_round(
        _cap: &AdminCap,
        lottery: &mut Lottery,
        round_commitment: vector<u8>,
        clock: &Clock,
    ) {
        assert!(lottery.pause == true, E_ROUND_ALREADY_STARTED);
        lottery.current_round = lottery.current_round + 1;
        lottery.round_start_timestamp = clock::timestamp_ms(clock);
        lottery.randomness_commitment = round_commitment;
        lottery.pause = false;
    }

    public fun enter(lottery: &mut Lottery, ticket_coin: Coin<SUI>, ctx: &mut TxContext) {
        assert!(lottery.pause == false, E_ROUND_NOT_STARTED);
        //write and then read, solves race condition
        let deposit_value = coin::value(&ticket_coin);
        let deposit_balance = coin::into_balance(ticket_coin);
        balance::join(&mut lottery.current_pool, deposit_balance);
        let pool_value_after_join = balance::value(&lottery.current_pool);
        
        let ticket = Ticket {
            id: object::new(ctx),
            lottery_id: object::id(lottery),
            round: lottery.current_round,
            start_number: pool_value_after_join - deposit_value + 1,
            end_number: pool_value_after_join,
        };
        transfer::transfer(ticket, tx_context::sender(ctx));
    }

    fun draw_winner(
        _cap: &AdminCap,
        lottery: &mut Lottery,
        secret_number: u64,
        secret_salt: vector<u8>,
        next_round_commitment: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!lottery.pause, E_ROUND_EXPIRED);
        assert!(vector::length(&lottery.randomness_commitment) > 0, E_ROUND_NOT_STARTED);
        
        let current_time = clock::timestamp_ms(clock);
        //need enough time between rounds
        assert!(current_time >= lottery.round_start_timestamp + lottery.when_can_end, E_ROUND_NOT_CLOSABLE_YET);
        //admin reveal secret_number+secret_hash, smart contract verify it is match original hash
        let mut secret_bytes = bcs::to_bytes(&secret_number);
        vector::append(&mut secret_bytes, secret_salt);
        let revealed_hash = sha2_256(secret_bytes);
        assert!(revealed_hash == lottery.randomness_commitment, E_INVALID_COMMITMENT);
        //check that commision defined and pool big enough to pay it
        let total_pool_value = balance::value(&lottery.current_pool);
        assert!(total_pool_value >= lottery.admin_commission * 2, E_POOL_TOO_SMALL_FOR_COMMISSION);
        //pay commission to admin running this script
        let commission_balance = balance::split(&mut lottery.current_pool, lottery.admin_commission);
        let commission_coin = coin::from_balance(commission_balance, ctx);
        //sender has admin cap so got to be admin
        transfer::public_transfer(commission_coin, tx_context::sender(ctx));

        let prize_pool_value  = balance::value(&lottery.current_pool);
        assert!(prize_pool_value  > 0, E_LOTTERY_IS_EMPTY);

        let winning_number = (secret_number % total_pool_value) + 1;

        let prize_balance = balance::split(&mut lottery.current_pool, prize_pool_value );
        let receipt = LotteryReceipt {
            id: object::new(ctx),
            lottery_id: object::id(lottery),
            round: lottery.current_round,
            prize_pool: prize_balance,
            winning_number,
            prize_claimed: false,
            was_canceled: false,
        };
        //connect receipt to lottery in efficient way
        dynamic_field::add(&mut lottery.id, lottery.current_round, receipt);
        //notify round ended
        event::emit(RoundCompleted { round: lottery.current_round, winning_number, prize_pool: prize_pool_value });
        
    }

    //allow to stop lottery for maintanance
    entry fun draw_winner_and_close_for_maintanance(
        _cap: &AdminCap,
        lottery: &mut Lottery,
        secret_number: u64,
        secret_salt: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
        ) {
        draw_winner(_cap, lottery, secret_number, secret_salt, vector[], clock, ctx);
        //reset
        lottery.pause = true;
    }


    entry fun draw_winner_and_start_next_round(
        _cap: &AdminCap,
        lottery: &mut Lottery,
        secret_number: u64,
        secret_salt: vector<u8>,
        next_round_commitment: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        draw_winner(_cap, lottery, secret_number, secret_salt, next_round_commitment, clock, ctx);
        //reset
        let current_time = clock::timestamp_ms(clock);
        lottery.current_round = lottery.current_round + 1;
        lottery.round_start_timestamp = current_time;
        lottery.randomness_commitment = next_round_commitment;
    }
    
    //in a scenario that the admin gone offline and didnt ended the lottery for a long time, allow players to cancel current lottery for refund
    entry fun cancel_round(
        lottery: &mut Lottery, 
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&lottery.randomness_commitment) > 0, E_ROUND_NOT_STARTED);
        
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= lottery.round_start_timestamp + lottery.when_can_cancel, E_ROUND_NOT_CANCELLABLE_YET);
        
        let total_pool_value = balance::value(&lottery.current_pool);
        //empty original pool for the refunded pool
        let prize_balance = balance::split(&mut lottery.current_pool, total_pool_value);
        //create the receipt people can query for refund
        let receipt = LotteryReceipt {
            id: object::new(ctx),
            lottery_id: object::id(lottery),
            round: lottery.current_round,
            prize_pool: prize_balance,
            winning_number: 0,
            prize_claimed: false,
            was_canceled: true,
        };
        dynamic_field::add(&mut lottery.id, lottery.current_round, receipt);
        //notify round canceled
        event::emit(RoundCanceled { round: lottery.current_round, prize_pool: total_pool_value });
        //reset
        lottery.round_start_timestamp = 0;
        lottery.randomness_commitment = vector[];
        lottery.pause = true;
    }
    
    entry fun claim_refund(lottery: &mut Lottery, ticket: Ticket, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        //we save using dynamic_field(lottery.id,lottery.current_round,receipt), current_round match ticker_round, now we extract receipt from ticket.round
        let receipt: &mut LotteryReceipt = dynamic_field::borrow_mut(&mut lottery.id, ticket.round);

        assert!(receipt.was_canceled, E_ROUND_NOT_CANCELED);
        let refund_amount = ticket.end_number - ticket.start_number + 1;
        //get Balance<T> with amount to refund
        let refund_balance = balance::split(&mut receipt.prize_pool, refund_amount);
        //create coin from balance
        let refund_coin = coin::from_balance(refund_balance, ctx);
        //send player
        transfer::public_transfer(refund_coin, sender);
        //notify refund
        event::emit(RefundClaimed { player: sender, amount: refund_amount, round: ticket.round });
        //destroy ticket after refund
        let Ticket { id, lottery_id: _, round: _, start_number: _, end_number: _ } = ticket;
        object::delete(id);
    }
    
    entry fun claim_prize(lottery: &mut Lottery, winning_ticket: Ticket, ctx: &mut TxContext) {
        let round = winning_ticket.round;
        let receipt: &mut LotteryReceipt = dynamic_field::borrow_mut(&mut lottery.id, round);
        
        assert!(!receipt.was_canceled, E_ROUND_NOT_CANCELED);
        assert!(!receipt.prize_claimed, E_PRIZE_ALREADY_CLAIMED);
        assert!(winning_ticket.round == receipt.round, E_WRONG_LOTTERY_ROUND);
        assert!(receipt.winning_number >= winning_ticket.start_number && receipt.winning_number <= winning_ticket.end_number, E_NOT_WINNING_TICKET);
        
        let winner_address = tx_context::sender(ctx);
        let prize_amount = balance::value(&receipt.prize_pool);
        let prize_balance = balance::split(&mut receipt.prize_pool, prize_amount);
        let prize_coin = coin::from_balance(prize_balance, ctx);
        transfer::public_transfer(prize_coin, winner_address);
        receipt.prize_claimed = true;
        //notify prize claimed
        event::emit(PrizeClaimed { winner: winner_address, prize: prize_amount, round: receipt.round });
        //destroy ticket after claimed prize
        let Ticket { id, lottery_id: _, round: _, start_number: _, end_number: _ } = winning_ticket;
        object::delete(id);
    }

    //Tests
    #[test_only]
    public(package) fun current_pool_value(lottery: &Lottery): u64 { balance::value(&lottery.current_pool) }
    #[test_only]
    public(package) fun current_round(lottery: &Lottery): u64 { lottery.current_round }
    #[test_only]
    public(package) fun get_receipt_winning_number(lottery: &Lottery, round: u64): u64 {
        let receipt: &LotteryReceipt = dynamic_field::borrow(&lottery.id, round);
        receipt.winning_number
    }
    #[test_only]
    public(package) fun get_commission(lottery: &Lottery): u64 { lottery.admin_commission }

     #[test_only]
    public(package) fun get_when_can_end(lottery: &Lottery): u64 {
        lottery.when_can_end
    }

    #[test_only]
    public(package) fun get_when_can_cancel(lottery: &Lottery): u64 {
        lottery.when_can_cancel
    }
}