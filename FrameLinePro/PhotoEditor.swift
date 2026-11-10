import SwiftUI
import CoreImage

struct PhotoEditor: View {
    @Bindable var store: CameraStore
    let item: CaptureItem
    @Environment(\.dismiss) private var dismiss
    @State private var edit = PhotoEdit()
    @State private var standardSource: CIImage?
    @State private var rawSource: CIImage?
    @State private var saving = false
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
            ScrollView {
                VStack(spacing: 18) {
                    if let source = edit.useRAW == true ? rawSource : standardSource {
                        InteractivePhotoPreview(source: source, edit: edit)
                            .aspectRatio(source.extent.width / source.extent.height, contentMode: .fit)
                            .frame(maxHeight: 340).clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        ProgressView("Preparing preview…").frame(height: 260)
                    }
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
                    }.disabled(saving || (edit.useRAW == true ? rawSource == nil : standardSource == nil) || loadingRAW || (edit.useRAW == true && rawSource == nil))
                }
            }
            .task { edit = store.photoEdits[item.id] ?? PhotoEdit() }
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
        }.preferredColorScheme(.dark)
        .interactiveDismissDisabled(saving)
    }
    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(1))).monospacedDigit() }
            Slider(value: value, in: range).tint(Theme.gold)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}
