import { useSignAndExecuteTransaction, useSuiClient } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { LOTTERY_ID, PACKAGE_ID } from "./constants";

const mistToSui = (mist: number | string): number => {
    return Number(mist) / 1_000_000_000;
};

// CORRECTED: Interface to match the actual flat data structure from the API
interface LotteryFields {
    total_pool: string;
}

export function LotteryView() {
    const suiClient = useSuiClient();
    const [betAmount, setBetAmount] = useState("1");
    const { mutate: executeTransaction, isPending } = useSignAndExecuteTransaction();

    const { data, isLoading, error, refetch } = useQuery({
        queryKey: ['lotteryObject', LOTTERY_ID],
        queryFn: async () => suiClient.getObject({ id: LOTTERY_ID, options: { showContent: true } }),
        refetchInterval: 5000,
    });

    const handleEnterLottery = () => {
        const tx = new Transaction();
        const amountInMist = parseFloat(betAmount) * 1_000_000_000;
        if (isNaN(amountInMist) || amountInMist <= 0) {
            alert("Please enter a valid, positive amount.");
            return;
        }
        const [ticket] = tx.splitCoins(tx.gas, [amountInMist]);
        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::enter`,
            arguments: [tx.object(LOTTERY_ID), ticket],
        });
        executeTransaction({ transaction: tx }, {
            onSuccess: (result) => {
                console.log("Transaction successful! Digest:", result.digest);
                refetch();
                alert(`Successfully entered the lottery with ${betAmount} SUI!`);
            },
            onError: (err: Error) => {
                console.error("Transaction failed:", err);
                alert(`Error entering lottery: ${err.message}`);
            },
        });
    };

    const handleDrawWinner = () => {
        const tx = new Transaction();
        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::draw_winner`,
            // CORRECTED: Use direct, reliable addresses for system objects
            arguments: [
                tx.object(LOTTERY_ID),
                tx.object('0x8'), // Random object
                tx.object('0x6'), // Clock object
            ],
        });
        executeTransaction({ transaction: tx }, {
            onSuccess: (result) => {
                console.log("Draw successful! Digest:", result.digest);
                refetch();
                alert("Winner drawn successfully!");
            },
            onError: (err: Error) => {
                console.error("Draw failed:", err);
                alert(`Error drawing winner: ${err.message}`);
            },
        });
    };

    let prizePool = 0; // Use a number for the prize pool
    if (data?.data?.content?.dataType === 'moveObject') {
        const fields = data.data.content.fields as unknown as LotteryFields;
        // CORRECTED: Access the total_pool directly and convert to a number
        if (fields && fields.total_pool) {
            prizePool = Number(fields.total_pool);
        }
    }

    if (isLoading) return <div>Loading lottery data...</div>;
    if (error) return <div>Error fetching lottery data: {error.message}</div>;

    return (
        <div className="flex flex-col items-center gap-6 p-8 bg-gray-800 rounded-lg shadow-xl w-full max-w-md">
            <h1 className="text-5xl font-bold text-white">La Loto! 🔮</h1>
            <div className="w-full">
                <label htmlFor="bet-amount" className="block text-sm font-medium text-gray-300 mb-1">
                    Your Bet (SUI)
                </label>
                <div className="flex items-center gap-2">
                    <input
                        type="number"
                        id="bet-amount"
                        value={betAmount}
                        onChange={(e) => setBetAmount(e.target.value)}
                        className="w-full px-3 py-2 text-lg text-white bg-gray-700 border border-gray-500 rounded-md focus:ring-blue-500 focus:border-blue-500"
                        min="0.1"
                        step="0.1"
                        disabled={isPending}
                    />
                    <button
                        onClick={handleEnterLottery}
                        disabled={isPending}
                        className="px-6 py-2 text-lg font-bold text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:bg-gray-500 disabled:cursor-not-allowed"
                    >
                        {isPending ? "..." : "Enter"}
                    </button>
                </div>
            </div>
            <div className="text-center w-full py-4 border-y border-gray-600">
                <p className="text-lg text-gray-300">Current Prize Pool</p>
                <p className="text-6xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-teal-300">
                    {mistToSui(prizePool).toLocaleString()} SUI
                </p>
            </div>
            <div className="w-full">
                <button
                    onClick={handleDrawWinner}
                    disabled={isPending}
                    className="w-full px-4 py-3 mt-2 text-lg font-bold text-white bg-green-600 rounded-md hover:bg-green-700 disabled:bg-gray-500 disabled:cursor-not-allowed"
                >
                    {isPending ? "Submitting..." : "Draw Winner"}
                </button>
            </div>
        </div>
    );
}