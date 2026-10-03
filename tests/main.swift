import CoreGraphics
import Foundation

func check(_ ok: Bool, _ name: String) {
    print(ok ? "PASS" : "FAIL", name)
    if !ok { exit(1) }
}

// Laptop on the left, taller external monitor on the right, top-left coordinates like macOS uses.
let mac = CGRect(x: 0, y: 0, width: 1512, height: 982)
let monitor = CGRect(x: 1512, y: -300, width: 2560, height: 1440)
let displays = [mac, monitor]
let onMac = CGRect(x: 100, y: 100, width: 800, height: 600)
let onMac2 = CGRect(x: 200, y: 150, width: 800, height: 600)
let onMonitor = CGRect(x: 1700, y: 0, width: 1200, height: 900)

check(displayIndex(of: onMac, in: displays) == 0, "window on laptop belongs to laptop")
check(displayIndex(of: onMonitor, in: displays) == 1, "window on monitor belongs to monitor")
check(displayIndex(of: CGRect(x: 1300, y: 100, width: 800, height: 600), in: displays) == 1,
      "straddling window belongs to display holding most of it")
check(displayIndex(of: CGRect(x: -5000, y: 0, width: 100, height: 100), in: displays) == nil,
      "off-screen window belongs to no display")

check(pickWindow(windows: [onMonitor, onMac], displays: displays, mouseDisplay: 0, appIsFrontmost: false) == 1,
      "inactive app: laptop click picks laptop window even if monitor one is newer")
check(pickWindow(windows: [onMonitor, onMac2, onMac], displays: displays, mouseDisplay: 0, appIsFrontmost: false) == 1,
      "several windows on laptop: most recent one wins")
check(pickWindow(windows: [onMonitor], displays: displays, mouseDisplay: 0, appIsFrontmost: false) == nil,
      "no window on clicked display: leave macOS default")
check(pickWindow(windows: [onMac, onMonitor], displays: displays, mouseDisplay: 0, appIsFrontmost: true) == 1,
      "clicked again while laptop window is front: go to monitor window")
check(pickWindow(windows: [onMonitor, onMac], displays: displays, mouseDisplay: 0, appIsFrontmost: true) == 1,
      "active app showing monitor window: laptop click picks laptop window")
check(pickWindow(windows: [onMac], displays: displays, mouseDisplay: 0, appIsFrontmost: true) == nil,
      "clicked again with no window elsewhere: leave macOS default")
check(pickWindow(windows: [], displays: displays, mouseDisplay: 0, appIsFrontmost: false) == nil,
      "no windows: leave macOS default")
check(pickWindow(windows: [onMac], displays: [mac], mouseDisplay: 0, appIsFrontmost: true) == nil,
      "single display, clicked again: leave macOS default")
check(pickWindow(windows: [onMac, onMonitor], displays: displays, mouseDisplay: 0, appIsFrontmost: false) == 0,
      "inactive app whose newest window is on the clicked display: pick it")
check(pickWindow(windows: [onMonitor, onMac], displays: displays, mouseDisplay: 1, appIsFrontmost: true) == 1,
      "clicked again on the monitor: wrap around to the laptop window")
