// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import UIKit

extension UIView {

    @discardableResult
    public func constraint(edgesTo other: UIView, insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        let constraints = [
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            leftAnchor.constraint(equalTo: other.leftAnchor, constant: insets.left),
            rightAnchor.constraint(equalTo: other.rightAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ]
        activate(constraints)
        return constraints
    }

    @discardableResult
    public func constraint(centerTo other: UIView, insets: CGPoint = .zero) -> [NSLayoutConstraint] {
        let constraints = [
            centerXAnchor.constraint(equalTo: other.centerXAnchor, constant: insets.x),
            centerYAnchor.constraint(equalTo: other.centerYAnchor, constant: insets.y)
        ]
        activate(constraints)
        return constraints
    }

    private func activate(_ constraints: [NSLayoutConstraint]) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(constraints)
    }
}
