#if DEBUG
import SwiftUI

extension CameraStore {
    func verifyLibraryAndEdits() {
        Task { @MainActor in
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillarcLibraryVerification-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let begin = ProcessInfo.processInfo.systemUptime
            var ticks = 0
            let ticker = Task { @MainActor in while !Task.isCancelled { ticks += 1; try? await Task.sleep(for: .milliseconds(16)) } }
            defer { ticker.cancel() }
            let first = CaptureLibrary(root: root)
            let records = (0..<250).map { index in LibraryRecord(id: UUID(), date: Date(), detail: "Capture \(index)", mode: "photo", full: "Captures/test/full.jpg", edit: PhotoEdit(exposure: Double(index) / 250)) }
            do {
                try await first.save(records)
                let reopened = CaptureLibrary(root: root)
                let loaded = await reopened.load()
                let roundtrip = loaded.map(\.id) == records.map(\.id) && loaded.last?.edit == records.last?.edit
                try await reopened.save(Array(records.dropFirst()))
                let afterDelete = await first.load()
                NSLog("LIBRARY_VERIFY %@ roundtrip=%d edits=%d deletion=%d records=%ld", roundtrip && afterDelete.count == 249 ? "PASS" : "FAIL", roundtrip ? 1 : 0, loaded.last?.edit == records.last?.edit ? 1 : 0, afterDelete.count == 249 ? 1 : 0, loaded.count)
            } catch { NSLog("LIBRARY_VERIFY FAIL %@", error.localizedDescription) }
            guard let source = UIImage(named: "Story02")?.jpegData(compressionQuality: 0.93) else { NSLog("EDIT_VERIFY FAIL source"); return }
            let result = await Task.detached(priority: .userInitiated) {
                let originalURL = root.appendingPathComponent("original.jpg")
                try? source.write(to: originalURL, options: .atomic)
                guard let thumbnail = PreparedStill.thumbnail(source, maxPixel: 1200), let data = thumbnail.jpegData(compressionQuality: 0.95) else { return false }
                for index in 0..<30 {
                    let edit = PhotoEdit(styleID: FilmLook.lineup[index % FilmLook.lineup.count].id, exposure: Double(index % 5) * 0.1, saturation: 0.8, warmth: 0.15)
                    guard let developed = PhotoDeveloper.develop(data, edit: edit), let preview = PreparedStill.thumbnail(developed), max(preview.size.width, preview.size.height) <= 640 else { return false }
                }
                return (try? Data(contentsOf: originalURL)) == source && PhotoDeveloper.natural(Data()) == nil
            }.value
            NSLog("EDIT_VERIFY %@ iterations=30 originalPreserved=1 mainActorTicks=%ld elapsed=%.2f", result ? "PASS" : "FAIL", ticks, ProcessInfo.processInfo.systemUptime - begin)
        }
    }
}
#endif
#if DEBUG
extension CameraStore {
    func verifyViewfinderFocus() {
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            try? await Task.sleep(for: .seconds(3))
            guard caps.supportsManualFocus else { NSLog("VIEWFINDER_FOCUS_VERIFY FAIL unsupported lens"); return }
            viewfinderPull = true; focusStart = nil; focusEnd = nil; focusMarkTarget = 0
            let exposureBefore = exposure
            selectFocusMark(at: CGPoint(x: 110, y: 210), in: CGSize(width: 390, height: 700))
            while focusMarkBusy { try? await Task.sleep(for: .milliseconds(40)) }
            selectFocusMark(at: CGPoint(x: 280, y: 420), in: CGSize(width: 390, height: 700))
            while focusMarkBusy { try? await Task.sleep(for: .milliseconds(40)) }
            guard let first = focusStart, let last = focusEnd else { NSLog("VIEWFINDER_FOCUS_VERIFY FAIL autofocus did not settle"); return }
            focusPullDuration = 0.5
            runFocusPull(reverse: true)
            try? await Task.sleep(for: .milliseconds(750))
            let firstOK = abs(liveFocus - first) < 0.06
            runFocusPull()
            try? await Task.sleep(for: .milliseconds(750))
            let lastOK = abs(liveFocus - last) < 0.06
            for _ in 0..<12 { runFocusPull(reverse: true); cancelFocusPull(); runFocusPull() }
            try? await Task.sleep(for: .milliseconds(750))
            NSLog("VIEWFINDER_FOCUS_VERIFY %@ A=%.3f B=%.3f exposurePreserved=%d cancelRepeat=12", firstOK && lastOK && abs(exposureBefore - exposure) < 0.01 && !focusPullRunning ? "PASS" : "FAIL", first, last, abs(exposureBefore - exposure) < 0.01 ? 1 : 0)
            viewfinderPull = false; setAuto(.focus)
        }
    }
}
#endif

