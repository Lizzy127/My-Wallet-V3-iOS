// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import NabuNetworkError
import PlatformKit

public protocol FiatWithdrawRepositoryAPI {

    func createWithdrawOrder(
        id: String,
        amount: MoneyValue
    ) -> AnyPublisher<Void, NabuNetworkError>
}