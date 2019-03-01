//
//  CardsViewController+KYC.swift
//  Blockchain
//
//  Created by Chris Arriola on 10/31/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import RxSwift

extension CardsViewController {
    @objc func reloadAllCards() {
        // Ignoring the disposable here since it can't be stored in CardsViewController.m/.h
        // since RxSwift doesn't work in Obj-C.
        guard WalletManager.shared.wallet.isInitialized() == true else { return }
        _ = Observable.zip(BlockchainDataRepository.shared.nabuUser, ExchangeService.shared.hasExecutedTrades().asObservable())
            .subscribeOn(MainScheduler.asyncInstance)
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] nabuUser, hasTrades in
                guard let strongSelf = self else { return }
                let canShowSwapCTA = nabuUser.swapApproved()
                let shouldHideSwapCTA = BlockchainSettings.App.shared.shouldHideSwapCard
                
                /// We display the `Swap` card if the user has not submitted a trade,
                /// has not hidden the card before, and if the user is at least tier1 approved.
                let displaySwapCTA = (hasTrades == false && shouldHideSwapCTA == false && canShowSwapCTA)
                if displaySwapCTA {
                    strongSelf.showSwapCTA()
                }
                
                /// If the user has traded before we need to set this flag as this is the only way
                /// `CardsViewController` can determine if it needs to show the `Swap` card.
                if hasTrades == true {
                    BlockchainSettings.App.shared.shouldHideSwapCard = true
                }
                
                let didShowAirdropAndKycCards = strongSelf.showAirdropAndKycCards(nabuUser: nabuUser)
                if !didShowAirdropAndKycCards {
                    strongSelf.reloadWelcomeCards()
                }
                strongSelf.dashboardScrollView.contentSize = CGSize(
                    width: strongSelf.view.frame.size.width,
                    height: strongSelf.dashboardContentView.frame.size.height + strongSelf.cardsViewHeight
                )
            }, onError: { [weak self] error in
                guard let strongSelf = self else { return }
                Logger.shared.error("Failed to get nabu user")
                strongSelf.reloadWelcomeCards()
                strongSelf.dashboardScrollView.contentSize = CGSize(
                    width: strongSelf.view.frame.size.width,
                    height: strongSelf.dashboardContentView.frame.size.height + strongSelf.cardsViewHeight
                )
            })
    }

    private func showAirdropAndKycCards(nabuUser: NabuUser) -> Bool {
        let airdropConfig = AppFeatureConfigurator.shared.configuration(for: .stellarAirdrop)
        let appSettings = BlockchainSettings.App.shared
        let kycSettings = KYCSettings.shared
        let onboardingSettings = BlockchainSettings.Onboarding.shared

        let shouldShowStellarAirdropCard = airdropConfig.isEnabled &&
            !onboardingSettings.hasSeenAirdropJoinWaitlistCard &&
            !appSettings.didTapOnAirdropDeepLink
        let shouldShowContinueKYCAnnouncementCard = kycSettings.isCompletingKyc
        let shouldShowAirdropPending = airdropConfig.isEnabled &&
            appSettings.didRegisterForAirdropCampaignSucceed &&
            nabuUser.status == .approved &&
            !appSettings.didSeeAirdropPending

        if shouldShowAirdropPending {
            showAirdropPending()
            return true
        } else if nabuUser.needsDocumentResubmission != nil {
            showUploadDocumentsCard()
            return true
        } else if shouldShowContinueKYCAnnouncementCard {
            showContinueKycCard()
            return true
        } else if shouldShowStellarAirdropCard {
            showStellarAirdropCard()
            return true
        }
        return false
    }

    private func showAirdropPending() {
        let model = AnnouncementCardViewModel.airdropOnItsWay(action: {}, onClose: { [weak self] in
            BlockchainSettings.App.shared.didSeeAirdropPending = true
            self?.animateHideCards()
        })
        showSingleCard(with: model)
    }

    private func showStellarAirdropCard() {
        let model = AnnouncementCardViewModel.joinAirdropWaitlist(action: {
            UIApplication.shared.openWebView(
                url: Constants.Url.airdropWaitlist,
                title: LocalizationConstants.Stellar.claimYourFreeXLMNow,
                presentingViewController: AppCoordinator.shared.tabControllerManager
            )
        }, onClose: { [weak self] in
            BlockchainSettings.Onboarding.shared.hasSeenAirdropJoinWaitlistCard = true
            self?.animateHideCards()
        })
        showSingleCard(with: model)
    }
    
    private func showSwapCTA() {
        let model = AnnouncementCardViewModel.swapCTA(action: {
            let tabController = AppCoordinator.shared.tabControllerManager
            ExchangeCoordinator.shared.start(rootViewController: tabController)
        }) { [weak self] in
            BlockchainSettings.App.shared.shouldHideSwapCard = true
            self?.animateHideCards()
        }
        showSingleCard(with: model)
    }

    private func showContinueKycCard() {
        let appSettings = BlockchainSettings.App.shared
        let kycSettings = KYCSettings.shared
        let isAirdropUser = appSettings.didRegisterForAirdropCampaignSucceed
        let model = AnnouncementCardViewModel.continueWithKYC(isAirdropUser: isAirdropUser, action: { [unowned self] in
            self.continueKyc()
        }, onClose: { [weak self] in
            kycSettings.isCompletingKyc = false
            self?.animateHideCards()
        })
        showSingleCard(with: model)
    }

    private func continueKyc() {
        // Ignoring the disposable here since it can't be stored in CardsViewController.m/.h
        // since RxSwift doesn't work in Obj-C.
        _ = BlockchainDataRepository.shared.fetchNabuUser()
            .subscribeOn(MainScheduler.asyncInstance)
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] user in
                guard self != nil else {
                    return
                }
                let tier = user.tiers?.selected ?? .tier1
                KYCCoordinator.shared.start(from: AppCoordinator.shared.tabControllerManager, tier: tier)
            })
    }

    private func showUploadDocumentsCard() {
        let model = AnnouncementCardViewModel.resubmitDocuments(action: { [unowned self] in
            self.continueKyc()
        }, onClose: { [weak self] in
            self?.animateHideCards()
        })
        showSingleCard(with: model)
    }
}