// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import PlatformUIKit
import RIBs

// MARK: - Builder

protocol SwapBootstrapBuildable: Buildable {
    func build(withListener listener: SwapBootstrapListener) -> SwapBootstrapRouting
}

final class SwapBootstrapBuilder: SwapBootstrapBuildable {

    func build(withListener listener: SwapBootstrapListener) -> SwapBootstrapRouting {
        let viewController = SwapBootstrapViewController()
        let interactor = SwapBootstrapInteractor(presenter: viewController)
        interactor.listener = listener
        return SwapBootstrapRouter(interactor: interactor, viewController: viewController)
    }
}