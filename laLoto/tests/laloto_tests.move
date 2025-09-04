// #[test_only]
// module final_contract::lottery_tests {
//     use final_contract::no_rake_lotto::{Self, Lottery, Ticket};
//     use sui::sui::SUI;
//     use sui::coin;
//     use sui::test_scenario::{Self, Scenario};
//     use std::hash::{sha2_256};
//     use sui::bcs;
//     use sui::clock;
//     use sui::test_utils;

//     const ADMIN: address = @0xAD;
//     const ALICE: address = @0xA1;
//     const BOB: address = @0xB0;
//     const CHARLIE: address = @0xC4; 

//     const CANCELLATION_PERIOD_MS: u64 = 43_200_000;

//     fun calculate_commitment(secret: u64, salt: vector<u8>): vector<u8> {
//         let mut secret_bytes = bcs::to_bytes(&secret);
//         std::vector::append(&mut secret_bytes, salt);
//         sha2_256(secret_bytes)
//     }

//     fun setup(scenario: &mut Scenario): (Lottery, clock::Clock) {
//         test_scenario::next_tx(scenario, ADMIN);
//         no_rake_lotto::test_init(test_scenario::ctx(scenario));
        
//         // Create a test clock starting at timestamp 0
//         let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        
//         test_scenario::next_tx(scenario, ADMIN);
//         let lottery = test_scenario::take_shared<Lottery>(scenario);
//         (lottery, clock)
//     }

//     #[test]
//     fun test_full_cycle_successful_draw() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         let (mut lottery, mut clock) = setup(&mut scenario);

//         // Set initial time
//         clock::set_for_testing(&mut clock, 1000);
        
//         let secret_1: u64 = 123;
//         let salt_1: vector<u8> = b"s1";
//         let commitment_1 = calculate_commitment(secret_1, salt_1);

//         let secret_2: u64 = 456;
//         let salt_2: vector<u8> = b"s2";
//         let commitment_2 = calculate_commitment(secret_2, salt_2);
        
//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::start_round(&mut lottery, commitment_1, &clock, test_scenario::ctx(&mut scenario));
//         assert!(no_rake_lotto::current_round(&lottery) == 1, 0);

//         test_scenario::next_tx(&mut scenario, ALICE);
//         no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
//         test_scenario::next_tx(&mut scenario, BOB);
//         no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

//         // Advance time by at least LAST_LOTTERY_PERIOD_MS
//         clock::increment_for_testing(&mut clock, 60_000);
        
//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::draw_winner_and_start_next_round(
//             &mut lottery, secret_1, salt_1, commitment_2, &clock, test_scenario::ctx(&mut scenario)
//         );

//         let expected_winning_number = (secret_1 % 3000) + 1;
//         let winning_number_from_receipt = no_rake_lotto::get_receipt_winning_number(&lottery, 1);
//         assert!(winning_number_from_receipt == expected_winning_number, 4);

//         test_scenario::next_tx(&mut scenario, ALICE);
//         let winning_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
//         no_rake_lotto::claim_prize(&mut lottery, winning_ticket, test_scenario::ctx(&mut scenario));
        
//         test_scenario::return_shared(lottery);
//         test_utils::destroy(clock);
//         scenario.end();
//     }

//     #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_CLOSABLE_YET)]
//     fun test_cannot_draw_too_early() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         let (mut lottery, mut clock) = setup(&mut scenario);

//         clock::set_for_testing(&mut clock, 1000);
        
//         let commitment = calculate_commitment(123, b"salt");
        
//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::start_round(&mut lottery, commitment, &clock, test_scenario::ctx(&mut scenario));

//         // Try to draw immediately without advancing time enough
//         clock::increment_for_testing(&mut clock, 30_000); // Only 30 seconds, need 60
        
//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::draw_winner_and_start_next_round(
//             &mut lottery, 123, b"salt", vector[], &clock, test_scenario::ctx(&mut scenario)
//         );
        
//         test_scenario::return_shared(lottery);
//         test_utils::destroy(clock);
//         scenario.end();
//     }

//     #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_EXPIRED)]
//     fun test_draw_fails_after_cancellation_period() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         let (mut lottery, mut clock) = setup(&mut scenario);

//         clock::set_for_testing(&mut clock, 1000);
//         let commitment = calculate_commitment(123, b"some salt");

//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::start_round(&mut lottery, commitment, &clock, test_scenario::ctx(&mut scenario));

//         // Advance time past cancellation period
//         clock::increment_for_testing(&mut clock, CANCELLATION_PERIOD_MS);
        
//         // Cancel the round first (sets pause to true)
//         test_scenario::next_tx(&mut scenario, CHARLIE);
//         no_rake_lotto::cancel_round(&mut lottery, &clock, test_scenario::ctx(&mut scenario));
        
//         // Now admin tries to draw after cancellation - should fail
//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::draw_winner_and_start_next_round(
//             &mut lottery, 123, b"some salt", vector[], &clock, test_scenario::ctx(&mut scenario)
//         );
        
//         test_scenario::return_shared(lottery);
//         test_utils::destroy(clock);
//         scenario.end();
//     }

//     #[test]
//     fun test_cancel_round_and_claim_refunds() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         let (mut lottery, mut clock) = setup(&mut scenario);

//         clock::set_for_testing(&mut clock, 1000);
//         let commitment = calculate_commitment(123, b"another salt");

//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::start_round(&mut lottery, commitment, &clock, test_scenario::ctx(&mut scenario));

//         test_scenario::next_tx(&mut scenario, ALICE);
//         no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
//         test_scenario::next_tx(&mut scenario, BOB);
//         no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
//         assert!(no_rake_lotto::current_pool_value(&lottery) == 3000, 1);
        
//         // Advance time past cancellation period
//         clock::increment_for_testing(&mut clock, CANCELLATION_PERIOD_MS);
        
//         test_scenario::next_tx(&mut scenario, CHARLIE);
//         no_rake_lotto::cancel_round(&mut lottery, &clock, test_scenario::ctx(&mut scenario));
        
//         assert!(no_rake_lotto::current_round(&lottery) == 1, 2);
//         assert!(no_rake_lotto::current_pool_value(&lottery) == 0, 3);

//         test_scenario::next_tx(&mut scenario, ALICE);
//         let alices_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
//         no_rake_lotto::claim_refund(&mut lottery, alices_ticket, test_scenario::ctx(&mut scenario));

//         test_scenario::next_tx(&mut scenario, BOB);
//         let bobs_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
//         no_rake_lotto::claim_refund(&mut lottery, bobs_ticket, test_scenario::ctx(&mut scenario));

//         test_scenario::return_shared(lottery);
//         test_utils::destroy(clock);
//         scenario.end();
//     }

//     #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_NOT_CANCELLABLE_YET)]
//     fun test_cannot_cancel_too_early() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         let (mut lottery, mut clock) = setup(&mut scenario);

//         clock::set_for_testing(&mut clock, 1000);
//         let commitment = calculate_commitment(123, b"salt");

//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::start_round(&mut lottery, commitment, &clock, test_scenario::ctx(&mut scenario));

//         // Try to cancel before cancellation period
//         clock::increment_for_testing(&mut clock, CANCELLATION_PERIOD_MS - 1000);
        
//         test_scenario::next_tx(&mut scenario, CHARLIE);
//         no_rake_lotto::cancel_round(&mut lottery, &clock, test_scenario::ctx(&mut scenario));
        
//         test_scenario::return_shared(lottery);
//         test_utils::destroy(clock);
//         scenario.end();
//     }
// }