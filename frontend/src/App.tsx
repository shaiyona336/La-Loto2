import { ConnectButton } from '@mysten/dapp-kit';
import { LotteryView } from './LotteryView';
import { WalletStatus } from './WalletStatus';

function App() {
  return (
    <div className="min-h-screen bg-gray-900 text-white flex flex-col items-center p-4">
      <header className="w-full flex justify-end p-4 items-center gap-4">
        <WalletStatus />
        <ConnectButton />
      </header>
      <main className="flex-grow flex items-center justify-center">
        <LotteryView />
      </main>
    </div>
  )
}

export default App;