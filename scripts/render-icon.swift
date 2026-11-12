import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Approved source artwork; resizing and tint adaptation do not alter the emblem.
let args=CommandLine.arguments
let dark=args.contains("--dark") || args.contains("--tinted")
let edge=args.contains("--master") ? 1254:(args.contains("--brand") ? 768:1024)
let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
let master=root.appendingPathComponent("Marketing/Icons/Stillarc-\(dark ? "Dark":"Light").png")
guard let source=CGImageSourceCreateWithURL(master as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {fatalError("Approved icon master missing")}
let tinted=args.contains("--tinted")
let space=CGColorSpace(name:tinted ? CGColorSpace.genericGrayGamma2_2:CGColorSpace.sRGB)!
let context=CGContext(data:nil,width:edge,height:edge,bitsPerComponent:8,bytesPerRow:edge*(tinted ? 1:4),space:space,bitmapInfo:tinted ? CGImageAlphaInfo.none.rawValue:CGImageAlphaInfo.noneSkipLast.rawValue)!
context.interpolationQuality = .high;context.draw(image,in:CGRect(x:0,y:0,width:edge,height:edge))
let url=URL(fileURLWithPath:args[1]),destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(destination,context.makeImage()!,nil)
guard CGImageDestinationFinalize(destination) else {fatalError("Icon PNG encoding failed")}
