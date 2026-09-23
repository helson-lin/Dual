//
//  ContentView.swift
//  Dual
//
//  Created by lin on 2026/3/23.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WindowConfigurator: NSViewRepresentable {
    /// The window is fixed-size and non-resizable, so this is both the
    /// content's `.frame` and the size forced on the `NSWindow`. Forcing it
    /// on every `configure` call overrides AppKit's automatic per-scene
    /// frame autosave, which otherwise restores a stale size from before
    /// the window became fixed-size.
    static let fixedContentSize = CGSize(width: 860, height: 680)

    final class Coordinator: NSObject {
        var observers: [NSObjectProtocol] = []

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configure(window)

            if context.coordinator.observers.isEmpty {
                let center = NotificationCenter.default
                let keyToken = center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { note in
                    guard let window = note.object as? NSWindow else { return }
                    applyFullScreenPolicy(to: window)
                }
                let mainToken = center.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main) { note in
                    guard let window = note.object as? NSWindow else { return }
                    applyFullScreenPolicy(to: window)
                }
                let updateToken = center.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { _ in
                    // SwiftUI can rewrite collectionBehavior at any point in the
                    // scene's life, so heal it instead of setting it once.
                    guard !window.collectionBehavior.contains(.fullScreenNone) else { return }
                    applyFullScreenPolicy(to: window)
                    hideFullScreenMenuItem()
                }
                let resizeToken = center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { note in
                    guard let window = note.object as? NSWindow else { return }
                    enforceFixedSize(on: window)
                }
                context.coordinator.observers = [keyToken, mainToken, updateToken, resizeToken]
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            configure(window)
        }
    }

    private func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        // An empty unified toolbar is what makes AppKit lay the traffic lights out
        // on the unified titlebar line, i.e. the vertical center of `toolbarHeight`.
        // Without it they sit in the 28pt titlebar, well above the toolbar content.
        if window.toolbar == nil {
            let toolbar = NSToolbar()
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
        }
        // Full screen is off, and the window has a single fixed size: nothing
        // to zoom or drag-resize to, so both are disabled outright.
        applyFullScreenPolicy(to: window)
        hideFullScreenMenuItem()
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        if window.contentView?.frame.size != Self.fixedContentSize {
            window.setContentSize(Self.fixedContentSize)
        }
        // Belt and suspenders: macOS can still grow the frame outside of
        // drag-resize (edge tiling, Stage Manager, scripted `set size of
        // window`), which would expose the window's clear background past
        // the fixed-size content. Pinning min/max to the same frame blocks
        // every path, not just the ones gated by `.resizable`.
        window.minSize = window.frame.size
        window.maxSize = window.frame.size
    }

    /// `minSize`/`maxSize` only constrain interactive drag-resizing. Window
    /// tiling (edge-drag, Stage Manager, the Window menu's Move & Resize
    /// commands) and scripted `setFrame` calls set the frame directly and
    /// skip that constraint, which would grow the window past its fixed
    /// content and expose the clear background behind it. Snap back
    /// immediately whenever the frame drifts from the fixed size.
    private func enforceFixedSize(on window: NSWindow) {
        let fixedSize = window.minSize
        guard fixedSize.width > 0, fixedSize.height > 0, window.frame.size != fixedSize else { return }
        var frame = window.frame
        frame.origin.y += frame.size.height - fixedSize.height
        frame.size = fixedSize
        window.setFrame(frame, display: true)
    }

    private func applyFullScreenPolicy(to window: NSWindow) {
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.fullScreenNone)
    }

    /// The window refuses full screen, so AppKit's menu item would just no-op.
    /// Hidden rather than removed: AppKit re-adds the item, and a hidden item
    /// survives that far better than a removed one. Matched by selector, not
    /// title, since the title is localized.
    private func hideFullScreenMenuItem() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
            for item in submenu.items where item.action == #selector(NSWindow.toggleFullScreen(_:)) {
                item.isHidden = true
            }
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
        nsView.state = .active
    }
}

private struct FocuslessTextField: NSViewRepresentable {
    final class NoFocusRingTextField: NSTextField {
        override var focusRingType: NSFocusRingType {
            get { .none }
            set { }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocuslessTextField

        init(parent: FocuslessTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }

    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NoFocusRingTextField()
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.textColor = NSColor.labelColor
        textField.placeholderString = ""
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.delegate = context.coordinator
    }
}


struct ContentView: View {
    private struct CloneRequest {
        let sourceAppPath: String
        let cloneName: String
        let bundleIdentifier: String
        let destinationDirectory: String
        let clearDataBeforeClone: Bool
        let addCloneBadge: Bool
    }

    private struct SuggestedApp: Identifiable {
        let id: String
        let name: String
        let path: String
        let icon: NSImage
    }

    private struct CloneRecord: Codable, Identifiable {
        var id: String { destinationAppPath }
        let sourceAppPath: String
        let destinationAppPath: String
        let cloneName: String
        let bundleIdentifier: String
        let addCloneBadge: Bool
        let updatedAt: Date
    }

    private static let cloneRecordsKey = "dual.cloneRecords"

