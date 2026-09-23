//
//  WelcomeOverlay.swift
//  Dual
//
//  First-run pitch, shown once until the user dismisses it.
//

import SwiftUI

struct WelcomeOverlay: View {
    var palette: DualPalette
    var onDismiss: () -> Void

    private struct Step {
        var symbol: String
        var titleKey: String
        var detailKey: String
    }

    private let steps: [Step] = [
        Step(symbol: "arrow.down.doc", titleKey: "welcome.step1.title", detailKey: "welcome.step1.detail"),
        Step(symbol: "tag", titleKey: "welcome.step2.title", detailKey: "welcome.step2.detail"),
        Step(symbol: "arrow.triangle.2.circlepath", titleKey: "welcome.step3.title", detailKey: "welcome.step3.detail")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.9))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "square.on.square")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(palette.canvas)
                )

            Text(localized("welcome.title"))
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.5)
                .padding(.top, 18)

            Text(localized("welcome.subtitle"))
                .font(.system(size: 13))
                .foregroundColor(palette.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(steps, id: \.titleKey) { step in
                    HStack(alignment: .top, spacing: 13) {
                        Circle()
                            .fill(palette.accentSoft)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: step.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(palette.accent)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized(step.titleKey))
                                .font(.system(size: 13, weight: .semibold))

                            Text(localized(step.detailKey))
                                .font(.system(size: 12))
                                .foregroundColor(palette.muted)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 24)

            HStack {
                Spacer()
                Button(localized("welcome.start"), action: onDismiss)
                    .buttonStyle(DualPrimaryButtonStyle(palette: palette))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 26)
        }
        .padding(28)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .shadow(color: palette.floatShadow, radius: 40, x: 0, y: 18)
    }

    private func localized(_ key: String) -> String {
        L10n.string(key)
    }
}
