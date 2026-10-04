// Renders the app icon: swift Scripts/make-icon.swift <output.png>
import AppKit

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
    guard let context = NSGraphicsContext.current?.cgContext else { return false }

    // macOS icon grid: 824 pt rounded square centred on a 1024 pt canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
    NSColor.black.setFill()
    shape.fill()
    context.restoreGState()

    NSGradient(starting: NSColor(red: 0.20, green: 0.21, blue: 0.25, alpha: 1),
               ending: NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1))?
        .draw(in: shape, angle: -90)

    // The strip the terminal drops from.
    shape.addClip()
    NSColor(white: 1, alpha: 0.92).setFill()
    NSBezierPath(roundedRect: CGRect(x: 362, y: 868, width: 300, height: 112), xRadius: 44, yRadius: 44).fill()

    let font = NSFont.monospacedSystemFont(ofSize: 400, weight: .bold)
    let prompt = NSMutableAttributedString(
        string: ">", attributes: [.font: font, .foregroundColor: NSColor(red: 0.20, green: 0.84, blue: 0.29, alpha: 1)])
    prompt.append(NSAttributedString(string: "_", attributes: [.font: font, .foregroundColor: NSColor.white]))
    let size = prompt.size()
    prompt.draw(at: CGPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2 - 20))
    return true
}

guard CommandLine.arguments.count > 1,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else { fatalError("usage: make-icon.swift <output.png>") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
