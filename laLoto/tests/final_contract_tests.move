#[test_only]
module final_contract::lottery_tests {
    use final_contract::no_rake_lotto::{Self, Lottery, Ticket, AdminCap};
    use sui::sui::SUI;
    use sui::coin;
    use sui::test_scenario::{Self, Scenario};
    use std::hash::{sha2_256};
    use sui::bcs;
    use sui::clock;
    use sui::test_utils;

    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA1;
    const BOB: address = @0xB0;
    const CHARLIE: address = @0xC4; 
    const DANA: address = @0xDA;

    const CANCELLATION_PERIOD_MS: u64 = 43_200_000;

    fun calculate_commitment(secret: u64, salt: vector<u8>): vector<u8> {
        let mut secret_bytes = bcs::to_bytes(&secret);
        std::vector::append(&mut secret_bytes, salt);
        sha2_256(secret_bytes)
    }

    fun setup(scenario: &mut Scenario): (Lottery, clock::Clock, AdminCap) {
        test_scenario::next_tx(scenario, ADMIN);
        no_rake_lotto::test_init(test_scenario::ctx(scenario));
        
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        
        test_scenario::next_tx(scenario, ADMIN);
        let lottery = test_scenario::take_shared<Lottery>(scenario);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        (lottery, clock, admin_cap)
    }
    

