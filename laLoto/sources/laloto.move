// Filename: sources/laloto.move

// The module declaration must match the name in your Sui.toml ([addresses] laloto = "0x0")
module laloto::no_rake_lotto {
    // --- Imports (Cleaned up to remove all warnings) ---
    use sui::sui::SUI;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::random::{Self, Random, new_generator};
    use sui::clock::{Self, Clock};

    // --- Structs ---
    public struct Player has store, drop {
        address: address,
        deposit_amount: u64,
    }

    public struct Lottery has key {
        id: UID,
        players: vector<Player>,
        total_pool: Balance<SUI>,
        round: u64,
        last_draw_timestamp: u64,
    }

    // --- Errors & Constants ---
    const E_LOTTERY_IS_EMPTY: u64 = 0;
    const E_TOO_EARLY_TO_DRAW: u64 = 1;
    const SIXTY_SECONDS_MS: u64 = 60_000;
    const FEE_REIMBURSEMENT_MIST: u64 = 5_000_000; // 0.005 SUI

    // --- Functions ---
    fun init(ctx: &mut TxContext) {
        let lottery = Lottery {
            id: object::new(ctx),
            players: vector[],
            total_pool: balance::zero(),
            round: 1,
            last_draw_timestamp: 0,
        };
        transfer::share_object(lottery);
    }

    public fun enter(lottery: &mut Lottery, ticket: Coin<SUI>, ctx: &mut TxContext) {
        let deposit_value = coin::value(&ticket);
        let deposit_balance = coin::into_balance(ticket);
        let new_player = Player {
            address: tx_context::sender(ctx),
            deposit_amount: deposit_value,
        };
        vector::push_back(&mut lottery.players, new_player);
        balance::join(&mut lottery.total_pool, deposit_balance);
    }

    // FIX: Changed to simply 'entry fun'. This is the correct syntax for a function
    // that is callable from a transaction but is private to other contracts.
    entry fun draw_winner(lottery: &mut Lottery, random: &Random, clock: &Clock, ctx: &mut TxContext) {
        assert!(
            clock::timestamp_ms(clock) >= lottery.last_draw_timestamp + SIXTY_SECONDS_MS,
            E_TOO_EARLY_TO_DRAW
        );

        let total_pool_value = balance::value(&lottery.total_pool);
        assert!(total_pool_value > FEE_REIMBURSEMENT_MIST, E_LOTTERY_IS_EMPTY);

        let sender = tx_context::sender(ctx);
        let fee_balance = balance::split(&mut lottery.total_pool, FEE_REIMBURSEMENT_MIST);
        let fee_coin = coin::from_balance(fee_balance, ctx);
        transfer::public_transfer(fee_coin, sender);

        let remaining_pool_value = balance::value(&lottery.total_pool);
        assert!(vector::length(&lottery.players) > 0, E_LOTTERY_IS_EMPTY);

        let mut generator = new_generator(random, ctx);
        let winning_number = random::generate_u64_in_range(&mut generator, 1, remaining_pool_value);

        let mut winner_address: address = @0x0;
        let mut current_ticket_boundary: u64 = 0;
        let mut i = 0;
        let len = vector::length(&lottery.players);

        while (i < len) {
            let player = vector::borrow(&lottery.players, i);
            current_ticket_boundary = current_ticket_boundary + player.deposit_amount;
            if (winning_number <= current_ticket_boundary) {
                winner_address = player.address;
                // FIX: Removed unnecessary semicolon after 'break'
                break
            };
            i = i + 1;
        };

        let prize = balance::split(&mut lottery.total_pool, remaining_pool_value);
        let prize_coin = coin::from_balance(prize, ctx);
        transfer::public_transfer(prize_coin, winner_address);

        lottery.players = vector[];
        lottery.round = lottery.round + 1;
        lottery.last_draw_timestamp = clock::timestamp_ms(clock);
    }
}
