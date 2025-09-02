// #[test_only]
// module imp_con::lottery_tests {
//     use imp_con::no_rake_lotto::{Self, Lottery, Ticket};
//     use sui::sui::SUI;
//     use sui::coin;
//     use sui::test_scenario;

//     const ADMIN: address = @0xAD;
//     const ALICE: address = @0xA1;
//     const BOB: address = @0xB0;

//     #[test]
//     fun test_full_cycle() {
//         // --- 1. SETUP ---
//         let mut scenario = test_scenario::begin(ADMIN);
        
//         // Transaction 1: Call the correct 'test_init' function.
//         no_rake_lotto::test_init(scenario.ctx());

//         // End Tx 1 and start Tx 2 to commit the shared object.
//         scenario.next_tx(ADMIN);

//         // Transaction 2: Take the shared lottery object.
//         let mut lottery = scenario.take_shared<Lottery>();

//         // --- 2. ENTER ---
//         // Transaction 3: Alice enters.
//         scenario.next_tx(ALICE);
//         {
//             let coin = coin::mint_for_testing<SUI>(1_000_000_000, scenario.ctx());
//             no_rake_lotto::enter(&mut lottery, coin, scenario.ctx());
//         };

//         // Transaction 4: Bob enters.
//         scenario.next_tx(BOB);
//         {
//             let coin = coin::mint_for_testing<SUI>(2_000_000_000, scenario.ctx());
//             no_rake_lotto::enter(&mut lottery, coin, scenario.ctx());
//         };
//         assert!(no_rake_lotto::current_pool_value(&lottery) == 3_000_000_000, 0);
//         assert!(no_rake_lotto::current_round(&lottery) == 1, 1);
        
//         // --- 3. DRAW WINNER ---
//         // Transaction 5: Admin draws the winner.
//         scenario.next_tx(ADMIN);
//         {
//             let winning_number_for_bob = 1_500_000_000;
//             let current_timestamp = 60_001;
            
//             no_rake_lotto::draw_winner(
//                 &mut lottery, 
//                 winning_number_for_bob,
//                 current_timestamp,
//                 scenario.ctx()
//             );
//         };

//         // --- 4. ASSERT AND CLAIM ---
//         assert!(no_rake_lotto::current_pool_value(&lottery) == 0, 2);
//         assert!(no_rake_lotto::current_round(&lottery) == 2, 3);
//         assert!(no_rake_lotto::is_open(&lottery), 4);
        
//         let winning_number_from_receipt = no_rake_lotto::get_receipt_winning_number(&lottery, 1);
//         assert!(winning_number_from_receipt == 1_500_000_000, 5);

//         // Transaction 6: Bob claims his prize.
//         scenario.next_tx(BOB);
//         let winning_ticket = scenario.take_from_sender<Ticket>();
//         no_rake_lotto::claim_prize(&mut lottery, winning_ticket, scenario.ctx());
        
//         // --- 5. CLEANUP ---
//         test_scenario::return_shared(lottery);
//         scenario.end();
//     }
// }