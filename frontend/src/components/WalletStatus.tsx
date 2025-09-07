import { useCurrentAccount, useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";

const mistToSui = (mist: string | number) => Number(mist) / 1_000_000_000;

export function WalletStatus() {
    const account = useCurrentAccount();
    const suiClient = useSuiClient();

    //this hook fetches the balance for the current account
    const { data: balance, isLoading } = useQuery({
        queryKey: ['balance', account?.address],
        queryFn: async () => {
            if (!account) return null;
            const res = await suiClient.getBalance({ owner: account.address });
            return res.totalBalance;
        },
        enabled: !!account, //only run the query if an account is connected
        refetchInterval: 10000, //refetch the balance every 10 seconds
    });

    //dont render anything if the wallet is not connected
    if (!account) {
        return null;
    }

    return (
        <div className="bg-gray-800 p-3 rounded-lg text-white text-sm shadow-lg">
            <p className="font-medium">
                Balance: {' '}
                <span className="font-bold text-lg text-teal-300">
                    {isLoading ? '...' : `${mistToSui(balance || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 })} SUI`}
                </span>
            </p>
        </div>
    );
}