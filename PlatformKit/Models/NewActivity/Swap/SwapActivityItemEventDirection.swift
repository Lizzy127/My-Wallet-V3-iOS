//
//  SwapActivityItemEventDirection.swift
//  PlatformKit
//
//  Created by Alex McGregor on 10/19/20.
//  Copyright © 2020 Blockchain Luxembourg S.A. All rights reserved.
//

// TODO: This is replicated in `TransactionKit`.
public enum SwapActivityItemEventDirection: String, Codable {
    /// From non-custodial to non-custodial
    case onChain = "ON_CHAIN"
    /// From non-custodial to custodial
    case fromUserKey = "FROM_USERKEY"
    /// From custodial to non-custodial
    case toUserKey = "TO_USERKEY"
    /// From custodial to custodial
    case `internal` = "INTERNAL"
}
