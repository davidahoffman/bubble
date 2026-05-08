import SwiftUI

struct SidebarView: View {
    var store: DocumentStore
    @State private var hoveredID: UUID?
    @State private var editingID: UUID?
    @State private var editName = ""
    @State private var draggingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.documents) { doc in
                        SidebarTab(
                            name: doc.displayName,
                            isActive: doc.id == store.activeDocumentID,
                            isDirty: doc.isDirty,
                            isHovered: hoveredID == doc.id,
                            isEditing: editingID == doc.id,
                            editName: editingID == doc.id ? $editName : .constant(""),
                            onSelect: { store.activeDocumentID = doc.id },
                            onClose: { withAnimation(.easeInOut(duration: 0.15)) { store.closeDocument(doc.id) } },
                            onDoubleClick: {
                                editName = doc.displayName
                                editingID = doc.id
                            },
                            onRenameCommit: {
                                let trimmed = editName.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    store.renameDocument(doc.id, to: trimmed)
                                }
                                editingID = nil
                            },
                            onRenameCancel: {
                                editingID = nil
                            }
                        )
                        .onHover { over in hoveredID = over ? doc.id : nil }
                        .opacity(draggingID == doc.id ? 0.4 : 1)
                        .onDrag {
                            draggingID = doc.id
                            return NSItemProvider(object: doc.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabDropDelegate(
                            targetID: doc.id,
                            store: store,
                            draggingID: $draggingID
                        ))
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .background(.regularMaterial)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          ["md", "markdown", "txt"].contains(url.pathExtension.lowercased())
                    else { return }
                    DispatchQueue.main.async { store.openURL(url) }
                }
            }
            return true
        }
    }
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let targetID: UUID
    let store: DocumentStore
    @Binding var draggingID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragID = draggingID, dragID != targetID,
              let from = store.documents.firstIndex(where: { $0.id == dragID }),
              let to = store.documents.firstIndex(where: { $0.id == targetID })
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            store.documents.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Tab

struct SidebarTab: View {
    let name: String
    let isActive: Bool
    let isDirty: Bool
    let isHovered: Bool
    let isEditing: Bool
    @Binding var editName: String
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDoubleClick: () -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary.opacity(isDirty ? 0.6 : 0))
                .frame(width: 5, height: 5)

            if isEditing {
                TextField("Name", text: $editName, onCommit: onRenameCommit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($fieldFocused)
                    .onExitCommand(perform: onRenameCancel)
                    .onAppear { fieldFocused = true }
            } else {
                Text(name)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .onTapGesture(count: 2, perform: onDoubleClick)
                    .onTapGesture(count: 1, perform: onSelect)
            }

            Spacer()
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .opacity(isHovered && !isEditing ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.primary.opacity(0.07) : Color.clear)
        )
    }
}