#if DEBUG
import CoreImage

extension CameraStore {
    func verifyDirectGrade() {
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                guard let source = UIImage(named: "Story04")?.cgImage else { return false }
                let original = CIImage(cgImage: source, options: [.colorSpace: NSNull()])
                let input = original.transformed(by: CGAffineTransform(scaleX: 2160 / original.extent.width, y: 3840 / original.extent.height))
                let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
                let resolver = CameraFrameRenderer()
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                for index in 1...3 {
                    var style = StyleParams(look: FilmLook.lineup[index], options: LookOptions(), dials: LookRecipe.defaultDials(for: FilmLook.lineup[index].id))
                    style.grain = 0.25; style.glow = 0.15; style.sharpen = 0.1
                    let graph = StyleGrade.grade(input, cube: nil, cubeSize: 0, intensity: 1, style: style).cropped(to: input.extent)
                    let working = input.transformed(by: CGAffineTransform(scaleX: 1920.0 / 2160, y: 1920.0 / 2160))
                    let optimizedGraph = StyleGrade.grade(working, cube: nil, cubeSize: 0, intensity: 1, style: style).cropped(to: working.extent)
                    guard let reference = resolver.materialize(graph, context: context), let optimized = resolver.materialize(optimizedGraph, context: context) else { return false }
                    for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920)] {
                        func resolved(_ image: CIImage) -> CIImage? {
                            let crop = ReelGeometry.crop(in: image.extent, ratio: size.width / size.height, center: CGPoint(x: 0.5, y: 0.5))
                            let output = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)).transformed(by: CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
                            return context.createCGImage(output, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: space).map { CIImage(cgImage: $0) }
                        }
                        guard let a = resolved(reference), let b = resolved(optimized) else { return false }
                        let difference = a.applyingFilter("CIDifferenceBlendMode", parameters: ["inputBackgroundImage": b])
                        for rect in [CGRect(origin: .zero, size: size), CGRect(x: 0, y: 0, width: 8, height: size.height)] {
                            let average = difference.applyingFilter("CIAreaAverage", parameters: ["inputExtent": CIVector(cgRect: rect)])
                            var pixel: [Float] = [0,0,0,0]
                            context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0,y: 0,width: 1,height: 1), format: .RGBAf, colorSpace: nil)
                            let delta = max(pixel[0],pixel[1],pixel[2])
                            NSLog("DIRECT_GRADE_VERIFY style=%ld width=%.0f edge=%d delta=%.5f", index, size.width, rect.width == 8 ? 1 : 0, delta)
                            if !delta.isFinite || delta > 0.025 { return false }
                        }
                    }
                }
                return true
            }.value
            NSLog("DIRECT_GRADE_VERIFY %@ three styles, both crops and left edges compared", result ? "PASS" : "FAIL")
        }
    }
}
#endif
#if DEBUG
extension CameraStore {
    func verifyNV12Output() {
        Task {
            let passed = await Task.detached(priority: .userInitiated) {
                guard let cg = UIImage(named: "Story04")?.cgImage else { return false }
                let source = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: 640.0 / CGFloat(cg.width), y: 960.0 / CGFloat(cg.height)))
                let context = CIContext(options: [.cacheIntermediates: false])
                let size = CGRect(x: 0,y: 0,width: 640,height: 960)
                let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
                guard let referenceCG = context.createCGImage(source, from: size, format: .RGBA8, colorSpace: srgb) else { return false }
                let reference = CIImage(cgImage: referenceCG)
                var productionError: Float = 1
                for transfer709 in [false,true] {
                  for matrix709 in [false,true] {
                    let space = transfer709 ? CGColorSpace(name: CGColorSpace.itur_709)! : srgb
                    var buffer: CVPixelBuffer?
                    guard CVPixelBufferCreate(nil, 640, 960, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else { return false }
                    CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
                    CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, transfer709 ? kCVImageBufferTransferFunction_ITU_R_709_2 : kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
                    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, matrix709 ? kCVImageBufferYCbCrMatrix_ITU_R_709_2 : kCVImageBufferYCbCrMatrix_ITU_R_601_4, .shouldPropagate)
                    let target = CIRenderDestination(pixelBuffer: buffer); target.colorSpace = space
                    do { _ = try context.startTask(toRender: source, from: size, to: target, at: .zero).waitUntilCompleted() }
                    catch { NSLog("NV12_VERIFY render FAIL %@", error.localizedDescription); return false }
                    let image = CIImage(cvPixelBuffer: buffer)
                    let diff = reference.applyingFilter("CIDifferenceBlendMode", parameters: ["inputBackgroundImage": image]).applyingFilter("CIAreaAverage", parameters: ["inputExtent": CIVector(cgRect: size)])
                    var pixel: [Float] = [0,0,0,0]
                    context.render(diff, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0,y: 0,width: 1,height: 1), format: .RGBAf, colorSpace: nil)
                    let error = max(pixel[0],pixel[1],pixel[2]); if !transfer709 && matrix709 { productionError = error }
                    NSLog("NV12_VERIFY transfer709=%d matrix709=%d delta=%.5f", transfer709 ? 1 : 0, matrix709 ? 1 : 0, error)
                  }
                }
                return productionError.isFinite && productionError < 0.01
            }.value
            NSLog("NV12_VERIFY %@", passed ? "PASS" : "FAIL")
        }
    }
}
#endif

