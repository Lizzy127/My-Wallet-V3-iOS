//  Copyright © 2021 Blockchain Luxembourg S.A. All rights reserved.

import SwiftUI

struct TaggedView<Tag, Content: View>: View where Tag: Blockchain.Tag {

    let tag: Tag
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .identity(tag)
    }
}

extension View {

    @ViewBuilder
    func identity<Tag>(_ tag: Tag) -> some View where Tag: Blockchain.Tag {
        id(tag)
            .accessibility(identifier: tag())
    }
}

/// A unique identifier backed by a String value, allowing us to create safer ways to
/// define, share and reuse identifiers across the blockchain.com iOS app.
/// Eventually we will want to move this into a new swift package, however, before
/// that happens we need to produce an RFC document highlighting the usage of
/// this tool and it's future direction.
class Tag: Hashable {

    let _id: String

    required init(_ id: String) {
        _id = id
    }

    func callAsFunction() -> String { _id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(_id)
    }

    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs._id == rhs._id
    }
}

extension Tag: CustomStringConvertible {

    var description: String { _id }
}

extension Equatable where Self: Tag {

    static var id: String {
        String(describing: Self.self).tagTypeToId
    }
}

extension Identifiable where Self: Tag {

    var id: String {
        String(describing: Self.self).tagTypeToId
    }
}

extension String {

    var tagTypeToId: String {
        split(separator: "_")
            .dropFirst()
            .joined(separator: ".")
    }
}
