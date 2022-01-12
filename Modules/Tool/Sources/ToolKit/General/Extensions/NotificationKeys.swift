// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Foundation

extension Notification.Name {
    public static let login = Notification.Name("notification_did_login")
    public static let logout = Notification.Name("notification_did_logout")
    public static let kycStatusChanged = Notification.Name("notification_kyc_status_did_change")
    public static let transaction = Notification.Name("notification_did_transaction")
}
