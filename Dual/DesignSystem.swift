//
//  DesignSystem.swift
//  Dual
//
//  Tokens, controls and motion shared by the whole interface.
//  Values mirror "Dual Main Interface.html", the reference design.
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Palette

/// Every color in the app resolves through here so light and dark stay in step.
struct DualPalette {
    var isDark: Bool

    var canvas: Color { isDark ? Color(nsColor: .windowBackgroundColor) : Color(hex: 0xF7F8FB) }
    var surface: Color { isDark ? Color(nsColor: .controlBackgroundColor) : .white }
    var surfaceSoft: Color { isDark ? Color.white.opacity(0.07) : Color(hex: 0xF2F4F8) }
    var surfaceHover: Color { isDark ? Color.white.opacity(0.05) : Color(hex: 0xF8FAFF) }

    var line: Color { isDark ? Color.white.opacity(0.10) : Color(hex: 0x141923).opacity(0.09) }
    var muted: Color { isDark ? Color.white.opacity(0.58) : Color(hex: 0x747A84) }

    var accent: Color { isDark ? Color(hex: 0x4C86F5) : Color(hex: 0x2866E8) }
    var accentStrong: Color { isDark ? Color(hex: 0x6C9CFF) : Color(hex: 0x174FC5) }
    var accentSoft: Color { isDark ? Color(hex: 0x4C86F5).opacity(0.16) : Color(hex: 0xE9F0FF) }

    var success: Color { isDark ? Color(hex: 0x3FBF86) : Color(hex: 0x23875D) }

    var warningSurface: Color { isDark ? Color.orange.opacity(0.14) : Color(hex: 0xFFF7E8) }
    var warningInk: Color { isDark ? Color.orange.opacity(0.92) : Color(hex: 0x76501B) }

    var toastSurface: Color { isDark ? Color(hex: 0x3A3F48) : Color(hex: 0x24272D) }

    var cardShadow: Color { Color.black.opacity(isDark ? 0.38 : 0.07) }
    var floatShadow: Color { Color.black.opacity(isDark ? 0.5 : 0.14) }

    static let radius: CGFloat = 14
    static let controlRadius: CGFloat = 10
}

private struct DualPaletteKey: EnvironmentKey {
    static let defaultValue = DualPalette(isDark: false)
}

extension EnvironmentValues {
    var dualPalette: DualPalette {
        get { self[DualPaletteKey.self] }
        set { self[DualPaletteKey.self] = newValue }
    }
}

// MARK: - Motion

enum DualMotion {
    /// Critically damped — the default for anything that isn't momentum driven.
    static let standard = Animation.spring(response: 0.34, dampingFraction: 1.0)
    /// Slightly under-damped; only for motion that follows a physical gesture.
    static let playful = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let hover = Animation.easeOut(duration: 0.14)

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : animation
    }
}

// MARK: - Buttons

/// Shared press/hover behaviour: feedback lands on pointer-down, never on release.
/// `isEnabled` is read here rather than in the `ButtonStyle`, where environment
/// updates are not guaranteed to propagate.
private struct DualButtonSurface<Background: View>: View {
    var configuration: ButtonStyleConfiguration
    var foreground: (Bool) -> Color
    var liftsOnHover: Bool
    @ViewBuilder var background: (Bool, Bool) -> Background

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .foregroundColor(foreground(isEnabled))
            .background(background(isHovered, isEnabled))
            // A clear-filled background (DualTextButtonStyle when unhovered) isn't
            // hit-tested on its own, so without this the padding around the label
            // would be dead space instead of part of the button.
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .offset(y: liftsOnHover && isHovered && !configuration.isPressed ? -1 : 0)
            .animation(DualMotion.hover, value: isHovered)
            .animation(DualMotion.hover, value: configuration.isPressed)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if isHovered {
                    isHovered = false
                    NSCursor.pop()
                }
            }
    }
}

struct DualPrimaryButtonStyle: ButtonStyle {
    var palette: DualPalette

    func makeBody(configuration: Configuration) -> some View {
        DualButtonSurface(
            configuration: configuration,
            foreground: { isEnabled in isEnabled ? .white : palette.muted },
            liftsOnHover: true
        ) { isHovered, isEnabled in
            RoundedRectangle(cornerRadius: DualPalette.controlRadius, style: .continuous)
                .fill(isEnabled ? (isHovered ? palette.accentStrong : palette.accent) : palette.surfaceSoft)
                .shadow(
                    color: isEnabled ? palette.accent.opacity(0.22) : .clear,
                    radius: 10,
                    x: 0,
                    y: 5
                )
        }
    }
}

struct DualSecondaryButtonStyle: ButtonStyle {
    var palette: DualPalette

    func makeBody(configuration: Configuration) -> some View {
        DualButtonSurface(
            configuration: configuration,
            foreground: { isEnabled in isEnabled ? .primary : palette.muted },
            liftsOnHover: true
        ) { isHovered, isEnabled in
            RoundedRectangle(cornerRadius: DualPalette.controlRadius, style: .continuous)
                .fill(isEnabled ? (isHovered ? palette.surfaceHover : palette.surface) : palette.surfaceSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: DualPalette.controlRadius, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                )
        }
    }
}

struct DualTextButtonStyle: ButtonStyle {
    var palette: DualPalette

    func makeBody(configuration: Configuration) -> some View {
        DualButtonSurface(
            configuration: configuration,
            foreground: { isEnabled in isEnabled ? palette.accent : palette.muted },
            liftsOnHover: false
        ) { isHovered, _ in
            RoundedRectangle(cornerRadius: DualPalette.controlRadius, style: .continuous)
                .fill(isHovered ? palette.accentSoft : Color.clear)
        }
    }
}

// MARK: - Surfaces

/// The soft card used by the drop zone, the clone list and the sheet.
struct DualCard: ViewModifier {
    var palette: DualPalette
    var radius: CGFloat = DualPalette.radius
    var stroke: Color?
    var strokeWidth: CGFloat = 1
    var shadowRadius: CGFloat = 18
    var shadowY: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke ?? palette.line, lineWidth: strokeWidth)
            )
            .shadow(color: palette.cardShadow, radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    func dualCard(
        _ palette: DualPalette,
        radius: CGFloat = DualPalette.radius,
        stroke: Color? = nil,
        strokeWidth: CGFloat = 1,
        shadowRadius: CGFloat = 18,
        shadowY: CGFloat = 6
    ) -> some View {
        modifier(
            DualCard(
                palette: palette,
                radius: radius,
                stroke: stroke,
                strokeWidth: strokeWidth,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}

// MARK: - Toast

struct DualToast: Equatable, Identifiable {
    let id = UUID()
    var message: String

    static func == (lhs: DualToast, rhs: DualToast) -> Bool { lhs.id == rhs.id }
}

struct DualToastView: View {
    var palette: DualPalette
    var message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.toastSurface)
            )
            .shadow(color: palette.floatShadow, radius: 20, x: 0, y: 10)
            .accessibilityAddTraits(.isStaticText)
    }
}
