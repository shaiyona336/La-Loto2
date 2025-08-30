// src/components/LotteryView.tsx

import { useSignAndExecuteTransactionBlock, useSuiClient } from "@mysten/dapp-kit";
import { TransactionBlock } from "@mysten/sui.js/transactions";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { LOTTERY_ID, PACKAGE_ID } from "../constants";

/**
 * Converts a MIST value (as a string or number) to its SUI equivalent.
 */
const mistToSui = (mist: number | string): number => {
    return Number(mist) / 1_000_000_000;
};

/**
 * Represents the structure of the `fields` property of our Lottery Move object.
 */
interface LotteryFields {
    total_pool: string;
}

interface TransactionResult {
    digest: string;
    effects?: any;
    errors?: any[];
}

export function LotteryView() {
    const suiClient = useSuiClient();
    const [betAmount, setBetAmount] = useState("1");
    const { mutate: executeTransaction, isPending } = useSignAndExecuteTransactionBlock();

    const { data, isLoading, error, refetch } = useQuery({
        queryKey: ['lotteryObject', LOTTERY_ID],
        queryFn: async () => {
            return suiClient.getObject({
                id: LOTTERY_ID,
                options: { showContent: true },
            });
        },
        refetchInterval: 5000,
    });

    const handleEnterLottery = () => {
        const tx = new TransactionBlock();
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
        
        executeTransaction(
            { transactionBlock: tx },
            {
                onSuccess: (result: TransactionResult) => {
                    console.log("Transaction successful! Digest:", result.digest);
                    refetch();
                    alert(`Successfully entered the lottery with ${betAmount} SUI!`);
                },
                onError: (err: Error) => {
                    console.error("Transaction failed:", err);
                    alert(`Error entering lottery: ${err.message}`);
                },
            }
        );
    };

    const handleDrawWinner = () => {
        const tx = new TransactionBlock();
        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::draw_winner`,
            arguments: [
                tx.object(LOTTERY_ID),
                tx.object('0x8'),
                tx.object('0x6'),
            ],
        });
        
        executeTransaction(
            { transactionBlock: tx },
            {
                onSuccess: (result: TransactionResult) => {
                    console.log("Draw successful! Digest:", result.digest);
                    refetch();
                    alert("Winner drawn successfully!");
                },
                onError: (err: Error) => {
                    console.error("Draw failed:", err);
                    alert(`Error drawing winner: ${err.message}`);
                },
            }
        );
    };

    let prizePool = 0;
    if (data?.data?.content?.dataType === 'moveObject') {
        const fields = data.data.content.fields as unknown as LotteryFields;
        if (fields && fields.total_pool) {
            prizePool = Number(fields.total_pool);
        }
    }

    if (isLoading) return (
        <div className="flex items-center justify-center h-64">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-purple-500"></div>
        </div>
    );
    
    if (error) return (
        <div className="text-red-400 bg-red-900/20 border border-red-500/50 rounded-xl p-4">
            Error fetching lottery data: {error.message}
        </div>
    );

    return (
        <div className="flex flex-col items-center gap-8 p-10 bg-gradient-to-br from-slate-900 via-purple-900/20 to-slate-900 rounded-3xl shadow-2xl border border-purple-500/20 backdrop-blur-xl w-full max-w-lg">
            {/* Title with animated gradient */}
            <div className="relative">
                <h1 className="text-6xl font-black text-white tracking-tight relative z-10">
                    La Loto!
                </h1>
                <div className="absolute -inset-1 bg-gradient-to-r from-purple-600 to-pink-600 rounded-lg blur-lg opacity-30 animate-pulse"></div>
                <span className="text-5xl absolute -right-12 -top-2 animate-bounce">🎰</span>
            </div>

            {/* Prize Pool Display - HIGH VISIBILITY */}
            <div className="w-full bg-gradient-to-r from-slate-800/80 to-purple-800/30 rounded-2xl p-6 border border-purple-500/30 shadow-inner relative overflow-hidden">
                {/* Animated background effect */}
                <div className="absolute inset-0 bg-gradient-to-r from-yellow-400/10 via-pink-400/10 to-purple-400/10 animate-pulse"></div>
                
                <p className="text-sm font-medium text-purple-300 uppercase tracking-wider mb-2 text-center relative z-10">
                    Current Prize Pool
                </p>
                <div className="relative z-10">
                    <p className="text-5xl font-black text-center bg-gradient-to-r from-yellow-300 via-pink-300 to-purple-300 bg-clip-text text-transparent animate-pulse">
                        {mistToSui(prizePool).toLocaleString()} SUI
                    </p>
                    {/* Extra glow effect for visibility */}
                    <div className="absolute -inset-2 bg-gradient-to-r from-yellow-400/20 to-purple-400/20 rounded-lg blur-xl"></div>
                </div>
                <p className="text-xs text-gray-400 text-center mt-2 relative z-10">
                    💎 Winner takes all!
                </p>
            </div>

            {/* Betting Section */}
            <div className="w-full space-y-4">
                <label htmlFor="bet-amount" className="block text-sm font-medium text-purple-300 uppercase tracking-wide">
                    Enter Your Bet
                </label>
                <div className="flex items-center gap-3">
                    <div className="relative flex-1">
                        <input
                            type="number"
                            id="bet-amount"
                            value={betAmount}
                            onChange={(e) => setBetAmount(e.target.value)}
                            className="w-full px-4 py-3 text-lg text-white bg-slate-800/80 border-2 border-purple-500/30 rounded-xl focus:border-purple-400 focus:outline-none focus:ring-2 focus:ring-purple-400/20 transition-all duration-300 pr-12"
                            min="0.1"
                            step="0.1"
                            disabled={isPending}
                            placeholder="Amount"
                        />
                        <span className="absolute right-4 top-1/2 -translate-y-1/2 text-purple-400 font-bold">
                            SUI
                        </span>
                    </div>
                    <button
                        onClick={handleEnterLottery}
                        disabled={isPending}
                        className="px-8 py-3 bg-gradient-to-r from-blue-600 to-purple-600 text-white font-bold rounded-xl hover:from-blue-700 hover:to-purple-700 disabled:from-gray-600 disabled:to-gray-700 disabled:cursor-not-allowed transition-all duration-300 shadow-lg hover:shadow-purple-500/30 transform hover:scale-105 active:scale-95"
                    >
                        {isPending ? (
                            <span className="flex items-center gap-2">
                                <span className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full"></span>
                                Entering...
                            </span>
                        ) : (
                            'Enter Lottery 🎲'
                        )}
                    </button>
                </div>
            </div>

            {/* Draw Winner Button */}
            <div className="w-full mt-4">
                <button
                    onClick={handleDrawWinner}
                    disabled={isPending}
                    className="w-full py-4 bg-gradient-to-r from-green-600 to-emerald-600 text-white font-bold text-lg rounded-xl hover:from-green-700 hover:to-emerald-700 disabled:from-gray-600 disabled:to-gray-700 disabled:cursor-not-allowed transition-all duration-300 shadow-lg hover:shadow-green-500/30 transform hover:scale-105 active:scale-95"
                >
                    {isPending ? (
                        <span className="flex items-center justify-center gap-2">
                            <span className="animate-spin h-5 w-5 border-2 border-white border-t-transparent rounded-full"></span>
                            Drawing Winner...
                        </span>
                    ) : (
                        <span className="flex items-center justify-center gap-2">
                            Draw Winner 🏆
                            <span className="text-xs bg-white/20 px-2 py-1 rounded-full">Admin Only</span>
                        </span>
                    )}
                </button>
            </div>

            {/* Info Cards */}
            <div className="grid grid-cols-3 gap-3 w-full mt-4">
                <div className="bg-slate-800/50 rounded-lg p-3 text-center border border-slate-700/50">
                    <p className="text-2xl mb-1">🎯</p>
                    <p className="text-xs text-gray-400">Fair Draw</p>
                </div>
                <div className="bg-slate-800/50 rounded-lg p-3 text-center border border-slate-700/50">
                    <p className="text-2xl mb-1">⚡</p>
                    <p className="text-xs text-gray-400">Instant Win</p>
                </div>
                <div className="bg-slate-800/50 rounded-lg p-3 text-center border border-slate-700/50">
                    <p className="text-2xl mb-1">🔒</p>
                    <p className="text-xs text-gray-400">Secure</p>
                </div>
            </div>
        </div>
    );
}