import SwiftUI

struct SelectionActionBar: View {
    let selectedCount: Int
    var onMove: (() -> Void)? = nil
    var leadingSystemImage = "folder"
    var leadingLabel = "Move"
    var itemName = "Item"
    var deleteSuffix = ""
    var deleteMessage = "These items will be moved to Recently Deleted."
    var totalCount = 0
    var actsOnAllWhenEmpty = false
    var onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private func plural(_ count: Int) -> String { "\(itemName)\(count == 1 ? "" : "s")" }

    private var isAll: Bool { actsOnAllWhenEmpty && selectedCount == 0 && totalCount > 0 }
    private var effectiveCount: Int { isAll ? totalCount : selectedCount }

    private var countText: String {
        if isAll { return "All \(totalCount) \(plural(totalCount))" }
        return selectedCount == 0 ? "Select \(itemName)s" : "\(selectedCount) \(plural(selectedCount)) Selected"
    }

    private var dialogTitle: String {
        let noun = plural(effectiveCount).lowercased()
        return isAll ? "Delete all \(effectiveCount) \(noun)\(deleteSuffix)?" : "Delete \(effectiveCount) \(noun)\(deleteSuffix)?"
    }

    private var dialogButton: String {
        isAll ? "Delete All \(effectiveCount) \(plural(effectiveCount))\(deleteSuffix)" : "Delete \(effectiveCount) \(plural(effectiveCount))\(deleteSuffix)"
    }

    var body: some View {
        ZStack {
            Text(countText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            GlassEffectContainer(spacing: 20) {
                HStack {
                    if let onMove {
                        circleButton(systemImage: leadingSystemImage, tint: .primary, label: isAll ? "\(leadingLabel) All" : leadingLabel, action: onMove)
                    }
                    Spacer()
                    circleButton(systemImage: "trash", tint: .red, label: isAll ? "Delete All" : "Delete") { showDeleteConfirm = true }
                        .confirmationDialog(
                            dialogTitle,
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible
                        ) {
                            Button(dialogButton, role: .destructive, action: onDelete)
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(deleteMessage)
                        }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .padding(.top, 6)
        .excludesSelectionTouches()
    }

    private func circleButton(systemImage: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(effectiveCount == 0)
        .opacity(effectiveCount == 0 ? 0.4 : 1)
        .accessibilityLabel(label)
    }
}

#Preview {
    VStack {
        Spacer()
        SelectionActionBar(selectedCount: 9, onMove: {}, onDelete: {})
    }
}
