import Foundation
import UIKit
import CoreImage

nonisolated struct PhotoEdit: Codable, Equatable, Sendable {
    var styleID = "standard"
    var exposure = 0.0
    var saturation = 1.0
    var warmth = 0.0
    var useRAW: Bool? = nil
}

// File names are relative to Documents, so records survive app-container changes.
nonisolated struct LibraryRecord: Codable, Sendable {
    var id: UUID; var date: Date; var detail: String; var mode: String
    var full: String?; var crop: String?; var raw: String?
    var movie: String?; var reel: String?; var gradedFull: String?; var gradedCrop: String?
    var edit: PhotoEdit?
    var liveMovie: String? = nil
    var gradedMovie: String? = nil
    var gradedReel: String? = nil
    var clip: ClipInfo? = nil
}

actor CaptureLibrary {
    static let shared = CaptureLibrary()
    private let root: URL
    init(root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) { self.root = root }
    private var index: URL { root.appendingPathComponent("gallery-v1.json") }
    func load() -> [LibraryRecord] {
        guard let data = try? Data(contentsOf: index) else { return [] }
        return (try? JSONDecoder().decode([LibraryRecord].self, from: data)) ?? []
    }
    func save(_ records: [LibraryRecord]) throws {
        try JSONEncoder().encode(records).write(to: index, options: .atomic)
    }
    func clear() throws { try? FileManager.default.removeItem(at: index) }
}

nonisolated enum PhotoDeveloper {
    static let context = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: true])
    static func natural(_ raw: Data) -> Data? {
        guard let filter = CIRAWFilter(imageData: raw, identifierHint: nil) else { return nil }
        filter.isDraftModeEnabled = false
        filter.luminanceNoiseReductionAmount = 0
        filter.colorNoiseReductionAmount = 0
        filter.sharpnessAmount = 0
        filter.localToneMapAmount = 0
        filter.boostAmount = 0
        guard let image = filter.outputImage else { return nil }
        return encode(image)
    }
    static func rawPreview(_ data: Data) -> Data? {
        guard let filter = CIRAWFilter(imageData: data, identifierHint: nil) else { return nil }
        filter.isDraftModeEnabled = true; filter.scaleFactor = 0.3
        guard let image = filter.outputImage else { return nil }; return encode(image)
    }
    static func develop(_ source: Data, edit: PhotoEdit, rawData: Data? = nil) -> Data? {
        var base: CIImage?
        if edit.useRAW == true, let rawData, let filter = CIRAWFilter(imageData: rawData, identifierHint: nil) {
            filter.exposure = Float(edit.exposure)
            base = filter.outputImage
        } else { base = CIImage(data: source, options: [.applyOrientationProperty: true]) }
        guard let image = base else { return nil }
        var recipe = edit
        if edit.useRAW == true && rawData != nil { recipe.exposure = 0 }
        return encode(adjust(image, edit: recipe))
    }
    static func adjust(_ source: CIImage, edit: PhotoEdit) -> CIImage {
        var image = source
        if let look = FilmLook.lineup.first(where: { $0.id == edit.styleID }) ?? CustomLookRegistry.shared.look(for: edit.styleID).map(FilmLook.custom), look.id != "standard" {
            let style = StyleParams(look: look, options: LookOptions(), dials: LookRecipe.defaultDials(for: look.id))
            image = StyleGrade.grade(image, cube: nil, cubeSize: 0, intensity: 1, style: style)
        }
        image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": edit.exposure])
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": edit.saturation])
            .applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + edit.warmth * 2000, y: 0)])
        return image
    }
    static func encode(_ image: CIImage) -> Data? {
        context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.97])
    }
}

