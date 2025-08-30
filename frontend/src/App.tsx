import { ConnectButton } from '@mysten/dapp-kit';
import { LotteryView } from './components/LotteryView';
import { WalletStatus } from './components/WalletStatus'; // 1. Import the new component

function App() {
  return (
    <div className="min-h-screen bg-gray-900 text-white flex flex-col items-center p-4">
      {/* 2. Update the header to include the WalletStatus component */}
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