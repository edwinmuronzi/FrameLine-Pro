#if DEBUG
import SwiftUI

struct ReelGeometryVerification: View {
    @State private var status = "Checking 9:16 framing…"
    var body: some View {
        Text(status).task {
            var checks = 0
            var failure: String?
            for ratio: CGFloat in [0.45, 9.0/16, 0.65, 3.0/4, 1, 1.5] {
                for landscape in [false,true] {
                    let crop = VideoFrameGeometry.captureCrop(aspect:.reel,viewRatio:ratio,landscape:landscape)
                    let outputRatio = crop.rect.width * crop.ratio / crop.rect.height
                    if abs(outputRatio - 9.0/16) > 0.000001 { failure = "Output aspect is not 9:16" }
                    let preview = VideoFrameGeometry.normalizedRect(aspect:.reel,viewRatio:ratio,landscape:landscape)
                    if preview.minX < 0 || preview.maxX > 1 || preview.minY < 0 || preview.maxY > 1 || preview.isEmpty { failure = "Crop escaped viewfinder" }
                    let expected = landscape ? CGRect(x:preview.minY,y:preview.minX,width:preview.height,height:preview.width) : preview
                    if crop.rect != expected { failure = "Preview/export crops differ" }
                    checks += 1
                }
            }
            for style in SafeZoneStyle.allCases {
                let rect = style.rect
                if rect.minX < 0 || rect.maxX > 1 || rect.minY < 0 || rect.maxY > 1 { failure = "Unsafe guide bounds" }
                checks += 1
            }
            do {
                let roundtrip = try JSONDecoder().decode(FrameAspect.self,from:JSONEncoder().encode(FrameAspect.reel))
                if roundtrip != .reel { failure = "9:16 persistence failed" }
            } catch { failure = error.localizedDescription }
            let report: [String:Any] = ["passed":failure == nil,"geometryChecks":checks,"error":failure ?? "none"]
            let file = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("reel-geometry-verification.json")
            if let data = try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted) { try? data.write(to:file,options:.atomic) }
            status = failure ?? "9:16 framing passed"
            NSLog("REEL_GEOMETRY_VERIFY passed=%d checks=%d",failure == nil ? 1 : 0,checks)
        }
    }
}
#endif