extension CameraStore {
    private var libraryRoot: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    func trimGalleryPreviews() {
        guard captures.count > 24 else { return }
        for index in 24..<captures.count {
            captures[index].fullImage = nil; captures[index].cropImage = nil
            let key = AnyHashable(captures[index].id)
            if graded[key] != nil { graded[key]?.full = nil; graded[key]?.crop = nil }
        }
    }
    func restoreLibrary() {
        Task {
            let records = await CaptureLibrary.shared.load()
            let root = libraryRoot
            let loaded = await Task.detached(priority: .utility) {
                records.compactMap { record -> (CaptureItem, GradedStills?, PhotoEdit?)? in
                    func url(_ name: String?) -> URL? {
                        guard let name, !name.contains(".."), !name.hasPrefix("/") else { return nil }
                        let result = root.appendingPathComponent(name)
                        return FileManager.default.fileExists(atPath: result.path) ? result : nil
                    }
                    func thumb(_ file: URL?) -> UIImage? { file.flatMap { try? Data(contentsOf: $0) }.flatMap { PreparedStill.thumbnail($0) } }
                    let full = url(record.full), crop = url(record.crop), movie = url(record.movie)
                    guard full != nil || crop != nil || movie != nil else { return nil }
                    var item = CaptureItem(fullImage: record.id == records.first?.id ? thumb(full) : nil, cropImage: nil, movieURL: movie, storiesURL: url(record.reel), rawURL: url(record.raw), detail: record.detail, simulated: false, mode: CaptureMode(rawValue: record.mode) ?? .photo)
                    item.id = record.id; item.date = record.date; item.fullPhotoURL = full; item.cropPhotoURL = crop; item.livePhotoMovieURL = url(record.liveMovie)
                    let gf = url(record.gradedFull), gc = url(record.gradedCrop)
                    let grade = gf == nil && gc == nil && record.gradedMovie == nil ? nil : GradedStills(fullURL: gf, cropURL: gc, full: record.id == records.first?.id ? thumb(gf) : nil, crop: nil, movie: url(record.gradedMovie), storiesMovie: url(record.gradedReel))
                    return (item, grade, record.edit)
                }
            }.value
            for (item, grade, edit) in loaded where !captures.contains(where: { $0.id == item.id }) {
                captures.append(item)
                if let grade { graded[AnyHashable(item.id)] = grade }
                if let edit { photoEdits[item.id] = edit }
                if let info = records.first(where: { $0.id == item.id })?.clip { clipInfo[AnyHashable(item.id)] = info }
            }
            captures.sort { $0.date > $1.date }
            libraryReady = true
            if libraryDirty { libraryDirty = false; persistLibrary() }
            await importLockedCaptures()
        }
    }
    func persistLibrary() {
        guard !isShowcase else { return }
        guard libraryReady else { libraryDirty = true; return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--verify-") }) { return }
        #endif
        let root = libraryRoot.path + "/"
        func relative(_ url: URL?) -> String? {
            guard let url, url.path.hasPrefix(root) else { return nil }
            return String(url.path.dropFirst(root.count))
        }
        let records = captures.filter { !$0.simulated }.map { item in
            let grade = graded[AnyHashable(item.id)]
            return LibraryRecord(id: item.id, date: item.date, detail: item.detail, mode: item.mode.rawValue,
                full: relative(item.fullPhotoURL), crop: relative(item.cropPhotoURL), raw: relative(item.rawURL),
                movie: relative(item.movieURL), reel: relative(item.storiesURL), gradedFull: relative(grade?.fullURL), gradedCrop: relative(grade?.cropURL), edit: photoEdits[item.id], liveMovie: relative(item.livePhotoMovieURL), gradedMovie: relative(grade?.movie), gradedReel: relative(grade?.storiesMovie), clip: clipInfo[AnyHashable(item.id)])
        }
        let previous = librarySaveTask
        librarySaveTask = Task {
            await previous?.value
            do { try await CaptureLibrary.shared.save(records); return true }
            catch { showToast("Gallery changes couldn’t be stored. Check available space."); return false }
        }
    }
    func developPhoto(_ item: CaptureItem, edit: PhotoEdit) async -> Bool {
        guard let source = item.fullPhotoURL ?? item.cropPhotoURL, !editingPhotos.contains(item.id) else { return false }
        editingPhotos.insert(item.id)
        defer { editingPhotos.remove(item.id) }
        let crop = item.fullPhotoURL != nil ? item.cropPhotoURL : nil
        let prepared = await Task.detached(priority: .userInitiated) { () -> ((URL, UIImage)?, (URL, UIImage)?) in
            let raw = edit.useRAW == true ? item.rawURL.flatMap { try? Data(contentsOf: $0) } : nil
            let sourceData = try? Data(contentsOf: source)
            let rawFull = raw.flatMap { _ in sourceData.flatMap { PhotoDeveloper.develop($0, edit: edit, rawData: raw) } }
            if edit.useRAW == true && rawFull == nil { return (nil, nil) }
            func render(_ url: URL, role: String) -> (URL, UIImage)? {
                guard let data = try? Data(contentsOf: url) else { return nil }
                var output = rawFull ?? PhotoDeveloper.develop(data, edit: edit)
                if role == "crop", let rawFull, let developed = CIImage(data: rawFull),
                   let sourceData, let original = CIImage(data: sourceData, options: [.applyOrientationProperty: true]),
                   let cropOriginal = CIImage(data: data, options: [.applyOrientationProperty: true]) {
                    let width = developed.extent.width * min(1, cropOriginal.extent.width / original.extent.width)
                    let height = developed.extent.height * min(1, cropOriginal.extent.height / original.extent.height)
                    output = PhotoDeveloper.encode(developed.cropped(to: CGRect(x: (developed.extent.width - width) / 2, y: (developed.extent.height - height) / 2, width: width, height: height)))
                }
                guard let output, let thumb = PreparedStill.thumbnail(output) else { return nil }
                let file = source.deletingLastPathComponent().appendingPathComponent("edit-\(UUID().uuidString)-\(role).jpg")
                do { try output.write(to: file, options: .atomic); return (file, thumb) } catch { return nil }
            }
            let full = render(source, role: "full")
            let framed = crop.flatMap { $0 == source ? full : render($0, role: "crop") }
            return (full, framed)
        }.value
        guard let full = prepared.0, captures.contains(where: { $0.id == item.id }) else { return false }
        let old = graded[AnyHashable(item.id)]
        graded[AnyHashable(item.id)] = item.fullPhotoURL == nil
            ? GradedStills(cropURL: full.0, full: nil, crop: full.1)
            : GradedStills(fullURL: full.0, cropURL: prepared.1?.0, full: full.1, crop: prepared.1?.1)
        photoEdits[item.id] = edit
        persistLibrary()
        // Old versions remain until the new index is safely written.
        guard await librarySaveTask?.value == true else { return false }
        for url in [old?.fullURL, old?.cropURL].compactMap({ $0 }) where url != item.fullPhotoURL && url != item.cropPhotoURL { try? FileManager.default.removeItem(at: url) }
        return true
    }
}
