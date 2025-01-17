// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import Foundation

public protocol AppProtocol: AnyObject, CustomStringConvertible {
    var language: Language { get }
    var events: Session.Events { get }
}

public class App: AppProtocol, CustomStringConvertible {

    public let language: Language
    public let events: Session.Events = .init()

    public init(language: Language = Language.root.language) {
        self.language = language
    }
}

extension AppProtocol {

    public func post(event id: L, context: Tag.Context = [:]) {
        post(event: language[id], context: context)
    }

    public func post(event tag: Tag, context: Tag.Context = [:]) {
        events.send(Session.Event(tag: tag, context: context))
    }

    public func post<E: Error>(
        _ tag: L_blockchain_ux_type_analytics_error,
        error: E,
        context: Tag.Context = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        post(tag[], error: error, context: context, file: file, line: line)
    }

    public func post<E: Error>(
        error: E,
        context: Tag.Context = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        if let error = error as? Tag.Error {
            post(error.tag, error: error, context: context, file: file, line: line)
        } else {
            post(blockchain.ux.type.analytics.error[], error: error, context: context, file: file, line: line)
        }
    }

    private func post<E: Error>(
        _ tag: Tag,
        error: E,
        context: Tag.Context = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        events.send(
            Session.Event(
                tag: tag,
                context: context + [
                    e.message: "\(error)",
                    e.file: file,
                    e.line: line
                ]
            )
        )
    }

    public func on(
        _ first: L,
        _ rest: L...
    ) -> AnyPublisher<Session.Event, Never> {
        on([language[first]] + rest.map { language[$0] })
    }

    public func on(
        _ first: Tag,
        _ rest: Tag...
    ) -> AnyPublisher<Session.Event, Never> {
        on([first] + rest)
    }

    public func on<Tags>(
        _ tags: Tags
    ) -> AnyPublisher<Session.Event, Never> where Tags: Sequence, Tags.Element == Tag {
        events.is(tags).eraseToAnyPublisher()
    }
}

private let e = (
    message: blockchain.ux.type.analytics.error.message[],
    file: blockchain.ux.type.analytics.error.file[],
    line: blockchain.ux.type.analytics.error.line[]
)

extension App {
    public var description: String { "App \(language.id)" }
}
