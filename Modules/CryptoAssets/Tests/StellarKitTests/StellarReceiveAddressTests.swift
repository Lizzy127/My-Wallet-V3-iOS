// Copyright © Blockchain Luxembourg S.A. All rights reserved.

@testable import StellarKit
import XCTest

final class StellarReceiveAddressTests: XCTestCase {

    func testStellarReceiveAddressAbsoluteURLIsCorrect() throws {
        let address = StellarReceiveAddress(
            address: StellarTestData.address,
            label: StellarTestData.label,
            memo: StellarTestData.memo
        )
        XCTAssertEqual(address.metadata.absoluteString, StellarTestData.urlStringWithMemo)
    }

    func testSEP7URIWithMemoTypeText() throws {
        let url = URL(string: StellarTestData.urlStringWithMemoType)!
        let address = SEP7URI(url: url)
        XCTAssertEqual(address?.absoluteString, StellarTestData.urlStringWithMemo)
    }

    func testSEP7URIWithoutMemoType() throws {
        let url = URL(string: StellarTestData.urlStringWithMemo)!
        let address = SEP7URI(url: url)
        XCTAssertEqual(address?.absoluteString, StellarTestData.urlStringWithMemo)
    }

    func testSEP7URIWithMemoTypeTextAmount() throws {
        let url = URL(string: StellarTestData.urlStringWithMemoAndAmount)!
        let address = SEP7URI(url: url)
        XCTAssertEqual(address?.absoluteString, StellarTestData.urlStringWithMemoAndAmount)
    }
}
