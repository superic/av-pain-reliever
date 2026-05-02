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
                Section {
                    // Wrapping the TextField in a left-aligned VStack
                    // overrides Form(.grouped)'s default label/value
                    // pair layout (which renders the field's title
                    // arg as a left label and pushes the input right).
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("e.g. home-office", text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        if let hint = viewModel.nameValidationHint {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("Letters, numbers, hyphens, or underscores. Pretty-cased automatically (\"home-office\" → \"Home Office\").")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Name")
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
                            Text(entry.displayName)
                                .font(.callout)
                            Text(idLine(for: entry.device))
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

    /// Caption line under each device row. Shows vid/pid and the
    /// serial number when present — both are useful for the user to
    /// verify what's being captured (especially when two of the same
    /// model exist at different locations and the serial is what
    /// disambiguates them).
    private func idLine(for device: USBDevice) -> String {
        var parts = [String(format: "vid=0x%04x  pid=0x%04x", device.vendorID, device.productID)]
        if let serial = device.serialNumber, !serial.isEmpty {
            parts.append("serial \(serial)")
        }
        return parts.joined(separator: "  •  ")
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
