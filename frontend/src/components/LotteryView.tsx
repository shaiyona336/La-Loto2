// src/components/LotteryView.tsx

import { useSignAndExecuteTransactionBlock, useSuiClient, useCurrentAccount } from "@mysten/dapp-kit";
import { TransactionBlock } from "@mysten/sui.js/transactions";
import { SuiMoveObject, SuiObjectResponse } from "@mysten/sui.js/client";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { LOTTERY_ID, PACKAGE_ID } from "../constants";

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

// Helper to convert MIST to SUI
const mistToSui = (mist: number | string): number => {
    return Number(mist) / 1_000_000_000;
};

// Helper to convert SUI to MIST for transactions
const suiToMist = (sui: number | string): bigint => {
    return BigInt(Number(sui) * 1_000_000_000);
};

// CORRECTED: This is a "type guard" to safely identify Move objects for tickets.
function isTicketObject(
    obj: SuiObjectResponse
): obj is SuiObjectResponse & { data: { content: SuiMoveObject } } {
    return obj.data?.content?.dataType === 'moveObject';
}

export function LotteryView() {
    const suiClient = useSuiClient();
    const currentAccount = useCurrentAccount();
    const [suiAmount, setSuiAmount] = useState("0.1");
    const { mutate: executeTransaction, isPending } = useSignAndExecuteTransactionBlock();

    // Query for the main Lottery object
    const { data: lotteryData } = useQuery({
        queryKey: ['lotteryObject', LOTTERY_ID],
        queryFn: async () => suiClient.getObject({ id: LOTTERY_ID, options: { showContent: true } }),
        refetchInterval: 5000,
    });

    // Query for the user's tickets
    const { data: userTickets, refetch: refetchUserTickets } = useQuery({
        queryKey: ['userTickets', LOTTERY_ID, currentAccount?.address],
        queryFn: async (): Promise<Ticket[]> => {
            if (!currentAccount) return [];

            const ticketObjects = await suiClient.getOwnedObjects({
                owner: currentAccount.address,
                filter: { StructType: `${PACKAGE_ID}::no_rake_lotto::Ticket` },
                options: { showContent: true },
            });

            // CORRECTED: Use the type guard in the filter for 100% type safety.
            return ticketObjects.data
                .filter(isTicketObject) // Using the safe type guard here
                .map(obj => {
                    // No more "as any" or "!" needed. It's now safe.
                    const fields = obj.data.content.fields as { round: string }; // We can cast the inner fields for clarity
                    return {
                        id: obj.data.objectId,
                        round: fields.round,
                    };
                });
        },
        enabled: !!currentAccount,
        refetchInterval: 10000,
    });

    // Parse data from the main lottery object
    const lotteryFields = lotteryData?.data?.content?.dataType === 'moveObject'
        ? (lotteryData.data.content.fields as unknown as LotteryFields)
        : null;

    const prizePool = lotteryFields ? mistToSui(lotteryFields.current_pool) : 0;
    const isPaused = lotteryFields?.pause ?? true;
    const currentRound = lotteryFields?.current_round ?? '0';

    // Logic to buy tickets
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
            onSuccess: (result) => {
                console.log("Entered lottery! Digest:", result.digest);
                refetchUserTickets(); // Refetch tickets after successful entry
                alert(`Successfully entered with ${amount} SUI!`);
            },
            onError: (err) => {
                console.error("Transaction failed:", err);
                alert(`Error entering lottery: ${err.message}`);
            },
        });
    };

    // Handler for claiming prize or refund
    const handleClaim = (claimType: 'prize' | 'refund') => {
        if (!userTickets || userTickets.length === 0) {
            alert("You have no tickets to claim with.");
            return;
        }

        // For simplicity, we'll use the user's first available ticket.
        const ticketToClaim = userTickets[0];
        const tx = new TransactionBlock();

        // The PTB needs the actual Ticket object.
        const [ticketObject] = tx.transferObjects([tx.object(ticketToClaim.id)], tx.pure(currentAccount!.address));

        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::claim_${claimType}`,
            arguments: [tx.object(LOTTERY_ID), ticketObject],
        });

        executeTransaction({ transactionBlock: tx }, {
            onSuccess: (result) => {
                console.log(`${claimType} claimed! Digest:`, result.digest);
                refetchUserTickets(); // Refetch tickets after a claim
                alert(`Successfully claimed your ${claimType}!`);
            },
            onError: (err) => {
                console.error("Claim failed:", err);
                alert(`Error claiming ${claimType}: ${err.message}`);
            },
        });
    };
    
    // UI Rendering
    return (
        <div className="flex flex-col items-center gap-4 p-6 bg-slate-800 rounded-xl max-w-lg mx-auto">
            <h1 className="text-4xl font-bold text-white">Sui Lottery</h1>
            <div className="text-center">
                <p className="text-lg text-gray-400">Current Round: {currentRound}</p>
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
                        disabled={isPending}
                        className="w-full py-3 bg-purple-600 text-white font-bold rounded-lg hover:bg-purple-700 disabled:bg-gray-500"
                    >
                        {isPending ? "Processing..." : `Enter with ${suiAmount} SUI`}
                    </button>
                </div>
            )}

            <div className="w-full border-t border-slate-700 my-4"></div>

            <div className="text-center">
                <p className="text-gray-400">You have {userTickets?.length ?? 0} tickets for this lottery.</p>
                <div className="flex gap-4 mt-2">
                     <button
                        onClick={() => handleClaim('prize')}
                        disabled={isPending || !userTickets || userTickets.length === 0}
                        className="px-6 py-2 bg-green-600 text-white font-bold rounded-lg hover:bg-green-700 disabled:bg-gray-500"
                    >
                        {isPending ? "..." : "Claim Prize"}
                    </button>
                    <button
                        onClick={() => handleClaim('refund')}
                        disabled={isPending || !userTickets || userTickets.length === 0}
                        className="px-6 py-2 bg-red-600 text-white font-bold rounded-lg hover:bg-red-700 disabled:bg-gray-500"
                    >
                        {isPending ? "..." : "Claim Refund"}
                    </button>
                </div>
            </div>
        </div>
    );
}