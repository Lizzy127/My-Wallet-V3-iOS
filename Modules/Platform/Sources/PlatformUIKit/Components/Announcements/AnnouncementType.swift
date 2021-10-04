// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Foundation
import ToolKit

/// The announcement types as defined remotely
public enum AnnouncementType: String, Codable {
    case resubmitDocumentsAfterRecovery = "kyc_recovery_resubmission"
    case sddUsersFirstBuy = "sdd_users_buy"
    case simpleBuyKYCIncomplete = "sb_finish_signup"
    case simpleBuyPendingTransaction = "sb_pending_buy"
    case walletIntro = "wallet_intro"
    case buyBitcoin = "buy_btc"
    case verifyEmail = "verify_email"
    case transferBitcoin = "transfer_btc"
    case exchangeLinking = "pit_linking"
    case twoFA = "two_fa"
    case backupFunds = "backup_funds"
    case verifyIdentity = "kyc_incomplete"
    case resubmitDocuments = "kyc_resubmit"
    case newSwap = "swap_v2"
    case cloudBackup = "cloud_backup"
    case bitpay
    case kycAirdrop = "kyc_airdrop"
    case fiatFundsKYC = "fiat_funds_kyc"
    case fiatFundsNoKYC = "fiat_funds_no_kyc"
    case interestFunds = "interest_funds"
    case newAsset = "new_asset"
    case assetRename = "asset_rename"

    /// The key identifying the announcement in cache
    var key: AnnouncementRecord.Key {
        switch self {
        case .resubmitDocumentsAfterRecovery:
            return .resubmitDocumentsAfterRecovery
        case .sddUsersFirstBuy:
            return .sddUsersFirstBuy
        case .newSwap:
            return .newSwap
        case .cloudBackup:
            return .cloudBackup
        case .walletIntro:
            return .walletIntro
        case .verifyEmail:
            return .verifyEmail
        case .buyBitcoin:
            return .buyBitcoin
        case .transferBitcoin:
            return .transferBitcoin
        case .kycAirdrop:
            return .kycAirdrop
        case .exchangeLinking:
            return .exchange
        case .twoFA:
            return .twoFA
        case .backupFunds:
            return .backupFunds
        case .verifyIdentity:
            return .identityVerification
        case .bitpay:
            return .bitpay
        case .resubmitDocuments:
            return .resubmitDocuments
        case .simpleBuyPendingTransaction:
            return .simpleBuyPendingTransaction
        case .simpleBuyKYCIncomplete:
            return .simpleBuyKYCIncomplete
        case .fiatFundsKYC:
            return .fiatFundsKYC
        case .fiatFundsNoKYC:
            return .fiatFundsNoKYC
        case .interestFunds:
            return .interestFunds
        case .newAsset:
            #if INTERNAL_BUILD
            unimplemented("AnnouncementType.newAsset does not have a default key.")
            #else
            return .newAsset(code: "")
            #endif
        case .assetRename:
            #if INTERNAL_BUILD
            unimplemented("AnnouncementType.assetRename does not have a default key.")
            #else
            return .assetRename(code: "")
            #endif
        }
    }
}