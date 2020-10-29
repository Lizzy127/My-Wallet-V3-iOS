//
//  SwapKind.swift
//  PlatformKit
//
//  Created by Alex McGregor on 10/19/20.
//  Copyright © 2020 Blockchain Luxembourg S.A. All rights reserved.
//

public struct SwapKind: Decodable, Equatable {
    
    public let direction: SwapActivityItemEventDirection
    public let depositAddress: String?
    public let depositTxHash: String?
    public let withdrawalAddress: String?
    public let withdrawalTxHash: String?
    
    enum CodingKeys: String, CodingKey {
        case direction
        case depositAddress
        case depositTxHash
        case withdrawalAddress
        case withdrawalTxHash
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        direction = try values.decode(SwapActivityItemEventDirection.self, forKey: .direction)
        depositAddress = try values.decodeIfPresent(String.self, forKey: .depositAddress)
        depositTxHash = try values.decodeIfPresent(String.self, forKey: .depositTxHash)
        withdrawalAddress = try values.decodeIfPresent(String.self, forKey: .withdrawalAddress)
        withdrawalTxHash = try values.decodeIfPresent(String.self, forKey: .withdrawalTxHash)
    }
}
