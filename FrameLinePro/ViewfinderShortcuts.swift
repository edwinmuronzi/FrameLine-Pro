import SwiftUI

nonisolated enum ViewfinderShortcut: String, CaseIterable, Identifiable {
    case timelapse, magnify, timer, histogram, focusPull, looks, manual, gallery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .timelapse: "Timelapse"; case .magnify: "Magnifier"; case .timer: "Countdown"
        case .histogram: "Histogram"; case .focusPull: "Focus pull"; case .looks: "Looks & LUTs"; case .manual: "Manual controls"; case .gallery: "Gallery"
        }
    }
    var help: String {
        switch self {
        case .timelapse: "Take pictures at intervals to show time passing."
        case .magnify: "Enlarge the preview to check focus; the saved frame stays the same."
        case .timer: "Give yourself time to get into the picture."
        case .histogram: "Check how much of the image is dark, midtone or bright."
        case .focusPull: "In Video, remember two focus distances and move smoothly between them."
        case .looks: "Choose the colors and texture of your pictures."
        case .manual: "Set exposure, focus and white balance yourself."
        case .gallery: "Review your saved captures and develop photos."
        }
    }
    var symbol: String {
        switch self {
        case .timelapse: "clock.arrow.circlepath"; case .magnify: "plus.magnifyingglass"; case .timer: "timer"
        case .histogram: "chart.bar.xaxis"; case .focusPull: "camera.metering.center.weighted"; case .looks: "camera.filters"; case .manual: "slider.horizontal.3"; case .gallery: "photo.on.rectangle"
        }
    }
}

nonisolated enum PhotoToolbarControl: String, CaseIterable, Identifiable {
    case rangefinder, aspect, raw, flash, manual, histogram, looks, gallery, hidden
    static let defaults: [Self] = [.rangefinder, .aspect, .raw, .flash, .manual]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rangefinder: "Rangefinder"
        case .aspect: "Aspect ratio"
        case .raw: "RAW"
        case .flash: "Flash"
        case .manual: "Manual controls"
        case .histogram: "Histogram"
        case .looks: "Looks & LUTs"
        case .gallery: "Gallery"
        case .hidden: "Empty"
        }
    }

    static func load() -> [Self] {
        let saved = UserDefaults.standard.stringArray(forKey: "frameline.photoToolbar.v1")?.compactMap(Self.init(rawValue:))
        guard let saved, saved.count == defaults.count else { return defaults }
        return saved
    }
}

struct ShortcutSettings: View {
    @Bindable var store: CameraStore
    var body: some View {
        Form {
            Section("Three buttons above the zoom ruler") {
                ForEach(0..<3) { index in
                    Picker(["Left", "Middle", "Right"][index], selection: Binding(get: { store.viewfinderShortcuts[index] }, set: { value in
                        var choices = store.viewfinderShortcuts
                        if let duplicate = choices.firstIndex(of: value) { choices[duplicate] = choices[index] }
                        choices[index] = value; store.viewfinderShortcuts = choices
                    })) { ForEach(ViewfinderShortcut.allCases) { Text($0.title).tag($0) } }
                }
                Button("Restore defaults") { store.viewfinderShortcuts = [.timelapse, .magnify, .timer] }
            }
            Section {
                ForEach(PhotoToolbarControl.defaults.indices, id: \.self) { index in
                    Picker(["Far left", "Left", "Center", "Right", "Far right"][index], selection: Binding(
                        get: { store.photoToolbar[index] },
                        set: { value in
                            var controls = store.photoToolbar
                            if value != .hidden, let previous = controls.firstIndex(of: value) {
                                controls[previous] = controls[index]
                            }
                            controls[index] = value
                            store.photoToolbar = controls
                        }
                    )) {
                        ForEach(PhotoToolbarControl.allCases) { Text($0.title).tag($0) }
                    }
                }
                Button("Restore photo controls") { store.photoToolbar = PhotoToolbarControl.defaults }
            } header: {
                Text("Photo & Rangefinder bottom row")
            } footer: {
                Text("Move the controls you use most or leave a position empty.")
            }
            Section("What they do") {
                ForEach(ViewfinderShortcut.allCases) { shortcut in
                    LabeledContent { Text(shortcut.help).font(.caption).foregroundStyle(.secondary) } label: { Label(shortcut.title, systemImage: shortcut.symbol) }
                }
            }
        }.navigationTitle("Viewfinder shortcuts")
    }
}

struct CustomShortcutButton: View {
    @Bindable var store: CameraStore
    let shortcut: ViewfinderShortcut
    var body: some View {
        Button {
            switch shortcut {
            case .histogram: store.showHistogram.toggle()
            case .focusPull: if store.mode == .video { store.toggleViewfinderPull() } else { store.showToast("Focus pulls are available in Video.") }
            case .looks: store.showLUTPanel.toggle()
            case .manual: store.showManual.toggle()
            case .gallery: store.requestGallery = true
            default: break
            }
        } label: {
            Label(shortcut.title, systemImage: shortcut.symbol).labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .bold)).frame(width: 52, height: 28)
                .foregroundStyle(.white).glass(Capsule())
        }.accessibilityLabel(shortcut.title).accessibilityHint(shortcut.help)
    }
}
