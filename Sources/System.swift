import AppKit

/// A window of another app, as the window server sees it.
struct AppWindow {
    let id: CGWindowID
    let frame: CGRect
}

private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
}

/// The running app whose Dock icon is under `point` (global top-left coordinates), or nil
/// for anything else: clicks outside the Dock, Trash, folders, stacks, apps not running yet.
/// The icon is matched to the app by bundle identifier (e.g. com.apple.Safari), never by name.
func dockApp(at point: CGPoint) -> NSRunningApplication? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    var hit: AXUIElement?
    // ponytail: asks the Dock on every left click (one quick IPC); add a screen-edge pre-check if clicks ever feel slow.
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(dock.processIdentifier),
                                           Float(point.x), Float(point.y), &hit) == .success,
          let item = hit, value(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
          let url = value(item, kAXURLAttribute) as? URL,
          let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    // Two copies of the same app can run at once; prefer the one this Dock icon points to.
    let path = url.resolvingSymlinksInPath().path
    return running.first { $0.bundleURL?.resolvingSymlinksInPath().path == path } ?? running.first
}

/// Bounds of every active display, left to right, in the same top-left coordinates as mouse events.
func displayBounds() -> [CGRect] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map(CGDisplayBounds).sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
}

/// The app's real windows on every Space, including full-screen ones, most recently used first.
/// Minimized windows are left out. Only bounds, owner, layer and id are read, so no Screen
/// Recording permission is needed.
func appWindows(of app: NSRunningApplication) -> [AppWindow] {
    let pid = app.processIdentifier
    let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // The full list is not in recency order; the on-screen list is front to back. Showing
    // windows go first in that order, so the app's focused window is first.
    // ponytail: windows on hidden Spaces keep the window server's order, not true recency.
    let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
        .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    let rank = Dictionary(onScreen.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    return all.compactMap { info -> AppWindow? in
        guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
              info[kCGWindowLayer as String] as? Int == 0,
              let id = info[kCGWindowNumber as String] as? CGWindowID,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              // ponytail: size floor drops toolbar strips and helper windows (e.g. Safari's 52-pt
              // full-screen toolbar); use Accessibility subroles if a real tiny window is ever missed.
              rect.width >= 100, rect.height >= 100,
              spaceCount(of: id) > 0 else { return nil }
        return AppWindow(id: id, frame: rect)
    }
    .enumerated()
    .sorted { (rank[$0.element.id] ?? Int.max, $0.offset) < (rank[$1.element.id] ?? Int.max, $1.offset) }
    .map(\.element)
}
