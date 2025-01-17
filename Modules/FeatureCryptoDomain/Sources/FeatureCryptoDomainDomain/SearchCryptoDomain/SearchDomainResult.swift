// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Localization

private typealias LocalizedString = LocalizationConstants.FeatureCryptoDomain.SearchDomain

public enum DomainType: Equatable {
    case free
    case premium

    public var statusLabel: String {
        switch self {
        case .free:
            return LocalizedString.ListView.freeDomain
        case .premium:
            return LocalizedString.ListView.premiumDomain
        }
    }
}

public enum DomainAvailability: Equatable {
    case availableForFree
    case availableForPremiumSale(price: String)
    case unavailable

    public var availabilityLabel: String {
        switch self {
        case .availableForFree:
            return LocalizedString.ListView.free
        case .availableForPremiumSale(let price):
            return "$\(price)"
        case .unavailable:
            return LocalizedString.ListView.unavailable
        }
    }
}

public struct SearchDomainResult: Equatable {
    public let domainName: String
    public let domainType: DomainType
    public let domainAvailability: DomainAvailability

    public init(
        domainName: String,
        domainType: DomainType,
        domainAvailability: DomainAvailability
    ) {
        self.domainName = domainName
        self.domainType = domainType
        self.domainAvailability = domainAvailability
    }
}
