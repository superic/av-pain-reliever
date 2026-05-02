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
                        HStack(spacing: 10) {
                            TextField("e.g. Home Office", text: $viewModel.name)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            // Live preview of the SF Symbol the menu
                            // will render for this profile. Picks an
                            // icon from the typed slug (auto-mapping —
                            // V1 doesn't expose a picker). Subtle, but
                            // it surfaces the product feature ("each
                            // location gets its own icon") visually
                            // and tells the user what their slug
                            // matched on.
                            Image(systemName: ProfileIcon.symbol(for: viewModel.previewSlug))
                                .font(.title2)
                                .foregroundStyle(Theme.Color.primary)
                                .frame(width: 32, height: 24)
                                .help("Menu icon for this profile (auto-picked from the name)")
                                .animation(.easeInOut(duration: 0.18), value: viewModel.previewSlug)
                        }
                        // Hint defaults to brief instructions; switches
                        // to a quiet preview the moment a name is being
                        // typed so the user sees how it'll appear in
                        // the menu bar.
                        if !viewModel.prettyPreview.isEmpty {
                            Text("Will appear as “\(viewModel.prettyPreview)”")
                                .font(.caption)
                                .foregroundStyle(Theme.Color.highlight)
                        } else {
                            Text("Pick anything human — letters, spaces, punctuation are fine.")
                                .font(.caption)
                                .foregroundStyle(Theme.Color.chrome)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    sectionHeader("Name", symbol: Theme.Symbol.nameSection)
                }

                Section {
                    devicesList
                } header: {
                    HStack {
                        sectionHeader("USB fingerprint", symbol: Theme.Symbol.usbSection)
                        Spacer()
                        Button("Refresh", action: viewModel.refresh)
                            .controlSize(.small)
                    }
                } footer: {
                    Text("Uncheck peripherals that aren't unique to this location (keyboards, mice, phones). The profile matches when every checked device is attached.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.chrome)
                }

                Section {
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
                } header: {
                    sectionHeader("Audio", symbol: Theme.Symbol.audioSection)
                }

                Section {
                    cameraPicker
                } header: {
                    sectionHeader("Camera", symbol: Theme.Symbol.cameraSection)
                } footer: {
                    Text("Sets macOS's preferred camera. Apps with their own camera picker (Zoom, Slack, Teams) won't follow this — configure those once per location and they'll remember.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.chrome)
                }
            }
            .formStyle(.grouped)

            if let error = viewModel.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Color.error)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Theme.Color.error.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.Color.error.opacity(0.35), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(action: { viewModel.save() }) {
                    HStack(spacing: 6) {
                        if viewModel.didSave {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Color.success)
                            Text("Saved")
                        } else if viewModel.isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Saving…")
                        } else {
                            Text(viewModel.editingExisting ? "Update Profile" : "Save Profile")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.didSave ? Theme.Color.success : Theme.Color.primary)
                .disabled(!viewModel.canSave)
                .keyboardShortcut(.defaultAction)
                .animation(.easeInOut(duration: 0.18), value: viewModel.didSave)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 540, idealHeight: 600)
        .onChange(of: viewModel.didSave) { _, saved in
            // Brief save-success window (~0.45 s) so the green check
            // and "Saved" affordance read as a beat of feedback rather
            // than disappearing instantly.
            if saved {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    dismiss()
                }
            }
        }
        .alert(
            "Profile already exists",
            isPresented: collisionPresented,
            presenting: viewModel.pendingCollision
        ) { collision in
            Button("Update “\(collision.existingPrettyName)”") {
                viewModel.confirmReplace()
            }
            Button("Save as “\(collision.newPrettyName)”") {
                viewModel.confirmSaveAsNew()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelCollision()
            }
        } message: { collision in
            Text("There's already a profile called “\(collision.existingPrettyName)”. Did you mean to update it with the devices and audio you've selected, or is this a different location?")
        }
    }

    /// Glue between SwiftUI's `isPresented` Binding API and our
    /// `Identifiable?` collision state — bound to true whenever a
    /// pending collision exists; setting it false clears the state.
    private var collisionPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingCollision != nil },
            set: { presented in
                if !presented { viewModel.cancelCollision() }
            }
        )
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: Theme.Symbol.appIcon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Color.primary)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.editingExisting ? "Edit Profile" : "Add a Profile")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Color.primary)
                Text(viewModel.editingExisting
                     ? "Tweak how this location switches your audio + camera."
                     : "Capture the dock you're at right now.")
                    .font(.callout)
                    .foregroundStyle(Theme.Color.highlight)
            }
            Spacer()
        }
    }

    /// Section-header label shared by every Form section. Keeps
    /// title + section icon consistent across the wizard.
    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Color.primary)
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
                    let isDisconnected = viewModel.disconnectedDeviceIDs.contains(entry.device)
                    Toggle(isOn: binding(for: entry.device)) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(entry.displayName)
                                    .font(.callout)
                                    .foregroundStyle(isDisconnected ? .secondary : .primary)
                                if isDisconnected {
                                    // Saved-but-not-attached devices
                                    // stay in the form so the user
                                    // can see what their profile
                                    // actually fingerprints, even
                                    // when they're away from that
                                    // location. Yellow pill makes
                                    // the unavailable state obvious.
                                    pill(text: "Not connected", tint: Theme.Color.warn)
                                } else if let category = DevicePortability
                                    .portabilityCategory(deviceName: entry.name) {
                                    // Yellow "Suggested: untick" pill so
                                    // the user immediately spots the
                                    // travelling peripherals (keyboards,
                                    // mice, phones) that shouldn't go in
                                    // a location fingerprint. Hint, not
                                    // an instruction — the user is free
                                    // to keep them ticked.
                                    pill(text: "Suggested: untick (\(category))", tint: Theme.Color.warn)
                                }
                            }
                            Text(idLine(for: entry.device))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Camera picker — mirrors `audioPicker`'s treatment of saved-
    /// but-currently-unavailable values. Keeps a synthesized "(not
    /// connected)" entry so a Home Office profile's external camera
    /// stays visible when the user's editing from the laptop café.
    private var cameraPicker: some View {
        let saved = $viewModel.camera.wrappedValue
        let savedAvailable = saved.map { name in
            viewModel.cameras.contains(where: { $0.name == name })
        } ?? true
        return Picker("Camera", selection: $viewModel.camera) {
            Text("Don't change").tag(String?.none)
            if let saved, !savedAvailable {
                Text("\(saved)  (not connected)")
                    .tag(String?.some(saved))
            }
            ForEach(viewModel.cameras) { cam in
                Text(cam.name).tag(String?.some(cam.name))
            }
        }
    }

    private func audioPicker(title: String, selection: Binding<String?>, devices: [AudioDevice]) -> some View {
        // If the saved value isn't in the live device list (the user
        // is editing the profile while away from this location),
        // synthesize an entry so the picker still displays the saved
        // choice and the binding stays stable. The "(not connected)"
        // suffix tells the user nothing's wrong — the device just
        // isn't here right now.
        let saved = selection.wrappedValue
        let savedAvailable = saved.map { name in
            devices.contains(where: { $0.name == name })
        } ?? true
        return Picker(title, selection: selection) {
            Text("Don't change").tag(String?.none)
            if let saved, !savedAvailable {
                Text("\(saved)  (not connected)")
                    .tag(String?.some(saved))
            }
            ForEach(devices) { device in
                Text(device.name).tag(String?.some(device.name))
            }
        }
    }

    /// One-stop pill builder used by both the "Not connected" badge
    /// and the "Suggested: untick" hint. Single source of truth for
    /// the wizard's small status pills.
    private func pill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.85), in: Capsule())
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
