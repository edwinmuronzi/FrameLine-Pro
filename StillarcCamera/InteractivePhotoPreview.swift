import CoreImage
import MetalKit
import SwiftUI

// The decoded preview is prepared once. Slider changes update a small CI graph
// and render directly to a drawable: no debounce, JPEG encode or UIImage decode.
struct InteractivePhotoPreview: UIViewRepresentable {
    let source: CIImage
    let edit: PhotoEdit
    var depthMask: CIImage? = nil
    func makeCoordinator() -> Renderer { Renderer() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.framebufferOnly = false; view.isPaused = true; view.enableSetNeedsDisplay = true
        view.isOpaque = true; view.backgroundColor = .black; view.delegate = context.coordinator
        view.contentScaleFactor = min(view.traitCollection.displayScale, 2)
        view.colorPixelFormat = .rgba16Float
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name:CGColorSpace.extendedLinearSRGB)
            layer.wantsExtendedDynamicRangeContent = true
        }
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(source: source, edit: edit, depthMask: depthMask, view: view)
    }
    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.delegate = nil
        coordinator.clear()
    }

    @MainActor final class Renderer: NSObject, MTKViewDelegate {
        let device = MTLCreateSystemDefaultDevice()
        lazy var commands = device?.makeCommandQueue()
        lazy var context = device.map { CIContext(mtlDevice: $0, options:[.cacheIntermediates:false,.workingColorSpace:PhotoDeveloper.workingColorSpace]) }
        var source: CIImage?
        var edit = PhotoEdit()
        var depthMask: CIImage?
        private var drawing = false
        private var dirty = true

        func update(source: CIImage, edit: PhotoEdit, depthMask: CIImage?, view: MTKView) {
            guard self.source !== source || self.edit != edit || self.depthMask !== depthMask else { return }
            self.source = source
            self.edit = edit
            self.depthMask = depthMask
            invalidate(view)
        }

        func clear() {
            source = nil
            depthMask = nil
            context?.clearCaches()
        }

        private func invalidate(_ view: MTKView) {
            dirty = true
            if !drawing { view.setNeedsDisplay() }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { invalidate(view) }
        func draw(in view: MTKView) {
            guard dirty, !drawing, let source, let drawable = view.currentDrawable, let commands, let command = commands.makeCommandBuffer(), let context else { return }
            #if DEBUG
            let began = CACurrentMediaTime()
            #endif
            let size = view.drawableSize
            guard size.width > 0, size.height > 0 else { return }
            drawing = true
            dirty = false
            var recipe = edit; recipe.useRAW = false
            let image = PhotoDeveloper.adjust(source, edit: recipe, depthMask: depthMask)
            let scale = min(size.width / image.extent.width, size.height / image.extent.height)
            let placed = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: (size.width - image.extent.width * scale) / 2, y: (size.height - image.extent.height * scale) / 2))
            let frame = placed.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size)))
            context.render(frame, to: drawable.texture, commandBuffer: command, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!)
            #if DEBUG
            command.addCompletedHandler { _ in EditorPreviewProbe.shared.record((CACurrentMediaTime() - began) * 1000) }
            #endif
            command.addCompletedHandler { [weak self, weak view] _ in
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.drawing = false
                    if self.dirty { view.setNeedsDisplay() }
                }
            }
            command.present(drawable); command.commit()
        }
    }
}
