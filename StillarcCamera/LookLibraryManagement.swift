import SwiftUI

nonisolated struct LookLibraryPreferences: Codable, Equatable {
    var hidden: [String] = []
    var order: [String] = []
    var deletedLooks: [CustomLook] = []
    var deletedPresets: [ShootingPreset] = []
    static func load() -> Self {
        UserDefaults.standard.data(forKey: "frameline.lookLibrary.v1").flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "frameline.lookLibrary.v1") } }
}
nonisolated struct LookLibrarySnapshot: Codable {
    var preferences: LookLibraryPreferences
    var looks: [CustomLook]
    var presets: [ShootingPreset]
    var dials: [String: LookDials]
    var activeStyle: String? = nil
    var selectedPreset: UUID? = nil
    var options: LookOptions? = nil
}

extension CameraStore {
    func rememberLibraryChange() {
        libraryUndo.append(LookLibrarySnapshot(preferences: lookLibrary, looks: customLooks, presets: shootingPresets, dials: lookDials, activeStyle: look.id, selectedPreset: selectedPresetID, options: lookOptions))
        libraryUndo = Array(libraryUndo.suffix(8))
        if !isShowcase, let data = try? JSONEncoder().encode(libraryUndo) { UserDefaults.standard.set(data, forKey: "frameline.lookLibrary.undo") }
    }
    func deleteStyles(_ offsets: IndexSet) {
        let ids = offsets.map { allLooks[$0].id }.filter { $0 != "standard" }
        guard !ids.isEmpty else { return }; rememberLibraryChange()
        for id in ids {
            if let custom = customLooks.first(where: { $0.lookID == id }) {
                if !lookLibrary.deletedLooks.contains(where: { $0.id == custom.id }) { lookLibrary.deletedLooks.append(custom) }
                customLooks.removeAll { $0.lookID == id }
            } else if !lookLibrary.hidden.contains(id) { lookLibrary.hidden.append(id) }
            if look.id == id { look = .standard }
        }
    }
    func moveStyles(from offsets: IndexSet, to destination: Int) {
        rememberLibraryChange(); var ids = allLooks.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination); lookLibrary.order = ids
    }
    func deleteManagedPresets(_ offsets: IndexSet) {
        rememberLibraryChange()
        for index in offsets {
            let preset = shootingPresets[index]
            if !lookLibrary.deletedPresets.contains(where: { $0.id == preset.id }) { lookLibrary.deletedPresets.append(preset) }
        }
        shootingPresets.remove(atOffsets: offsets)
    }
    func moveManagedPresets(from offsets: IndexSet, to destination: Int) {
        rememberLibraryChange(); shootingPresets.move(fromOffsets: offsets, toOffset: destination)
    }
    func undoLibraryChange() {
        guard let previous = libraryUndo.popLast() else { return }
        lookLibrary = previous.preferences; customLooks = previous.looks; shootingPresets = previous.presets; lookDials = previous.dials
        lookOptions = previous.options ?? lookOptions
        look = allLooks.first(where: { $0.id == previous.activeStyle }) ?? .standard
        selectedPresetID = previous.selectedPreset
        if !isShowcase, let data = try? JSONEncoder().encode(libraryUndo) { UserDefaults.standard.set(data, forKey: "frameline.lookLibrary.undo") }
    }
    func restoreDeletedLibraryItems() {
        rememberLibraryChange()
        for value in lookLibrary.deletedLooks where !customLooks.contains(where: { $0.id == value.id }) { customLooks.append(value) }
        for value in lookLibrary.deletedPresets where !shootingPresets.contains(where: { $0.id == value.id }) { shootingPresets.append(value) }
        lookLibrary.hidden = []; lookLibrary.deletedLooks = []; lookLibrary.deletedPresets = []
    }
    func resetStyleLibrary() {
        rememberLibraryChange()
        lookLibrary = LookLibraryPreferences(); customLooks = []; shootingPresets = []; lookDials = [:]; lookOptions = LookOptions(); look = .standard
    }
}
