#[test_only]
#[allow(deprecated_usage)]
module final_contract::lottery_tests {
    use final_contract::no_rake_lotto::{Self, Lottery, Ticket, AdminCap};
    use sui::sui::SUI;
    use sui::coin;
    use sui::test_scenario::{Self, Scenario};
    use std::hash::{sha2_256};
    use sui::bcs;
    use sui::clock;
    use sui::test_utils;
    use sui::random::{Self, Random};

    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA1;
    const BOB: address = @0xB0;
    const CHARLIE: address = @0xC4; 
    const DANA: address = @0xDA;

    const CANCELLATION_PERIOD_MS: u64 = 43_200_000;



    fun setup(scenario: &mut Scenario): (Lottery, clock::Clock, AdminCap, Random) {
        test_scenario::next_tx(scenario, ADMIN);
        no_rake_lotto::test_init(test_scenario::ctx(scenario));
        
        //create random
        test_scenario::next_tx(scenario, @0x0);
        random::create_for_testing(test_scenario::ctx(scenario));

        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        
        test_scenario::next_tx(scenario, ADMIN);
        let lottery = test_scenario::take_shared<Lottery>(scenario);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        let r = test_scenario::take_shared<Random>(scenario);
        (lottery, clock, admin_cap, r)
    }
    



    #[test]
    fun test_set_when_can_end() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, clock, admin_cap, r) = setup(&mut scenario);
        
        let new_time = 120_000; //2 minutes
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::set_when_can_end(&admin_cap, &mut lottery, new_time);
        
        assert!(no_rake_lotto::get_when_can_end(&lottery) == new_time, 0);

        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }

    #[test]
    fun test_set_when_can_cancel() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, clock, admin_cap, r) = setup(&mut scenario);
        
        let new_time = 86_400_000; //24 hours
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::set_when_can_cancel(&admin_cap, &mut lottery, new_time);
        
        assert!(no_rake_lotto::get_when_can_cancel(&lottery) == new_time, 0);

        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }


    #[test]
    fun test_full_cycle_successful_draw() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap, mut r) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, &clock);
        assert!(no_rake_lotto::current_round(&lottery) == 1, 0);

        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, BOB);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

        clock::increment_for_testing(&mut clock, 60_000);

        test_scenario::next_tx(&mut scenario, @0x0);
        //update random for next round (simulated)
        random::update_randomness_state_for_testing(
            &mut r,
            0,
            b"test_randomness",
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::next_tx(&mut scenario, ADMIN);

        no_rake_lotto::draw_winner_and_start_next_round(
            &mut lottery, &r, &clock, test_scenario::ctx(&mut scenario)
        );

        //we cannot predict the winner easily with random module test utils without deeper setup, so we just verify someone won
        let winning_number_from_receipt = no_rake_lotto::get_receipt_winning_number(&lottery, 1);
        assert!(winning_number_from_receipt > 0, 4);

        //Assume ALICE or BOB won, try to claim. 
        //In a real generic test we might iterate or check events. 
        //For simplicity, just end here or assumes successful draw is enough.
        //If we want to test claim, we need to know who won.
        
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }

    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_CLOSABLE_YET)]
    fun test_cannot_draw_too_early() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap, r) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, &clock);

        clock::increment_for_testing(&mut clock, 30_000); 
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &mut lottery, &r, &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }

    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_EXPIRED)]
    fun test_draw_fails_after_cancellation_period() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap, mut r) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);

        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, &clock);

        clock::increment_for_testing(&mut clock, CANCELLATION_PERIOD_MS);
        
        test_scenario::next_tx(&mut scenario, CHARLIE);
        no_rake_lotto::cancel_round(&mut lottery, &clock, test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, @0x0);
        random::update_randomness_state_for_testing(
            &mut r,
            0,
            b"test_randomness",
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &mut lottery, &r, &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }

    #[test]
    fun test_cancel_round_and_claim_refunds() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap, r) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);

        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, &clock);

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
        test_scenario::return_shared(r);
        scenario.end();
    }

    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_CANCELLABLE_YET)]
    fun test_cannot_cancel_too_early() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap, r) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);

        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, &clock);

        clock::increment_for_testing(&mut clock, CANCELLATION_PERIOD_MS - 1000);
        
        test_scenario::next_tx(&mut scenario, CHARLIE);
        no_rake_lotto::cancel_round(&mut lottery, &clock, test_scenario::ctx(&mut scenario));
        
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }


    ///tests that a player cannot enter a lottery that is paused (right after creation)
    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_STARTED)]
    fun test_cannot_enter_paused_lottery() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, clock, admin_cap, r) = setup(&mut scenario);

        //try to enter immediately, before start_round is called
        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

        //clean
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }

    ///tests that the admin cannot draw a winner if the pool is too small to pay their commission


    ///tests that a player cannot claim a refund for a round that was successfully completed (not canceled)
    #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_CANCELED)]
    fun test_cannot_claim_refund_for_valid_round() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap, mut r) = setup(&mut scenario);

        clock::set_for_testing(&mut clock, 1000);
        
        //start and play round 1
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, &clock);
        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, BOB);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

        //draw the winner for round 1 successfully
        clock::increment_for_testing(&mut clock, 60_000);
        test_scenario::next_tx(&mut scenario, @0x0);
        random::update_randomness_state_for_testing(
            &mut r,
            0,
            b"test_randomness",
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &mut lottery, &r, &clock, test_scenario::ctx(&mut scenario)
        );

        //now bob(a loser from round 1) tries to claim a refund. this should fail
        test_scenario::next_tx(&mut scenario, BOB);
        let bobs_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
        no_rake_lotto::claim_refund(&mut lottery, bobs_ticket, test_scenario::ctx(&mut scenario));

        //cleanup
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }

    ///tests that the contract state resets correctly and works for a second round
    #[test]
    fun test_full_cycle_for_round_two() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut lottery, mut clock, admin_cap, mut r) = setup(&mut scenario);

        //round 1
        clock::set_for_testing(&mut clock, 1000);
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::start_round(&admin_cap, &mut lottery, &clock);
        test_scenario::next_tx(&mut scenario, ALICE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        
        clock::increment_for_testing(&mut clock, 60_000);
        test_scenario::next_tx(&mut scenario, @0x0);
        random::update_randomness_state_for_testing(
            &mut r,
            0,
            b"test_randomness",
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &mut lottery, &r, &clock, test_scenario::ctx(&mut scenario)
        );
        assert!(no_rake_lotto::current_round(&lottery) == 2, 0);

        //round 2
        test_scenario::next_tx(&mut scenario, CHARLIE);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(5_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, DANA);
        no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(5_000_000_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
        assert!(no_rake_lotto::current_pool_value(&lottery) == 10_000_000_000, 1);
        
        clock::increment_for_testing(&mut clock, 60_000);
        test_scenario::next_tx(&mut scenario, @0x0);
        random::update_randomness_state_for_testing(
            &mut r,
            1,
            b"test_randomness_2",
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::next_tx(&mut scenario, ADMIN);
        no_rake_lotto::draw_winner_and_start_next_round(
            &mut lottery, &r, &clock, test_scenario::ctx(&mut scenario)
        );
        
        //check winner of round 2
        let winner_2_num = no_rake_lotto::get_receipt_winning_number(&lottery, 2);
        assert!(winner_2_num > 0, 2);

        //cleanup
        test_scenario::return_shared(lottery);
        test_utils::destroy(admin_cap);
        test_utils::destroy(clock);
        test_scenario::return_shared(r);
        scenario.end();
    }
}
