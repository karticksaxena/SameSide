// Draws the app icon and the DMG window background. Run from the repo root after changing a design:
//   swift Tools/make-assets.swift
// Writes Resources/AppIcon.icns and Resources/dmg-background.tiff (1x + 2x).
import AppKit

let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("sameside-assets-\(getpid())")
try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Renders `size` points at `scale` into a PNG. Drawing uses points with the origin at the bottom left.
func render(_ size: NSSize, scale: CGFloat, to url: URL, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    try! p.run()
    p.waitUntilExit()
    precondition(p.terminationStatus == 0, "\(tool) failed")
}

func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

// MARK: App icon (designed on a 1024-point canvas: a window lifting out of a highlighted Dock icon)

func drawIcon(_ points: CGFloat) {
    let t = NSAffineTransform()
    t.scale(by: points / 1024)
    t.concat()
    let body = roundRect(100, 100, 824, 824, 185)
    NSGradient(starting: color(0x6A9BFF), ending: color(0x3B45D9))!.draw(in: body, angle: -90)
    // Dock with four icons, the second one active.
    color(0xFFFFFF, 0.22).setFill()
    roundRect(220, 180, 584, 120, 60).fill()
    for (i, x) in [265, 395, 525, 655].enumerated() {
        color(0xFFFFFF, i == 1 ? 1 : 0.5).setFill()
        roundRect(CGFloat(x), 205, 74, 74, 20).fill()
    }
    // Arrow from the active icon up to the window.
    color(0xFFFFFF).setFill()
    roundRect(421, 318, 22, 110, 11).fill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 384, y: 420))
    head.line(to: NSPoint(x: 480, y: 420))
    head.line(to: NSPoint(x: 432, y: 478))
    head.close()
    head.fill()
    // The window that comes forward.
    color(0xFFFFFF).setFill()
    roundRect(230, 500, 564, 320, 40).fill()
    color(0xDCE3FF).setFill()
    NSBezierPath(roundedRect: NSRect(x: 230, y: 750, width: 564, height: 70), xRadius: 40, yRadius: 40).fill()
    NSRect(x: 230, y: 750, width: 564, height: 30).fill()
    for (x, c) in [(285, 0xFF5F57), (330, 0xFEBC2E), (375, 0x28C840)] as [(CGFloat, UInt32)] {
        color(c).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 13, y: 772, width: 26, height: 26)).fill()
    }
    color(0x3B45D9, 0.18).setFill()
    for (y, w) in [(680, 420), (630, 360), (580, 400)] as [(CGFloat, CGFloat)] {
        roundRect(290, y, w, 22, 11).fill()
    }
}

let iconset = tmp.appendingPathComponent("AppIcon.iconset")
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        let points = CGFloat(base)
        render(NSSize(width: points, height: points), scale: CGFloat(scale), to: iconset.appendingPathComponent(name)) {
            drawIcon(points)
        }
    }
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"])

// MARK: DMG background (660 x 400 points; Finder puts the app at (165, 190) and Applications at (495, 190) from the top left)

func drawBackground() {
    let size = NSSize(width: 660, height: 400)
    NSGradient(starting: color(0xF7F8FB), ending: color(0xE6EAF2))!.draw(in: NSRect(origin: .zero, size: size), angle: -90)
    func text(_ s: String, _ y: CGFloat, _ font: NSFont, _ c: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c]
        let w = (s as NSString).size(withAttributes: attrs).width
        (s as NSString).draw(at: NSPoint(x: (size.width - w) / 2, y: y), withAttributes: attrs)
    }
    text("Drag SameSide into Applications", 335, .systemFont(ofSize: 22, weight: .semibold), color(0x1D1D1F))
    text("Then open SameSide and allow Accessibility when macOS asks.", 42, .systemFont(ofSize: 13), color(0x6E6E73))
    // Arrow between the two icons (icon centres at y = 400 - 190 = 210).
    color(0x8E99AE).setFill()
    roundRect(258, 205, 120, 10, 5).fill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 372, y: 228))
    head.line(to: NSPoint(x: 402, y: 210))
    head.line(to: NSPoint(x: 372, y: 192))
    head.close()
    head.fill()
}

let bg1 = tmp.appendingPathComponent("background.png")
let bg2 = tmp.appendingPathComponent("background@2x.png")
render(NSSize(width: 660, height: 400), scale: 1, to: bg1, drawBackground)
render(NSSize(width: 660, height: 400), scale: 2, to: bg2, drawBackground)
run("/usr/bin/tiffutil", ["-cathidpicheck", bg1.path, bg2.path, "-out", "Resources/dmg-background.tiff"])
try? fm.removeItem(at: tmp)
print("Wrote Resources/AppIcon.icns and Resources/dmg-background.tiff")
