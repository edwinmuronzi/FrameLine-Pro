import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct FeatureStory: Identifiable {
    let id: Int
    let category: String
    let title: String
    let summary: String
    let tip: String
    let symbol: String
    let scene: String
    let marketingTitle: String
    let marketingSubtitle: String

    static let all: [FeatureStory] = [
        .init(id: 0, category: "YOUR POCKET CAMERA STUDIO", title: "A camera.\nYour point of view.", summary: "Photography, cinematic video and a rangefinder way of seeing. One considered space to make the image yours.", tip: "Three shooting modes. A signature look. Every frame intentional.", symbol: "viewfinder", scene: "Story01", marketingTitle: "Your vision.\nBeautifully framed.", marketingSubtitle: "Photo. Video. Rangefinder.\nOne creative camera."),
        .init(id: 1, category: "PHOTOGRAPHY", title: "Photographs\nwith feeling.", summary: "Capture natural detail in HEIF or JPEG. Choose HEIF Max or RAW on supported cameras, then keep shooting while your look develops.", tip: "Tap the shutter repeatedly. Full-resolution originals stay available in the gallery.", symbol: "camera", scene: "Story02", marketingTitle: "Make the everyday\nextraordinary.", marketingSubtitle: "Natural detail. Expressive color.\nHEIF, JPEG and supported RAW."),
        .init(id: 2, category: "VIDEO", title: "Motion,\nwith intention.", summary: "Choose the resolution, frame rate and codec your camera supports. Shape exposure, lock white balance, and monitor your sound.", tip: "Apple Log, Log 2 and ProRes appear only on compatible hardware and formats.", symbol: "video", scene: "Story03", marketingTitle: "Think in scenes.\nShoot in motion.", marketingSubtitle: "Manual video, supported Log\nand a look you can bake in."),
        .init(id: 3, category: "DUAL SHOT", title: "One take.\nTwo stories.", summary: "Record a landscape video and a vertical reel at the same time. Move and resize the live landscape window while you frame the reel.", tip: "Two finished videos. Your style and enabled LUT bake into the pair while recording.", symbol: "rectangle.on.rectangle", scene: "Story04", marketingTitle: "Shoot once.\nTell both stories.", marketingSubtitle: "Landscape + vertical reel.\nTwo live views. Two saved videos."),
        .init(id: 4, category: "LOOKS & LUTS", title: "Find your\nsignature.", summary: "Explore camera styles, tune Quality and Tone, or import a .cube LUT. Preview the result before you commit to the moment.", tip: "A LUT is a saved color transformation. Preview shows it; Bake saves its effect into your video. Try the looks below.", symbol: "camera.filters", scene: "Story09", marketingTitle: "Color that\nfeels like you.", marketingSubtitle: "Live camera styles, custom looks\nand imported .cube LUTs."),
        .init(id: 5, category: "RANGEFINDER", title: "See beyond\nthe frame.", summary: "Compose with frame lines while keeping the wider scene in sight. Choose your focal length and save the full image, the framed crop, or both.", tip: "Frame lines show what the crop will keep, while the area around them helps you anticipate movement.", symbol: "viewfinder.rectangular", scene: "Story06", marketingTitle: "See the scene.\nFind the frame.", marketingSubtitle: "Rangefinder frame lines\nwith full-frame and crop saving."),
        .init(id: 6, category: "MANUAL CONTROL", title: "Make every\nsetting yours.", summary: "Open M for exposure, ISO, shutter, white balance and supported manual focus. Stay automatic where you want, precise where it matters.", tip: "Slide the rulers, tap a value to type, and hold the viewfinder to lock focus and exposure.", symbol: "slider.horizontal.3", scene: "Story07", marketingTitle: "Automatic ease.\nManual precision.", marketingSubtitle: "Exposure, shutter, ISO, white balance\nand supported manual focus."),
        .init(id: 7, category: "EXPOSURE & FOCUS AIDS", title: "See what\nyour eye can’t.", summary: "Check RGB histograms and waveform, protect highlights with zebras, find focus with peaking, or read exposure through false color.", tip: "Histogram and waveform show brightness. Zebras warn about bright areas; peaking outlines sharp edges; false color turns brightness into a color guide.", symbol: "waveform.path", scene: "Story05", marketingTitle: "Know your light.\nTrust your focus.", marketingSubtitle: "RGB scopes, zebras, focus peaking\nand false-color exposure aids."),
        .init(id: 8, category: "SHOOTING TOOLS", title: "Your favorites.\nYour order.", summary: "Save your camera setup, create your own styles, and arrange the styles and presets you use most. Shooting tools also include reel tracking, focus pulls and audio monitoring.", tip: "Open Manage in the Look Studio or Shooting tools. Remove or reorder styles and presets, restore deleted items, undo changes or reset the library. Your photos stay safe.", symbol: "square.stack.3d.up", scene: "Story08", marketingTitle: "Build your workflow.\nKeep your rhythm.", marketingSubtitle: "Shooting presets, reel tracking,\nfocus pulls and audio monitoring."),
        .init(id: 9, category: "NATURAL RAW", title: "Less processing.\nMore character.", summary: "Start with one sensor RAW and turn down sharpening and noise smoothing. Keep the natural texture, then choose your own look.", tip: "Fn → Shooting tools → Photo capture. Needs a compatible rear lens; grain and bright skies can be harder to control.", symbol: "camera.aperture", scene: "Story02", marketingTitle: "Keep the texture.", marketingSubtitle: "Gentle RAW development on supported lenses."),
        .init(id: 10, category: "MOTION & DEPTH", title: "Keep the moment.\nShape the background.", summary: "Live Photo saves a little movement around your picture. Depth portrait keeps distance information so you can soften the background and change the blur later.", tip: "Choose one in Photo capture. Live Photo saves the original full frame; open Develop photo to adjust depth blur. Exported portraits are still images; available lenses vary.", symbol: "livephoto", scene: "Story04", marketingTitle: "More than a still.", marketingSubtitle: "Live moments and supported depth portraits."),
        .init(id: 11, category: "YOUR PHOTO LAB", title: "The original stays.\nThe look can change.", summary: "Edit light, color and style while watching the photo. Crop, straighten and choose a smaller sharing copy. Keep HDR highlights when the original supports them.", tip: "Your original stays safe. In Gallery, use Select to remove several items, or Delete all to clear the app gallery. Copies already saved to Photos stay there.", symbol: "slider.horizontal.3", scene: "Story09", marketingTitle: "Make it yours again.", marketingSubtitle: "A persistent gallery and re-editable originals."),
        .init(id: 12, category: "VIEWFINDER FOCUS PULLS", title: "Tap two subjects.\nTell one story.", summary: "In Video, enable Focus Pull and tap your first subject for A, then your second for B. Tap either letter to move focus smoothly without leaving the viewfinder.", tip: "Choose the duration or move focus yourself with the slider. Marks remember distances; they don’t follow moving subjects. Set up before recording.", symbol: "camera.metering.center.weighted", scene: "Story07", marketingTitle: "Focus where it matters.", marketingSubtitle: "A and B, directly in your viewfinder."),
        .init(id: 13, category: "READY WHEN YOU ARE", title: "Less searching.\nMore shooting.", summary: "Pick your three viewfinder shortcuts in Shooting tools. Add FrameLine camera to your Lock Screen for a simple private photo capture, then unlock to bring those shots into your gallery.", tip: "Customize the Lock Screen’s bottom control and choose FrameLine camera. Locked capture keeps other photos private and uses its own simple camera.", symbol: "lock.open", scene: "Story06", marketingTitle: "Ready for the moment.", marketingSubtitle: "Custom shortcuts and private locked capture."),
        .init(id: 14, category: "MAKE SOMETHING YOURS", title: "Your camera.\nYour next story.", summary: "Photo, video and rangefinder. One creative space, with images processed on your device.", tip: "Start with a moment, then make it yours. Camera access starts after this tour.", symbol: "sparkles", scene: "Story10", marketingTitle: "A creative camera.\nEvery day.", marketingSubtitle: "A considered interface.\nA cinematic point of view.")
    ]
}

