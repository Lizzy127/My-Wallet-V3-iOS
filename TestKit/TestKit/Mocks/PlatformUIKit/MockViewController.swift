// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import UIKit

public final class MockViewController: UIViewController {
    
    public struct RecordedInvocations {
        public var presentViewController: [UIViewController] = []
    }
    
    private(set) public var recordedInvocations = RecordedInvocations()
    
    override public func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        recordedInvocations.presentViewController.append(viewControllerToPresent)
    }
}