    /// Clones land in their own folder so they never sit next to the originals.
    /// Created on demand by `ensureWritableDirectory(_:)` if it doesn't exist.
    private static let defaultDestinationDirectory = "/Applications/Cloned"

    @State private var sourceAppPath = ""
    @State private var cloneName = ""
    @State private var bundleIdentifier = ""
    @State private var destinationDirectory = Self.defaultDestinationDirectory
    @State private var clearDataBeforeClone = true
    @State private var addCloneBadge = true
    @State private var showClonePanel = false
    @State private var isProcessing = false
    @State private var logText = ""
    @State private var logQueue: [Character] = []
    @State private var logTypingTask: Task<Void, Never>?
    @State private var showingLog = false
    @State private var errorText = ""
    @State private var isDropTargeted = false
    @State private var appIcon: NSImage?
    @State private var lastOutputPath = ""
    @State private var showAdminPrivilegeAlert = false
    @State private var pendingAdminRequest: CloneRequest?
    @State private var suggestedApps: [SuggestedApp] = []
    @State private var cloneRecords: [CloneRecord] = []
    @State private var cloneSuccess = false
    @State private var progressPhase: CGFloat = 0.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var riskAccepted = false
    @State private var toast: DualToast?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var hoveredRecordID: String?
    @State private var isDropZoneHovered = false
    @State private var hoveredSuggestionID: String?
    @AppStorage("dual.hasSeenWelcome") private var hasSeenWelcome = false

    private var isDark: Bool { colorScheme == .dark }
    private var palette: DualPalette { DualPalette(isDark: isDark) }

    /// Horizontal inset of the scrolling content, matching the design's `clamp(26px, 5vw, 54px)`.
    private static let contentInset: CGFloat = 54

    /// Drives both the SwiftUI toolbar and the stretched titlebar behind it.
    private static let toolbarHeight: CGFloat = 52

    private var primaryActionTitle: String {
        if isProcessing {
            return localized("common.processing")
        }
        if cloneSuccess {
            return localized("common.openNow")
        }
        return localized("action.startClone")
    }

    /// The three states a clone row can be in, shared by the row and "Check updates".
    private enum CloneStatus {
        case sourceMissing
        case needsUpdate
        case upToDate
    }

    private func status(of record: CloneRecord) -> CloneStatus {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: record.sourceAppPath) else { return .sourceMissing }
        guard fileManager.fileExists(atPath: record.destinationAppPath) else { return .upToDate }
        let sourceFingerprint = appVersionFingerprint(for: record.sourceAppPath)
        let cloneFingerprint = appVersionFingerprint(for: record.destinationAppPath)
        return sourceFingerprint == cloneFingerprint ? .upToDate : .needsUpdate
    }

    var body: some View {
        ZStack {
            palette.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topToolbar

                if showingLog {
                    logPanel
                        .padding(24)
                } else {
                    workspace
                }
            }
            .ignoresSafeArea(.container, edges: .top)

            if !hasSeenWelcome {
                WelcomeOverlay(palette: palette) {
                    withAnimation(motion(DualMotion.standard)) {
                        hasSeenWelcome = true
                    }
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                DualToastView(palette: palette, message: toast.message)
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.dualPalette, palette)
        .frame(width: WindowConfigurator.fixedContentSize.width, height: WindowConfigurator.fixedContentSize.height)
        .background(WindowConfigurator())
        .sheet(isPresented: $showClonePanel) {
            cloneSheet.frame(width: 520)
        }
        .alert(localized("admin.alert.title"), isPresented: $showAdminPrivilegeAlert) {
            Button(localized("common.cancel"), role: .cancel) {
                pendingAdminRequest = nil
                appendLog(localized("log.cancelAdmin"))
            }
            Button(localized("common.continueWithAdmin")) {
                continueCloneWithAdminPrivileges()
            }
        } message: {
            Text(localized("admin.alert.message"))
        }
        .onAppear {
            appIcon = nil
            suggestedApps = loadSuggestedApps()
            cloneRecords = loadCloneRecords()
            // Anyone who already has clones has long since read the pitch.
            if !cloneRecords.isEmpty {
                hasSeenWelcome = true
            }
        }
    }

    // MARK: - Toolbar

    private var topToolbar: some View {
        HStack(spacing: 18) {
            // Clears the traffic lights (they end at x ≈ 80 from the window edge)
            // and, with the stack's own 18pt spacing, keeps the design's gap
            // between them and the first label.
            Color.clear
                .frame(width: 58, height: 1)

            Text("Dual")
                .font(.system(size: 14, weight: .bold))
                .tracking(-0.15)
                .lineLimit(1)
                .fixedSize()

            // Rectangle()
            //     .fill(palette.line)
            //     .frame(width: 1, height: 20)

            // Text(localized("toolbar.workspace"))
            //     .font(.system(size: 13, weight: .semibold))
            //     .foregroundColor(palette.muted)
            //     .lineLimit(1)
            //     .fixedSize()

            Spacer(minLength: 12)

            if isProcessing && !showingLog {
                Button {
                    withAnimation(motion(DualMotion.standard)) {
                        showingLog = true
                    }
                } label: {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                        Text(localized("log.status.processing"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(palette.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        Capsule(style: .continuous)
                            .fill(palette.accentSoft)
                    )
                }
                .buttonStyle(.plain)
                .help(localized("log.status.processing"))
            }
        }
        .padding(.horizontal, 22)
        .frame(height: Self.toolbarHeight)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
    }

    // MARK: - Workspace

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            dropZone

            cloneRecordsSection
                .padding(.top, 30)
        }
        .frame(maxWidth: 1080, alignment: .leading)
        .padding(.horizontal, Self.contentInset)
        .padding(.top, 34)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                Text(sourceAppPath.isEmpty ? localized("drop.title.empty") : localized("status.sourceAppSelected"))
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)

                Text(sourceAppPath.isEmpty ? localized("drop.subtitle.empty") : localized("drop.subtitle.selected"))
                    .font(.system(size: 13))
                    .foregroundColor(palette.muted)
                    .lineSpacing(2)
                    .padding(.top, 9)
                    .frame(maxWidth: 500, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 9) {
                    Button(sourceAppPath.isEmpty ? localized("action.chooseSourceApp") : localized("common.continue")) {
                        if sourceAppPath.isEmpty {
                            pickSourceApp()
                        } else {
                            showClonePanel = true
                        }
                    }
                    .buttonStyle(DualPrimaryButtonStyle(palette: palette))
                    .disabled(isProcessing)

                    Button(localized("drop.supportsAnyApp")) {
                        showToast(localized("toast.supportsAnyApp"))
                    }
                    .buttonStyle(DualTextButtonStyle(palette: palette))
                }
                .padding(.top, 20)
            }

