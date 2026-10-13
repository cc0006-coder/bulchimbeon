import IOKit.pwr_mgt

/// IOKit power assertion 한 개. 이 앱이 건 assertion 만 해제하므로
/// caffeinate 등 다른 도구의 assertion 과 충돌하지 않는다.
final class PowerAssertion {
    enum Kind: String {
        case display = "PreventUserIdleDisplaySleep"
        case system = "PreventUserIdleSystemSleep"
    }

    private var assertionID: IOPMAssertionID = 0
    private(set) var isHeld = false

    @discardableResult
    func acquire(_ kind: Kind, reason: String) -> Bool {
        release()
        let result = IOPMAssertionCreateWithName(
            kind.rawValue as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isHeld = result == kIOReturnSuccess
        return isHeld
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        isHeld = false
    }

    deinit { release() }
}