#if DEBUG
extension CameraStore {
    func verifyStyleManagement() {
        let test = CameraStore(); test.isShowcase = true
        test.lookLibrary = LookLibraryPreferences(); test.libraryUndo = []; test.customLooks = []; test.shootingPresets = []
        let original = test.allLooks.map(\.id)
        guard original.count > 2 else { NSLog("MANAGER_VERIFY FAIL empty catalog"); return }
        test.moveStyles(from: IndexSet(integer: 1), to: original.count)
        let moved = test.allLooks.last?.id == original[1]
        test.deleteStyles(IndexSet(integer: test.allLooks.count - 1))
        let hidden = !test.allLooks.contains(where: { $0.id == original[1] })
        test.restoreDeletedLibraryItems()
        let restored = test.allLooks.contains(where: { $0.id == original[1] })
        let custom = test.addCustomLook(basedOn: .standard)
        let preset = test.currentShootingPreset(named: "Verification")
        test.shootingPresets = [preset]
        if let index = test.allLooks.firstIndex(where: { $0.id == test.customLooks.first?.lookID }) { test.deleteStyles(IndexSet(integer: index)) }
        test.deleteManagedPresets(IndexSet(integer: 0)); test.restoreDeletedLibraryItems()
        let recovered = test.customLooks.contains(where: { $0.id == custom }) && test.shootingPresets.contains(where: { $0.id == preset.id })
        test.resetStyleLibrary()
        let reset = test.customLooks.isEmpty && test.shootingPresets.isEmpty && test.allLooks.map(\.id) == original
        test.undoLibraryChange()
        let undo = test.customLooks.contains(where: { $0.id == custom }) && test.shootingPresets.contains(where: { $0.id == preset.id })
        let data = try? JSONEncoder().encode(test.lookLibrary)
        let durable = data.flatMap { try? JSONDecoder().decode(LookLibraryPreferences.self, from: $0) } == test.lookLibrary
        NSLog("MANAGER_VERIFY %@ reorder=%d hide=%d restore=%d customAndPreset=%d reset=%d undo=%d persistence=%d", moved && hidden && restored && recovered && reset && undo && durable ? "PASS" : "FAIL", moved ? 1 : 0, hidden ? 1 : 0, restored ? 1 : 0, recovered ? 1 : 0, reset ? 1 : 0, undo ? 1 : 0, durable ? 1 : 0)
    }
}
#endif
