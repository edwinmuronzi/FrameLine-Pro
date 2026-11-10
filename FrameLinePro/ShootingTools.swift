import SwiftUI

struct ShootingToolsSheet: View {
    @Bindable var store: CameraStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { ShootingPresetsView(store: store) } label: {
                        Label("Shooting presets", systemImage: "square.stack.3d.up")
                    }
                    NavigationLink { TrackingToolsView(store: store) } label: {
                        Label("Subject tracking", systemImage: "viewfinder")
                    }
                    NavigationLink { FocusPullToolsView(store: store, onRun: { dismiss() }) } label: {
                        Label("Focus pulls", systemImage: "camera.metering.center.weighted")
                    }
                    NavigationLink { FramingToolsView(store: store) } label: {
                        Label("Safe zones & anamorphic", systemImage: "aspectratio")
                    }
                    NavigationLink { AudioToolsView(store: store) } label: {
                        Label("Microphone & monitoring", systemImage: "waveform")
                    }
                } footer: {
                    Text("Tracking and safe-zone guides stay out of saved images. Anamorphic correction is saved only when you enable it.")
                }
            }
            .navigationTitle("Shooting tools")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Theme.gold)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

struct ShootingPresetsView: View {
    @Bindable var store: CameraStore
    @State private var name = ""
    @State private var renameID: UUID?
    @State private var renamed = ""
    var body: some View {
        Form {
            Section("Save this setup") {
                TextField("Preset name", text: $name)
                Button("Save current setup", systemImage: "plus.circle") {
                    store.saveShootingPreset(named: name); name = ""
                }
                .disabled(store.isRecording)
            }
            Section {
                if store.shootingPresets.isEmpty { Text("No shooting presets yet.").foregroundStyle(.secondary) }
                ForEach(store.shootingPresets) { preset in
                    HStack {
                        Button {
                            store.applyShootingPreset(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name).foregroundStyle(.primary)
                                Text("\(preset.mode.uppercased()) · \(preset.dual ? "Dual Shot" : "Single") · \(preset.fps.map { "\($0) fps" } ?? "Auto fps")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(store.isRecording)
                        Menu {
                            Button("Rename", systemImage: "pencil") { renamed = preset.name; renameID = preset.id }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.shootingPresets.removeAll { $0.id == preset.id }
                            }
                        } label: { Image(systemName: "ellipsis").padding(8) }
                    }
                }
            } header: { Text("Your presets") } footer: {
                Text("Includes camera format, exposure, white balance, focus, lens, look/LUT, Dual Shot, framing and audio choices. Apply a preset between recordings.")
            }
        }
        .navigationTitle("Shooting presets")
        .alert("Rename preset", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("Name", text: $renamed)
            Button("Save") {
                let trimmed = String(renamed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
                if let index = store.shootingPresets.firstIndex(where: { $0.id == renameID }), !trimmed.isEmpty {
                    store.shootingPresets[index].name = trimmed
                }
                renameID = nil
            }
            Button("Cancel", role: .cancel) { renameID = nil }
        }
    }
}

private struct TrackingToolsView: View {
    @Bindable var store: CameraStore
    var body: some View {
        Form {
            Section {
                if (store.mode != .video || !store.dualShot) && !store.isRecording {
                    Button("Use Dual Shot video") { store.selectMode(.video); store.dualShot = true }
                }
                Toggle("Follow subject in reel", isOn: $store.subjectTracking)
                    .disabled(store.mode != .video || !store.dualShot)
                LabeledContent("Status", value: !store.subjectTracking ? "Off" : (store.trackingLost ? "Lost · tap to reacquire" : (store.trackedSubjectRect == nil ? "Looking for a face" : "Tracking")))
                Button("Stop tracking") { store.subjectTracking = false }
                    .disabled(!store.subjectTracking)
            } footer: {
                Text("Enable Video and Dual Shot, then tap your subject in the reel viewfinder. A visible face can be picked automatically. The landscape view stays wide; only the reel crop follows. Move the phone if the subject goes outside the camera’s available framing.")
            }
            Section {
                Text("Autofocus follows the tracked subject while AF is on. Manual focus and focus pulls keep control of focus.")
            }
        }
        .navigationTitle("Subject tracking")
    }
}

private struct FocusPullToolsView: View {
    @Bindable var store: CameraStore
    var onRun: () -> Void
    var body: some View {
        Form {
            Section {
                Toggle("Fixed-lens focus mode", isOn: $store.focusPullLensEnabled)
                    .disabled(store.isRecording)
            } footer: {
                Text("Choose before recording. This enables focus pulls on the rear 1× lens and its 2× crop. Turn it off to return to smooth zoom across all rear lenses.")
            }
            Section {
                LabeledContent("Focus", value: store.focusAuto ? "Autofocus" : String(format: "%.2f", store.lensPosition))
                Slider(value: Binding(get: { Double(store.focusAuto ? store.liveFocus : store.lensPosition) }, set: {
                    store.cancelFocusPull(); store.setValue(.focus, $0)
                }), in: 0...1)
                .disabled(!store.caps.supportsManualFocus)
                Button("Use autofocus") { store.cancelFocusPull(); store.setAuto(.focus) }
            }
            Section {
                HStack {
                    Button("Set start") { store.markFocusStart() }
                    Spacer()
                    Text(store.focusStart.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit()
                }
                HStack {
                    Button("Set end") { store.markFocusEnd() }
                    Spacer()
                    Text(store.focusEnd.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit()
                }
                Button("Go to start") {
                    if let mark = store.focusStart { store.cancelFocusPull(); store.setValue(.focus, Double(mark)) }
                }
                .disabled(store.focusStart == nil)
                LabeledContent("Duration", value: String(format: "%.1f s", store.focusPullDuration))
                Slider(value: $store.focusPullDuration, in: 0.5...10, step: 0.5)
            } footer: {
                Text(store.caps.supportsManualFocus
                    ? "Focus on the first subject and set Start. Focus on the second and set End. Go to Start, then run the pull. You can run it while recording."
                    : "This camera does not currently support custom focus positions.")
            }
            .disabled(!store.caps.supportsManualFocus)
            Section {
                HStack {
                    Button("Start → End") { store.runFocusPull(); onRun() }
                    Spacer()
                    Button("End → Start") { store.runFocusPull(reverse: true); onRun() }
                }
                .disabled(store.focusStart == nil || store.focusEnd == nil || !store.caps.supportsManualFocus || store.focusPullRunning)
                if store.focusPullRunning {
                    ProgressView(value: store.focusPullProgress)
                    Button("Stop pull", role: .destructive) { store.cancelFocusPull() }
                }
            }
        }
        .navigationTitle("Focus pulls")
    }
}

private struct FramingToolsView: View {
    @Bindable var store: CameraStore
    private var rawLog: Bool { store.logProfile != .off && !store.styleActive && !store.isLUTBaking }
    var body: some View {
        Form {
            Section {
                Toggle("Show reel safe zones", isOn: $store.framingOptions.safeZones)
                Picker("Guide", selection: $store.framingOptions.safeZoneStyle) {
                    ForEach(SafeZoneStyle.allCases) { Text($0.rawValue).tag($0) }
                }
            } footer: {
                Text("Dual Shot guides keep important faces and text clear of common caption and interface areas. They are visual guides, not platform-exact templates, and are never baked into video.")
            }
            Section {
                Picker("Anamorphic lens", selection: $store.framingOptions.anamorphic) {
                    ForEach(AnamorphicLens.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Squeeze direction", selection: $store.framingOptions.squeezeAxis) {
                    ForEach(SqueezeAxis.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(store.framingOptions.anamorphic == .off)
                Toggle("Save corrected video", isOn: $store.framingOptions.saveDesqueezed)
                    .disabled(store.framingOptions.anamorphic == .off || rawLog)
            } header: { Text("Anamorphic · video") } footer: {
                Text("Choose the factor and direction printed on your attached lens. Off is correct for ordinary lenses. Preview-only keeps the saved pixels squeezed. Saving correction uses full-frame composition; Dual Shot retains its 16:9 and 9:16 outputs. Raw Log without a baked look/LUT supports preview correction only.")
            }
            .disabled(store.isRecording)
        }
        .navigationTitle("Framing")
    }
}

private struct AudioToolsView: View {
    @Bindable var store: CameraStore
    var body: some View {
        Form {
            Section {
                if !store.microphonePermission {
                    Button("Allow microphone access") { store.requestAudioAccess() }
                }
                Picker("Microphone", selection: $store.selectedMicrophone) {
                    Text("Automatic").tag(String?.none)
                    ForEach(store.microphoneOptions) { Text($0.name).tag(Optional($0.id)) }
                }
                .disabled(store.isRecording || !store.microphonePermission)
            } footer: {
                Text("Connect a USB or wireless microphone to include it here. Select the microphone before recording.")
            }
            Section {
                Toggle("Headphone monitoring", isOn: $store.headphoneMonitoring)
                LabeledContent("Output", value: store.headphonesConnected ? "Headphones connected" : "Connect headphones or USB audio")
                ProgressView(value: Double(store.audioLevel))
                    .tint(store.audioClipping ? .red : Theme.gold)
                Text(store.audioClipping ? "CLIPPING · lower the microphone’s input level" : "Input level")
                    .font(.caption)
                    .foregroundStyle(store.audioClipping ? .red : .secondary)
            } footer: {
                Text("Live microphone playback is muted on the phone’s speakers to prevent feedback. Red clipping alerts also appear above the viewfinder’s audio meter.")
            }
        }
        .navigationTitle("Audio")
        .onAppear { store.refreshAudioTools() }
    }
}

struct ReelAssistOverlay: View {
    let safeZones: Bool
    let style: SafeZoneStyle
    let subject: CGRect?
    let lost: Bool
    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height * 9 / 16)
            let height = width * 16 / 9
            let left = (geo.size.width - width) / 2
            let top = (geo.size.height - height) / 2
            if safeZones {
                let rect = style.rect
                Rectangle()
                    .stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(width: width * rect.width, height: height * rect.height)
                    .position(x: left + width * rect.midX, y: top + height * rect.midY)
            }
            if lost {
                Text("Tracking lost · tap subject to resume")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(6)
                    .background(.black.opacity(0.65), in: Capsule())
                    .position(x: geo.size.width / 2, y: top + height * 0.65)
            }
            if let subject, !subject.isNull {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(lost ? Color.orange : Theme.gold, lineWidth: 1.5)
                    .frame(width: width * subject.width, height: height * subject.height)
                    .position(x: left + width * subject.midX, y: top + height * subject.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ShootingPresetsSheet: View {
    @Bindable var store: CameraStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ShootingPresetsView(store: store)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Theme.gold)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

struct ExposureAidsPanel: View {
    @Bindable var store: CameraStore
    var dismiss: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Toggle("Waveform", isOn: $store.showWaveform)
                Toggle("Zebra", isOn: $store.showZebra)
                Toggle("Focus peaking", isOn: $store.showPeaking)
                Toggle("False color", isOn: $store.showFalseColor)
                if store.mode == .video, store.dualShot {
                    Divider().padding(.vertical, 6)
                    Toggle("Track reel subject", isOn: $store.subjectTracking)
                    Toggle("Reel safe zones", isOn: $store.framingOptions.safeZones)
                }
                Divider().padding(.vertical, 6)
                if store.focusPullRunning {
                    action("Stop focus pull", icon: "stop.circle") { store.cancelFocusPull(); dismiss() }
                } else if store.focusStart != nil, store.focusEnd != nil, store.caps.supportsManualFocus {
                    action("Focus start → end", icon: "arrow.right") { store.runFocusPull(); dismiss() }
                    action("Focus end → start", icon: "arrow.left") { store.runFocusPull(reverse: true); dismiss() }
                }
                action("Shooting tools…", icon: "camera.badge.ellipsis") {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        store.showShootingTools = true
                    }
                }
                action("Hide all controls", icon: "eye.slash") { dismiss(); store.cleanFeed = true }
            }
            .toggleStyle(.switch)
            .tint(Theme.gold)
            .font(.subheadline)
            .padding(16)
        }
        .frame(width: 290, height: store.mode == .video && store.dualShot ? 390 : 310)
    }
    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