    #[test]
    fun test_set_admin_commission() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, clock, admin_cap) = setup(&mut scenario);
        
        let new_fee = 500_000_000; // 0.5 SUI
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::set_admin_commission(&admin_cap, &mut lottery, new_fee);
        
        assert!(no_rake_lotto::get_commission(&lottery) == new_fee, 0);

        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    #[test]
    fun test_set_when_can_end() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, clock, admin_cap) = setup(&mut scenario);
        
        let new_time = 120_000; // 2 minutes
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::set_when_can_end(&admin_cap, &mut lottery, new_time);
        
        assert!(no_rake_lotto::get_when_can_end(&lottery) == new_time, 0);

        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    #[test]
    fun test_set_when_can_cancel() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, clock, admin_cap) = setup(&mut scenario);
        
        let new_time = 86_400_000; // 24 hours
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::set_when_can_cancel(&admin_cap, &mut lottery, new_time);
        
        assert!(no_rake_lotto::get_when_can_cancel(&lottery) == new_time, 0);

        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }


    #[test]
    fun test_full_cycle_successful_draw() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        
        let secret_1: u64 = 123;
        let salt_1: vector<u8> = b"s1";
        let commitment_1 = calculate_commitment(secret_1, salt_1);
        let secret_2: u64 = 456;
        let salt_2: vector<u8> = b"s2";
        let commitment_2 = calculate_commitment(secret_2, salt_2);
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, commitment_1, &clock);
        assert!(no_rake_lotto::current_round(&lottery) == 1, 0);

        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, BOB);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

        clock::increment_for_testing(&mut clock, 60_000);

        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &admin_cap, &mut lottery, secret_1, salt_1, commitment_2, &clock, test_scenario::ctx(&mut scenario)
        );

        let expected_winning_number = (secret_1 % 3_000_000_000) + 1;
        let winning_number_from_receipt = no_rake_lotto::get_receipt_winning_number(&lottery, 1);
        assert!(winning_number_from_receipt == expected_winning_number, 4);

        test_scenario::next_tx(&mut scenario, ALICE);
        let winning_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
        no_rake_lotto::claim_prize(&mut lottery, winning_ticket, test_scenario::ctx(&mut scenario));
        
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_CLOSABLE_YET)]
    fun test_cannot_draw_too_early() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        
        let commitment = calculate_commitment(123, b"salt");
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, commitment, &clock);

        clock::increment_for_testing(&mut clock, 30_000); 
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &admin_cap, &mut lottery, 123, b"salt", vector[], &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_EXPIRED)]
    fun test_draw_fails_after_cancellation_period() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        let commitment = calculate_commitment(123, b"some salt");

        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, commitment, &clock);

        clock::increment_for_testing(&mut clock, CANCELLATION_PERIOD_MS);
        
        test_scenario::next_tx(&mut scenario, CHARLIE);
        no_rake_lotto::cancel_round(&mut lottery, &clock, test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &admin_cap, &mut lottery, 123, b"some salt", vector[], &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    #[test]
    fun test_cancel_round_and_claim_refunds() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        let commitment = calculate_commitment(123, b"another salt");

        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, commitment, &clock);

        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, BOB);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        assert!(no_rake_lotto::current_pool_value(&lottery) == 3_000_000_000, 1);
        
        clock::increment_for_testing(&mut clock, CANCELLATION_PERIOD_MS);
        
        test_scenario::next_tx(&mut scenario, CHARLIE);
        no_rake_lotto::cancel_round(&mut lottery, &clock, test_scenario::ctx(&mut scenario));
        
        assert!(no_rake_lotto::current_round(&lottery) == 1, 2);
        assert!(no_rake_lotto::current_pool_value(&lottery) == 0, 3);

        test_scenario::next_tx(&mut scenario, ALICE);
        let alices_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
        no_rake_lotto::claim_refund(&mut lottery, alices_ticket, test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, BOB);
        let bobs_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
        no_rake_lotto::claim_refund(&mut lottery, bobs_ticket, test_scenario::ctx(&mut scenario));

        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_CANCELLABLE_YET)]
    fun test_cannot_cancel_too_early() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        let commitment = calculate_commitment(123, b"salt");

        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, commitment, &clock);

        clock::increment_for_testing(&mut clock, CANCELLATION_PERIOD_MS - 1000);
        
        test_scenario::next_tx(&mut scenario, CHARLIE);
        no_rake_lotto::cancel_round(&mut lottery, &clock, test_scenario::ctx(&mut scenario));
        
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }


    /// Tests that a player cannot enter a lottery that is paused (e.g., right after creation).
    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_STARTED)]
    fun test_cannot_enter_paused_lottery() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, clock, admin_cap) = setup(&mut scenario);

        // Try to enter immediately, before start_round is called
        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

        // Cleanup
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    /// Tests that the admin cannot draw a winner if the pool is too small to pay their commission.
    #[test, expected_failure(abort_code = no_rake_lotto::E_POOL_TOO_SMALL_FOR_COMMISSION)]
    fun test_draw_fails_if_pool_too_small_for_commission() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap) = setup(&mut scenario);

        // 1. Admin sets a commission that is larger than the potential prize pool
        let high_commission = 5_000_000_000; // 5 SUI
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::set_admin_commission(&admin_cap, &mut lottery, high_commission);

        // 2. Admin starts the round
        clock::set_for_testing(&mut clock, 1000);
        let commitment = calculate_commitment(123, b"salt");
        no_rake_lotto::start_round(&admin_cap, &mut lottery, commitment, &clock);

        // 3. A player enters with an amount smaller than 2x the commission
        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

        // 4. Admin tries to draw the winner - this should fail
        clock::increment_for_testing(&mut clock, 60_000);
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &admin_cap, &mut lottery, 123, b"salt", vector[], &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Cleanup
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    /// Tests that a player cannot claim a refund for a round that was successfully completed (not canceled).
    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_CANCELED)]
    fun test_cannot_claim_refund_for_valid_round() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        let commitment_1 = calculate_commitment(123, b"s1");
        let commitment_2 = calculate_commitment(456, b"s2");
        
        // Start and play round 1
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, commitment_1, &clock);
        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, BOB);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

        // Draw the winner for round 1 successfully
        clock::increment_for_testing(&mut clock, 60_000);
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &admin_cap, &mut lottery, 123, b"s1", commitment_2, &clock, test_scenario::ctx(&mut scenario)
        );

        // Now, Bob (a loser from round 1) tries to claim a refund. This should fail.
        test_scenario::next_tx(&mut scenario, BOB);
        let bobs_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
        no_rake_lotto::claim_refund(&mut lottery, bobs_ticket, test_scenario::ctx(&mut scenario));

        // Cleanup
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }

    /// Tests that the contract state resets correctly and works for a second round.
    #[test]
    fun test_full_cycle_for_round_two() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap) = setup(&mut scenario);

        // --- ROUND 1 ---
        clock::set_for_testing(&mut clock, 1000);
        let secret_1 = 123;
        let salt_1 = b"s1";
        let commitment_1 = calculate_commitment(secret_1, salt_1);
        let secret_2 = 456;
        let salt_2 = b"s2";
        let commitment_2 = calculate_commitment(secret_2, salt_2);
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, commitment_1, &clock);
        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        
        clock::increment_for_testing(&mut clock, 60_000);
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &admin_cap, &mut lottery, secret_1, salt_1, commitment_2, &clock, test_scenario::ctx(&mut scenario)
        );
        assert!(no_rake_lotto::current_round(&lottery) == 2, 0);

        // --- ROUND 2 ---
        // The previous call already started round 2 with commitment_2
        test_scenario::next_tx(&mut scenario, CHARLIE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(5_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, DANA);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(5_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        assert!(no_rake_lotto::current_pool_value(&lottery) == 10_000_000_000, 1);
        
        let commitment_3 = calculate_commitment(789, b"s3");
        clock::increment_for_testing(&mut clock, 60_000);
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &admin_cap, &mut lottery, secret_2, salt_2, commitment_3, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Check winner of ROUND 2
        // Total pool was 10000. Winning number = (456 % 10000) + 1 = 457. Charlie's ticket is 1-5000. Charlie wins.
        let winner_2_num = no_rake_lotto::get_receipt_winning_number(&lottery, 2);
        assert!(winner_2_num == 457, 2);

        // Charlie claims the prize
        test_scenario::next_tx(&mut scenario, CHARLIE);
        let charlies_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
        no_rake_lotto::claim_prize(&mut lottery, charlies_ticket, test_scenario::ctx(&mut scenario));

        // Cleanup
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        scenario.end();
    }
}
