// #[test_only]
// module imp_con::lottery_tests {
//     use imp_con::no_rake_lotto::{Self, Lottery, Ticket};
//     use sui::sui::SUI;
//     use sui::coin;
//     use sui::test_scenario::{Self, Scenario};
//     use std::hash::{sha2_256};
//     use sui::bcs;

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

//     fun setup(scenario: &mut Scenario): Lottery {
//         test_scenario::next_tx(scenario, ADMIN);
//         no_rake_lotto::test_init(test_scenario::ctx(scenario));
//         test_scenario::next_tx(scenario, ADMIN);
//         test_scenario::take_shared<Lottery>(scenario)
//     }

//     #[test]
//     fun test_full_cycle_successful_draw() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         let mut lottery = setup(&mut scenario);

//         let start_timestamp = 1000;
//         let secret_1: u64 = 123;
//         let salt_1: vector<u8> = b"s1";
//         let commitment_1 = calculate_commitment(secret_1, salt_1);

//         let secret_2: u64 = 456;
//         let salt_2: vector<u8> = b"s2";
//         let commitment_2 = calculate_commitment(secret_2, salt_2);
        
//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::start_round(&mut lottery, commitment_1, start_timestamp, test_scenario::ctx(&mut scenario));
//         assert!(no_rake_lotto::current_round(&lottery) == 1, 0);

//         test_scenario::next_tx(&mut scenario, ALICE);
//         no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
//         test_scenario::next_tx(&mut scenario, BOB);
//         no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));

//         test_scenario::next_tx(&mut scenario, ADMIN);
//         let draw_timestamp = start_timestamp + 60_000;
//         no_rake_lotto::draw_winner_and_start_next_round(
//             &mut lottery, secret_1, salt_1, commitment_2, draw_timestamp, test_scenario::ctx(&mut scenario)
//         );

//         let expected_winning_number = (secret_1 % 3000) + 1;
//         let winning_number_from_receipt = no_rake_lotto::get_receipt_winning_number(&lottery, 1);
//         assert!(winning_number_from_receipt == expected_winning_number, 4);

//         test_scenario::next_tx(&mut scenario, ALICE);
//         let winning_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
//         no_rake_lotto::claim_prize(&mut lottery, winning_ticket, test_scenario::ctx(&mut scenario));
        
//         test_scenario::return_shared(lottery);
//         scenario.end();
//     }

//     #[test, expected_failure(abort_code = no_rake_lotto::E_ROUND_EXPIRED)]
//     fun test_draw_fails_after_cancellation_period() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         let mut lottery = setup(&mut scenario);

//         let start_timestamp = 1000;
//         let commitment = calculate_commitment(123, b"some salt");

//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::start_round(&mut lottery, commitment, start_timestamp, test_scenario::ctx(&mut scenario));

//         // FIXED: The test must simulate the real-world scenario where a user
//         // calls cancel_round first, which sets the `pause` flag to true.
//         test_scenario::next_tx(&mut scenario, CHARLIE);
//         let cancel_timestamp = start_timestamp + CANCELLATION_PERIOD_MS;
//         no_rake_lotto::cancel_round(&mut lottery, cancel_timestamp, test_scenario::ctx(&mut scenario));
        
//         // NOW, when the admin tries to draw, the `!lottery.pause` check will fail.
//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::draw_winner_and_start_next_round(
//             &mut lottery, 123, b"some salt", vector[], cancel_timestamp, test_scenario::ctx(&mut scenario)
//         );
        
//         test_scenario::return_shared(lottery);
//         scenario.end();
//     }

//     #[test]
//     fun test_cancel_round_and_claim_refunds() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         let mut lottery = setup(&mut scenario);

//         let start_timestamp = 1000;
//         let commitment = calculate_commitment(123, b"another salt");

//         test_scenario::next_tx(&mut scenario, ADMIN);
//         no_rake_lotto::start_round(&mut lottery, commitment, start_timestamp, test_scenario::ctx(&mut scenario));

//         test_scenario::next_tx(&mut scenario, ALICE);
//         no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(1_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
//         test_scenario::next_tx(&mut scenario, BOB);
//         no_rake_lotto::enter(&mut lottery, coin::mint_for_testing<SUI>(2_000, test_scenario::ctx(&mut scenario)), test_scenario::ctx(&mut scenario));
//         assert!(no_rake_lotto::current_pool_value(&lottery) == 3000, 1);
        
//         test_scenario::next_tx(&mut scenario, CHARLIE);
//         let cancel_timestamp = start_timestamp + CANCELLATION_PERIOD_MS;
//         no_rake_lotto::cancel_round(&mut lottery, cancel_timestamp, test_scenario::ctx(&mut scenario));
        
//         // FIXED: The round number does not advance on cancellation in the new logic.
//         assert!(no_rake_lotto::current_round(&lottery) == 1, 2);
//         assert!(no_rake_lotto::current_pool_value(&lottery) == 0, 3);

//         test_scenario::next_tx(&mut scenario, ALICE);
//         let alices_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
//         no_rake_lotto::claim_refund(&mut lottery, alices_ticket, test_scenario::ctx(&mut scenario));

//         test_scenario::next_tx(&mut scenario, BOB);
//         let bobs_ticket = test_scenario::take_from_sender<Ticket>(&scenario);
//         no_rake_lotto::claim_refund(&mut lottery, bobs_ticket, test_scenario::ctx(&mut scenario));

//         test_scenario::return_shared(lottery);
//         scenario.end();
//     }
// }