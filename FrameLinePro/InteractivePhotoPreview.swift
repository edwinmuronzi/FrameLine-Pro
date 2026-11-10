import CoreImage
import MetalKit
import SwiftUI

// The decoded preview is prepared once. Slider changes update a small CI graph
// and render directly to a drawable: no debounce, JPEG encode or UIImage decode.
struct InteractivePhotoPreview: UIViewRepresentable {
    let source: CIImage
    let edit: PhotoEdit
    func makeCoordinator() -> Renderer { Renderer() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.framebufferOnly = false; view.isPaused = true; view.enableSetNeedsDisplay = true
        view.isOpaque = true; view.backgroundColor = .black; view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.source = source; context.coordinator.edit = edit
        view.setNeedsDisplay()
    }
    final class Renderer: NSObject, MTKViewDelegate {
        let device = MTLCreateSystemDefaultDevice()
        lazy var commands = device?.makeCommandQueue()
        lazy var context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: true]) }
        var source: CIImage?
        var edit = PhotoEdit()
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }
        func draw(in view: MTKView) {
            guard let source, let drawable = view.currentDrawable, let commands, let command = commands.makeCommandBuffer(), let context else { return }
            #if DEBUG
            let began = CACurrentMediaTime()
            #endif
            let size = view.drawableSize
            guard size.width > 0, size.height > 0 else { return }
            var recipe = edit; recipe.useRAW = false
            let image = PhotoDeveloper.adjust(source, edit: recipe)
            let scale = min(size.width / image.extent.width, size.height / image.extent.height)
            let placed = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: (size.width - image.extent.width * scale) / 2, y: (size.height - image.extent.height * scale) / 2))
            let frame = placed.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size)))
            context.render(frame, to: drawable.texture, commandBuffer: command, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            #if DEBUG
            command.addCompletedHandler { _ in EditorPreviewProbe.shared.record((CACurrentMediaTime() - began) * 1000) }
            #endif
            command.present(drawable); command.commit()
        }
    }
}
