import SwiftUI
import UniformTypeIdentifiers

struct PresetFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var presets: [ShootingPreset]

    init(presets: [ShootingPreset]) { self.presets = presets }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        presets = try Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encode(presets))
    }

    nonisolated static func encode(_ presets: [ShootingPreset]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Archive(version: 1, presets: presets))
        _ = try decode(data)
        return data
    }

    nonisolated static func read(_ url: URL) throws -> [ShootingPreset] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try decode(handle.read(upToCount: limit + 1) ?? Data())
    }

    private nonisolated struct Archive: Codable {
        let version: Int
        let presets: [ShootingPreset]
    }

    private nonisolated static let limit = 1_048_576

    private nonisolated static func decode(_ data: Data) throws -> [ShootingPreset] {
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1, !archive.presets.isEmpty, archive.presets.count <= 1000,
              archive.presets.allSatisfy(isValid) else { throw CocoaError(.fileReadCorruptFile) }
        return archive.presets
    }

    private nonisolated static func isValid(_ preset: ShootingPreset) -> Bool {
        let dimensions = (preset.width, preset.height)
        let validSize: Bool
        switch dimensions {
        case (nil, nil): validSize = true
        case let (width?, height?): validSize = (1280...8192).contains(width) && (720...8192).contains(height)
        default: validSize = false
        }
        return validSize
            && (preset.fps.map { (1...240).contains($0) } ?? true)
            && (24...90).contains(preset.focal) && (-3...3).contains(preset.exposure)
            && (1...100_000).contains(preset.iso) && (0.00001...30).contains(preset.shutter)
            && (0...360).contains(preset.shutterAngle) && (2000...12_000).contains(preset.whiteBalance)
            && (0...1).contains(preset.focus) && (preset.focusStart.map { (0...1).contains($0) } ?? true)
            && (preset.focusEnd.map { (0...1).contains($0) } ?? true) && (0.05...60).contains(preset.focusDuration)
            && (0.1...32).contains(preset.lens) && (0...8).contains(preset.zoom)
            && (0...1).contains(preset.lutIntensity) && (0...1).contains(preset.lookOptions.strength)
            && (0...2).contains(preset.lookOptions.grainAmount)
    }
}
