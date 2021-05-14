// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import DIKit
import PlatformKit
import RxSwift
import ToolKit

extension Coincore {
    
    public func createTransactionProcessor(
        with account: SingleAccount,
        target: TransactionTarget,
        action: AssetAction
    ) -> Single<TransactionProcessor> {
        switch account {
        case is CryptoNonCustodialAccount:
            return createOnChainProcessor(
                with: account as! CryptoNonCustodialAccount,
                target: target,
                action: action
            )
        case is CryptoTradingAccount:
            return createTradingProcessor(
                with: account as! CryptoTradingAccount,
                target: target,
                action: action
            )
        default:
            impossible()
        }
    }

    private func createOnChainProcessor(with account: CryptoNonCustodialAccount,
                                        target: TransactionTarget,
                                        action: AssetAction) -> Single<TransactionProcessor> {
        switch (target, action) {
        case (is BitPayInvoiceTarget, .send):
            let factory = { () -> OnChainTransactionEngineFactory in resolve(tag: account.asset) }()
            return account
                .requireSecondPassword
                .map { (requiresSecondPassword) -> TransactionProcessor in
                    .init(sourceAccount: account,
                          transactionTarget: target,
                          engine: BitPayTransactionEngine(
                            onChainEngine: factory.build(requiresSecondPassword: requiresSecondPassword)
                          )
                    )
                }
        case (is CryptoAccount, .swap):
            let factory = { () -> OnChainTransactionEngineFactory in resolve(tag: account.asset) }()
            return account
                .requireSecondPassword
                .map { (requiresSecondPassword) -> TransactionProcessor in
                    .init(sourceAccount: account,
                          transactionTarget: target,
                          engine: OnChainSwapTransactionEngine(
                            quotesEngine: SwapQuotesEngine(),
                            requireSecondPassword: requiresSecondPassword,
                            onChainEngine: factory.build(requiresSecondPassword: requiresSecondPassword)
                          )
                    )
                }
        case (is CryptoReceiveAddress, .send):
            let factory = { () -> OnChainTransactionEngineFactory in resolve(tag: account.asset) }()
            
            /// `Target` must be a `CryptoReceiveAddress`
            guard let receiveAddress = target as? CryptoReceiveAddress else {
                fatalError("Expected a receiveAddress: \(target)")
            }
            return account
                .requireSecondPassword
                .map { requiresSecondPassword -> TransactionProcessor in
                    .init(
                        sourceAccount: account,
                        transactionTarget: receiveAddress,
                        engine: factory.build(requiresSecondPassword: requiresSecondPassword)
                    )
                }
            
        case (is CryptoAccount, .send):
            let factory = { () -> OnChainTransactionEngineFactory in resolve(tag: account.asset) }()
            
            /// `Target` must be a `CryptoReceiveAddress`
            guard let destination = target as? SingleAccount else {
                fatalError("Expected a SingleAccount: \(target)")
            }
            let data = Single.zip(destination.receiveAddress,
                                  account.requireSecondPassword)
            return data
                .map { values -> TransactionProcessor in
                    let (receiveAddress, requiresSecondPassword) = values
                    return .init(
                        sourceAccount: account,
                        transactionTarget: receiveAddress,
                        engine: factory.build(requiresSecondPassword: requiresSecondPassword)
                    )
                }
        default:
            unimplemented()
        }
    }

    private func createTradingProcessor(with account: CryptoTradingAccount,
                                        target: TransactionTarget,
                                        action: AssetAction) -> Single<TransactionProcessor> {
        switch action {
        case .swap:
            return createTradingProcessorSwap(with: account, target: target)
        case .send:
            return createTradingProcessorSend(with: account, target: target)
        case .sell:
            unimplemented() // CustodialSellTxEngine
        case .deposit, .receive, .viewActivity, .withdraw:
            unimplemented()
        }
    }

    private func createTradingProcessorSwap(with account: CryptoTradingAccount,
                                            target: TransactionTarget) -> Single<TransactionProcessor> {
        Single.just(
            TransactionProcessor(
                sourceAccount: account,
                transactionTarget: target as! CryptoTradingAccount,
                engine: TradingToTradingSwapTransactionEngine(
                    quotesEngine: SwapQuotesEngine()
                )
            )
        )
    }

    private func createTradingProcessorSend(with account: CryptoTradingAccount,
                                            target: TransactionTarget) -> Single<TransactionProcessor> {
        let receiveAddressTarget: Single<ReceiveAddress>
        switch target {
        case is ReceiveAddress:
            receiveAddressTarget = .just(target as! ReceiveAddress)
        case is CryptoAccount:
            receiveAddressTarget = (target as! CryptoAccount).receiveAddress
        default:
            impossible()
        }
        return receiveAddressTarget
            .map { receiveAddress -> TransactionProcessor in
                TransactionProcessor(
                    sourceAccount: account,
                    transactionTarget: receiveAddress,
                    engine: TradingToOnChainTransactionEngine()
                )
            }
    }
}