@MainActor
struct CameraShowcase: View {
    let story: FeatureStory
    var previewImage: UIImage?
    var previewLook: FilmLook?
    @State private var store: CameraStore

    init(story: FeatureStory, previewImage: UIImage? = nil, previewLook: FilmLook? = nil) {
        self.story = story; self.previewImage = previewImage; self.previewLook = previewLook
        let s = CameraStore()
        s.isShowcase = true; s.showcaseScene = story.scene
        s.lookOptions = LookOptions(); s.lookDials = [:]
        s.look = previewLook ?? .standard
        s.mode = [2, 3, 8, 12].contains(story.id) ? .video : (story.id == 5 || story.id == 0 ? .rangefinder : .photo)
        s.caps.hasCamera = true
        s.selectedCodec = RecordingCodec(rawValue: "hvc1")
        s.storageTotalBytes = 256_000_000_000
        s.storageFreeBytes = 128_000_000_000
        s.dualShot = story.id == 3
        s.showManual = story.id == 6
        if story.id == 12 {
            s.viewfinderPull = true; s.focusStart = 0.2; s.focusEnd = 0.8; s.focusAuto = false
            s.focusAPoint = CGPoint(x: 0.3, y: 0.4); s.focusBPoint = CGPoint(x: 0.7, y: 0.6)
        }
        if story.id == 6 { s.isoAuto = false; s.shutterAuto = false; s.iso = 200; s.shutter = 1.0 / 125 }
        if story.id == 5 { s.focal = FocalLength(value: 50) }
        if story.id == 4 { s.showLUTPanel = true }
        if story.id == 7 {
            s.showHistogram = true
            let bins = (0..<64).map { i in Float(exp(-pow((Double(i) - 30) / 16, 2))) }
            s.histogramData = bins
            s.histogramChannels = [bins, Array(bins.reversed()), bins.map { $0 * 0.7 }]
        }
        if story.id == 8 {
            let preset = s.currentShootingPreset(named: "Golden Hour")
            s.shootingPresets = [preset]; s.selectedPresetID = preset.id; s.showLUTPanel = true
        }
        _store = State(initialValue: s)
    }
    var body: some View {
        CameraScreen(store: store)
            .onChange(of: previewImage) { _, image in store.showcaseImage = image }
            .onChange(of: previewLook?.id) { _, _ in store.look = previewLook ?? .standard }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct FeatureTour: View {
    var finish: () -> Void
    @State private var page = 0
    @State private var look = 0
    @State private var lookedImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 33
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var tipSize: CGFloat = 12

    init(finish: @escaping () -> Void) {
        self.finish = finish
        #if DEBUG
        if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--tour-page"), ProcessInfo.processInfo.arguments.count > flag + 1 {
            _page = State(initialValue: min(FeatureStory.all.count - 1, max(0, Int(ProcessInfo.processInfo.arguments[flag + 1]) ?? 0)))
        }
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(FeatureStory.all[page].scene).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .blur(radius: 18).overlay(.black.opacity(0.62)).ignoresSafeArea()
                VStack(spacing: 10) {
                    HStack {
                        Label("FRAMELINE PRO", systemImage: "viewfinder")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(2)
                        Spacer()
                        Button("Skip tour", action: finish).font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9).glassEffect(.regular, in: Capsule())
                    }.padding(.horizontal, 22).padding(.top, 8)
                    TabView(selection: $page) {
                        ForEach(FeatureStory.all) { story in
                            storyPage(story, size: geometry.size).tag(story.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    HStack(spacing: 5) {
                        ForEach(0..<FeatureStory.all.count, id: \.self) { index in
                            Button { move(to: index) } label: {
                                Capsule().fill(index == page ? Theme.gold : .white.opacity(0.25))
                                    .frame(width: index == page ? 22 : 5, height: 5)
                                    .padding(.vertical, 10)
                            }.accessibilityLabel("Feature \(index + 1) of \(FeatureStory.all.count)")
                        }
                    }
                    Button {
                        if page == FeatureStory.all.count - 1 { finish() } else { move(to: page + 1) }
                    } label: {
                        HStack {
                            Spacer()
                            Text(page == FeatureStory.all.count - 1 ? "Open camera" : "Continue").font(.system(size: 17, weight: .bold))
                            Spacer()
                            Image(systemName: page == FeatureStory.all.count - 1 ? "camera.fill" : "arrow.right")
                        }
                        .foregroundStyle(.black).padding(18)
                        .background(Theme.gold, in: RoundedRectangle(cornerRadius: 23))
                    }.padding(.horizontal, 22)
                    Text("On-device creativity • Illustrated demo scenes")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 8)
                }
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
    }

    private func move(to next: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { page = next }
    }

    private func storyPage(_ story: FeatureStory, size: CGSize) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 17) {
                let previewHeight = min(story.id == FeatureStory.all.count - 1 ? 370 : 320, size.height * (story.id == FeatureStory.all.count - 1 ? 0.44 : 0.38))
                Group {
                    if story.id == FeatureStory.all.count - 1 {
                        FeatureSummary(active: page == FeatureStory.all.count - 1)
                    } else if (9...13).contains(story.id), story.id != 12 {
                        TourFeatureIllustration(story: story)
                    } else if story.id != 4, let cached = UIImage(named: String(format: "Screen%02d", story.id + 1)) {
                        Image(uiImage: cached).resizable().scaledToFit()
                    } else {
                        CameraShowcase(story: story, previewImage: story.id == 4 ? lookedImage : nil,
                            previewLook: story.id == 4 ? FilmLook.lineup[min(look, FilmLook.lineup.count - 1)] : nil)
                    }
                }
                    .frame(width: story.id == FeatureStory.all.count - 1 ? 820 : 394, height: 852)
                    .scaleEffect(previewHeight / 852)
                    .frame(width: (story.id == FeatureStory.all.count - 1 ? 820 : 394) * previewHeight / 852, height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 27))
                    .overlay(RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                    .padding(.top, 10)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: story.symbol)
                        Text(story.category).tracking(1.6)
                    }.font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.gold)
                    Text(story.title).font(.system(size: headlineSize, weight: .bold)).tracking(-1.1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(story.summary).font(.system(size: bodySize)).foregroundStyle(.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                    if story.id == 4 {
                        HStack(spacing: 6) {
                            ForEach(Array(["Natural", "Classic", "Eterna"].enumerated()), id: \.offset) { index, name in
                                Button { look = index } label: {
                                    Text(name).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                                        .background(index == look ? Theme.gold : .white.opacity(0.12), in: Capsule())
                                        .foregroundStyle(index == look ? .black : .white)
                                }
                            }
                        }
                        .task(id: look) { await renderLook() }
                    }
                    Text(story.tip).font(.system(size: tipSize)).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(.black.opacity(0.4)), in: RoundedRectangle(cornerRadius: 29))
                .padding(.horizontal, 20)
            }.padding(.bottom, 8)
        }
    }

    @MainActor private func renderLook() async {
        let chosen = look
        guard let source = UIImage(named: "Story09")?.cgImage else { return }
        let style = chosen == 0 ? StyleParams.identity : StyleParams(look: FilmLook.lineup[min(chosen, FilmLook.lineup.count - 1)], options: LookOptions(), dials: LookRecipe.defaultDials(for: FilmLook.lineup[min(chosen, FilmLook.lineup.count - 1)].id))
        let result = await Task.detached(priority: .userInitiated) {
            let input = CIImage(cgImage: source)
            let context = TourLookRenderer.context
            let graded = StyleGrade.grade(input, cube: nil, cubeSize: 0, intensity: 1, style: style)
            return context.createCGImage(graded, from: input.extent).map { UIImage(cgImage: $0) }
        }.value
        guard !Task.isCancelled, chosen == look else { return }
        lookedImage = result
    }
}

