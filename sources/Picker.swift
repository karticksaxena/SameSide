import CoreGraphics

/// Index of the display holding the largest part of `frame`, or nil if the frame is on no display.
func displayIndex(of frame: CGRect, in displays: [CGRect]) -> Int? {
    var best: Int?
    var bestArea: CGFloat = 0
    for (i, display) in displays.enumerated() {
        let overlap = frame.intersection(display)
        let area = overlap.isNull ? 0 : overlap.width * overlap.height
        if area > bestArea { best = i; bestArea = area }
    }
    return best
}

/// Picks the window a Dock click should bring forward.
/// - windows: the app's eligible window frames, most recently used first.
/// - displays: display bounds, in cycle order.
/// - mouseDisplay: index of the display the click came from.
/// - appIsFrontmost: whether the clicked app is already the active app.
/// Returns an index into `windows`, or nil to leave macOS's default behaviour alone.
func pickWindow(windows: [CGRect], displays: [CGRect], mouseDisplay: Int, appIsFrontmost: Bool) -> Int? {
    let windowDisplays = windows.map { displayIndex(of: $0, in: displays) }
    let frontDisplay = windowDisplays.first ?? nil
    // First click: this display's most recent window, unless the app is already showing it.
    if !appIsFrontmost || frontDisplay != mouseDisplay {
        return windowDisplays.firstIndex(of: mouseDisplay)
    }
    // Clicked again: the next display that has a window.
    // ponytail: stateless, so with 3+ displays repeat clicks alternate between this display and the next;
    // remember the last raised window per app if a third display needs full cycling.
    for step in 1..<max(displays.count, 1) {
        if let i = windowDisplays.firstIndex(of: (mouseDisplay + step) % displays.count) { return i }
    }
    return nil
}
