import AVFoundation
import Foundation
import Testing
@testable import AddLadder

@MainActor
private func never() async -> Bool {
    Issue.record("the user should not have been asked")
    return false
}

@MainActor
@Test func grantedCameraOnCapableHardwareIsReady() async {
    let availability = await ScannerPermission.resolve(
        isSupported: true, status: .authorized, requestAccess: never
    )
    #expect(availability == .ready)
}

@MainActor
@Test func aFirstTimeUserIsAskedRatherThanSentToSettings() async {
    // The bug this test exists for: `.notDetermined` reads as "no access" if you
    // squint, and treating it as denial tells someone their camera is off before
    // anyone has ever asked them for it.
    var asked = false
    let availability = await ScannerPermission.resolve(
        isSupported: true,
        status: .notDetermined,
        requestAccess: { asked = true; return true }
    )
    #expect(asked)
    #expect(availability == .ready)
}

@MainActor
@Test func sayingNoToThePromptIsADenial() async {
    let availability = await ScannerPermission.resolve(
        isSupported: true, status: .notDetermined, requestAccess: { false }
    )
    #expect(availability == .permissionDenied)
}

@MainActor
@Test func anAlreadyAnsweredNoIsNotAskedAgain() async {
    for settled in [AVAuthorizationStatus.denied, .restricted] {
        let availability = await ScannerPermission.resolve(
            isSupported: true, status: settled, requestAccess: never
        )
        #expect(availability == .permissionDenied)
    }
}

@MainActor
@Test func hardwareIsCheckedBeforeTheUserIsBothered() async {
    // We get one permission prompt. Spending it on a device that cannot scan
    // means the real ask, later, is the one the user has already dismissed.
    for status in [AVAuthorizationStatus.notDetermined, .authorized, .denied] {
        let availability = await ScannerPermission.resolve(
            isSupported: false, status: status, requestAccess: never
        )
        #expect(availability == .unsupportedDevice)
    }
}

@MainActor
@Test func anUnrecognisedStatusIsNotTreatedAsPermission() async {
    let availability = await ScannerPermission.resolve(
        isSupported: true,
        status: AVAuthorizationStatus(rawValue: 99) ?? .denied,
        requestAccess: never
    )
    #expect(availability == .permissionDenied)
}
