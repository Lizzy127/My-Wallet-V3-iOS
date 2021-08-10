// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import DIKit
import PlatformKit
import ToolKit

public enum InterestAccountLimitsError: Error {
    case networkError(Error)
}

protocol InterestAccountLimitsRepositoryAPI {
    /// Fetches all `CryptoCurrency` `InterestAccountLimits` for a given `FiatCurrency`.
    /// - Parameter fiatCurrency: The user's `FiatCurrency`
    func fetchInterestAccountLimitsForAllAssets(
        _ fiatCurrency: FiatCurrency
    ) -> AnyPublisher<[InterestAccountLimits], InterestAccountLimitsError>
}

public final class InterestAccountLimitsRepository: InterestAccountLimitsRepositoryAPI {

    // MARK: - Private Properties

    private let enabledCurrenciesService: EnabledCurrenciesServiceAPI
    private let client: InterestAccountLimitsClientAPI

    // MARK: - Init

    init(
        enabledCurrenciesService: EnabledCurrenciesServiceAPI = resolve(),
        client: InterestAccountLimitsClientAPI = resolve()
    ) {
        self.enabledCurrenciesService = enabledCurrenciesService
        self.client = client
    }

    // MARK: - InterestAccountLimitsRepositoryAPI

    func fetchInterestAccountLimitsForAllAssets(
        _ fiatCurrency: FiatCurrency
    ) -> AnyPublisher<[InterestAccountLimits], InterestAccountLimitsError> {
        let enabledCryptoCurrencies = enabledCurrenciesService
            .allEnabledCryptoCurrencies
        return client
            .fetchInterestAccountLimitsResponseForFiatCurrency(fiatCurrency)
            .mapError(InterestAccountLimitsError.networkError)
            .map { response -> [InterestAccountLimits] in
                enabledCryptoCurrencies
                    .compactMap { crypto -> InterestAccountLimits? in
                        guard let value = response[crypto] else { return nil }
                        return InterestAccountLimits(value, cryptoCurrency: crypto)
                    }
            }
            .eraseToAnyPublisher()
    }
}