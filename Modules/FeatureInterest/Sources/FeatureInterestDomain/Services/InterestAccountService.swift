// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import DIKit
import MoneyKit
import PlatformKit
import RxSwift
import ToolKit

final class InterestAccountService: InterestAccountServiceAPI {

    // MARK: - Private Properties

    private let fiatCurrencyService: FiatCurrencyServiceAPI
    private let kycTiersService: KYCTiersServiceAPI
    private let priceService: PriceServiceAPI
    private let interestAccountBalanceRepository: InterestAccountBalanceRepositoryAPI
    private let interestAccountLimitsRepository: InterestAccountLimitsRepositoryAPI
    private let interestAccountEligibilityRepository: InterestAccountEligibilityRepositoryAPI
    private let interestAccountRateRepository: InterestAccountRateRepositoryAPI

    // MARK: - Setup

    init(
        interestAccountBalanceRepository: InterestAccountBalanceRepositoryAPI = resolve(),
        interestAccountLimitsRepository: InterestAccountLimitsRepositoryAPI = resolve(),
        interestAccountEligibilityRepository: InterestAccountEligibilityRepositoryAPI = resolve(),
        interestAccountRateRepository: InterestAccountRateRepositoryAPI = resolve(),
        fiatCurrencyService: FiatCurrencyServiceAPI = resolve(),
        kycTiersService: KYCTiersServiceAPI = resolve(),
        priceService: PriceServiceAPI = resolve()
    ) {
        self.interestAccountRateRepository = interestAccountRateRepository
        self.interestAccountEligibilityRepository = interestAccountEligibilityRepository
        self.interestAccountLimitsRepository = interestAccountLimitsRepository
        self.interestAccountBalanceRepository = interestAccountBalanceRepository
        self.priceService = priceService
        self.fiatCurrencyService = fiatCurrencyService
        self.kycTiersService = kycTiersService
    }

    // MARK: - InterestAccountServiceAPI

    func fetchInterestAccountLimitsForCryptoCurrency(
        _ currency: CryptoCurrency
    ) -> Single<InterestAccountLimits?> {
        fiatCurrencyService
            .fiatCurrency
            .flatMap(weak: self) { (self, fiatCurrency) in
                self.interestAccountLimitsRepository
                    .fetchInterestAccountLimitsForAllAssets(fiatCurrency)
                    .asObservable()
                    .take(1)
                    .asSingle()
            }
            .map { $0.filter { $0.cryptoCurrency == currency } }
            .map(\.first)
    }

    func fetchInterestAccountDetailsForCryptoCurrency(
        _ currency: CryptoCurrency
    ) -> Single<ValueCalculationState<InterestAccountBalanceDetails>> {
        details(for: currency)
    }

    func details(for currency: CryptoCurrency) -> Single<ValueCalculationState<InterestAccountBalanceDetails>> {
        interestAccountsBalance
            .map { balances in
                switch balances[currency] {
                case .none:
                    return .invalid(.empty)
                case .some(let details):
                    return .value(details)
                }
            }
    }

    // MARK: - InterestAccountOverviewAPI

    func balance(for currency: CryptoCurrency) -> Single<CustodialAccountBalanceState> {
        interestAccountsBalance
            .map(CustodialAccountBalanceStates.init)
            .map(\.[currency.currencyType])
    }

    func rate(for currency: CryptoCurrency) -> Single<Double> {
        interestAccountRateRepository
            .fetchInterestAccountRateForCryptoCurrency(currency)
            .map(\.rate)
            .asSingle()
    }

    private var interestAccountsBalance: Single<InterestAccountBalances> {
        Single
            .zip(
                kycTiersService.tiers.map(\.isTier2Approved).asSingle(),
                fiatCurrencyService.fiatCurrency
            )
            .flatMap { [interestAccountBalanceRepository] tier2Approved, fiatCurrency
                -> Single<InterestAccountBalances> in
                guard tier2Approved else {
                    return .just(.empty)
                }
                return interestAccountBalanceRepository
                    .fetchInterestAccountsBalance(fiatCurrency: fiatCurrency)
                    .asSingle()
            }
            .catchErrorJustReturn(InterestAccountBalances.empty)
    }
}
