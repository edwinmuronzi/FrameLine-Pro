#if DEBUG
import SwiftUI
import UIKit

struct MarketingSlide: View {
    let story: FeatureStory
    let screenshot: UIImage
    var body: some View {
        ZStack {
            Image(story.scene).resizable().scaledToFill().frame(width: 440, height: 956).clipped()
            LinearGradient(colors: [.black.opacity(0.90), .black.opacity(0.42), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "viewfinder").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.gold)
                    Text("FRAMELINE PRO").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(2.8)
                    Spacer()
                    Text(String(format: "%02d", story.id + 1)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                }
                Text(story.marketingTitle).font(.system(size: 40, weight: .bold)).tracking(-1.7)
                    .lineSpacing(-1).fixedSize(horizontal: false, vertical: true).padding(.top, 22)
                Text(story.marketingSubtitle).font(.system(size: 16, weight: .medium)).lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.77)).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                Spacer(minLength: 12)
                HStack {
                    Spacer()
                    Image(uiImage: screenshot).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 258, height: 558)
                        .clipShape(RoundedRectangle(cornerRadius: 37))
                        .padding(6)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 43))
                        .overlay(RoundedRectangle(cornerRadius: 43).stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.05), .white.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                        .shadow(color: .black.opacity(0.65), radius: 28, y: 18)
                    Spacer()
                }
                Spacer(minLength: 10)
                HStack {
                    Text("PHOTO  /  VIDEO  /  RANGEFINDER").tracking(1.3)
                    Spacer()
                    Image(systemName: story.symbol).foregroundStyle(Theme.gold)
                }.font(.system(size: 9, weight: .semibold, design: .monospaced))
                Text("Illustrative scene · Actual app interface · Features vary by hardware")
                    .font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)).padding(.top, 8)
            }
            .padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 23)
        }.frame(width: 440, height: 956).foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
}

struct MarketingExportHost: View {
    @State private var message = "Rendering FrameLinePro marketing set…"
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 20) {
                Image(systemName: "viewfinder").font(.system(size: 60)).foregroundStyle(Theme.gold)
                Text(message).foregroundStyle(.white)
            }
        }
        .task { await export() }
    }
    @MainActor private func export() async {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MarketingExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var rendered = 0
        for story in FeatureStory.all {
            let input = root.deletingLastPathComponent().appendingPathComponent("MarketingInput")
                .appendingPathComponent(String(format: "camera-%02d.png", story.id + 1))
            guard let shot = UIImage(contentsOfFile: input.path) else {
                NSLog("MARKETING_EXPORT missing native interface screenshot %@", input.path)
                continue
            }
            let card = ImageRenderer(content: MarketingSlide(story: story, screenshot: shot))
            card.proposedSize = ProposedViewSize(width: 440, height: 956)
            card.scale = 3; card.isOpaque = true
            guard let image = card.uiImage else { NSLog("MARKETING_EXPORT FAIL slide %ld", story.id); continue }
            try? image.pngData()?.write(to: root.appendingPathComponent(String(format: "%02d-%@.png", story.id + 1, story.category.lowercased().replacingOccurrences(of: " ", with: "-"))))
            rendered += 1
            NSLog("MARKETING_EXPORT slide %ld complete", story.id + 1)
            message = "Rendered \(story.id + 1) of 10"
            await Task.yield()
        }
        message = "\(rendered) images ready"
        try? String(rendered).write(to: root.appendingPathComponent("export-complete.txt"), atomically: true, encoding: .utf8)
        NSLog("MARKETING_EXPORT COMPLETE %@", root.path)
    }
}
#endif
