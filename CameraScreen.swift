import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct CameraScreen: View {
    @Bindable var store: CameraStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGallery = false
    @State private var showFn = false
    @State private var showSettings = false
    @State private var importLUT = false
    @State private var dragStartExposure: Float?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Viewfinder / Live Camera Preview
                ViewfinderArea(store: store, size: geo.size)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if dragStartExposure == nil {
                                    dragStartExposure = store.exposureBias
                                }
                                let delta = Float(-gesture.translation.height / 100.0)
                                let initial = dragStartExposure ?? 0
                                store.exposureBias = min(max(initial + delta, -3.0), 3.0)
                            }
                            .onEnded { _ in
                                dragStartExposure = nil
                            }
                    )

                // Overlay UI Controls
                VStack {
                    TopBar(
                        store: store,
                        showSettings: $showSettings
                    )
                    .padding(.top, geo.safeAreaInsets.top > 0 ? 0 : 8)

                    Spacer()

                    if let toast = store.toastMessage {
                        Text(toast)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                            .transition(.opacity.combined(with: .scale))
                            .padding(.bottom, 12)
                    }

                    ToolBar(
                        store: store,
                        showFn: $showFn,
                        showGallery: $showGallery
                    )
                    .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? 0 : 12)
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(store: store, importLUT: $importLUT)
        }
        .sheet(isPresented: $showFn) {
            FnPanelSheet(store: store)
        }
        .sheet(isPresented: $showGallery) {
            GallerySheet(store: store)
        }
        .fileImporter(
            isPresented: $importLUT,
            allowedContentTypes: [.item]
        ) { result in
            switch result {
            case .success(let url):
                store.importLUT(from: url)
            case .failure(let error):
                store.showToast("Import failed: \(error.localizedDescription)")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.startEngine()
            } else if newPhase == .background {
                store.stopEngine()
            }
        }
    }
}

private struct ViewfinderArea: View {
    @Bindable var store: CameraStore
    let size: CGSize

    var body: some View {
        ZStack {
            if store.caps.hasCamera {
                Color.gray.opacity(0.2)
            } else {
                DemoHarborScene()
            }

            // Frame lines
            let sourceRatio = size.height > 0 ? size.width / size.height : 1.0
            let focalScale = CGFloat(35.0 / store.focalLength.value)
            let rect = FrameMath.normalizedRect(
                focalScale: focalScale,
                aspect: store.aspect,
                sourceRatio: sourceRatio
            )

            Rectangle()
                .path(in: CGRect(
                    x: rect.minX * size.width,
                    y: rect.minY * size.height,
                    width: rect.width * size.width,
                    height: rect.height * size.height
                ))
                .stroke(Color.white.opacity(0.85), lineWidth: 1.5)

            // Rangefinder focal point indicator
            if store.mode == .rangefinder {
                Circle()
                    .stroke(Color.yellow, lineWidth: 1)
                    .frame(width: 44, height: 44)
            }
        }
        .ignoresSafeArea()
    }
}

private struct TopBar: View {
    @Bindable var store: CameraStore
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            Button {
                cycleFlash()
            } label: {
                Image(systemName: store.flash.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }

            Button {
                cycleAspect()
            } label: {
                Text(store.aspect.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
        }
    }

    private func cycleAspect() {
        let all = FrameAspect.allCases
        let index = all.firstIndex(of: store.aspect) ?? 0
        store.aspect = all[(index + 1) % all.count]
        store.showToast(store.aspect.title)
    }

    private func cycleFlash() {
        let all = FlashChoice.allCases
        let index = all.firstIndex(of: store.flash) ?? 0
        store.flash = all[(index + 1) % all.count]
    }
}

struct ToolBar: View {
    @Bindable var store: CameraStore
    @Binding var showFn: Bool
    @Binding var showGallery: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Mode selector
            HStack(spacing: 20) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        store.selectMode(mode)
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(store.mode == mode ? Color.yellow : Color.white.opacity(0.6))
                    }
                }
            }

            // Main Control Strip
            HStack {
                Button {
                    showFn = true
                } label: {
                    Text("Fn")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }

                Spacer()

                // Shutter Button
                Button {
                    store.triggerShutter()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 72, height: 72)
                        Circle()
                            .fill(store.isRecording ? Color.red : Color.white)
                            .frame(width: store.isRecording ? 32 : 60, height: store.isRecording ? 32 : 60)
                            .clipShape(RoundedRectangle(cornerRadius: store.isRecording ? 6 : 30))
                    }
                }

                Spacer()

                Button {
                    showGallery = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
