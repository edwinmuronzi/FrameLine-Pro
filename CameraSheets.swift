import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @Bindable var store: CameraStore
    @Binding var importLUT: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Save Options") {
                    Picker("Save Target", selection: $store.saveTarget) {
                        ForEach(SaveTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(store.saveTarget.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Format & Profile") {
                    Picker("Photo Format", selection: $store.photoFormat) {
                        ForEach(PhotoFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }

                    Picker("Log Profile", selection: $store.logProfile) {
                        ForEach(LogProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                }

                Section("Color & Look (LUT)") {
                    Button {
                        importLUT = true
                    } label: {
                        Label("Import 3D .cube LUT", systemImage: "doc.badge.plus")
                    }

                    if let lut = store.activeLUT {
                        HStack {
                            Text("Active LUT")
                            Spacer()
                            Text(lut.name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Video Recording") {
                    Toggle("Export Stories (9:16)", isOn: $store.storiesExport)
                    Toggle("Dual Camera Recording", isOn: $store.dualActive)
                }

                Section("Hardware Info") {
                    HStack {
                        Text("Camera Hardware")
                        Spacer()
                        Text(store.caps.hasCamera ? "Available" : "Simulated / Demo")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("ISO Range")
                        Spacer()
                        Text("\(Int(store.caps.minISO)) - \(Int(store.caps.maxISO))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FnPanelSheet: View {
    @Bindable var store: CameraStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Exposure Controls") {
                    VStack(alignment: .leading) {
                        Text("Exposure Bias: \(store.exposureBias, specifier: "%.1f") EV")
                        Slider(value: $store.exposureBias, in: -3.0...3.0, step: 0.5)
                    }

                    VStack(alignment: .leading) {
                        Text("ISO: \(Int(store.iso))")
                        Slider(value: $store.iso, in: Float(store.caps.minISO)...Float(store.caps.maxISO), step: 50)
                    }

                    VStack(alignment: .leading) {
                        Text("Shutter: 1/\(Int(1.0 / max(store.shutterSpeed, 0.0001)))s")
                        Slider(value: $store.shutterSpeed, in: store.caps.minShutter...store.caps.maxShutter)
                    }
                }

                Section("White Balance") {
                    Toggle("Lock White Balance", isOn: $store.wbLocked)

                    if store.wbLocked {
                        VStack(alignment: .leading) {
                            Text("Temperature: \(Int(store.wbTemperature)) K")
                            Slider(value: $store.wbTemperature, in: 2500...9000, step: 100)
                        }
                    }
                }

                Section("Film Look & Grade") {
                    Picker("Look Profile", selection: $store.selectedFilmLookID) {
                        Text("Standard").tag("standard")
                        Text("Monochrome").tag("mono")
                        Text("Vivid").tag("vivid")
                        Text("Warm Vintage").tag("vintage")
                    }
                }
            }
            .navigationTitle("Function Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GallerySheet: View {
    @Bindable var store: CameraStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.galleryItems.isEmpty {
                    ContentUnavailableView(
                        "No Captures Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Photos and videos you capture will appear here.")
                    )
                } else {
                    List {
                        ForEach(store.galleryItems) { item in
                            HStack(spacing: 12) {
                                if let image = item.cropImage ?? item.fullImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 60, height: 60)
                                        .overlay {
                                            Image(systemName: item.movieURL != nil ? "video.fill" : "photo")
                                                .foregroundStyle(.secondary)
                                        }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.detail)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(item.date.formatted(date: .numeric, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { indexSet in
                            store.galleryItems.remove(atOffsets: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
