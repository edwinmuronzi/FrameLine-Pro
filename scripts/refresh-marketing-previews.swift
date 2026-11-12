import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
let shots=URL(fileURLWithPath:CommandLine.arguments[1])
func contact(_ inputs:[URL],width:Int,height:Int,columns:Int,to output:URL) throws {
    let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.setFillColor(CGColor(red:0.025,green:0.03,blue:0.04,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height));c.interpolationQuality = .high
    let rows=(inputs.count+columns-1)/columns,pad=14.0
    let w=(Double(width)-pad*Double(columns+1))/Double(columns),h=(Double(height)-pad*Double(rows+1))/Double(rows)
    for (index,url) in inputs.enumerated() {
        guard let s=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(s,0,nil) else {throw NSError(domain:"MarketingPreview",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing image: "+url.path])}
        let scale=min(w/Double(image.width),h/Double(image.height)),iw=Double(image.width)*scale,ih=Double(image.height)*scale
        let x=pad+Double(index%columns)*(w+pad)+(w-iw)/2,y=Double(height)-pad-Double(index/columns)*(h+pad)-ih-(h-ih)/2
        c.draw(image,in:CGRect(x:x,y:y,width:iw,height:ih))
    }
    let d=CGImageDestinationCreateWithURL(output as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(d,c.makeImage()!,[kCGImageDestinationLossyCompressionQuality:0.92] as CFDictionary)
    guard CGImageDestinationFinalize(d) else {throw NSError(domain:"MarketingPreview",code:2)}
}
let deck=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("Marketing/AppStore"),includingPropertiesForKeys:nil).filter {$0.pathExtension=="png"}.sorted {$0.lastPathComponent<$1.lastPathComponent}
guard deck.count==10 else {fatalError("Expected ten marketing slides")}
try contact(deck,width:1272,height:1080,columns:5,to:root.appendingPathComponent("Marketing/Overview.jpg"))
let tour=[0,3,8,14].map {shots.appendingPathComponent("tour-\($0).png")}
try contact(tour,width:1180,height:633,columns:4,to:root.appendingPathComponent("Marketing/Onboarding.jpg"))
