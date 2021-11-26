// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import MoneyKit
import NetworkKit
import PlatformKit
import ToolKit

public enum InterestAccountBalanceRepositoryError: Error {
    case networkError(Error)
}

public protocol InterestAccountBalanceRepositoryAPI: AnyObject {

    /// Fetches `InterestAccountBalances` for a given `FiatCurrency`.
    /// Use the subscript function on `InterestAccountBalances` to
    /// return a `InterestAccountBalanceDetails` for a given
    /// CryptoCurrency.
    /// - Parameter fiatCurrency: FiatCurrency
    func fetchInterestAccountsBalance(
        fiatCurrency: FiatCurrency
    ) -> AnyPublisher<InterestAccountBalances, InterestAccountBalanceRepositoryError>
}
