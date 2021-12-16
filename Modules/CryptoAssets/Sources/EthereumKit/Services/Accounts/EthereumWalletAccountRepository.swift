// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import DIKit
import MetadataKit
import PlatformKit
import ToolKit
import WalletPayloadKit

public enum WalletAccountRepositoryError: Error {
    case missingWallet
    case failedToFetchAccount(Error)
}

public protocol EthereumWalletAccountRepositoryAPI {

    var defaultAccount: AnyPublisher<EthereumWalletAccount, WalletAccountRepositoryError> { get }
}

final class EthereumWalletAccountRepository: EthereumWalletAccountRepositoryAPI {

    // MARK: - Types

    private struct Key: Hashable {}

    // MARK: - EthereumWalletAccountRepositoryAPI

    var defaultAccount: AnyPublisher<EthereumWalletAccount, WalletAccountRepositoryError> {
        cachedValue.get(key: Key())
    }

    // MARK: - Private Properties

    private let accountBridge: EthereumWalletAccountBridgeAPI
    private let cachedValue: CachedValueNew<
        Key,
        EthereumWalletAccount,
        WalletAccountRepositoryError
    >

    // MARK: - Init

    init(
        accountBridge: EthereumWalletAccountBridgeAPI = resolve(),
        walletMetadataEntryService: WalletMetadataEntryServiceAPI = resolve(),
        nativeWalletEnabled: @escaping () -> AnyPublisher<Bool, Never> = { nativeWalletFlagEnabled() }
    ) {
        self.accountBridge = accountBridge

        let cache: AnyCache<Key, EthereumWalletAccount> = InMemoryCache(
            configuration: .onLoginLogout(),
            refreshControl: PerpetualCacheRefreshControl()
        ).eraseToAnyCache()

        let fetch_old = { [accountBridge] () -> AnyPublisher<EthereumWalletAccount, WalletAccountRepositoryError> in
            accountBridge.wallets
                .eraseError()
                .map(\.first)
                .mapError(WalletAccountRepositoryError.failedToFetchAccount)
                .onNil(.missingWallet)
                .map { account in
                    EthereumWalletAccount(
                        index: account.index,
                        publicKey: account.publicKey,
                        label: account.label,
                        archived: account.archived
                    )
                }
                .eraseToAnyPublisher()
        }

        let fetch_new = { [walletMetadataEntryService] () -> AnyPublisher<EthereumWalletAccount, WalletAccountRepositoryError> in
            walletMetadataEntryService.fetchEntry(type: EthereumEntryPayload.self)
                .flatMap { entry -> AnyPublisher<EthereumWalletAccount, WalletAssetFetchError> in
                    guard let firstAccount = entry.ethereum.accounts.first else {
                        return .failure(.notInitialized)
                    }
                    return .just(
                        EthereumWalletAccount(
                            index: entry.ethereum.defaultAccountIndex,
                            publicKey: firstAccount.address,
                            label: firstAccount.label,
                            archived: firstAccount.archived
                        )
                    )
                }
                .catch { error in
                    fatalError(error.localizedDescription)
                }
                .mapError(WalletAccountRepositoryError.failedToFetchAccount)
                .eraseToAnyPublisher()
        }

        cachedValue = CachedValueNew(
            cache: cache,
            fetch: { [nativeWalletEnabled] _ in
                nativeWalletEnabled()
                    .flatMap { isEnabled -> AnyPublisher<EthereumWalletAccount, WalletAccountRepositoryError> in
                        guard isEnabled else {
                            return fetch_old()
                        }
                        return fetch_new()
                    }
                    .eraseToAnyPublisher()
            }
        )
    }
}
