// src/components/LotteryView.tsx

import { useSignAndExecuteTransactionBlock, useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { TransactionBlock } from "@mysten/sui.js/transactions";
import { SuiMoveObject, SuiObjectResponse } from "@mysten/sui.js/client";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { LOTTERY_ID, PACKAGE_ID } from "../constants";
import { LotteryHistory } from "./LotteryHistory";

// Interfaces for our contract's data structures
interface LotteryFields {
    id: { id: string };
    current_pool: string;
    current_round: string;
    round_start_timestamp: string;
    pause: boolean;
    admin_commission: string;
    when_can_end: string;
    when_can_cancel: string;
}

interface Ticket {
    id: string;
    round: string;
    start_number: string;
    end_number: string;
}

// Helper functions for SUI/MIST conversion
const mistToSui = (mist: number | string): number => {
    return Number(mist) / 1_000_000_000;
};

const suiToMist = (sui: number | string): bigint => {
    return BigInt(Number(sui) * 1_000_000_000);
};

// Type guard to ensure we are working with a valid Ticket object
function isTicketObject(
    obj: SuiObjectResponse
): obj is SuiObjectResponse & { data: { content: SuiMoveObject } } {
    return obj.data?.content?.dataType === 'moveObject';
}

export function LotteryView() {
    // Dapp-kit hooks for interacting with the wallet and network
    const suiClient = useSuiClient();
    const currentAccount = useCurrentAccount();
    const { mutate: executeTransaction, isPending } = useSignAndExecuteTransactionBlock();

    // Local state for the SUI amount input
    const [suiAmount, setSuiAmount] = useState("0.1");

    // React Query hook to fetch the main Lottery object data
    const { data: lotteryData, refetch } = useQuery({
        queryKey: ['lotteryObject', LOTTERY_ID],
        queryFn: async () => suiClient.getObject({ id: LOTTERY_ID, options: { showContent: true } }),
        refetchInterval: 5000,
    });

    // Parse the fields from the fetched lottery data
    const lotteryFields = lotteryData?.data?.content?.dataType === 'moveObject'
        ? (lotteryData.data.content.fields as unknown as LotteryFields)
        : null;

    const prizePool = lotteryFields ? mistToSui(lotteryFields.current_pool) : 0;
    const isPaused = lotteryFields?.pause ?? true;
    const currentRound = lotteryFields?.current_round;
    const roundStartTime = lotteryFields ? Number(lotteryFields.round_start_timestamp) : 0;
    const roundDuration = lotteryFields ? Number(lotteryFields.when_can_end) : 0;

    // Check if round can be closed
    const now = Date.now();
    const canClose = !isPaused && (now >= roundStartTime + roundDuration);

    // React Query hook to fetch ALL of the user's tickets
    const { data: userTickets, refetch: refetchUserTickets } = useQuery({
        queryKey: ['userTickets', LOTTERY_ID, currentAccount?.address],
        queryFn: async (): Promise<Ticket[]> => {
            if (!currentAccount) return [];

            const ticketObjects = await suiClient.getOwnedObjects({
                owner: currentAccount.address,
                filter: { StructType: `${PACKAGE_ID}::no_rake_lotto::Ticket` },
                options: { showContent: true },
            });

            // Map all valid ticket objects to our simplified Ticket type
            return ticketObjects.data
                .filter(isTicketObject)
                .map(obj => {
                    const fields = obj.data.content.fields as any;
                    return {
                        id: obj.data.objectId,
                        round: fields.round,
                        start_number: fields.start_number,
                        end_number: fields.end_number,
                    };
                });
        },
        enabled: !!currentAccount,
    });

    // Function to handle buying a ticket
    const handleBuySui = () => {
        const amount = parseFloat(suiAmount);
        if (isNaN(amount) || amount <= 0) {
            alert("Please enter a valid SUI amount.");
            return;
        }

        const tx = new TransactionBlock();
        const mistAmount = suiToMist(amount);
        const [payment] = tx.splitCoins(tx.gas, [mistAmount]);

        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::enter`,
            arguments: [tx.object(LOTTERY_ID), payment],
        });

        executeTransaction({ transactionBlock: tx }, {
            onSuccess: () => {
                refetch();
                refetchUserTickets();
                alert(`Successfully entered with ${amount} SUI!`);
            },
            onError: (err) => alert(`Error entering lottery: ${err.message}`),
        });
    };

    // Close the round (Permissionless)
    const handleCloseRound = () => {
        const tx = new TransactionBlock();
        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::draw_winner_and_start_next_round`,
            arguments: [
                tx.object(LOTTERY_ID),
                tx.object('0x8'), // Random Object
                tx.object('0x6') // Clock Object
            ],
        });

        executeTransaction({ transactionBlock: tx }, {
            onSuccess: () => {
                refetch();
                refetchUserTickets();
                alert(`Round closed successfully! Winner drawn.`);
            },
            onError: (err) => alert(`Error closing round: ${err.message}`),
        });
    };

    // UI Rendering
    return (
        <div className="flex flex-col items-center gap-8 p-6 bg-slate-800 rounded-xl w-full max-w-4xl mx-auto min-h-[80vh]">
            <div className="bg-slate-900 p-8 rounded-2xl w-full max-w-lg shadow-2xl border border-slate-700">
                <h1 className="text-5xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-purple-400 to-pink-600 mb-2 text-center">La Loto</h1>
                <div className="text-center space-y-4">
                    <div className="bg-slate-800 p-4 rounded-xl border border-slate-700">
                        <p className="text-sm text-gray-400 uppercase tracking-wider">Current Jackpot</p>
                        <p className="text-5xl font-bold text-white mt-1 drop-shadow-lg">{prizePool.toLocaleString()} SUI</p>
                    </div>

                    <div className="flex justify-between items-center text-sm text-gray-400 px-2">
                        <span>Round #{currentRound ?? '-'}</span>
                        <span>{isPaused ? "PAUSED" : "LIVE"}</span>
                    </div>
                </div>

                <div className="mt-8">
                    {isPaused ? (
                        <div className="p-4 bg-yellow-900/30 border border-yellow-700 text-yellow-200 rounded-lg text-center">
                            Lottery is currently paused.
                        </div>
                    ) : (
                        <div className="w-full space-y-4">
                            <div className="relative">
                                <input
                                    type="number"
                                    value={suiAmount}
                                    onChange={(e) => setSuiAmount(e.target.value)}
                                    className="w-full pl-4 pr-12 py-4 text-xl text-white bg-slate-800 border-2 border-slate-600 rounded-xl focus:border-purple-500 focus:outline-none transition-colors"
                                    min="0.01"
                                    step="0.01"
                                    disabled={isPending}
                                />
                                <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">SUI</span>
                            </div>
                            <button
                                onClick={handleBuySui}
                                disabled={isPending || !currentAccount}
                                className="w-full py-4 bg-gradient-to-r from-purple-600 to-pink-600 text-white text-xl font-bold rounded-xl hover:from-purple-500 hover:to-pink-500 disabled:opacity-50 disabled:cursor-not-allowed transform hover:-translate-y-1 transition-all shadow-lg active:translate-y-0"
                            >
                                {isPending ? "Processing..." : `BUY TICKET`}
                            </button>
                        </div>
                    )}

                    {/* Permissionless Close Button */}
                    {!isPaused && (
                        <div className="mt-6 pt-6 border-t border-slate-700">
                            {canClose ? (
                                <button
                                    onClick={handleCloseRound}
                                    disabled={isPending}
                                    className="w-full py-3 bg-blue-600/20 text-blue-300 border border-blue-500/50 hover:bg-blue-600/40 rounded-lg transition-colors font-mono text-sm uppercase tracking-widest"
                                >
                                    Time Reached - Close Round & Draw Winner
                                </button>
                            ) : (
                                <p className="text-center text-xs text-gray-500 font-mono">
                                    Round ending in: {Math.max(0, Math.floor(((roundStartTime + roundDuration) - now) / 1000))}s
                                </p>
                            )}
                        </div>
                    )}
                </div>
            </div>

            {/* History Section */}
            <LotteryHistory
                currentRound={currentRound}
                userTickets={userTickets || []}
                onClaimSuccess={() => {
                    refetch();
                    refetchUserTickets();
                }}
            />
        </div>
    );
}