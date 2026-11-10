import AVKit
import SwiftUI
import UIKit

struct FnSheet: View {
    @Bindable var store: CameraStore
    var onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    // Starts short, so the viewfinder stays in view while styles are tried.
    @State private var detent: PresentationDetent = Self.compact
    @State private var thumbs: [String: UIImage] = [:]
    @State private var showStudio = false
    @State private var showShootingTools = false

    private static let compact = PresentationDetent.height(300)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Camera style") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(store.allLooks) { look in
                                    styleButton(look)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Text(detent == Self.compact
                            ? "Tap a style and watch the viewfinder. Pull up for look details, LUT and video options."
                            : "Styles show live in the viewfinder. With a style on, the graded photo saves to Photos; your original remains in the session gallery.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Button {
                        showStudio = true
                    } label: {
                        Label("Open the look studio", systemImage: "slider.horizontal.below.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Theme.gold, in: Capsule())
                    }

                    Button {
                        showShootingTools = true
                    } label: {
                        Label("Shooting tools", systemImage: "camera.badge.ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                    }

                    section("Look details") {
                        lookDetails
                    }

                    section("LUT") {
                        ForEach(store.luts) { lut in
                            HStack {
                                Button {
                                    store.selectedLUT = store.selectedLUT == lut ? nil : lut
                                } label: {
                                    HStack {
                                        Image(systemName: store.selectedLUT == lut ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(Theme.gold)
                                        Text(lut.name)
                                            .foregroundStyle(.white)
                                        if lut.isBuiltIn {
                                            Text("Built in")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white.opacity(0.45))
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                if lut.isBuiltIn == false {
                                    Button(role: .destructive) {
                                        store.removeLUT(lut)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                            }
                        }
                        Toggle("Bake LUT into photos and video", isOn: $store.bakeLUT)
                            .tint(Theme.gold)
                        Button {
                            dismiss()
                            onImport()
                        } label: {
                            Label("Import .cube LUT", systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("The viewfinder shows the full LUT when its preview is on. With bake on, the LUT is saved into photos and video. Dual Shot saves only two videos, with the look and baked LUT applied.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    section("Video") {
                        Picker("Gamma", selection: $store.logProfile) {
                            ForEach(LogProfile.allCases) { profile in
                                Text(profile.title).tag(profile)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(logNote)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                        Toggle("Dual shot", isOn: $store.dualShot)
                            .tint(Theme.gold)
                        Text("Capture a landscape video and a vertical reel at the same time. One recording saves as two videos: landscape 16:9 and vertical 9:16.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(20)
            }
            .background(Theme.ink)
            .navigationTitle("Looks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { buildThumbs() }
            .onChange(of: store.customLooks) { _, _ in buildThumbs() }
            .fullScreenCover(isPresented: $showStudio) {
                LookStudio(store: store)
            }
        }
        .presentationDetents([Self.compact, .medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .sheet(isPresented: $showShootingTools) { ShootingToolsSheet(store: store) }
        .presentationBackground(Theme.ink.opacity(0.94))
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // Strength, and each detail of the chosen look, on or off.
    @ViewBuilder
    private var lookDetails: some View {
        let recipe = LookRecipe.recipe(for: store.look.id)
        let hasLook = store.look.id != "standard"

        VStack(alignment: .leading, spacing: 12) {
            if hasLook {
                HStack {
                    Text("Strength")

                    Spacer()

                    Text("\(Int((store.lookOptions.strength * 100).rounded()))%")
                        .foregroundStyle(.white.opacity(0.6))
                }

                Slider(
                    value: Binding(
                        get: { Double(store.lookOptions.strength) },
                        set: { store.lookOptions.strength = Float($0) }
                    ),
                    in: 0...1
                )
                .tint(Theme.gold)

                if recipe.vignette > 0 {
                    Toggle("Dark corners", isOn: $store.lookOptions.vignetteOn)
                        .tint(Theme.gold)
                }

                if recipe.glow > 0 {
                    Toggle("Glow", isOn: $store.lookOptions.glowOn)
                        .tint(Theme.gold)
                }

                if recipe.soften > 0 || recipe.sharpen > 0 {
                    Toggle(
                        recipe.sharpen > 0 ? "Sharpening" : "Softness",
                        isOn: $store.lookOptions.softnessOn
                    )
                    .tint(Theme.gold)
                }
            }

            Toggle("Date stamp", isOn: $store.lookOptions.dateStamp)
                .tint(Theme.gold)

            Text("The date stamp adds an orange date to the corner, like a compact film camera. It shows in the viewfinder, in saved photos and in graded video.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func styleButton(_ look: FilmLook) -> some View {
        let selected = store.look.id == look.id

        return Button {
            store.look = look
        } label: {
            VStack(spacing: 7) {
                Group {
                    if let image = thumbs[look.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Color.white.opacity(0.08))
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? Theme.gold : .white.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                }

                Text(look.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 84)
                    .foregroundStyle(selected ? Theme.gold : .white)
            }
        }
        .buttonStyle(.plain)
    }

    // Each style applied to a small sample, so the strip shows what it does.
    private func buildThumbs() {
        guard let base = LookPreview.sample(from: store, longSide: 220) else { return }

        let list = store.allLooks.map {
            ($0.id, StyleParams(look: $0, options: LookOptions(), dials: nil))
        }

        Task {
            let result = await Task.detached(priority: .utility) { () -> [String: UIImage] in
                var made: [String: UIImage] = [:]

                for (id, params) in list {
                    if let image = LookPreview.render(base, params: params) {
                        made[id] = image
                    }
                }

                return made
            }.value

            thumbs = result
        }
    }

    private var logNote: String {
        switch store.logProfile {
        case .off:
            "Standard video gamma."
        case .log:
            store.caps.supportsLog ? "This iPhone can record Apple Log." : "Apple Log is not on this camera, so video stays in standard gamma."
        case .log2:
            store.caps.supportsLog2 ? "This iPhone can record Apple Log 2." : "Apple Log 2 is not on this camera, so video stays in standard gamma."
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

struct SettingsSheet: View {
    @Bindable var store: CameraStore
    @Environment(\.dismiss) private var dismiss
    @State private var showStudio = false

    private var codecBinding: Binding<RecordingCodec?> {
        Binding(
            get: { store.selectedCodec },
            set: { next in
                if let next {
                    store.selectCodec(next)
                }
            }
        )
    }

    private var resolutionBinding: Binding<RecResolution?> {
        Binding(
            get: { store.recSettings.resolution },
            set: { store.selectResolution($0) }
        )
    }

    private var frameRateBinding: Binding<Int?> {
        Binding(
            get: { store.recSettings.frameRate },
            set: { store.selectFrameRate($0) }
        )
    }

    private var bitrateBinding: Binding<RecBitrate> {
        Binding(
            get: { store.recSettings.bitrate },
            set: { store.selectBitrate($0) }
        )
    }

    private var recordingLocked: Bool {
        store.isRecording
    }

    private var isProRes: Bool {
        store.selectedCodec?.isProRes == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Looks") {
                    Button {
                        showStudio = true
                    } label: {
                        Label("Look studio and presets", systemImage: "slider.horizontal.below.rectangle")
                    }

                    Text("Try looks with the Quality and Tone dials, and make your own presets from an existing one, from scratch, or at random.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Viewfinder") {
                    Toggle("Thirds grid", isOn: $store.grid)
                    Toggle("Level line", isOn: $store.showLevel)

                    if store.showPeaking {
                        Picker("Peaking colour", selection: $store.peakColor) {
                            ForEach(PeakColor.allCases) { colour in
                                Text(colour.title).tag(colour)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Peaking sensitivity")

                                Spacer()

                                Text("\(Int((store.peakSensitivity * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(store.peakSensitivity) },
                                    set: { store.peakSensitivity = Float($0) }
                                ),
                                in: 0...1
                            )
                        }
                    }

                    Picker("Frame", selection: $store.aspect) {
                        ForEach(FrameAspect.allCases, id: \.self) { aspect in
                            Text(aspect.title).tag(aspect)
                        }
                    }

                    Picker("Save", selection: $store.saveTarget) {
                        ForEach(SaveTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                }

                Section("Discover FrameLinePro") {
                    Button("Replay the feature tour", systemImage: "sparkles.rectangle.stack") { store.showWelcome = true }
                }

                Section("Shooting") {
                    Toggle("Preserve settings", isOn: $store.preserveSettings)
                    Toggle("Lock white balance while recording", isOn: $store.lockWBOnRecord)

                    Picker("Stabilization", selection: $store.stabilization) {
                        ForEach(StabilizationChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .disabled(store.isRecording)

                    Picker("Timelapse interval", selection: $store.timelapseInterval) {
                        Text("Off").tag(0)
                        Text("1 second").tag(1)
                        Text("2 seconds").tag(2)
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                    }

                    Text("Photo modes take a photo every interval. Video mode records a timelapse video.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Audio") {
                    Picker(
                        "Microphone",
                        selection: Binding(
                            get: { store.selectedMicUID },
                            set: { store.selectMic($0) }
                        )
                    ) {
                        Text("Automatic").tag("")

                        ForEach(store.micInputs) { input in
                            Text(input.name).tag(input.uid)
                        }
                    }

                    if store.micGainAvailable {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Input gain")

                                Spacer()

                                Text("\(Int((store.micGain * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(store.micGain) },
                                    set: { store.setMicGain(Float($0)) }
                                ),
                                in: 0...1
                            )
                        }
                    }
                }

                Section {
                    Picker("Codec", selection: codecBinding) {
                        if store.availableCodecs.isEmpty {
                            Text("Discovering…").tag(RecordingCodec?.none)
                        }

                        ForEach(store.availableCodecs) { codec in
                            Text(codec.title).tag(Optional(codec))
                        }
                    }
                    .disabled(recordingLocked)

                    Picker("Resolution", selection: resolutionBinding) {
                        Text("Auto").tag(RecResolution?.none)

                        ForEach(store.videoOptions.resolutions) { resolution in
                            Text(resolution.title).tag(Optional(resolution))
                        }
                    }
                    .disabled(recordingLocked || store.videoOptions.locked)

                    Picker("Frame rate", selection: frameRateBinding) {
                        Text("Auto").tag(Int?.none)

                        ForEach(
                            store.videoOptions.frameRates(for: store.recSettings.resolution),
                            id: \.self
                        ) { fps in
                            Text("\(fps) fps").tag(Optional(fps))
                        }
                    }
                    .disabled(recordingLocked || store.videoOptions.locked)

                    Picker("Bitrate", selection: bitrateBinding) {
                        ForEach(RecBitrate.allCases) { bitrate in
                            Text(store.bitrateTitle(bitrate)).tag(bitrate)
                        }
                    }
                    .disabled(
                        recordingLocked
                            || isProRes
                            || store.videoOptions.bitrateSupported == false
                    )
                } header: {
                    Text("Video recording")
                } footer: {
                    Text(recordingNote)
                }

                Section("Files") {
                    Toggle("Save to Photos", isOn: $store.saveToPhotos)
                    Text("Rangefinder keeps the wide frame and writes the frame-line crop beside it when BOTH is selected. With a style or baked LUT on, each is saved untouched and graded. RAW adds a DNG when the camera supports it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("This camera") {
                    LabeledContent("Capture", value: store.caps.hasCamera ? "Live" : "Preview scene")
                    LabeledContent("Apple Log", value: store.caps.supportsLog ? "Available" : "Unavailable")
                    LabeledContent("Apple Log 2", value: store.caps.supportsLog2 ? "Available" : "Unavailable")
                    LabeledContent("Dual camera", value: store.caps.supportsMultiCam ? "Available" : "Vertical crop fallback")
                    LabeledContent("RAW", value: store.caps.supportsRaw ? "Available" : "Unavailable")
                }
            }
            .fullScreenCover(isPresented: $showStudio) {
                LookStudio(store: store)
            }
            .navigationTitle("Settings")
            .onAppear { store.refreshMics() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var recordingNote: String {
        if store.videoOptions.locked {
            return "Dual shot picks the resolution and frame rate automatically."
        }

        if isProRes {
            return "ProRes records at a fixed bitrate. Choose HEVC or H.264 to set one."
        }

        if store.videoOptions.bitrateSupported == false {
            return "This format does not allow a custom bitrate. Resolution and frame rate options follow the current gamma (Standard, Log or Log 2)."
        }

        return "Only options this camera supports in the current gamma are listed. Changing resolution or frame rate refreshes the available codecs."
    }
}

struct GallerySheet: View {
    @Bindable var store: CameraStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.captures.isEmpty {
                    ContentUnavailableView(
                        "No frames yet",
                        systemImage: "viewfinder",
                        description: Text("The shutter keeps the wide frame and the crop side by side.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(store.captures) { item in
                                NavigationLink {
                                    CaptureDetail(
                                        store: store,
                                        item: item,
                                        graded: store.graded[AnyHashable(item.id)],
                                        info: store.clipInfo[AnyHashable(item.id)]
                                    )
                                } label: {
                                    CaptureThumb(
                                        item: item,
                                        graded: store.graded[AnyHashable(item.id)],
                                        info: store.clipInfo[AnyHashable(item.id)]
                                    )
                                }
                                .contextMenu {
                                    Button("Delete", role: .destructive) { store.delete(item) }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Theme.ink)
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct CaptureThumb: View {
    let item: CaptureItem
    var graded: GradedStills?
    var info: ClipInfo?

    @State private var videoFrame: UIImage?

    private var still: UIImage? {
        graded?.crop ?? graded?.full ?? item.cropImage ?? item.fullImage
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = still ?? videoFrame {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.white.opacity(0.08))
            }

            if still == nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 6) {
                Text(item.simulated ? "Preview" : item.mode.title)
                    .pill()

                if let info {
                    Text(String(format: "CLIP %02d", info.number))
                        .pill()
                }

                if graded != nil {
                    Text("Graded")
                        .pill()
                }
            }
            .padding(8)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: item.movieURL) {
            guard still == nil, let url = item.movieURL else { return }
            videoFrame = await VideoFrame.load(from: url, maxSide: 600)
        }
    }
}

private extension Text {
    func pill() -> some View {
        font(.caption2.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.gold, in: Capsule())
    }
}

enum VideoFrame {
    static func load(from url: URL, maxSide: CGFloat) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)

        do {
            let result = try await generator.image(at: time)
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }
}

enum StillVersion: String, CaseIterable, Identifiable {
    case graded = "Graded"
    case original = "Original"

    var id: String { rawValue }
}

struct CaptureDetail: View {
    let store: CameraStore
    let item: CaptureItem
    var graded: GradedStills?
    var info: ClipInfo?

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    @State private var version: StillVersion = .graded
    @State private var master: AVPlayer?
    @State private var stories: AVPlayer?
    @State private var gradedMaster: AVPlayer?

    private var showingGraded: Bool {
        graded != nil && version == .graded
    }

    @State private var fullResolutionPreview: UIImage?
    @State private var cropResolutionPreview: UIImage?
    private var fullPhotoURL: URL? { showingGraded ? (graded?.fullURL ?? item.fullPhotoURL) : item.fullPhotoURL }
    private var cropPhotoURL: URL? { showingGraded ? (graded?.cropURL ?? item.cropPhotoURL) : item.cropPhotoURL }
    private var sharePhotoURL: URL? { cropPhotoURL ?? fullPhotoURL }

    // The picture the share button sends: the version on screen.
    private var shareImage: UIImage? {
        if showingGraded {
            return graded?.crop ?? graded?.full ?? item.cropImage ?? item.fullImage
        }

        return item.cropImage ?? item.fullImage
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.55))

            Spacer()

            Text(value)
                .foregroundStyle(.white)
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                if let info {
                    VStack(spacing: 8) {
                        infoRow("Clip", String(format: "CLIP %02d", info.number))
                        infoRow("Timecode", "\(info.start) – \(info.end)")
                        infoRow("Codec", info.codec)
                        infoRow("Gamma", info.gamma)

                        if let resolution = info.resolution {
                            infoRow("Resolution", resolution)
                        }

                        infoRow("Frame rate", "\(info.frameRate) fps")
                    }
                    .padding(14)
                    .background(
                        Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                if graded != nil, item.movieURL == nil {
                    Picker("Version", selection: $version) {
                        ForEach(StillVersion.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let full = fullResolutionPreview ?? (showingGraded ? (graded?.full ?? item.fullImage) : item.fullImage) {
                    labeled("Full frame", image: full)
                }

                if let crop = cropResolutionPreview ?? (showingGraded ? (graded?.crop ?? item.cropImage) : item.cropImage) {
                    labeled("Frame lines", image: crop)
                }

                if let raw = item.rawURL {
                    ShareLink(item: raw) { Label("Share RAW", systemImage: "square.and.arrow.up") }
                }

                if let movie = item.movieURL {
                    Text("Master")
                        .font(.headline)
                    if let master {
                        VideoPlayer(player: master)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    ShareLink(item: movie) { Label("Share master", systemImage: "square.and.arrow.up") }
                }

                if let gradedMovie = graded?.movie {
                    Text("Graded master")
                        .font(.headline)
                    if let gradedMaster {
                        VideoPlayer(player: gradedMaster)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    ShareLink(item: gradedMovie) { Label("Share graded master", systemImage: "square.and.arrow.up") }
                }

                if let storiesURL = item.storiesURL {
                    Text("Stories")
                        .font(.headline)
                    if let stories {
                        VideoPlayer(player: stories)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    ShareLink(item: storiesURL) { Label("Share Stories", systemImage: "square.and.arrow.up") }
                }
            }
            .padding(20)
        }
        .background(Theme.ink)
        .navigationTitle(item.mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url = sharePhotoURL {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                } else if let image = shareImage {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview("Photo", image: Image(uiImage: image))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .task(id: showingGraded) {
            let full = fullPhotoURL; let crop = cropPhotoURL
            fullResolutionPreview = nil; cropResolutionPreview = nil
            let images = await Task.detached(priority: .userInitiated) {
                let first = full.flatMap { try? Data(contentsOf: $0) }.flatMap { PreparedStill.thumbnail($0, maxPixel: 2560) }
                let second = crop.flatMap { try? Data(contentsOf: $0) }.flatMap { PreparedStill.thumbnail($0, maxPixel: 2560) }
                return (first, second)
            }.value
            guard !Task.isCancelled else { return }
            fullResolutionPreview = images.0; cropResolutionPreview = images.1
        }
        .confirmationDialog(
            "Delete this capture from the gallery?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(item)
                dismiss()
            }
        } message: {
            Text("Copies already saved to Photos are not removed.")
        }
        .onAppear {
            // Built once, so redraws never replace a playing video.
            if master == nil, let url = item.movieURL {
                master = AVPlayer(url: url)
            }

            if stories == nil, let url = item.storiesURL {
                stories = AVPlayer(url: url)
            }

            if gradedMaster == nil, let url = graded?.movie {
                gradedMaster = AVPlayer(url: url)
            }
        }
        .onChange(of: graded?.movie) { _, url in
            if gradedMaster == nil, let url {
                gradedMaster = AVPlayer(url: url)
            }
        }
        .onDisappear {
            master?.pause()
            stories?.pause()
            gradedMaster?.pause()
        }
    }

    private func labeled(_ title: String, image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

extension StyleParams {
    init(look: FilmLook) {
        self.init(look: look, options: LookOptions())
    }
}
