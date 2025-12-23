import { useSuiClient, useCurrentAccount, useSignAndExecuteTransactionBlock } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { LOTTERY_ID, PACKAGE_ID } from "../constants";
import { TransactionBlock } from "@mysten/sui.js/transactions";

import { useState } from "react";

interface Ticket {
    id: string;
    round: string;
    start_number: string;
    end_number: string;
}

interface LotteryReceipt {
    id: { id: string };
    lottery_id: string;
    round: string;
    prize_pool: string;
    winning_number: string;
    prize_claimed: boolean;
    was_canceled: boolean;
}

// Helper to check if a ticket is a winner for a given receipt
const isWinningTicket = (ticket: Ticket, receipt: LotteryReceipt) => {
    if (receipt.was_canceled) return false;
    const winNum = BigInt(receipt.winning_number);
    const start = BigInt(ticket.start_number);
    const end = BigInt(ticket.end_number);
    return winNum >= start && winNum <= end;
};

const mistToSui = (mist: number | string): string => {
    const val = Number(mist) / 1_000_000_000;
    return val.toLocaleString(undefined, { maximumFractionDigits: 4 });
};

export function LotteryHistory({ currentRound, userTickets, onClaimSuccess }: {
    currentRound: string | undefined,
    userTickets: Ticket[],
    onClaimSuccess: () => void
}) {
    const suiClient = useSuiClient();
    const currentAccount = useCurrentAccount();
    const { mutate: executeTransaction, isPending } = useSignAndExecuteTransactionBlock();
    const [claimingId, setClaimingId] = useState<string | null>(null);

    // Fetch receipts (Dynamic Fields of the Lottery Object)
    const { data: receipts } = useQuery({
        queryKey: ['lotteryReceipts', LOTTERY_ID],
        queryFn: async () => {
            // Fetch dynamic fields
            const dfs = await suiClient.getDynamicFields({
                parentId: LOTTERY_ID,
            });

            // Filter and fetch objects for receipts requires specific knowledge of how they are stored
            // The contract says: dynamic_field::add(&mut lottery.id, lottery.current_round, receipt);
            // So key is u64 (round), value is LotteryReceipt

            // We need to fetch the actual objects for these fields
            const receiptObjects = await Promise.all(
                dfs.data.map(df => suiClient.getObject({
                    id: df.objectId,
                    options: { showContent: true }
                }))
            );

            // Parse valid receipts
            const parsedReceipts: LotteryReceipt[] = [];
            receiptObjects.forEach(obj => {
                if (obj.data?.content?.dataType === 'moveObject') {
                    // The dynamic field object wraps the value. 
                    // Field<u64, LotteryReceipt>
                    const fields = obj.data.content.fields as any;
                    if (fields.value && fields.value.fields) {
                        parsedReceipts.push(fields.value.fields as LotteryReceipt);
                    }
                }
            });

            // Sort by round descending
            return parsedReceipts.sort((a, b) => Number(b.round) - Number(a.round));
        },
        refetchInterval: 10000,
    });

    const handleClaim = (receipt: LotteryReceipt, ticket: Ticket) => {
        if (!currentAccount) return;
        setClaimingId(receipt.round);

        const tx = new TransactionBlock();
        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::claim_prize`,
            arguments: [
                tx.object(LOTTERY_ID),
                tx.object(ticket.id)
            ],
        });

        executeTransaction({ transactionBlock: tx }, {
            onSuccess: () => {
                alert("Prize claimed successfully!");
                onClaimSuccess(); // Prompt parent to refetch
            },
            onError: (err) => alert(`Error claiming prize: ${err.message}`),
            onSettled: () => setClaimingId(null)
        });
    };

    // Helper to render a single row
    const renderRow = (roundNum: number) => {
        // Is this the current round?
        const isCurrent = currentRound && roundNum === Number(currentRound);

        // Find receipt if it exists (past rounds)
        const receipt = receipts?.find(r => Number(r.round) === roundNum);

        // Find user tickets for this round
        const ticketsForRound = userTickets.filter(t => Number(t.round) === roundNum);

        // Determine status and style
        let bgColor = "bg-gray-700"; // Default/Lost
        let statusText = "Past Round";
        let action = null;

        if (isCurrent) {
            bgColor = "bg-blue-900 border-2 border-blue-500";
            statusText = "Current Round";
            if (ticketsForRound.length > 0) {
                statusText += ` (${ticketsForRound.length} Tickets)`;
            }
        } else if (receipt) {
            if (receipt.was_canceled) {
                bgColor = "bg-red-900/50";
                statusText = "Canceled";
                // Logic for refund claim could go here similarly
            } else {
                // Check for winning ticket
                const winningTicket = ticketsForRound.find(t => isWinningTicket(t, receipt));

                if (winningTicket) {
                    // User WON
                    if (receipt.prize_claimed) {
                        // User (or someone?) claimed it. 
                        // Wait, the receipt object on chain is shared/dynamic field. 
                        // `prize_claimed` bool in receipt tracks if the prize was claimed.
                        // Since there is only 1 winner per round in this logic, if it's claimed, it's claimed.
                        bgColor = "bg-green-900/50 text-green-200 border border-green-700";
                        statusText = "Won & Claimed";
                    } else {
                        // Winner & Unclaimed
                        bgColor = "bg-red-900 border-2 border-red-500 animate-pulse"; // "red" as requested for waiting user action
                        statusText = "WINNER! - Unclaimed";
                        action = (
                            <button
                                onClick={() => handleClaim(receipt, winningTicket)}
                                disabled={isPending || claimingId === receipt.round}
                                className="ml-4 px-4 py-2 bg-green-500 hover:bg-green-600 text-white font-bold rounded shadow-lg transform hover:scale-105 transition-all"
                            >
                                {claimingId === receipt.round ? "Claiming..." : "CLAIM PRIZE"}
                            </button>
                        );
                    }
                } else {
                    // User played but didn't win
                    if (ticketsForRound.length > 0) {
                        statusText = "Lost";
                    } else {
                        // User didn't play this round
                        statusText = "Ended";
                    }
                }
            }
        }

        return (
            <div key={roundNum} className={`flex flex-col sm:flex-row justify-between items-center p-4 rounded-lg ${bgColor} mb-2 transition-all`}>
                <div className="flex flex-col">
                    <span className="font-bold text-lg">Round #{roundNum}</span>
                    <span className="text-sm opacity-80">{statusText}</span>
                    {receipt && !receipt.was_canceled && (
                        <span className="text-xs text-yellow-500 mt-1">Winning #: {receipt.winning_number} | Prize: {mistToSui(receipt.prize_pool)} SUI</span>
                    )}
                </div>

                <div className="flex items-center mt-2 sm:mt-0">
                    {action}
                    {!action && ticketsForRound.length > 0 && (
                        <span className="text-xs bg-black/20 px-2 py-1 rounded ml-2">
                            You had {ticketsForRound.length} ticket(s)
                        </span>
                    )}
                </div>
            </div>
        );
    };

    // Generate list of rounds to show
    // We want to show: Current Round -> Down to 1
    // But we might have GAP in receipts if we depend only on existing receipts.
    // Ideally we assume round 1 to current_round exists.

    const maxRound = currentRound ? Number(currentRound) : (receipts && receipts.length > 0 ? Number(receipts[0].round) : 0);
    const rounds = Array.from({ length: maxRound }, (_, i) => maxRound - i); // [10, 9, 8, ... 1]

    return (
        <div className="w-full max-w-2xl mt-8">
            <h2 className="text-2xl font-bold text-white mb-4">Lottery History</h2>
            <div className="space-y-2 max-h-[600px] overflow-y-auto pr-2 custom-scrollbar">
                {rounds.map(r => renderRow(r))}
                {rounds.length === 0 && <div className="text-gray-500 text-center">No history yet.</div>}
            </div>
        </div>
    );
}
