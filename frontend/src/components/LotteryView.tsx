// src/components/LotteryView.tsx

import { useSignAndExecuteTransactionBlock, useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { TransactionBlock } from "@mysten/sui.js/transactions";
import { SuiMoveObject, SuiObjectResponse } from "@mysten/sui.js/client";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { LOTTERY_ID, PACKAGE_ID } from "../constants";

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
        refetchInterval: 5000, // Refetch every 5 seconds
    });

    // Parse the fields from the fetched lottery data
    const lotteryFields = lotteryData?.data?.content?.dataType === 'moveObject'
        ? (lotteryData.data.content.fields as unknown as LotteryFields)
        : null;

    const prizePool = lotteryFields ? mistToSui(lotteryFields.current_pool) : 0;
    const isPaused = lotteryFields?.pause ?? true;
    const currentRound = lotteryFields?.current_round;

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
                    const fields = obj.data.content.fields as { round: string };
                    return {
                        id: obj.data.objectId,
                        round: fields.round,
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

    // Corrected function to handle claiming a prize or refund for a SPECIFIC ticket
    const handleClaim = (claimType: 'prize' | 'refund', ticketId: string) => {
        if (!currentAccount) return;

        const tx = new TransactionBlock();
        
        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::claim_${claimType}`,
            arguments: [
                tx.object(LOTTERY_ID),
                tx.object(ticketId)
            ],
        });
        
        executeTransaction({ transactionBlock: tx }, {
            onSuccess: () => {
                refetch();
                refetchUserTickets();
                alert(`Successfully claimed your ${claimType}!`);
            },
            onError: (err) => alert(`Error claiming ${claimType}: ${err.message}`),
        });
    };
    
    // UI Rendering
    return (
        <div className="flex flex-col items-center gap-4 p-6 bg-slate-800 rounded-xl max-w-lg mx-auto">
            <h1 className="text-4xl font-bold text-white">Sui Lottery</h1>
            <div className="text-center">
                <p className="text-lg text-gray-400">Current Round: {currentRound ?? 'Loading...'}</p>
                <p className="text-3xl font-bold text-purple-400">{prizePool.toLocaleString()} SUI</p>
                <p className="text-gray-400">in the prize pool</p>
            </div>

            {isPaused ? (
                <div className="p-4 bg-yellow-900/50 text-yellow-300 rounded-lg">
                    Lottery is currently paused. Please wait for the admin to start the next round.
                </div>
            ) : (
                <div className="w-full space-y-2">
                    <input
                        type="number"
                        value={suiAmount}
                        onChange={(e) => setSuiAmount(e.target.value)}
                        className="w-full px-4 py-2 text-white bg-slate-700 border border-slate-600 rounded-md"
                        min="0.01"
                        step="0.01"
                        disabled={isPending}
                    />
                    <button
                        onClick={handleBuySui}
                        disabled={isPending || !currentAccount}
                        className="w-full py-3 bg-purple-600 text-white font-bold rounded-lg hover:bg-purple-700 disabled:bg-gray-500"
                    >
                        {isPending ? "Processing..." : `Enter with ${suiAmount} SUI`}
                    </button>
                </div>
            )}

            <div className="w-full border-t border-slate-700 my-4"></div>

            <div className="text-center w-full">
                <h2 className="text-xl text-white font-semibold">Your Tickets</h2>
                <p className="text-gray-400">You have {userTickets?.length ?? 0} total tickets.</p>
                <div className="mt-4 space-y-2 max-h-60 overflow-y-auto">
                    {userTickets && userTickets.length > 0 ? (
                        userTickets.map(ticket => (
                            <div key={ticket.id} className="flex justify-between items-center p-2 bg-slate-700 rounded-lg">
                                <span className="text-white">Ticket for Round {ticket.round}</span>
                                <div className="flex gap-2">
                                    <button
                                        onClick={() => handleClaim('prize', ticket.id)}
                                        disabled={isPending}
                                        className="px-4 py-1 bg-green-600 text-white text-sm font-bold rounded-lg hover:bg-green-700 disabled:bg-gray-500"
                                    >
                                        Claim Prize
                                    </button>
                                    <button
                                        onClick={() => handleClaim('refund', ticket.id)}
                                        disabled={isPending}
                                        className="px-4 py-1 bg-red-600 text-white text-sm font-bold rounded-lg hover:bg-red-700 disabled:bg-gray-500"
                                    >
                                        Claim Refund
                                    </button>
                                </div>
                            </div>
                        ))
                    ) : (
                        <p className="text-gray-500 mt-4">You don't have any tickets.</p>
                    )}
                </div>
            </div>
        </div>
    );
}