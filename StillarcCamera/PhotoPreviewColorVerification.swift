#if DEBUG
import CoreImage
import UIKit

nonisolated enum PhotoPreviewColorVerification {
    static func run() -> [String:Any] {
        let space = CGColorSpace(name:CGColorSpace.sRGB)!
        let context = PhotoDeveloper.context
        func mean(_ image:CIImage) -> [Float] {
            let average = image.applyingFilter("CIAreaAverage",parameters:["inputExtent":CIVector(cgRect:image.extent.insetBy(dx:8,dy:8))])
            var result = [Float](repeating:0,count:4)
            context.render(average,toBitmap:&result,rowBytes:16,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBAf,colorSpace:space)
            return result
        }
        var maximum:Float = 0, tested = 0
        var details = [[String:Any]]()
        for rgb:[CGFloat] in [[0.2,0.35,0.5],[0.5,0.5,0.5],[0.8,0.6,0.4]] {
            let image = CIImage(color:CIColor(red:rgb[0],green:rgb[1],blue:rgb[2],colorSpace:space)!).cropped(to:CGRect(x:0,y:0,width:192,height:256))
            guard let source = PhotoDeveloper.encode(image) else { return ["passed":false,"error":"source"] }
            for look in FilmLook.lineup.filter({ ["standard","fuji","eterna","night35"].contains($0.id) }) {
                var style = StyleParams(look:look,options:LookOptions(),dials:LookRecipe.defaultDials(for:look.id)); style.refinedPhotoTexture = true
                if look.id == "night35", style.glow > 0 { style.halation = 0.38; style.glow = 0 }
                let reference = StillComposer.compose(imageData:source,request:StillComposer.Request(focalScale:1,aspectRatio:nil,saveTarget:"FULL",style:style))
                guard let expected = CIImage(data:reference.gradedFull ?? source), let input = CIImage(data:source) else { return ["passed":false,"error":"reference"] }
                let edit = PhotoEdit(styleID:look.id)
                let preview = PhotoDeveloper.adjust(input,edit:edit)
                guard let exported = PhotoDeveloper.develop(source,edit:edit), let reopened = CIImage(data:exported) else { return ["passed":false,"error":"export"] }
                let a = mean(expected), b = mean(preview), c = mean(reopened)
                let error = (0..<3).map { abs(a[$0]-b[$0]) }.max() ?? 1
                maximum = max(maximum,error)
                details.append(["look":look.id,"input":rgb,"reference":a,"preview":b,"error":error])
                guard (0..<3).allSatisfy({ abs(b[$0]-c[$0]) < 0.015 }) else { return ["passed":false,"error":"preview/export color mismatch"] }
                tested += 1
            }
        }
        return ["passed":maximum < 0.01,"cameraLookMeanError":maximum,"lookSwatches":tested,"previewExportMatch":true,"details":details]
    }
}
#endif
