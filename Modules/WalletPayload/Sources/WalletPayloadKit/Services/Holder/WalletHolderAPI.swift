// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import Foundation

/// Types adopting the `WalletHolderAPI` protocol provide in-memory `Wallet` object.
protocol WalletHolderAPI {
    /// Creates and stores a new `Wallet` using a factory closure
    /// - Parameter creator: A `ProvideWallet` factory closure
    /// - Returns: `AnyPublisher<Wallet, Never>`
    func hold(
        using creator: @escaping ProvideWallet
    ) -> AnyPublisher<Wallet, Never>
}

/// Types adopting the `InMemoryWalletProviderAPI` should be able to provide a `Wallet` object
protocol InMemoryWalletProviderAPI {
    /// Returns a `Wallet` object if it exists, otherwise `nil`
    func provideWallet() -> Wallet?
}

/// Types adopting `ReleasableWalletAPI` should be able to release a previous initialized `Wallet` object
public protocol ReleasableWalletAPI {
    /// Releases a in-memory `Wallet` object
    func release()
}