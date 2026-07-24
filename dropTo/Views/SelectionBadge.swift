//
//  SelectionBadge.swift
//  dropTo
//
//  A consistent, clearly-readable "is this selected?" indicator, reused
//  anywhere the app has a multi-select grid (albums, photos, deleted
//  items). Selected = filled blue circle + checkmark. Unselected = a
//  plain circle outline with a solid white backing, so it stays visible
//  no matter how bright or dark the thumbnail underneath is.
//

import SwiftUI

struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
            Circle()
                .strokeBorder(isSelected ? Color.clear : Color.black.opacity(0.25), lineWidth: 1.5)
            if isSelected {
                Circle()
                    .fill(Color.blue)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .padding(8)
    }
}

/// Applies the standard "dim what's NOT selected, ring what IS" look
/// used across every select-mode grid in the app.
struct SelectionOverlay: ViewModifier {
    let isSelecting: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                (isSelecting && !isSelected) ? Color.black.opacity(0.35) : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .bottomTrailing) {
                if isSelecting {
                    SelectionBadge(isSelected: isSelected)
                }
            }
    }
}

extension View {
    func selectionOverlay(isSelecting: Bool, isSelected: Bool) -> some View {
        modifier(SelectionOverlay(isSelecting: isSelecting, isSelected: isSelected))
    }
}
