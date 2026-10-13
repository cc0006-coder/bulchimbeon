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
    private var lastKind: Kind = .system
    private var lastReason = ""

    @discardableResult
    func acquire(_ kind: Kind, reason: String) -> Bool {
        release()
        lastKind = kind
        lastReason = reason
        let result = IOPMAssertionCreateWithName(
            kind.rawValue as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isHeld = result == kIOReturnSuccess
        return isHeld
    }

    /// 들고 있다고 생각하는 assertion 이 시스템에 실제로 남아 있는지.
    /// (경쟁 앱의 "가끔 혼자 꺼져 있다" 류 문제 대비)
    func isActuallyHeld() -> Bool {
        guard isHeld else { return false }
        return IOPMAssertionCopyProperties(assertionID)?.takeRetainedValue() != nil
    }

    /// 근무지 이탈 시 같은 종류로 다시 건다.
    @discardableResult
    func reacquire() -> Bool {
        isHeld = false // 이미 사라진 ID 는 release 하지 않는다
        return acquire(lastKind, reason: lastReason)
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        isHeld = false
    }

    deinit { release() }
}
