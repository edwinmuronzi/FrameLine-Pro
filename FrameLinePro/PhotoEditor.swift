import SwiftUI

struct PhotoEditor: View {
    @Bindable var store: CameraStore
    let item: CaptureItem
    @Environment(\.dismiss) private var dismiss
    @State private var edit = PhotoEdit()
    @State private var preview: UIImage?
    @State private var saving = false
    @State private var rawPreviewData: Data?
    @State private var loadingRAW = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image = preview ?? item.fullImage ?? item.cropImage {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    Text("Your original stays untouched. Change the look now, or come back and change it again later.")
                        .font(.caption).foregroundStyle(.secondary)
                    if item.rawURL != nil && item.fullPhotoURL != nil {
                        Toggle("Develop from RAW", isOn: Binding(get: { edit.useRAW ?? false }, set: { edit.useRAW = $0 }))
                        Text("Use the digital negative for more freedom with brightness and color. RAW development can take longer.").font(.caption).foregroundStyle(.secondary)
                        if loadingRAW { ProgressView("Preparing RAW preview…") }
                    }
                    Picker("Look", selection: $edit.styleID) {
                        ForEach(FilmLook.lineup) { Text($0.name).tag($0.id) }
                    }
                    adjustment("Brightness", value: $edit.exposure, range: -2...2, help: "Make the whole photograph lighter or darker.")
                    adjustment("Color", value: $edit.saturation, range: 0...2, help: "From black and white to stronger colors.")
                    adjustment("Warmth", value: $edit.warmth, range: -1...1, help: "Move toward cooler blues or warmer golden tones.")
                    Button("Reset edits") { edit = PhotoEdit() }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(20)
            }
            .navigationTitle("Develop photo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save edit") {
                        saving = true
                        Task {
                            if await store.developPhoto(item, edit: edit) { dismiss() }
                            else { error = "The edit couldn’t be saved. Your original is safe."; saving = false }
                        }
                    }.disabled(saving || preview == nil || loadingRAW || (edit.useRAW == true && rawPreviewData == nil))
                }
            }
            .task { edit = store.photoEdits[item.id] ?? PhotoEdit() }
            .task(id: edit.useRAW) {
                guard edit.useRAW == true, rawPreviewData == nil, let url = item.rawURL else { return }
                loadingRAW = true
                let data = await Task.detached(priority: .utility) { (try? Data(contentsOf: url)).flatMap { PhotoDeveloper.rawPreview($0) } }.value
                guard !Task.isCancelled else { loadingRAW = false; return }
                rawPreviewData = data; loadingRAW = false
                if data == nil { error = "RAW preview is unavailable. Turn off Develop from RAW to edit the original photo." }
            }
            .task(id: PreviewKey(edit: edit, rawReady: rawPreviewData != nil)) {
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled, let url = item.fullPhotoURL ?? item.cropPhotoURL else { return }
                var recipe = edit
                let rawPreview = edit.useRAW == true ? rawPreviewData : nil
                recipe.useRAW = false
                let image = await Task.detached(priority: .userInitiated) {
                    guard let data = rawPreview ?? (try? Data(contentsOf: url)), let thumb = PreparedStill.thumbnail(data, maxPixel: 1100),
                          let small = thumb.jpegData(compressionQuality: 0.93), let developed = PhotoDeveloper.develop(small, edit: recipe) else { return Optional<UIImage>.none }
                    return UIImage(data: developed)
                }.value
                guard !Task.isCancelled else { return }
                preview = image
            }
        }.preferredColorScheme(.dark)
        .interactiveDismissDisabled(saving)
    }
    private struct PreviewKey: Equatable { let edit: PhotoEdit; let rawReady: Bool }
    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(1))).monospacedDigit() }
            Slider(value: value, in: range).tint(Theme.gold)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}
