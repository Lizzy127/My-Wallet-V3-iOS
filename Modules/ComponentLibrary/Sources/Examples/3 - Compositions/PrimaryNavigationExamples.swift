// Copyright © Blockchain Luxembourg S.A. All rights reserved.

@testable import ComponentLibrary
import SwiftUI

struct PrimaryNavigationExamples: View {
    var body: some View {
        VStack {
            Text("👆")
                .typography(.display)

            Spacer()

            PrimaryNavigationLink(
                destination: Text("Try swipe to go back").primaryNavigation(title: "Another view")
            ) {
                Text("Tap to push another view")
                    .typography(.title3)
            }

            Spacer()
        }
        .primaryNavigation(title: "Navigation") {
            IconButton(icon: .qRCode) {}

            IconButton(icon: .user) {}
        }
    }
}

struct PrimaryNavigationExamples_Previews: PreviewProvider {
    static var previews: some View {
        PrimaryNavigationView {
            PrimaryNavigationExamples()
        }
        .previewDisplayName("Wallet")

        PrimaryNavigationView {
            PrimaryNavigationExamples()
        }
        .environment(\.navigationUsesCircledBackButton, false)
        .previewDisplayName("Exchange")
    }
}