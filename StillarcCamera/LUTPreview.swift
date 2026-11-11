
import AVFoundation
import CoreImage
import Metal
import MetalKit
import UIKit

final class LUTPreviewRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let context: CIContext

    private let lock = NSLock()
    private weak var metalView: MTKView?

    private var latestImage: CIImage?
    private var lutData: Data?
    private var lutSize: Int = 0
    private var intensity: Float = 1

    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.context = CIContext(
            mtlDevice: device,
            options: [.cacheIntermediates: false]
        )
        self.metalView = metalView

        super.init()

        metalView.device = device
        metalView.delegate = self
        metalView.framebufferOnly = false
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
    }

    func updateLUT(
        data: Data?,
        size: Int,
        intensity: Float
    ) {
        lock.lock()
        lutData = data
        lutSize = size
        self.intensity = min(max(intensity, 0), 1)
        lock.unlock()

        requestDisplay()
    }

    func submit(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)

        lock.lock()
        latestImage = image
        lock.unlock()

        requestDisplay()
    }

    private func requestDisplay() {
        DispatchQueue.main.async { [weak self] in
            self?.metalView?.setNeedsDisplay()
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        lock.lock()
        let source = latestImage
        let cubeData = lutData
        let cubeSize = lutSize
        let mix = intensity
        lock.unlock()

        guard let source else { return }

        var output = source

        if let cubeData, cubeSize >= 2, mix > 0 {
            let cube = CIFilter(name: "CIColorCube")
            cube?.setValue(source, forKey: kCIInputImageKey)
            cube?.setValue(cubeData, forKey: "inputCubeData")
            cube?.setValue(cubeSize, forKey: "inputCubeDimension")

            if let graded = cube?.outputImage {
                if mix >= 1 {
                    output = graded
                } else {
                    let dissolve = CIFilter(name: "CIDissolveTransition")
                    dissolve?.setValue(source, forKey: kCIInputImageKey)
                    dissolve?.setValue(graded, forKey: "inputTargetImage")
                    dissolve?.setValue(mix, forKey: "inputTime")
                    output = dissolve?.outputImage ?? source
                }
            }
        }

        let bounds = CGRect(
            origin: .zero,
            size: view.drawableSize
        )

        guard bounds.width > 0,
              bounds.height > 0,
              output.extent.width > 0,
              output.extent.height > 0 else {
            return
        }

        let extent = output.extent

        let scale = max(
            bounds.width / extent.width,
            bounds.height / extent.height
        )

        output = output.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        let scaledExtent = output.extent

        output = output.transformed(
            by: CGAffineTransform(
                translationX: -scaledExtent.midX + bounds.midX,
                y: -scaledExtent.midY + bounds.midY
            )
        )

        output = output.cropped(to: bounds)

        context.render(
            output,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {}
}