            Spacer(minLength: 16)

            appStack
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: DualPalette.radius, style: .continuous)
                .fill(palette.surface)
                .overlay(alignment: .topTrailing) {
                    // The soft halo from the design, clipped by the card itself.
                    Circle()
                        .fill(palette.accent.opacity(0.07))
                        .frame(width: 320, height: 320)
                        .offset(x: 120, y: -160)
                }
                .clipShape(RoundedRectangle(cornerRadius: DualPalette.radius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DualPalette.radius, style: .continuous)
                .stroke(isDropTargeted ? palette.accent : palette.accent.opacity(0.18), lineWidth: isDropTargeted ? 2 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DualPalette.radius, style: .continuous)
                .stroke(palette.accentSoft, lineWidth: isDropTargeted ? 4 : 0)
                .padding(-3)
        )
        .shadow(color: palette.cardShadow, radius: 26, x: 0, y: 9)
        .scaleEffect(isDropTargeted ? 0.995 : 1)
        .animation(motion(DualMotion.standard), value: isDropTargeted)
        .onHover { hovering in
            withAnimation(motion(DualMotion.playful)) {
                isDropZoneHovered = hovering
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
    }

    /// A fan of the three apps on this Mac most likely to be cloned. Each icon is
    /// a shortcut: clicking one picks it as the source app.
    private var appStack: some View {
        let lifted = isDropZoneHovered || isDropTargeted
        let apps = Array(suggestedApps.prefix(3))

        return ZStack {
            if apps.isEmpty {
                genericMark
            } else {
                let hoveredIndex = apps.firstIndex { $0.id == hoveredSuggestionID }
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    suggestionMark(
                        app,
                        index: index,
                        count: apps.count,
                        hoveredIndex: hoveredIndex,
                        lifted: lifted
                    )
                }
            }
        }
        .frame(width: 244, height: 150)
    }

    private static let appMarkSize: CGFloat = 96

    private func suggestionMark(
        _ app: SuggestedApp,
        index: Int,
        count: Int,
        hoveredIndex: Int?,
        lifted: Bool
    ) -> some View {
        // A straight deck: every icon stands upright on the same baseline and the
        // stack recedes to the right. Rotation is deliberately avoided — macOS icons
        // carry their own shape and shadow, and tilting them reads as stickers.
        let size = Self.appMarkSize
        let depth = CGFloat(index)
        let isHovered = hoveredSuggestionID == app.id
        // Icons overlap by less than half, so the center of every icon stays
        // clear of the hit area of the one in front of it.
        let step: CGFloat = lifted ? 64 : 58
        let scale = 1 - depth * 0.11
        // Icons behind the one being reached for slide back to open a gap.
        let yield: CGFloat = hoveredIndex.map { index > $0 ? 9 : 0 } ?? 0
        let centering = -CGFloat(count - 1) * step / 2

        return Button {
            applySourceApp(url: URL(fileURLWithPath: app.path))
        } label: {
            // The hit area is this fixed rectangle. Every hover response lives in
            // the overlay, which is excluded from hit testing — otherwise the icon
            // moves out from under the pointer that just picked it up and the
            // hover state oscillates.
            Color.clear
                .frame(width: size, height: size)
                .overlay(
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .shadow(
                            color: palette.cardShadow,
                            radius: isHovered ? 24 : 16 - depth * 3,
                            x: 0,
                            y: isHovered ? 14 : 9 - depth * 2
                        )
                        .scaleEffect(isHovered ? 1.06 : 1, anchor: .bottom)
                        .offset(x: yield, y: isHovered ? -8 : 0)
                        .animation(motion(DualMotion.standard), value: isHovered)
                        .animation(motion(DualMotion.standard), value: yield)
                        .allowsHitTesting(false)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .help(localized("quickPick.add", app.name))
        // Scaling from the bottom keeps the whole deck on one baseline.
        .scaleEffect(scale, anchor: .bottom)
        .opacity(1 - depth * 0.13)
        .offset(x: centering + depth * step)
        .zIndex(isHovered ? Double(count) + 1 : Double(count - index))
        .onHover { hovering in
            guard !isProcessing else { return }
            hoveredSuggestionID = hovering ? app.id : (hoveredSuggestionID == app.id ? nil : hoveredSuggestionID)
        }
    }

    /// Shown only when this Mac has no third-party app to suggest.
    private var genericMark: some View {
        let size = Self.appMarkSize

        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(palette.accent)
            Text("A²")
                .font(.system(size: size * 0.4, weight: .bold))
                .tracking(-1.8)
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: palette.cardShadow, radius: 18, x: 0, y: 10)
    }

    // MARK: - Clone list

    private var cloneRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text(localized("clones.title"))
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)

                Text(localized("workspace.count", cloneRecords.count))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(palette.muted)

                Spacer(minLength: 8)

                Text(localized("clones.rowHint"))
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)

                Button(localized("clones.import")) {
                    importExistingClone()
                }
                .buttonStyle(DualTextButtonStyle(palette: palette))
                .disabled(isProcessing)
            }
            .padding(.horizontal, 2)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    if cloneRecords.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(palette.muted.opacity(0.7))
                            Text(localized("clones.empty.title"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(localized("clones.empty.subtitle"))
                                .font(.system(size: 11))
                                .foregroundColor(palette.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        ForEach(Array(cloneRecords.enumerated()), id: \.element.id) { index, record in
                            cloneRecordRow(record)
                            if index < cloneRecords.count - 1 {
                                Rectangle()
                                    .fill(palette.line)
                                    .frame(height: 1)
                                    .padding(.leading, 71)
                            }
                        }
                    }
                }
                .background(ScrollerStyle(isDark: isDark))
            }
            .frame(minHeight: 140, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DualPalette.radius, style: .continuous))
            .dualCard(palette, shadowRadius: 14, shadowY: 5)
        }
        .frame(maxHeight: .infinity)
    }

    private func cloneRecordRow(_ record: CloneRecord) -> some View {
        let cloneExists = FileManager.default.fileExists(atPath: record.destinationAppPath)
        let isHovered = hoveredRecordID == record.id

        return HStack(spacing: 13) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: record.destinationAppPath))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.cloneName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(localized("clones.source", URL(fileURLWithPath: record.sourceAppPath).lastPathComponent, record.bundleIdentifier))
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 18)

            Text(appVersion(for: record.destinationAppPath) ?? "—")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(palette.muted)

            cloneRecordStatus(record)
                .frame(minWidth: 62, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 70)
        .background(isHovered && cloneExists ? palette.surfaceHover : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard cloneExists else { return }
            revealInFinder(path: record.destinationAppPath)
        }
        .onHover { hovering in
            hoveredRecordID = hovering ? record.id : (hoveredRecordID == record.id ? nil : hoveredRecordID)
            if hovering && cloneExists {
                NSCursor.pointingHand.push()
            } else if cloneExists {
                NSCursor.pop()
            }
        }
        .animation(DualMotion.hover, value: isHovered)
        .help(cloneExists ? localized("action.revealInFinder") : "")
    }

    @ViewBuilder
    private func cloneRecordStatus(_ record: CloneRecord) -> some View {
        switch status(of: record) {
        case .sourceMissing:
            Text(localized("clones.sourceMissing"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)
        case .needsUpdate:
            Button(localized("clones.update")) {
                updateClone(record)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(palette.accent)
            .disabled(isProcessing)
            .help(localized("clones.update"))
        case .upToDate:
            Text(localized("clones.current"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(palette.success)
        }
    }

    // MARK: - Clone sheet

    private var cloneSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Text(localized("clonePanel.title"))
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.5)

                Spacer(minLength: 8)

                Button {
                    showClonePanel = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(palette.muted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(palette.surfaceSoft))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 12) {
                if let appIcon {
                    HStack(spacing: 12) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: sourceAppPath).deletingPathExtension().lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))
                            Text(sourceAppPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(palette.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Button(localized("common.change")) {
                            pickSourceApp()
                        }
                        .buttonStyle(DualTextButtonStyle(palette: palette))
                        .disabled(isProcessing)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.surfaceSoft)
                    )
                }

                labeledField(localized("field.cloneDisplayName"), text: $cloneName)
                labeledField(localized("field.bundleIdentifier"), text: $bundleIdentifier)
                labeledField(
                    localized("field.destinationDirectory"),
                    text: $destinationDirectory,
                    help: localized("field.destinationDirectory.help"),
                    accessory: localized("action.chooseDestinationDirectory"),
                    accessoryAction: pickDestinationDirectory
                )

                VStack(spacing: 0) {
                    settingToggleRow(
                        localized("setting.addCloneBadge"),
                        detail: localized("setting.addCloneBadge.help"),
                        isOn: $addCloneBadge
                    )
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                    settingToggleRow(
                        localized("setting.clearCloneData"),
                        detail: localized("setting.clearCloneData.help"),
                        isOn: $clearDataBeforeClone
                    )
                }
                .padding(.top, 4)

                riskConsentCard

                if !errorText.isEmpty {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Spacer()

                Button(localized("common.cancel")) {
                    showClonePanel = false
                }
                .buttonStyle(DualSecondaryButtonStyle(palette: palette))
                .disabled(isProcessing)

                Button {
                    runCloneFlow()
                } label: {
                    HStack(spacing: 7) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        }
                        Text(primaryActionTitle)
                    }
                    .frame(minWidth: 96)
                }
                .buttonStyle(DualPrimaryButtonStyle(palette: palette))
                .keyboardShortcut(.defaultAction)
                .disabled(isProcessing || !riskAccepted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .background(palette.canvas)
        .onAppear {
            // Consent is per clone, never remembered across runs.
            riskAccepted = false
        }
    }

    private var riskConsentCard: some View {
        Button {
            withAnimation(motion(DualMotion.standard)) {
                riskAccepted.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: riskAccepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(riskAccepted ? palette.accent : palette.warningInk.opacity(0.55))

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("risk.confirm.title"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(localized("disclaimer.risk"))
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(palette.warningInk)

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: DualPalette.controlRadius, style: .continuous)
                    .fill(palette.warningSurface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityAddTraits(riskAccepted ? .isSelected : [])
    }

    // MARK: - Log panel

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(cloneName.isEmpty ? localized("log.title") : cloneName)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(localized("log.subtitle"))
                        .font(.system(size: 11))
                        .foregroundColor(palette.muted)
                }
                Spacer()
                if isProcessing {
                    Button {
                        withAnimation(motion(DualMotion.standard)) {
                            showingLog = false
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(palette.muted)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(palette.surfaceSoft))
                    }
                    .buttonStyle(.plain)
                    .help(localized("log.status.processing"))
                } else if cloneSuccess {
                    Button(localized("action.backHome")) {
                        returnToHome()
                    }
                    .buttonStyle(DualPrimaryButtonStyle(palette: palette))
                } else {
                    Button {
                        returnToHome()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(palette.muted)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(palette.surfaceSoft))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Indeterminate progress bar
            if isProcessing {
                GeometryReader { geo in
                    let barWidth = geo.size.width * 0.3
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.accent.opacity(0.4),
                                    palette.accent,
                                    palette.accent.opacity(0.4)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: barWidth, height: 2)
                        .offset(x: -barWidth + progressPhase * (geo.size.width + barWidth))
                }
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .onAppear {
                    progressPhase = 0
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        progressPhase = 1.0
                    }
                }
                .onDisappear {
                    progressPhase = 0
                }
            }

            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.horizontal, 20)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(logText.isEmpty ? localized("log.waiting") : logText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .foregroundColor(Color.primary.opacity(0.65))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .id("logEnd")
                        .background(ScrollerStyle(isDark: isDark))
                }
                .onChange(of: logText) { _ in
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }

            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.horizontal, 20)

            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(localized("log.status.processing"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.muted)
                } else if cloneSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.success)
                        .font(.system(size: 11))
                    Text(localized("log.status.success"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.success)
                    if !lastOutputPath.isEmpty {
                        Spacer()
                        Button(localized("action.revealInFinder")) {
                            revealInFinder(path: lastOutputPath)
                        }
                        .buttonStyle(DualTextButtonStyle(palette: palette))
                    }
                } else if !errorText.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                    Text(errorText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dualCard(palette, radius: DualPalette.radius, shadowRadius: 24, shadowY: 10)
    }

    // MARK: - Controls

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        help: String? = nil,
        accessory: String? = nil,
        accessoryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.primary.opacity(0.62))
                    .lineLimit(1)

                if let accessory, let accessoryAction {
                    Spacer(minLength: 4)
                    Button(accessory, action: accessoryAction)
                        .buttonStyle(DualTextButtonStyle(palette: palette))
                        .disabled(isProcessing)
                }
            }

            FocuslessTextField(text: text)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: DualPalette.controlRadius, style: .continuous)
                        .fill(palette.surfaceSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DualPalette.controlRadius, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                )

            if let help {
                Text(help)
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingToggleRow(_ label: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(palette.accent)
        .padding(.vertical, 10)
        .disabled(isProcessing)
    }

    // MARK: - Feedback

    private func motion(_ animation: Animation) -> Animation {
        DualMotion.resolved(animation, reduceMotion: reduceMotion)
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation(motion(DualMotion.standard)) {
            toast = DualToast(message: message)
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(motion(DualMotion.standard)) {
                toast = nil
            }
        }
    }

    private func pickSourceApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            applySourceApp(url: url)
        }
    }

    private func importExistingClone() {
        let clonePanel = NSOpenPanel()
        clonePanel.allowedContentTypes = [.application]
        clonePanel.allowsMultipleSelection = false
        clonePanel.canChooseDirectories = false
        clonePanel.canChooseFiles = true
        clonePanel.prompt = localized("clones.import")
        clonePanel.message = localized("clones.importClone.message")

        guard clonePanel.runModal() == .OK, let cloneURL = clonePanel.url else {
            return
        }

        let clonePlist = applicationInfoPlist(at: cloneURL)
        if
            let sourcePath = clonePlist?["DualSourceApplicationPath"] as? String,
            FileManager.default.fileExists(atPath: sourcePath)
        {
            persistImportedClone(cloneURL: cloneURL, sourceURL: URL(fileURLWithPath: sourcePath))
            return
        }

        let sourcePanel = NSOpenPanel()
        sourcePanel.allowedContentTypes = [.application]
        sourcePanel.allowsMultipleSelection = false
        sourcePanel.canChooseDirectories = false
        sourcePanel.canChooseFiles = true
        sourcePanel.prompt = localized("clones.importSource.prompt")
        sourcePanel.message = localized("clones.importSource.message")

        guard sourcePanel.runModal() == .OK, let sourceURL = sourcePanel.url else {
            return
        }
        persistImportedClone(cloneURL: cloneURL, sourceURL: sourceURL)
    }

    private func persistImportedClone(cloneURL: URL, sourceURL: URL) {
        guard
            cloneURL.standardizedFileURL != sourceURL.standardizedFileURL,
            let plist = applicationInfoPlist(at: cloneURL),
            let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        else {
            errorText = localized("clones.importInvalid")
            return
        }

        let record = CloneRecord(
            sourceAppPath: sourceURL.path,
            destinationAppPath: cloneURL.path,
            cloneName: (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? cloneURL.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleIdentifier,
            addCloneBadge: plist["DualCloneBadgeEnabled"] as? Bool ?? false,
            updatedAt: Date()
        )
        cloneRecords.removeAll { $0.destinationAppPath == record.destinationAppPath }
        cloneRecords.insert(record, at: 0)
        if let data = try? JSONEncoder().encode(cloneRecords) {
            UserDefaults.standard.set(data, forKey: Self.cloneRecordsKey)
        }
        errorText = ""
    }

    private func applicationInfoPlist(at appURL: URL) -> [String: Any]? {
        let url = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private func pickDestinationDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = localized("panel.chooseDestination.prompt")
        panel.message = localized("panel.chooseDestination.message")

        if panel.runModal() == .OK, let url = panel.url {
            destinationDirectory = url.path
            errorText = ""
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isProcessing else { return false }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var fileURL: URL?

            if let data = item as? Data {
                fileURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                fileURL = url
            }

            guard let droppedURL = fileURL else {
                return
            }

            let resolvedURL = droppedURL.standardizedFileURL
            guard resolvedURL.pathExtension.lowercased() == "app" else {
                Task { @MainActor in
                    errorText = localized("error.dropAppFile")
                }
                return
            }

            Task { @MainActor in
                applySourceApp(url: resolvedURL)
                errorText = ""
            }
        }

        return true
    }

    private func applySourceApp(url: URL) {
        showingLog = false
        sourceAppPath = url.path
        let name = url.deletingPathExtension().lastPathComponent
        cloneName = "\(name)2"
        bundleIdentifier = "com.dual.\(name.lowercased())2"
        cloneSuccess = false
        refreshAppIcon(for: url)
        showClonePanel = true
    }

    private func returnToHome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingLog = false
            errorText = ""
            cloneSuccess = false
        }
    }

    private func loadSuggestedApps() -> [SuggestedApp] {
        let searchRoots = [
            "/Applications",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        ]

        let fileManager = FileManager.default
        var candidates: [SuggestedApp] = []
        var seenPaths = Set<String>()

        for root in searchRoots {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in contents where url.pathExtension.lowercased() == "app" {
                let standardizedPath = url.standardizedFileURL.path
                guard !seenPaths.contains(standardizedPath) else { continue }
                guard let bundleID = bundleIdentifier(for: standardizedPath), !bundleID.hasPrefix("com.apple.") else {
                    continue
                }

                seenPaths.insert(standardizedPath)
                candidates.append(
                    SuggestedApp(
                        id: standardizedPath,
                        name: url.deletingPathExtension().lastPathComponent,
                        path: standardizedPath,
                        icon: NSWorkspace.shared.icon(forFile: standardizedPath)
                    )
                )
            }
        }

        return candidates
            .sorted { lhs, rhs in
                let lhsScore = suggestedAppPriority(lhs)
                let rhsScore = suggestedAppPriority(rhs)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(5)
            .map { $0 }
    }

    private func suggestedAppPriority(_ app: SuggestedApp) -> Int {
        let normalizedName = app.name.lowercased()
        let normalizedPath = app.path.lowercased()
        let bundleID = bundleIdentifier(for: app.path)?.lowercased() ?? ""
        let searchable = [normalizedName, normalizedPath, bundleID].joined(separator: " ")

        let chatKeywords = [
            "wechat", "weixin", "微信",
            "qq", "tim", "企业微信", "wecom", "wxwork", "钉钉", "dingtalk",
            "telegram", "discord", "slack", "messenger", "skype"
        ]
        let terminalKeywords = [
            "terminal", "iterm", "warp", "tabby", "alacritty", "kitty", "ghostty"
        ]
        let devToolKeywords = [
            "visual studio code", "vscode", "cursor", "windsurf", "xcode",
            "android studio", "postman", "insomnia", "docker", "orbstack", "fork", "github desktop"
        ]

        if chatKeywords.contains(where: { searchable.contains($0.lowercased()) }) {
            return 300
        }
        if terminalKeywords.contains(where: { searchable.contains($0.lowercased()) }) {
            return 200
        }
        if devToolKeywords.contains(where: { searchable.contains($0.lowercased()) }) {
            return 120
        }
        return 0
    }

    private func refreshAppIcon(for url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            appIcon = nil
            return
        }
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
    }

    private func bundleIdentifier(for appPath: String) -> String? {
        let infoPlist = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlist),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }

        return plist["CFBundleIdentifier"] as? String
    }

    private func appVersion(for appPath: String) -> String? {
        let infoPlist = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlist),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String
    }

    private func appVersionFingerprint(for appPath: String) -> String? {
        let infoPlist = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlist),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        return [
            plist["CFBundleShortVersionString"] as? String,
            plist["CFBundleVersion"] as? String
        ]
        .compactMap { $0 }
        .joined(separator: ":")
    }

    private func loadCloneRecords() -> [CloneRecord] {
        let storedRecords: [CloneRecord]
        if
            let data = UserDefaults.standard.data(forKey: Self.cloneRecordsKey),
            let decoded = try? JSONDecoder().decode([CloneRecord].self, from: data)
        {
            storedRecords = decoded
        } else {
            storedRecords = []
        }

        var recordsByPath = Dictionary(
            uniqueKeysWithValues: discoverCloneRecords().map { ($0.destinationAppPath, $0) }
        )
        for record in storedRecords where FileManager.default.fileExists(atPath: record.destinationAppPath) {
            recordsByPath[record.destinationAppPath] = record
        }
        return recordsByPath.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func discoverCloneRecords() -> [CloneRecord] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
        ]
        let fileManager = FileManager.default
        var records: [CloneRecord] = []

        for root in roots {
            guard let apps = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for app in apps where app.pathExtension.lowercased() == "app" {
                let infoPlist = app.appendingPathComponent("Contents/Info.plist")
                guard
                    let data = try? Data(contentsOf: infoPlist),
                    let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                    let sourceAppPath = plist["DualSourceApplicationPath"] as? String,
                    let bundleIdentifier = plist["CFBundleIdentifier"] as? String
                else {
                    continue
                }

                records.append(CloneRecord(
                    sourceAppPath: sourceAppPath,
                    destinationAppPath: app.path,
                    cloneName: (plist["CFBundleDisplayName"] as? String)
                        ?? (plist["CFBundleName"] as? String)
                        ?? app.deletingPathExtension().lastPathComponent,
                    bundleIdentifier: bundleIdentifier,
                    addCloneBadge: plist["DualCloneBadgeEnabled"] as? Bool ?? false,
                    updatedAt: (try? app.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                ))
            }
        }
        return records
    }

    private func persistCloneRecord(request: CloneRequest, destinationAppPath: String) {
        let record = CloneRecord(
            sourceAppPath: request.sourceAppPath,
            destinationAppPath: destinationAppPath,
            cloneName: request.cloneName,
            bundleIdentifier: request.bundleIdentifier,
            addCloneBadge: request.addCloneBadge,
            updatedAt: Date()
        )
        cloneRecords.removeAll { $0.destinationAppPath == destinationAppPath }
        cloneRecords.insert(record, at: 0)
        if let data = try? JSONEncoder().encode(cloneRecords) {
            UserDefaults.standard.set(data, forKey: Self.cloneRecordsKey)
        }
        // The first successful clone retires the onboarding copy for good.
        hasSeenWelcome = true
    }

    private func resolvedDestinationDirectory(input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Self.defaultDestinationDirectory
        }
        return (trimmed as NSString).expandingTildeInPath
    }

    private func ensureWritableDirectory(_ path: String) -> Bool {
        let manager = FileManager.default
        if !manager.fileExists(atPath: path) {
            do {
                try manager.createDirectory(atPath: path, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }

        return manager.isWritableFile(atPath: path)
    }

    private func runCloneFlow() {
        errorText = ""
        logText = ""
        logQueue.removeAll()
        logTypingTask?.cancel()
        logTypingTask = nil
        cloneSuccess = false

        guard let request = buildCloneRequest() else {
            return
        }

        startCloneRequest(request)
    }

    private func startCloneRequest(_ request: CloneRequest) {
        let writableDirectory = resolvedDestinationDirectory(input: request.destinationDirectory)
        let normalizedRequest = CloneRequest(
            sourceAppPath: request.sourceAppPath,
            cloneName: request.cloneName,
            bundleIdentifier: request.bundleIdentifier,
            destinationDirectory: writableDirectory,
            clearDataBeforeClone: request.clearDataBeforeClone,
            addCloneBadge: request.addCloneBadge
        )

        if !ensureWritableDirectory(writableDirectory) {
            if isSystemApplicationsDirectory(writableDirectory) {
                appendLog(localized("log.directoryNotWritable", writableDirectory))
                appendLog(localized("log.waitingForAdmin"))
                pendingAdminRequest = normalizedRequest
                showAdminPrivilegeAlert = true
                return
            }
            errorText = localized("error.destinationNotWritable", writableDirectory)
            return
        }

        runClone(request: normalizedRequest, useAdminPrivileges: false)
    }

    private func updateClone(_ record: CloneRecord) {
        errorText = ""
        logText = ""
        logQueue.removeAll()
        logTypingTask?.cancel()
        logTypingTask = nil
        cloneSuccess = false
        cloneName = record.cloneName
        sourceAppPath = record.sourceAppPath
        appIcon = NSWorkspace.shared.icon(forFile: record.destinationAppPath)

        startCloneRequest(CloneRequest(
            sourceAppPath: record.sourceAppPath,
            cloneName: record.cloneName,
            bundleIdentifier: record.bundleIdentifier,
            destinationDirectory: URL(fileURLWithPath: record.destinationAppPath).deletingLastPathComponent().path,
            clearDataBeforeClone: false,
            addCloneBadge: record.addCloneBadge
        ))
    }

    private func buildCloneRequest() -> CloneRequest? {
        let trimmedSourcePath = sourceAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourcePath.isEmpty else {
            errorText = localized("error.sourceRequired")
            return nil
        }

        let sourceURL = URL(fileURLWithPath: trimmedSourcePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            errorText = localized("error.sourceMissing", sourceURL.path)
            return nil
        }

        let trimmedCloneName = cloneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCloneName.isEmpty else {
            errorText = localized("error.cloneNameRequired")
            return nil
        }

        let trimmedBundleID = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBundleID.isEmpty else {
            errorText = localized("error.bundleIdRequired")
            return nil
        }

        return CloneRequest(
            sourceAppPath: sourceURL.path,
            cloneName: trimmedCloneName,
            bundleIdentifier: trimmedBundleID,
            destinationDirectory: destinationDirectory,
            clearDataBeforeClone: clearDataBeforeClone,
            addCloneBadge: addCloneBadge
        )
    }

    private func continueCloneWithAdminPrivileges() {
        guard let request = pendingAdminRequest else { return }
        pendingAdminRequest = nil
        appendLog(localized("log.adminConfirmed"))
        runClone(request: request, useAdminPrivileges: true)
    }

    private func runClone(request: CloneRequest, useAdminPrivileges: Bool) {
        let writableDirectory = resolvedDestinationDirectory(input: request.destinationDirectory)
        let destinationURL = URL(fileURLWithPath: writableDirectory)
            .appendingPathComponent("\(request.cloneName).app")

        isProcessing = true
        showClonePanel = false

        withAnimation(.easeInOut(duration: 0.2)) {
            showingLog = true
        }

        Task.detached {
            do {
                try await AppCloner.clone(
                    sourceApp: request.sourceAppPath,
                    destinationApp: destinationURL.path,
                    bundleIdentifier: request.bundleIdentifier,
                    bundleName: request.cloneName,
                    clearDataBeforeClone: request.clearDataBeforeClone,
                    addCloneBadge: request.addCloneBadge,
                    useAdminPrivileges: useAdminPrivileges,
                    localeIdentifier: nil,
                    logger: { line in
                        Task { @MainActor in
                            appendLog(line)
                        }
                    }
                )

                await MainActor.run {
                    appendLog(localized("log.finished", destinationURL.path))
                    lastOutputPath = destinationURL.path
                    persistCloneRecord(request: request, destinationAppPath: destinationURL.path)
                    isProcessing = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        cloneSuccess = true
                    }
                }
            } catch {
                await MainActor.run {
                    errorText = localized("error.executionFailed", friendlyErrorMessage(error, destination: writableDirectory))
                    isProcessing = false
                }
            }
        }
    }

    private func friendlyErrorMessage(_ error: Error, destination: String) -> String {
        let message: String
        if let appClonerError = error as? AppClonerError {
            message = appClonerError.localizedDescription(localeIdentifier: nil)
        } else {
            message = error.localizedDescription
        }

        if message.contains("Operation not permitted") || message.contains("Permission denied") {
            return localized("error.permissionSuggestion", message, destination)
        }
        return message
    }

    private func isSystemApplicationsDirectory(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return normalized == "/Applications" || normalized.hasPrefix("/Applications/")
    }

    private func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func openApp(path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor
    private func appendLog(_ text: String) {
        let chunk = (logText.isEmpty && logQueue.isEmpty) ? text : "\n\(text)"
        logQueue.append(contentsOf: chunk)
        startLogTypingIfNeeded()
    }

    @MainActor
    private func startLogTypingIfNeeded() {
        guard logTypingTask == nil else { return }
        logTypingTask = Task {
            while !Task.isCancelled {
                let batch: String? = await MainActor.run {
                    guard !logQueue.isEmpty else {
                        logTypingTask = nil
                        return nil
                    }
                    let count = min(logQueue.count, 12)
                    let chars = logQueue.prefix(count)
                    logQueue.removeFirst(count)
                    return String(chars)
                }

                guard let batch else { break }
                await MainActor.run {
                    logText.append(contentsOf: batch)
                }

                try? await Task.sleep(nanoseconds: 8_000_000)
            }

            await MainActor.run {
                if logTypingTask != nil {
                    logTypingTask = nil
                }
            }
        }
    }

    private func localized(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, arguments: arguments)
    }
}
