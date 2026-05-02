import SwiftUI
import AppKit
import AVPainReliever

struct AddProfileView: View {
    @ObservedObject var viewModel: AddProfileViewModel
    /// Called when the user wants to dismiss the window — either by
    /// hitting Cancel or after a successful save. AppKit wiring lives
    /// in AppDelegate; this view stays AppKit-free.
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Form {
                Section("Name") {
                    TextField("e.g. home-office", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                    Text("Letters, numbers, hyphens, or underscores. Pretty-cased automatically (\"home-office\" → \"Home Office\").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    devicesList
                } header: {
                    HStack {
                        Text("USB fingerprint")
                        Spacer()
                        Button("Refresh", action: viewModel.refresh)
                            .controlSize(.small)
                    }
                } footer: {
                    Text("Uncheck peripherals that aren't unique to this location (keyboards, mice, phones). The profile matches when every checked device is attached.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Audio") {
                    audioPicker(
                        title: "Input (microphone)",
                        selection: $viewModel.audioInput,
                        devices: viewModel.inputDevices
                    )
                    audioPicker(
                        title: "Output (speakers)",
                        selection: $viewModel.audioOutput,
                        devices: viewModel.outputDevices
                    )
                }

                Section("OBS scene (optional)") {
                    TextField("Leave blank if you don't use OBS", text: $viewModel.obsScene)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)

            if let error = viewModel.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(action: { viewModel.save() }) {
                    Text(viewModel.isSaving ? "Saving…" : "Save Profile")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 540, idealHeight: 600)
        .onChange(of: viewModel.didSave) { _, saved in
            if saved { dismiss() }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add a Profile")
                .font(.title2.bold())
            Text("Capture the dock you're at right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var devicesList: some View {
        Group {
            if viewModel.attachedDevices.isEmpty {
                Text("No USB devices attached. Plug your dock in, then click Refresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.attachedDevices) { entry in
                    Toggle(isOn: binding(for: entry.device)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name ?? "(unnamed device)")
                                .font(.callout)
                            Text(String(format: "vid=0x%04x  pid=0x%04x", entry.device.vendorID, entry.device.productID))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func audioPicker(title: String, selection: Binding<String?>, devices: [AudioDevice]) -> some View {
        Picker(title, selection: selection) {
            Text("Don't change").tag(String?.none)
            ForEach(devices) { device in
                Text(device.name).tag(String?.some(device.name))
            }
        }
    }

    private func binding(for device: USBDevice) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedDeviceIDs.contains(device) },
            set: { isOn in
                if isOn {
                    viewModel.selectedDeviceIDs.insert(device)
                } else {
                    viewModel.selectedDeviceIDs.remove(device)
                }
            }
        )
    }
}
