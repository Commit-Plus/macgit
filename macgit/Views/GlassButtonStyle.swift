//
//  GlassButtonStyle.swift
//  macgit
//

import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var fontSize: CGFloat = 11

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(tint.opacity(0.18), lineWidth: 0.5)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct GlassProminentButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var fontSize: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
