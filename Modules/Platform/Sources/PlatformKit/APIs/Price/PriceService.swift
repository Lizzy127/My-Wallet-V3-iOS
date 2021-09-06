// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import DIKit
import Foundation
import NetworkKit
import ToolKit

public protocol PriceServiceAPI {
    func moneyValuePair(base fiatValue: FiatValue, cryptoCurrency: CryptoCurrency, usesFiatAsBase: Bool) -> AnyPublisher<MoneyValuePair, NetworkError>
    func price(for baseCurrency: Currency, in quoteCurrency: Currency) -> AnyPublisher<PriceQuoteAtTime, NetworkError>
    func price(for baseCurrency: Currency, in quoteCurrency: Currency, at date: Date?) -> AnyPublisher<PriceQuoteAtTime, NetworkError>
    func priceSeries(
        within window: PriceWindow,
        of baseCurrency: CryptoCurrency,
        in quoteCurrency: FiatCurrency
    ) -> AnyPublisher<HistoricalPriceSeries, NetworkError>
}

public class PriceService: PriceServiceAPI {

    private let client: PriceClientAPI

    // MARK: - Setup

    public convenience init() {
        self.init(client: resolve())
    }

    public init(client: PriceClientAPI) {
        self.client = client
    }

    public func moneyValuePair(
        base fiatValue: FiatValue,
        cryptoCurrency: CryptoCurrency,
        usesFiatAsBase: Bool
    ) -> AnyPublisher<MoneyValuePair, NetworkError> {
        price(for: cryptoCurrency, in: fiatValue.currency)
            .map(\.moneyValue)
            .map { $0.fiatValue ?? .zero(currency: fiatValue.currencyType) }
            .map { MoneyValuePair(
                fiat: fiatValue,
                priceInFiat: $0,
                cryptoCurrency: cryptoCurrency,
                usesFiatAsBase: usesFiatAsBase
            )
            }
            .eraseToAnyPublisher()
    }

    public func price(
        for baseCurrency: Currency,
        in quoteCurrency: Currency
    ) -> AnyPublisher<PriceQuoteAtTime, NetworkError> {
        price(for: baseCurrency, in: quoteCurrency, at: nil)
    }

    public func price(
        for baseCurrency: Currency,
        in quoteCurrency: Currency,
        at date: Date? = nil
    ) -> AnyPublisher<PriceQuoteAtTime, NetworkError> {
        guard baseCurrency.code != quoteCurrency.code else {
            return .just(
                PriceQuoteAtTime(
                    timestamp: date ?? Date(),
                    moneyValue: MoneyValue.create(major: "1", currency: quoteCurrency.currency) ?? .zero(currency: quoteCurrency.currency)
                )
            )
        }
        if baseCurrency.isFiatCurrency, quoteCurrency.isFiatCurrency {
            return price(for: FiatCurrency(code: baseCurrency.code)!, in: FiatCurrency(code: quoteCurrency.code)!, at: date)
        }

        var timestamp: UInt64?
        if let date = date {
            timestamp = UInt64(date.timeIntervalSince1970)
        }
        return client
            .price(for: baseCurrency.code, in: quoteCurrency.code, at: timestamp)
            .compactMap { try? PriceQuoteAtTime(response: $0, currency: quoteCurrency) }
            .eraseToAnyPublisher()
    }

    private func price(
        for baseCurrency: FiatCurrency,
        in quoteCurrency: FiatCurrency,
        at date: Date? = nil
    ) -> AnyPublisher<PriceQuoteAtTime, NetworkError> {
        var timestamp: UInt64?
        if let date = date {
            timestamp = UInt64(date.timeIntervalSince1970)
        }
        let conversionCurrency = CryptoCurrency.coin(.bitcoin)
        let basePrice = client
            .price(for: conversionCurrency.code, in: baseCurrency.code, at: timestamp)
        let quotePrice = client
            .price(for: conversionCurrency.code, in: quoteCurrency.code, at: timestamp)

        return basePrice
            .zip(quotePrice)
            .map { basePrice, quotePrice in
                let price = basePrice.price != 0 ? quotePrice.price / basePrice.price : 0
                return PriceQuoteAtTime(
                    timestamp: basePrice.timestamp,
                    moneyValue: MoneyValue.create(major: "\(price)", currency: quoteCurrency.currency)!
                )
            }
            .eraseToAnyPublisher()
    }

    public func priceSeries(
        within window: PriceWindow,
        of baseCurrency: CryptoCurrency,
        in quoteCurrency: FiatCurrency
    ) -> AnyPublisher<HistoricalPriceSeries, NetworkError> {
        let start: TimeInterval = window.timeIntervalSince1970(
            cryptoCurrency: baseCurrency,
            calendar: .current,
            date: Date()
        )
        return client
            .priceSeries(
                of: baseCurrency.code,
                in: quoteCurrency.code,
                start: String(Int(start)),
                scale: String(window.scale)
            )
            .map { HistoricalPriceSeries(currency: baseCurrency, prices: $0) }
            .eraseToAnyPublisher()
    }
}
