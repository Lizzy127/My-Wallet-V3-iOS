// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import Foundation
import ToolKit
import WalletPayloadKit

/// Responsible for holding a decoded wallet in memory
final class WalletHolder: WalletHolderAPI, ReleasableWalletAPI {

    var walletStatePublisher: AnyPublisher<WalletState?, Never> {
        walletState.publisher
    }

    private(set) var walletState = Atomic<WalletState?>(nil)

    func provideWalletState() -> WalletState? {
        walletState.value
    }

    func hold(
        walletState: WalletState
    ) -> AnyPublisher<WalletState, Never> {
        Deferred { [weak self] in
            Future<WalletState, Never> { promise in
                self?.walletState.mutate { $0 = walletState }
                promise(
                    .success(walletState)
                )
            }
        }
        .setFailureType(to: Never.self)
        .eraseToAnyPublisher()
    }

    func release() {
        // TODO: It might be more than just this... revisit
        walletState.mutate { $0 = nil }
    }
}