private nonisolated enum TourLookRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])
}

// The tour alone owns this animation; it stops off-page and with Reduce Motion.
private struct FeatureSummary: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrolling = false
    private let tiles: [(String, String)] = [
        ("camera", "HEIF · JPEG · RAW"), ("video", "Cinematic video"),
        ("rectangle.on.rectangle", "Dual Shot"), ("viewfinder", "Rangefinder"),
        ("camera.filters", "Looks & LUTs"), ("slider.horizontal.3", "Manual controls"),
        ("waveform.path", "RGB scopes"), ("square.stack.3d.up", "Shooting presets"),
        ("viewfinder.circle", "Focus tools"), ("mic", "Audio monitoring"),
        ("livephoto", "Live moments"), ("camera.aperture", "Natural RAW"),
        ("crop.rotate", "Crop & straighten"), ("lock", "Lock Screen camera"),
        ("person.crop.rectangle", "Adjustable depth"), ("hand.tap", "Custom shortcuts"),
        ("square.grid.2x2", "Manage your styles"), ("arrow.uturn.backward", "Restore & undo"),
        ("sun.max", "HDR highlights"), ("checkmark.circle", "Select & delete"), ("photo.on.rectangle", "Fast gallery")
    ]
    private let heights: [CGFloat] = [180, 260, 210, 190, 240, 170, 220]
    var body: some View {
            ZStack {
                Color.black
                HStack(alignment: .top, spacing: 18) {
                    ForEach(0..<3) { column in
                        VStack(spacing: 18) {
                            ForEach(0..<(heights.count * 2)) { row in
                                let tile = tiles[((row % heights.count) * 3 + column) % tiles.count]
                                VStack(spacing: 18) {
                                    Image(systemName: tile.0).font(.system(size: 43, weight: .light)).foregroundStyle(Theme.gold.opacity(0.8))
                                    Text(tile.1).font(.system(size: 22, weight: .semibold)).multilineTextAlignment(.center)
                                }
                                .frame(width: (row % heights.count).isMultiple(of: 2) ? 250 : 290, height: heights[row % heights.count])
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: (row % heights.count).isMultiple(of: 2) ? 42 : 28))
                                .overlay(LinearGradient(colors: [.white.opacity(0.13), .clear, Theme.gold.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: (row % heights.count).isMultiple(of: 2) ? 42 : 28))
                                .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.12)))
                            }
                        }
                        .offset(y: (scrolling ? -(heights.reduce(0, +) + CGFloat(heights.count) * 18) : 0) - (column == 1 ? 100 : 0))
                    }
                }
                .frame(height: 852, alignment: .top)
                .opacity(0.88)
                .animation(active && !reduceMotion && scenePhase == .active ? .linear(duration: 42).repeatForever(autoreverses: false) : nil, value: scrolling)
                LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 24) {
                    Image("BrandIcon").resizable().scaledToFit().frame(width: 205, height: 205)
                        .clipShape(RoundedRectangle(cornerRadius: 39))
                        .overlay(RoundedRectangle(cornerRadius: 39).stroke(.white.opacity(0.35)))
                        .shadow(color: .black.opacity(0.6), radius: 25, y: 12)
                    Text("FrameLine Pro").font(.system(size: 51, weight: .bold)).tracking(-1.5)
                    Text("PHOTO  ·  VIDEO  ·  RANGEFINDER").font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Theme.gold)
                }
                .padding(42)
                .glassEffect(.regular.tint(.white.opacity(0.13)), in: RoundedRectangle(cornerRadius: 48))
            }.clipped()
        .onAppear { syncScrolling() }
        .onChange(of: active) { _, _ in syncScrolling() }
        .onChange(of: reduceMotion) { _, _ in syncScrolling() }
        .onChange(of: scenePhase) { _, _ in syncScrolling() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FrameLine Pro. Photo, video, rangefinder, Dual Shot, looks, LUTs, manual controls, HDR photo edits, gallery selection and shooting tools.")
    }
    private func syncScrolling() { scrolling = active && !reduceMotion && scenePhase == .active }
}

