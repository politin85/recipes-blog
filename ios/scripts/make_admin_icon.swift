// Renders the admin app's icon: the site icon on a dark tile with a "ניהול" label.
// Usage: swiftc -O scripts/make_admin_icon.swift -o /tmp/make_admin_icon &&
//        /tmp/make_admin_icon <AppIconEnhanced.png> Core/Resources/Fonts/SecularOne-Regular.ttf RecipesAdmin/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let icon = CGImageSourceCreateImageAtIndex(source, 0, nil)!
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: args[2]) as CFURL, .process, nil)

let size: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Ink background (#2C1F14)
ctx.setFillColor(red: 0x2C / 255, green: 0x1F / 255, blue: 0x14 / 255, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// The site icon, smaller and shifted up to leave room for the label.
let iconSize: CGFloat = 700
ctx.interpolationQuality = .high
ctx.draw(icon, in: CGRect(x: (size - iconSize) / 2, y: 262, width: iconSize, height: iconSize))

let font = CTFontCreateWithName("SecularOne-Regular" as CFString, 170, nil)
let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0xF0 / 255, green: 0xE4 / 255, blue: 0xCE / 255, alpha: 1),
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "ניהול", attributes: attributes))
let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
ctx.textPosition = CGPoint(x: (size - bounds.width) / 2 - bounds.minX, y: 70)
CTLineDraw(line, ctx)

let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
