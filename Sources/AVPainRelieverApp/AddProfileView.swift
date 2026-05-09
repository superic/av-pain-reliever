import SwiftUI
import AppKit
import AVPainReliever

struct AddProfileView: View {
    @ObservedObject var viewModel: AddProfileViewModel
    /// Called when the user wants to dismiss the window — either by
    /// hitting Cancel or after a successful save. AppKit wiring lives
    /// in AppDelegate; this view stays AppKit-free.
    let dismiss: () -> Void

    /// Drives the icon-picker popover anchored to the icon button.
    @State private var showIconPicker = false

    /// Programmatic focus on the name field. SwiftUI's Window scene
    /// keeps the same NSWindow across open/dismiss cycles, and the
    /// macOS first-responder is preserved across the `.id`-driven
    /// view rebuild — so the second-and-later wizard opens land
    /// without any field focused. Pushing focus on `.onAppear` makes
    /// every open feel like the first.
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                                .focused($nameFieldFocused)
                                .frame(maxWidth: .infinity)
                            // Tappable icon preview — defaults to the
                            // slug-driven auto-pick, but clicking opens
                            // a popover with the curated catalog so
                            // users can override. Selecting "Auto" in
                            // the popover clears the override and
                            // returns to the slug-driven default.
                            Button {
                                showIconPicker = true
                            } label: {
                                Image(systemName: ProfileIcon.effectiveSymbol(
                                    for: viewModel.previewSlug,
                                    override: viewModel.icon
                                ))
                                    .font(.title2)
                                    .foregroundStyle(.primary)
                                    .frame(width: 32, height: 24)
                                    .contentShape(Rectangle())
                                    .animation(.easeInOut(duration: 0.18), value: viewModel.previewSlug)
                                    .animation(.easeInOut(duration: 0.18), value: viewModel.icon)
                            }
                            .buttonStyle(.plain)
                            .help("Click to pick a custom icon for this profile")
                            .popover(isPresented: $showIconPicker, arrowEdge: .top) {
                                IconPickerView(
                                    selection: $viewModel.icon,
                                    slug: viewModel.previewSlug,
                                    onPick: { showIconPicker = false }
                                )
                            }
                        }
                        // Hint defaults to brief instructions; switches
                        // to a quiet preview the moment a name is being
                        // typed so the user sees how it'll appear in
                        // the menu bar. When the name was auto-filled
                        // from a recognised dock signature (e.g.
                        // CalDigit → "Home Office"), prefix the hint
                        // with "Suggested." so the auto-fill behavior
                        // is discoverable rather than feeling like the
                        // wizard read the user's mind.
                        if !viewModel.prettyPreview.isEmpty {
                            namePreviewCaption
                        } else {
                            Text("Pick anything human — letters, spaces, punctuation are fine.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    sectionHeader("Name", symbol: Theme.Symbol.nameSection)
                }

                Section {
                    devicesList
                    // Helper text rendered as the final section row,
                    // not in the `footer:` slot — Form(.grouped)
                    // forces footer content into the trailing
                    // labels-column layout, which makes a multi-line
                    // paragraph render as a narrow right-aligned
                    // strip even with `.frame(maxWidth: .infinity)`.
                    // As a row inside the section body it spans the
                    // section's full content width naturally.
                    fingerprintHint
                } header: {
                    HStack {
                        sectionHeader("USB fingerprint", symbol: Theme.Symbol.usbSection)
                        Spacer()
                        Button(action: viewModel.refresh) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Rescan attached USB devices")
                    }
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
                    // See USB fingerprint section above for why this
                    // helper text lives in the section body rather
                    // than the `footer:` slot.
                    cameraSectionHelperText
                } header: {
                    sectionHeader("Camera", symbol: Theme.Symbol.cameraSection)
                }
            }
            .groupedFormChrome()

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
                // Error banner sits OUTSIDE the Form, so give it the
                // same horizontal margin from the window edge that
                // the buttons row gets — keeps it visually parallel
                // to the action buttons rather than touching edges.
                .padding(.horizontal, 20)
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(action: { viewModel.save() }) {
                    HStack(spacing: 6) {
                        if viewModel.didSave {
                            // Custom-coloured success state — keep the
                            // explicit Image so we can tint just the
                            // checkmark, which Label can't do cleanly.
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
                .disabled(!viewModel.canSave)
                .keyboardShortcut(.defaultAction)
                .animation(.easeInOut(duration: 0.18), value: viewModel.didSave)
            }
            // Buttons row sits OUTSIDE the Form, so give it explicit
            // horizontal margin so Cancel / Save don't touch the
            // window edges.
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        // No outer horizontal padding on the VStack — the Form fills
        // the window edge-to-edge (with .groupedFormChrome's 8pt
        // breathing room baked in), exactly matching how a Settings
        // tab renders. The error banner and buttons row carry their
        // own per-element horizontal padding above so they don't
        // touch the window edges.
        .padding(.top, 8)
        // Fixed dialog size — pairs with the dialog chrome (no
        // resize/minimize/zoom) configured at the window scene. The
        // Form itself scrolls internally if the device list overflows
        // on a fingerprint-heavy location. Width matches the Settings
        // window so the wizard reads as the same family.
        .frame(width: 480, height: 600)
        // Window scene's static title is "Add Profile"; override it
        // dynamically so the title bar tracks Add vs Edit mode.
        .navigationTitle(viewModel.editingExisting ? "Edit Profile" : "Add Profile")
        .centeredOnScreen()
        .onAppear {
            // Defer one runloop tick so the TextField's underlying
            // NSResponder exists by the time we ask for focus —
            // setting `nameFieldFocused = true` synchronously inside
            // `.onAppear` no-ops on macOS 14 because the field's
            // first-responder isn't wired up yet at that point.
            DispatchQueue.main.async {
                nameFieldFocused = true
            }
        }
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
            isPresented: .isPresent($viewModel.pendingCollision),
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

    // MARK: - Subviews

    /// Section-header label shared by every Form section. Keeps
    /// title + section icon consistent across the wizard.
    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
    }

    /// Caption under the Name field that previews the slug-cased
    /// version. When the name was auto-filled from a recognised
    /// dock signature (e.g. CalDigit → "Home Office"), prefix with
    /// a bolded "Suggested." so the user knows the wizard guessed
    /// rather than thinking the field magically populated itself.
    /// The flag clears the moment the user edits the field, so any
    /// human edit drops the prefix.
    @ViewBuilder
    private var namePreviewCaption: some View {
        let preview = Text("Will appear as “\(viewModel.prettyPreview)”")
        if viewModel.nameWasAutoSuggested {
            (Text("Suggested. ").fontWeight(.medium) + preview)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            preview
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Section-body row that explains the fingerprint state. Two
    /// modes:
    ///
    /// - When at least one device is ticked: standard "uncheck the
    ///   peripherals that aren't unique" caption.
    /// - When zero devices are ticked: "implicit fallback" hint with
    ///   an info glyph, signaling that this profile will match any
    ///   USB state at specificity 0. That's the right setup for a
    ///   "laptop, undocked" fallback, but it's a misconfiguration if
    ///   the user meant to capture a docked location and accidentally
    ///   unticked everything. The hint makes the semantic
    ///   discoverable so a user doesn't ship a fingerprint they
    ///   didn't intend.
    @ViewBuilder
    private var fingerprintHint: some View {
        if viewModel.willMatchAnywhere {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.tint)
                (Text("Fallback profile. ").bold()
                    + Text("With no devices ticked, this profile matches whenever no other profile does — useful for a laptop-undocked default. Tick devices above to make it specific to a location."))
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Important hardware (mics, cameras, capture cards, audio interfaces) is pre-selected. Tick anything else that uniquely identifies this location. The profile matches when every ticked device is attached.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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
                                    StatusPill(text: "Not connected", tint: Theme.Color.warn)
                                } else if DevicePortability
                                    .portabilityCategory(deviceName: entry.name) != nil {
                                    // Muted gray "Travels with you"
                                    // pill on portable peripherals
                                    // (keyboards, mice, phones,
                                    // AirPods, watches, headphones).
                                    // These are auto-unticked by the
                                    // view model — the pill is
                                    // informational, explaining why
                                    // the row is shown unticked. Tone
                                    // is descriptive, not directive.
                                    StatusPill(text: "Travels with you", tint: .gray)
                                } else if let category = DevicePortability
                                    .importantCategory(deviceName: entry.name) {
                                    // Green "Important" pill on the
                                    // headline hardware that's most
                                    // likely defining this location —
                                    // dedicated mics, cameras, capture
                                    // cards, audio interfaces.
                                    // Auto-ticked by the view model;
                                    // pill confirms the auto-selection
                                    // and explains why. Mutually
                                    // exclusive with "Travels with you"
                                    // by classifier construction
                                    // (their keywords don't overlap).
                                    StatusPill(text: "Important: \(category)", tint: Theme.Color.success)
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

    /// Helper caption under the Camera picker. Two modes:
    ///
    /// - Virtual camera off: legacy V1 messaging — picking a camera
    ///   here sets macOS's preferred camera, but Zoom/Slack/Teams
    ///   maintain their own selection.
    /// - Virtual camera on: the picker's value names the *source*
    ///   the virtual camera will route. Zoom/Slack/Teams should
    ///   point at "AV Pain Reliever" once and inherit profile
    ///   switches automatically — that's the whole point of the
    ///   virtual camera being on.
    @ViewBuilder
    private var cameraSectionHelperText: some View {
        if viewModel.virtualCameraEnabled {
            Text("Virtual camera will use this as its source. Set Zoom, Slack, and Teams to “AV Pain Reliever” once — they'll follow your profile automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Sets macOS's preferred camera. Apps with their own camera picker (Zoom, Slack, Teams) won't follow this — configure those once per location and they'll remember.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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
