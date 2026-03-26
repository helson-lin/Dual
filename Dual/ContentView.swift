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
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.toolbar = nil
            window.standardWindowButton(.zoomButton)?.isHidden = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.toolbar = nil
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

private struct BottomActionSurfaceStyle: ViewModifier {
    let fill: Color
    let stroke: Color

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

struct ContentView: View {
    private struct CloneRequest {
        let sourceAppPath: String
        let cloneName: String
        let bundleIdentifier: String
        let destinationDirectory: String
        let clearDataBeforeClone: Bool
    }

    private struct SuggestedApp: Identifiable {
        let id: String
        let name: String
        let path: String
        let icon: NSImage
    }

    @State private var sourceAppPath = ""
    @State private var cloneName = ""
    @State private var bundleIdentifier = ""
    @State private var destinationDirectory = "/Applications"
    @State private var clearDataBeforeClone = true
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
    @State private var iconScale: CGFloat = 1.0
    @State private var cloneSuccess = false
    @State private var isButtonHovered = false
    @State private var isButtonPressed = false
    @State private var progressPhase: CGFloat = 0.0
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var panelBackground: Color {
        isDark ? Color(white: 0.13).opacity(0.88) : Color.white.opacity(0.7)
    }
    private var panelStroke: Color {
        isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }
    private var cardBackground: Color {
        isDark ? Color(white: 0.22).opacity(0.7) : Color.white.opacity(0.5)
    }
    private var cardStroke: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.42)
    }
    private var inputBackground: Color {
        isDark ? Color(white: 0.18) : Color(red: 0.96, green: 0.965, blue: 0.975)
    }
    private var inputStroke: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    private var secondaryButtonText: Color {
        isDark ? Color(white: 0.82) : Color(red: 0.2, green: 0.23, blue: 0.28)
    }
    private var bottomGradientColors: [Color] {
        isDark
            ? [Color.black.opacity(0.0), Color.black.opacity(0.06), Color.black.opacity(0.12)]
            : [Color.white.opacity(0.0), Color.white.opacity(0.1), Color.white.opacity(0.18)]
    }
    private var bottomDividerColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.22)
    }

    private var primaryActionTitle: String {
        if isProcessing {
            return localized("common.processing")
        }
        if cloneSuccess {
            return localized("common.openNow")
        }
        return localized("common.clone")
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color(red: 0.86, green: 0.91, blue: 0.98).opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topToolbar

                GeometryReader { _ in
                    HStack(spacing: 0) {
                        dropArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        rightPanel
                            .frame(width: 320)
                            .frame(maxHeight: .infinity)
                    }
                }
            }

        }
        .frame(minWidth: 660, minHeight: 560)
        .background(WindowConfigurator())
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
        }
    }

    private var topToolbar: some View {
        Color.clear
            .frame(height: 0)
    }

    private var rightPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(panelBackground)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(panelStroke, lineWidth: 1)

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionCard {
                            sectionLabel(localized("section.source"))
                            secondaryButton(localized("action.chooseSourceApp")) { pickSourceApp() }
                                .disabled(isProcessing)
                                .focusable(false)
                        }
                        .padding(.top, 12)

                        sectionCard {
                            sectionLabel(localized("section.cloneSettings"))
                            labeledField(localized("field.cloneDisplayName"), text: $cloneName)
                            labeledField(localized("field.bundleIdentifier"), text: $bundleIdentifier)
                        }

                        sectionCard {
                            sectionLabel(localized("section.destination"))
                            labeledField(localized("field.destinationDirectory"), text: $destinationDirectory)
                            secondaryButton(localized("action.chooseDestinationDirectory")) { pickDestinationDirectory() }
                                .disabled(isProcessing)
                            settingToggleRow(localized("setting.clearCloneData"), isOn: $clearDataBeforeClone)
                        }

                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 0)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .clipped()

                VStack(spacing: 10) {
                    if !errorText.isEmpty {
                        bottomActionSurface(
                            fill: Color(red: 1.0, green: 0.96, blue: 0.95).opacity(0.95),
                            stroke: Color(red: 0.91, green: 0.42, blue: 0.34).opacity(0.25)
                        ) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.84, green: 0.34, blue: 0.24))
                                    .padding(.top, 1)

                                Text(errorText)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Color(red: 0.74, green: 0.28, blue: 0.2))
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)
                            }
                        }
                    }

                    bottomActionSurface(fill: Color.white.opacity(0.56), stroke: Color.white.opacity(0)) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "exclamationmark.shield")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.72, green: 0.46, blue: 0.12))
                                .padding(.top, 1)

                            Text(localized("disclaimer.risk"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.62))
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                    }

                    Button {
                        if cloneSuccess, !lastOutputPath.isEmpty {
                            openApp(path: lastOutputPath)
                        } else {
                            runCloneFlow()
                        }
                    } label: {
                        bottomActionSurface(
                            fill: isProcessing
                                ? Color(red: 0.88, green: 0.89, blue: 0.91)
                                : cloneSuccess
                                ? Color(red: 0.18, green: 0.72, blue: 0.42)
                                : isButtonPressed
                                ? Color(red: 0.12, green: 0.32, blue: 0.78)
                                : isButtonHovered
                                ? Color(red: 0.15, green: 0.38, blue: 0.88)
                                : Color(red: 0.2, green: 0.45, blue: 0.95),
                            stroke: isProcessing
                                ? Color(red: 0.82, green: 0.84, blue: 0.86)
                                : cloneSuccess
                                ? Color(red: 0.14, green: 0.62, blue: 0.36)
                                : isButtonHovered
                                ? Color(red: 0.12, green: 0.32, blue: 0.82)
                                : Color(red: 0.16, green: 0.38, blue: 0.88)
                        ) {
                            ZStack {
                                Text(primaryActionTitle)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                HStack(spacing: 8) {
                                    if isProcessing {
                                        ProgressView()
                                            .controlSize(.small)
                                            .scaleEffect(0.8)
                                    } else if cloneSuccess {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .disabled(isProcessing)
                    .keyboardShortcut(.defaultAction)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isProcessing ? Color(red: 0.58, green: 0.6, blue: 0.64) : .white)
                    .shadow(
                        color: isProcessing
                            ? .clear
                            : cloneSuccess
                            ? Color(red: 0.18, green: 0.72, blue: 0.42).opacity(0.3)
                            : isButtonHovered
                            ? Color(red: 0.2, green: 0.45, blue: 0.95).opacity(0.35)
                            : Color(red: 0.2, green: 0.45, blue: 0.95).opacity(0.25),
                        radius: isButtonHovered ? 16 : 12,
                        x: 0,
                        y: isButtonHovered ? 6 : 4
                    )
                    .scaleEffect(isButtonPressed ? 0.98 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isButtonHovered = hovering
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isButtonPressed {
                                    withAnimation(.easeOut(duration: 0.08)) {
                                        isButtonPressed = true
                                    }
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                    isButtonPressed = false
                                }
                            }
                    )
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.3), value: cloneSuccess)
                    .animation(.easeInOut(duration: 0.2), value: isProcessing)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 22)
                .background(
                    LinearGradient(
                        colors: bottomGradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(bottomDividerColor)
                        .frame(height: 1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 0)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
    }

    private func sectionCard<Content: View>(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private func bottomActionSurface<Content: View>(
        fill: Color,
        stroke: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .modifier(BottomActionSurfaceStyle(fill: fill, stroke: stroke))
    }

    private func cardView<Content: View>(shadow: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .shadow(color: shadow ? Color.black.opacity(0.08) : .clear, radius: 18, x: 0, y: 8)
    }

    private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(secondaryButtonText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(inputStroke, lineWidth: 1)
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var dropArea: some View {
        Group {
            if showingLog {
                logPanel
            } else {
                VStack(spacing: 18) {
                    ZStack {
                        if let appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 96, height: 96)
                                .scaleEffect(iconScale)
                                .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(isDropTargeted ? 0.8 : 0.4))
                                .scaleEffect(isDropTargeted ? 1.15 : 1.0)
                                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDropTargeted)
                        }
                    }

                    VStack(spacing: 6) {
                        Text(sourceAppPath.isEmpty ? localized("drop.title.empty") : localized("status.sourceAppSelected"))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.88))
                        Text(sourceAppPath.isEmpty ? localized("drop.subtitle.empty") : localized("drop.subtitle.selected"))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)

                        if sourceAppPath.isEmpty {
                            if !suggestedApps.isEmpty {
                                VStack(spacing: 8) {
                                    Text(localized("drop.quickPick"))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 12)

                                    HStack(spacing: 12) {
                                        ForEach(suggestedApps) { app in
                                            Button {
                                                applySourceApp(url: URL(fileURLWithPath: app.path))
                                            } label: {
                                                VStack(spacing: 5) {
                                                    Image(nsImage: app.icon)
                                                        .resizable()
                                                        .interpolation(.high)
                                                        .scaledToFit()
                                                        .frame(width: 38, height: 38)
                                                    Text(app.name)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                        .frame(width: 60)
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .focusable(false)
                                            .focusEffectDisabled()
                                        }
                                    }
                                }
                            } else {
                                Text(localized("drop.supportsAnyApp"))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(Color.secondary.opacity(0.9))
                                    .padding(.top, 8)
                            }
                        } else {
                            Text(sourceAppPath)
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.92))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                                .frame(maxWidth: 420)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isDropTargeted ? Color(red: 0.52, green: 0.68, blue: 0.95).opacity(0.06) : Color.clear)
                        .padding(12)
                        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color(red: 0.52, green: 0.68, blue: 0.95).opacity(0.9) : Color.clear,
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                        )
                        .padding(12)
                        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
            }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with app info
            HStack(spacing: 10) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(cloneName.isEmpty ? localized("log.title") : cloneName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(localized("log.subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isProcessing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingLog = false
                            errorText = ""
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            // Indeterminate progress bar
            if isProcessing {
                GeometryReader { geo in
                    let barWidth = geo.size.width * 0.3
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.45, blue: 0.95).opacity(0.4),
                                    Color(red: 0.2, green: 0.45, blue: 0.95),
                                    Color(red: 0.2, green: 0.45, blue: 0.95).opacity(0.4)
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
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .onAppear {
                    progressPhase = 0
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        progressPhase = 1.0
                    }
                }
                .onDisappear {
                    progressPhase = 0
                }
            }

            Divider().padding(.horizontal, 20)

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logText.isEmpty ? localized("log.waiting") : logText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .foregroundStyle(Color.primary.opacity(0.65))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .id("logEnd")
                }
                .onChange(of: logText) {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }

            // Status bar
            Divider().padding(.horizontal, 20)
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(localized("log.status.processing"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if cloneSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.18, green: 0.72, blue: 0.42))
                        .font(.system(size: 12))
                    Text(localized("log.status.success"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.18, green: 0.72, blue: 0.42))
                    if !lastOutputPath.isEmpty {
                        Spacer()
                        Button(localized("action.revealInFinder")) {
                            revealInFinder(path: lastOutputPath)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.link)
                    }
                } else if !errorText.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text(errorText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
            FocuslessTextField(text: text)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(height: 32)
                .background(inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(inputStroke, lineWidth: 1)
                )
        }
    }

    private func readOnlyField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.82))
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .font(.system(size: 14.5, weight: .regular, design: .monospaced))
                .background(inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(inputStroke, lineWidth: 1)
                )
                .textSelection(.enabled)
        }
    }

    private func settingToggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.84))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.top, 2)
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

        // Spring bounce on icon appearance
        iconScale = 0.5
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
            iconScale = 1.0
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

    private func resolvedDestinationDirectory(input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "/Applications"
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

        let writableDirectory = resolvedDestinationDirectory(input: request.destinationDirectory)
        if !ensureWritableDirectory(writableDirectory) {
            if isSystemApplicationsDirectory(writableDirectory) {
                appendLog(localized("log.directoryNotWritable", writableDirectory))
                appendLog(localized("log.waitingForAdmin"))
                pendingAdminRequest = CloneRequest(
                    sourceAppPath: request.sourceAppPath,
                    cloneName: request.cloneName,
                    bundleIdentifier: request.bundleIdentifier,
                    destinationDirectory: writableDirectory,
                    clearDataBeforeClone: request.clearDataBeforeClone
                )
                showAdminPrivilegeAlert = true
                return
            }
            errorText = localized("error.destinationNotWritable", writableDirectory)
            return
        }

        runClone(request: CloneRequest(
            sourceAppPath: request.sourceAppPath,
            cloneName: request.cloneName,
            bundleIdentifier: request.bundleIdentifier,
            destinationDirectory: writableDirectory,
            clearDataBeforeClone: request.clearDataBeforeClone
        ), useAdminPrivileges: false)
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
            clearDataBeforeClone: clearDataBeforeClone
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
