// Local synthetic fixture only. No camera, network, credentials or app state.
// macOS Apple frameworks supplied by the existing toolchain; no dependencies.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else { fatalError("Provide a new JPEG output path") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Refusing to overwrite fixture") }
let width = 640, height = 480
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func fill(_ rect: CGRect, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
    context.setFillColor(red: r, green: g, blue: b, alpha: 1)
    context.fill(rect)
}
fill(CGRect(x: 0, y: 0, width: width, height: height), 0.94, 0.94, 0.92)
fill(CGRect(x: 30, y: 40, width: 580, height: 370), 0.68, 0.50, 0.32)
// Blue closed book with pale pages, to the right of the key.
fill(CGRect(x: 385, y: 130, width: 150, height: 180), 0.08, 0.26, 0.75)
fill(CGRect(x: 398, y: 137, width: 125, height: 12), 0.96, 0.94, 0.86)
// A gold house key: hollow bow, connected shaft and teeth. No label tells the model its name.
context.setStrokeColor(red: 0.94, green: 0.76, blue: 0.14, alpha: 1)
context.setLineWidth(18)
context.strokeEllipse(in: CGRect(x: 140, y: 240, width: 85, height: 85))
fill(CGRect(x: 175, y: 135, width: 18, height: 115), 0.94, 0.76, 0.14)
fill(CGRect(x: 188, y: 145, width: 32, height: 18), 0.94, 0.76, 0.14)
fill(CGRect(x: 188, y: 178, width: 24, height: 18), 0.94, 0.76, 0.14)
let image = context.makeImage()!
let encoded = NSMutableData()
let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("JPEG encoding failed") }
// ImageIO adds dimensions-only EXIF automatically. Remove optional metadata segments
// from this generated fixture; retain JFIF and all image coding/scan segments.
let bytes = [UInt8](encoded as Data)
var clean = Data(bytes.prefix(2)), offset = 2
while offset + 4 <= bytes.count {
    guard bytes[offset] == 255 else { fatalError("Invalid JPEG marker") }
    let marker = bytes[offset + 1]
    if marker == 0xda { clean.append(contentsOf: bytes[offset...]); break }
    let count = Int(bytes[offset + 2]) * 256 + Int(bytes[offset + 3]) + 2
    guard count >= 4, offset + count <= bytes.count else { fatalError("Invalid JPEG length") }
    if !(0xe1...0xef).contains(marker) && marker != 0xfe {
        clean.append(contentsOf: bytes[offset..<(offset + count)])
    }
    offset += count
}
try clean.write(to: output, options: .withoutOverwriting)
guard
      let source = CGImageSourceCreateWithURL(output as CFURL, nil),
      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { fatalError("JPEG failed to decode") }
print("Created and decoded one synthetic 640x480 JPEG. No inference performed.")
