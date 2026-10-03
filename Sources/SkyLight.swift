import AppKit

// Private macOS functions, the same ones AltTab and yabai use to focus a window on any Space
// (desktop), including full-screen ones. They are looked up at runtime: if a future macOS
// removes one, SameSide stops switching windows instead of failing to launch.
private let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

private func symbol<T>(_ name: String, as _: T.Type) -> T? {
    dlsym(RTLD_DEFAULT, name).map { unsafeBitCast($0, to: T.self) }
}

private let getProcessForPID = symbol("GetProcessForPID",
    as: (@convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus).self)
private let setFrontProcess = symbol("_SLPSSetFrontProcessWithOptions",
    as: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError).self)
private let postEventRecord = symbol("SLPSPostEventRecordTo",
    as: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError).self)
private let axGetWindow = symbol("_AXUIElementGetWindow",
    as: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
private let axCreateWithRemoteToken = symbol("_AXUIElementCreateWithRemoteToken",
    as: (@convention(c) (CFData) -> Unmanaged<AXUIElement>?).self)
private let mainConnectionID = symbol("SLSMainConnectionID", as: (@convention(c) () -> Int32).self)
private let copySpacesForWindows = symbol("SLSCopySpacesForWindows",
    as: (@convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?).self)

/// Names of the private functions this macOS no longer has. Logged once at launch.
func missingPrivateFunctions() -> [String] {
    [("GetProcessForPID", getProcessForPID != nil), ("_SLPSSetFrontProcessWithOptions", setFrontProcess != nil),
     ("SLPSPostEventRecordTo", postEventRecord != nil), ("_AXUIElementGetWindow", axGetWindow != nil),
     ("_AXUIElementCreateWithRemoteToken", axCreateWithRemoteToken != nil),
     ("SLSMainConnectionID", mainConnectionID != nil), ("SLSCopySpacesForWindows", copySpacesForWindows != nil)]
        .filter { !$0.1 }.map(\.0)
}

/// Number of Spaces the window is on. Zero for minimized windows and windows that are not shown.
func spaceCount(of window: CGWindowID) -> Int {
    guard let mainConnectionID, let copySpacesForWindows,
          let spaces = copySpacesForWindows(mainConnectionID(), 7, [window] as CFArray)?.takeRetainedValue() else { return 0 }
    return CFArrayGetCount(spaces)
}

/// Makes `window` of process `pid` the focused window. macOS switches to its Space if needed.
/// Returns false if the private functions are missing or refused.
@discardableResult
func focus(pid: pid_t, window: CGWindowID) -> Bool {
    guard let getProcessForPID, let setFrontProcess, let postEventRecord else { return false }
    var psn = ProcessSerialNumber()
    guard getProcessForPID(pid, &psn) == noErr,
          setFrontProcess(&psn, window, 0x200) == .success else { return false }  // 0x200: user generated
    // Make the window key with one synthetic mouse-down record, as current AltTab does:
    // - 0x100 zeroed bytes although the record is 0xf8: macOS 14.7.4+ reads past it (paneru#123).
    // - mouse-down only: a down/up pair is a real click on the window's content (AltTab #5381).
    // - aimed far past the bottom-right: NaN lands on top-left controls, near the edge resizes (AltTab #5900).
    var bytes = [UInt8](repeating: 0, count: 0x100)
    var point = CGPoint(x: 300_000, y: 300_000)
    var id = window
    bytes[0x04] = 0xf8  // record length
    bytes[0x08] = 0x01  // left mouse down
    bytes[0x3a] = 0x10
    memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)
    memcpy(&bytes[0x3c], &id, MemoryLayout<CGWindowID>.size)
    _ = postEventRecord(&psn, &bytes)
    // When the app is already active the calls above do not switch Spaces; raising the
    // window through Accessibility does.
    if let element = accessibilityWindow(pid: pid, window: window) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    } else {
        log.debug("no Accessibility element for window \(window); its Space may not switch")
    }
    return true
}

/// The Accessibility element for `window`, also when it is on a Space that is not showing.
private func accessibilityWindow(pid: pid_t, window: CGWindowID) -> AXUIElement? {
    guard let axGetWindow else { return nil }
    // Buttons and groups inside a window report their window's id too, so also require the window role.
    func isTarget(_ element: AXUIElement) -> Bool {
        var id: CGWindowID = 0
        var role: CFTypeRef?
        return axGetWindow(element, &id) == .success && id == window
            && AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success
            && role as? String == kAXWindowRole
    }
    var list: CFTypeRef?
    if AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &list) == .success,
       let found = (list as? [AXUIElement])?.first(where: isTarget) {
        return found
    }
    // The normal list leaves out windows on hidden Spaces. Probe element ids directly, as AltTab
    // does: the token is pid (4 bytes), 0 (4), "coco" (4), element id (8). Ids are sparse, so the
    // only bound is time (AltTab's 250 ms budget; this runs off the main thread).
    guard let axCreateWithRemoteToken else { return nil }
    var token = Data(count: 20)
    withUnsafeBytes(of: pid) { token.replaceSubrange(0..<4, with: $0) }
    withUnsafeBytes(of: Int32(0x636f636f)) { token.replaceSubrange(8..<12, with: $0) }
    let deadline = ProcessInfo.processInfo.systemUptime + 0.25
    var elementID: UInt64 = 0
    while ProcessInfo.processInfo.systemUptime < deadline {
        withUnsafeBytes(of: elementID) { token.replaceSubrange(12..<20, with: $0) }
        if let element = axCreateWithRemoteToken(token as CFData)?.takeRetainedValue(), isTarget(element) {
            return element
        }
        elementID += 1
    }
    return nil
}
