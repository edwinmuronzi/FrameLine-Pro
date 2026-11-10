import SwiftUI
import CoreImage

struct PhotoEditor: View {
    @Bindable var store: CameraStore
    let item: CaptureItem
    @Environment(\.dismiss) private var dismiss
    @State private var edit = PhotoEdit()
    @State private var standardSource: CIImage?
    @State private var rawSource: CIImage?
    @State private var depthMask: CIImage?
    @State private var saving = false
    @State private var framingExpanded = false
    @State private var loadingRAW = false
    @State private var error: String?
    private var availableLooks: [FilmLook] {
        let visible = store.allLooks
        guard !visible.contains(where: { $0.id == edit.styleID }),
              let archived = FilmLook.lineup.first(where: { $0.id == edit.styleID }) ?? store.lookLibrary.deletedLooks.first(where: { $0.lookID == edit.styleID }).map(FilmLook.custom) else { return visible }
        return visible + [archived]
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    preview.frame(height: min(280, geometry.size.height * 0.40)).padding(.horizontal, 20)
                    ScrollView {
                        VStack(spacing: 18) {
                            Text("Your original stays untouched. Change the look now, or come back and change it again later.")
                                .font(.caption).foregroundStyle(.secondary)
                            if item.rawURL != nil && item.fullPhotoURL != nil {
                                Toggle("Develop from RAW", isOn: Binding(get: { edit.useRAW ?? false }, set: { edit.useRAW = $0 }))
                                Text("Use the digital negative for more freedom with brightness and color. RAW development can take longer.").font(.caption).foregroundStyle(.secondary)
                                if loadingRAW { ProgressView("Preparing RAW preview…") }
                            }
                            Picker("Look", selection: $edit.styleID) {
                                ForEach(availableLooks) { Text($0.name).tag($0.id) }
                            }
                            adjustment("Brightness", value: $edit.exposure, range: -2...2, help: "Make the whole photograph lighter or darker.")
                            adjustment("Color", value: $edit.saturation, range: 0...2, help: "From black and white to stronger colors.")
                            adjustment("Warmth", value: $edit.warmth, range: -1...1, help: "Move toward cooler blues or warmer golden tones.")
                            if depthMask != nil && edit.useRAW != true {
                                adjustment("Background blur", value: Binding(get: { edit.depthAmount ?? 0.375 }, set: { edit.depthAmount = $0 }), range: 0...1, help: "Soften the background, or slide to zero to keep the whole photo sharp.")
                                adjustment("Subject separation", value: Binding(get: { edit.depthSeparation ?? 0.5 }, set: { edit.depthSeparation = $0 }), range: 0.1...0.9, help: "Choose how much of the scene stays sharp. Check edges around hair and glass.")
                            }
                            DisclosureGroup("Frame & export", isExpanded: $framingExpanded) {
                                VStack(spacing: 18) {
                                    Picker("Crop", selection: Binding(get: { edit.crop ?? .original }, set: { edit.crop = $0 })) {
                                        ForEach(PhotoCrop.allCases) { Text($0.title).tag($0) }
                                    }.pickerStyle(.segmented)
                                    if edit.crop != nil && edit.crop != .original {
                                        adjustment("Move left / right", value: Binding(get: { edit.cropX ?? 0.5 }, set: { edit.cropX = $0 }), range: 0...1, help: "Move the crop across your original photo.")
                                        adjustment("Move up / down", value: Binding(get: { edit.cropY ?? 0.5 }, set: { edit.cropY = $0 }), range: 0...1, help: "Move the crop vertically. Movement depends on the chosen shape.")
                                    }
                                    adjustment("Straighten", value: Binding(get: { edit.straighten ?? 0 }, set: { edit.straighten = $0 }), range: -10...10, help: "Level a tilted horizon. The edges trim automatically to avoid empty corners.")
                                    Picker("Saved size", selection: Binding(get: { edit.exportLongEdge ?? 0 }, set: { edit.exportLongEdge = $0 == 0 ? nil : $0 })) {
                                        Text("Full resolution").tag(0)
                                        Text("3840 px").tag(3840)
                                        Text("2048 px").tag(2048)
                                        Text("1080 px").tag(1080)
                                    }
                                    Text("Size sets the longest edge of the edited copy. Smaller copies are easier to share; your original stays full size. Photos are never enlarged.").font(.caption).foregroundStyle(.secondary)
                                }.padding(.top, 12)
                            }
                            Button("Reset edits") { edit = PhotoEdit() }
                            if let error { Text(error).foregroundStyle(.red) }
                        }.padding(20)
                    }.disabled(saving)
                }.padding(.top, 12)
            }
            .navigationTitle("Develop photo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save edit") {
                        saving = true
                        let recipe = edit
                        Task {
                            if await store.developPhoto(item, edit: recipe) { dismiss() }
                            else { error = "The edit couldn’t be saved. Your original is safe."; saving = false }
                        }
                    }.disabled(saving || (edit.useRAW == true ? rawSource == nil : standardSource == nil) || loadingRAW || (edit.useRAW == true && rawSource == nil))
                }
            }
            .task {
                edit = store.photoEdits[item.id] ?? PhotoEdit()
                if let url = item.depthMaskURL {
                    depthMask = await Task.detached(priority: .userInitiated) { DepthMask.load(url)?.image }.value
                }
            }
            .task(id: edit.useRAW) {
                let raw = edit.useRAW == true
                if raw && rawSource != nil || !raw && standardSource != nil { return }
                guard let url = raw ? item.rawURL : (item.fullPhotoURL ?? item.cropPhotoURL) else { return }
                loadingRAW = raw
                let image = await Task.detached(priority: .userInitiated) {
                    guard let data = try? Data(contentsOf: url) else { return Optional<CIImage>.none }
                    let decoded = raw ? PhotoDeveloper.rawPreview(data) : data
                    return decoded.flatMap { PreparedStill.thumbnail($0, maxPixel: 1200) }?.cgImage.map { CIImage(cgImage: $0) }
                }.value
                guard !Task.isCancelled else { return }
                if raw { rawSource = image } else { standardSource = image }
                loadingRAW = false
                if image == nil { error = "The preview couldn’t be prepared. Your original is safe." }
            }
        }.tint(Theme.gold).preferredColorScheme(.dark)
        .interactiveDismissDisabled(saving)
        #if DEBUG
        .onAppear { framingExpanded = ProcessInfo.processInfo.arguments.contains("--expand-editor") }
        #endif
    }
    @ViewBuilder private var preview: some View {
        if let source = edit.useRAW == true ? rawSource : standardSource {
            let extent = PhotoDeveloper.geometry(source, edit: edit).extent
            InteractivePhotoPreview(source: source, edit: edit, depthMask: depthMask)
                .aspectRatio(extent.width / extent.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            ProgressView("Preparing preview…")
        }
    }
    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(1))).monospacedDigit() }
            Slider(value: value, in: range).tint(Theme.gold)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}
