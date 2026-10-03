import AppKit
import os

/// One line per Dock click, at debug level: macOS keeps nothing unless someone is watching
/// with `log stream --level debug`. Public so that stream shows it instead of `<private>`.
let log = Logger(subsystem: "io.github.karticksaxena.SameSide", category: "click")

// Menu bar icon with a Quit item. Info.plist sets LSUIElement, so there is no Dock icon.
let app = NSApplication.shared
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "SameSide")
if statusItem.button?.image == nil { statusItem.button?.title = "DH" }
let menu = NSMenu()
menu.addItem(withTitle: "Quit SameSide", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
statusItem.menu = menu

/// Window lookups and focusing run here, off the main thread that also serves the click watcher.
let worker = DispatchQueue(label: "io.github.karticksaxena.SameSide.focus")

/// Runs on every left mouse-down, before the Dock sees it. Only finds the clicked Dock app and
/// notes whether it is already active (before the Dock's own activation can change that);
/// the rest runs on `worker` once the click has been passed on.
/// ponytail: acts on mouse-down, so long-pressing or dragging a running app's icon also switches to it;
/// acting on mouse-up instead would race the Dock's own activation and could flicker.
func handleClick(at point: CGPoint) {
    guard let target = dockApp(at: point) else { return }
    let isFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    worker.async { bringForward(target, clickedAt: point, wasFrontmost: isFront) }
}

/// Focuses the app's window on the display that was clicked, switching that display's Space if needed.
func bringForward(_ target: NSRunningApplication, clickedAt point: CGPoint, wasFrontmost isFront: Bool) {
    let start = ProcessInfo.processInfo.systemUptime
    let displays = displayBounds()
    guard let mouseDisplay = displays.firstIndex(where: { $0.contains(point) }) else { return }
    let windows = appWindows(of: target)
    let pick = pickWindow(windows: windows.map(\.frame), displays: displays, mouseDisplay: mouseDisplay, appIsFrontmost: isFront)
    var outcome = "macOS default"
    if let pick {
        let focused = focus(pid: target.processIdentifier, window: windows[pick].id)
        outcome = "window on display \(displayIndex(of: windows[pick].frame, in: displays) ?? -1)"
            + (focused ? "" : " NOT focused (private window functions unavailable)")
    }
    let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
    log.debug("\(target.localizedName ?? "?", privacy: .public) clicked on display \(mouseDisplay), \(windows.count) windows, frontmost=\(isFront) -> \(outcome, privacy: .public) (\(ms, format: .fixed(precision: 1)) ms)")
}

var tap: CFMachPort?

/// Starts watching left clicks. Returns false until Accessibility permission is granted.
func startTap() -> Bool {
    tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue),
        callback: { _, type, event, _ in
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            case .leftMouseDown where event.flags.isDisjoint(with: [.maskControl, .maskCommand]):  // control-click opens the Dock menu, command-click shows the app in Finder
                handleClick(at: event.location)
            default:
                break
            }
            return Unmanaged.passUnretained(event)  // never swallow or change the click
        },
        userInfo: nil)
    guard let tap else { return false }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    return true
}

// Every Accessibility request (to the Dock or a hung app) gives up after this long.
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
let missing = missingPrivateFunctions()
if !missing.isEmpty {
    log.error("this macOS lacks \(missing.joined(separator: ", "), privacy: .public); windows on other desktops will not switch")
}
if !startTap() {
    // Ask for Accessibility permission, then retry until it is granted.
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
        if startTap() { timer.invalidate() }
    }
}
app.run()
