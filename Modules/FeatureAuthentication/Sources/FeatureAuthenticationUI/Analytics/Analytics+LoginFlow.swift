// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import AnalyticsKit
import FeatureAuthenticationDomain

// TODO: refactor this when secure channel is moved to feature authentication
enum LoginSource {
    case secureChannel
    case magicLink
}

extension AnalyticsEvents.New {
    enum LoginFlow: AnalyticsEvent, Equatable {
        case loginClicked(
            origin: Origin
        )
        case loginViewed
        case loginIdentifierEntered(
            identifierType: IdentifierType
        )
        case loginPasswordEntered
        case loginRequestApproved(LoginSource)
        case loginRequestDenied(LoginSource)
        case loginTwoStepVerificationEntered
        case loginTwoStepVerificationDenied
        case deviceVerified(
            wallet: WalletInfo
        )

        var type: AnalyticsEventType { .nabu }

        var params: [String: Any]? {
            switch self {
            case .deviceVerified(let info):
                let walletInfoDecoded: [String: Any] = [
                    "guid_first_four": String(info.wallet?.guid.prefix(4) ?? ""),
                    "has_cloud_backup": info.wallet?.hasCloudBackup ?? false,
                    "is_mobile_setup": info.wallet?.isMobileSetup ?? false,
                    "mobile_device_type": Device.iOS.rawValue
                ]
                return ["wallet": walletInfoDecoded]
            case .loginPasswordEntered,
                 .loginTwoStepVerificationEntered,
                 .loginViewed,
                 .loginTwoStepVerificationDenied:
                return [:]

            case .loginRequestApproved(let source),
                 .loginRequestDenied(let source):
                return [
                    "login_source": String(describing: source)
                ]

            case .loginClicked(let origin):
                return [
                    "origin": origin.rawValue
                ]
            case .loginIdentifierEntered(let identifierType):
                return [
                    "identifier_type": identifierType.rawValue
                ]
            }
        }

        // MARK: Helpers

        enum IdentifierType: String, StringRawRepresentable {
            case email = "EMAIL"
            case walletId = "WALLET-ID"
        }

        enum Device: String, StringRawRepresentable {
            case iOS = "APP-iOS"
        }

        enum Origin: String, StringRawRepresentable {
            case navigation = "NAVIGATION"
        }
    }
}

extension AnalyticsEvents.New.LoginFlow {
    /// - Returns: The case of `.loginClicked` with default parameters
    static func loginClicked() -> Self {
        .loginClicked(
            origin: .navigation
        )
    }

    /// This returns the case `.deviceVerified` with default parameters
    /// - Parameter info: The `WalletInfo` as received from the deeplink
    static func deviceVerified(info: WalletInfo) -> Self {
        .deviceVerified(
            wallet: info
        )
    }
}

extension AnalyticsEventRecorderAPI {
    /// Helper method to record `LoginFlow` events
    /// - Parameter event: A `LoginFlow` event to be tracked
    func record(event: AnalyticsEvents.New.LoginFlow) {
        record(event: event)
    }
}