private struct TourFeatureIllustration: View {
    let story: FeatureStory
    var body: some View {
        ZStack {
            Image(story.scene).resizable().scaledToFill().frame(width: 394, height: 852).clipped()
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: story.symbol).font(.system(size: 90, weight: .ultraLight)).foregroundStyle(Theme.gold)
                Text(story.category).font(.system(size: 22, weight: .bold, design: .monospaced)).multilineTextAlignment(.center)
                Text(story.id == 12 ? "A     ⇄     B" : story.id == 11 ? "Original  +  Your edit" : "Make the moment yours")
                    .font(.system(size: 25, weight: .medium))
                Spacer()
            }.padding(35)
        }
    }
}

struct FeatureGuide: View {
    private let terms = [
        ("EV / brightness", "Make an automatic exposure lighter or darker."),
        ("ISO", "Increase sensitivity to brighten a shot, usually adding noise."),
        ("Shutter", "Choose how long light enters each frame. Slower speeds blur moving subjects."),
        ("White balance", "Keep whites neutral, or make the picture warmer or cooler."),
        ("LUT and Bake", "A LUT is a saved color transformation. Bake writes that color into the saved file."),
        ("RAW", "A sensor-oriented file for later development. It needs processing to become a viewable photo and can be larger and slower."),
        ("Histogram and waveform", "Graphs that help you see very dark areas and overly bright areas."),
        ("Peaking", "Colored outlines around sharp edges help you check focus."),
        ("Zebra", "Stripes warn you about areas above a brightness threshold."),
        ("False color", "A brightness guide shown as colors instead of the scene’s own colors.")
    ]
    var body: some View {
        List {
            Section("Quick definitions") {
                ForEach(terms, id: \.0) { term in VStack(alignment: .leading, spacing: 5) { Text(term.0).font(.headline); Text(term.1).font(.subheadline).foregroundStyle(.secondary) } }
            }
            ForEach(FeatureStory.all.dropFirst().dropLast()) { story in
                Section(story.category) {
                    Text(story.summary)
                    Text(story.tip).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Camera guide")
    }
}
