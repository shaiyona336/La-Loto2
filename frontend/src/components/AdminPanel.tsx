
import { useCurrentAccount, useSuiClientQuery, useSignAndExecuteTransactionBlock } from "@mysten/dapp-kit";
import { TransactionBlock } from "@mysten/sui.js/transactions";
import { useState } from "react";
import { PACKAGE_ID } from "../constants";

interface AdminPanelProps {
    lotteryId: string;
    currentEndDuration: number;
    currentCancelDuration: number;
    onUpdate: () => void;
}

export function AdminPanel({ lotteryId, currentEndDuration, currentCancelDuration, onUpdate }: AdminPanelProps) {
    const currentAccount = useCurrentAccount();
    const { mutate: executeTransaction, isPending } = useSignAndExecuteTransactionBlock();

    const [endDurationMs, setEndDurationMs] = useState<string>("");
    const [cancelDurationMs, setCancelDurationMs] = useState<string>("");

    const { data: adminCaps } = useSuiClientQuery('getOwnedObjects', {
        owner: currentAccount?.address || '',
        filter: { StructType: `${PACKAGE_ID}::no_rake_lotto::AdminCap` },
    }, {
        enabled: !!currentAccount,
    });

    const adminCapId = adminCaps?.data?.[0]?.data?.objectId;

    // Only render if user has AdminCap
    if (!adminCapId) return null;

    const handleSetEndDuration = () => {
        if (!endDurationMs) return;
        const tx = new TransactionBlock();
        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::set_when_can_end`,
            arguments: [
                tx.object(adminCapId),
                tx.object(lotteryId),
                tx.pure(parseInt(endDurationMs))
            ]
        });
        executeTransaction({ transactionBlock: tx }, {
            onSuccess: () => {
                alert("Round duration updated!");
                setEndDurationMs("");
                onUpdate();
            },
            onError: (err) => alert("Error: " + err.message)
        });
    };

    const handleSetCancelDuration = () => {
        if (!cancelDurationMs) return;
        const tx = new TransactionBlock();
        tx.moveCall({
            target: `${PACKAGE_ID}::no_rake_lotto::set_when_can_cancel`,
            arguments: [
                tx.object(adminCapId),
                tx.object(lotteryId),
                tx.pure(parseInt(cancelDurationMs))
            ]
        });
        executeTransaction({ transactionBlock: tx }, {
            onSuccess: () => {
                alert("Cancellation period updated!");
                setCancelDurationMs("");
                onUpdate();
            },
            onError: (err) => alert("Error: " + err.message)
        });
    };

    return (
        <div className="w-full max-w-lg mt-8 p-6 bg-red-900/10 border border-red-900/30 rounded-xl space-y-6">
            <h2 className="text-xl font-bold text-red-400 border-b border-red-900/30 pb-2">Admin Control Panel</h2>

            <div className="space-y-4">
                {/* Round Duration */}
                <div className="space-y-2">
                    <label className="text-sm text-gray-400">Round Duration (ms)</label>
                    <div className="text-xs text-gray-500">Current: {currentEndDuration} ms</div>
                    <div className="flex gap-2">
                        <input
                            type="number"
                            placeholder="New Duration (ms)"
                            value={endDurationMs}
                            onChange={(e) => setEndDurationMs(e.target.value)}
                            className="flex-1 bg-slate-900 border border-slate-700 rounded px-3 py-2 text-white focus:outline-none focus:border-red-500"
                        />
                        <button
                            onClick={handleSetEndDuration}
                            disabled={isPending || !endDurationMs}
                            className="px-4 py-2 bg-red-600/20 text-red-400 border border-red-600/50 rounded hover:bg-red-600/30 transition-colors disabled:opacity-50"
                        >
                            Set
                        </button>
                    </div>
                </div>

                {/* Cancellation Period */}
                <div className="space-y-2">
                    <label className="text-sm text-gray-400">Cancellation Period (ms)</label>
                    <div className="text-xs text-gray-500">Current: {currentCancelDuration} ms</div>
                    <div className="flex gap-2">
                        <input
                            type="number"
                            placeholder="New Period (ms)"
                            value={cancelDurationMs}
                            onChange={(e) => setCancelDurationMs(e.target.value)}
                            className="flex-1 bg-slate-900 border border-slate-700 rounded px-3 py-2 text-white focus:outline-none focus:border-red-500"
                        />
                        <button
                            onClick={handleSetCancelDuration}
                            disabled={isPending || !cancelDurationMs}
                            className="px-4 py-2 bg-red-600/20 text-red-400 border border-red-600/50 rounded hover:bg-red-600/30 transition-colors disabled:opacity-50"
                        >
                            Set
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
}
