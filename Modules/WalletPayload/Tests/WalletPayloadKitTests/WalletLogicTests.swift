// Copyright © Blockchain Luxembourg S.A. All rights reserved.

@testable import MetadataKit
@testable import MetadataKitMock
@testable import WalletPayloadDataKit
@testable import WalletPayloadKit

import Combine
import TestKit
import ToolKit
import XCTest

class WalletLogicTests: XCTestCase {

    private let jsonV4 = Fixtures.loadJSONData(filename: "wallet.v4", in: .module)!

    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    func test_wallet_logic_can_initialize_a_wallet() {
        let walletHolder = WalletHolder()
        var decoderWalletCalled = false
        let decoder: WalletDecoding = { data -> AnyPublisher<NativeWallet, WalletError> in
            decoderWalletCalled = true
            return WalletDecoder().createWallet(from: data)
        }
        let metadataService = MetadataServiceMock()

        let walletLogic = WalletLogic(
            holder: walletHolder,
            decoder: decoder,
            metadata: metadataService,
            notificationCenter: .default
        )

        metadataService.initializeValue = .just(MetadataState.mock)

        let expectation = expectation(description: "wallet-fetching-expectation")

        walletLogic.initialize(with: "password", payload: jsonV4)
            .sink { _ in
                //
            } receiveValue: { _ in
                XCTAssertTrue(decoderWalletCalled)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2)

        XCTAssertTrue(walletHolder.walletState.value!.isInitialised)
    }
}
