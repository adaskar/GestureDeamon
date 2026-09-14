import Cocoa

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let iconsetDir = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for (filename, size) in sizes {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    // Rounded Squircle Background
    let cornerRadius = size * 0.22
    let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.05, dy: size * 0.05), xRadius: cornerRadius, yRadius: cornerRadius)

    let grad = NSGradient(starting: NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0),
                          ending: NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0))
    grad?.draw(in: bgPath, angle: -45)

    // Border highlight
    NSColor(white: 1.0, alpha: 0.15).setStroke()
    bgPath.lineWidth = max(1.0, size * 0.02)
    bgPath.stroke()

    // Stylized Mouse outline
    let mouseRect = NSRect(x: size * 0.35, y: size * 0.24, width: size * 0.30, height: size * 0.52)
    let mouseCorner = size * 0.15
    let mousePath = NSBezierPath(roundedRect: mouseRect, xRadius: mouseCorner, yRadius: mouseCorner)
    NSColor(red: 0.25, green: 0.75, blue: 1.0, alpha: 0.9).setStroke()
    mousePath.lineWidth = max(1.5, size * 0.035)
    mousePath.stroke()

    // Scroll wheel line
    let wheelPath = NSBezierPath()
    wheelPath.move(to: NSPoint(x: size * 0.5, y: size * 0.58))
    wheelPath.line(to: NSPoint(x: size * 0.5, y: size * 0.68))
    wheelPath.lineWidth = max(1.5, size * 0.035)
    wheelPath.stroke()

    // Thumb gesture indicator wave / dot
    let wavePath = NSBezierPath()
    wavePath.move(to: NSPoint(x: size * 0.26, y: size * 0.40))
    wavePath.curve(to: NSPoint(x: size * 0.26, y: size * 0.60),
                   controlPoint1: NSPoint(x: size * 0.20, y: size * 0.46),
                   controlPoint2: NSPoint(x: size * 0.20, y: size * 0.54))
    NSColor(red: 0.3, green: 0.9, blue: 0.6, alpha: 0.9).setStroke()
    wavePath.lineWidth = max(1.2, size * 0.03)
    wavePath.stroke()

    img.unlockFocus()

    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let pngData = rep.representation(using: .png, properties: [:]) {
        let fileURL = iconsetDir.appendingPathComponent(filename)
        try? pngData.write(to: fileURL)
    }
}

print("Iconset created at build/AppIcon.iconset")
