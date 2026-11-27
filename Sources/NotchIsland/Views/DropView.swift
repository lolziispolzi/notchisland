import AppKit
import SwiftUI

/// Drop zone: files wait here until you copy, move, share, AirDrop or drag them out.
struct DropView: View {
    @ObservedObject var vm: NotchViewModel

    private var shelf: ShelfStore { vm.shelf }

    var body: some View {
        if shelf.items.isEmpty {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundColor(.white.opacity(vm.isDropTargeted ? 0.8 : 0.3))
                .overlay(
                    VStack(spacing: 6) {
                        SymbolImage("tray.and.arrow.down.fill")
                            .font(.system(size: 22))
                        Text("Drop files here")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Then copy, move, share or AirDrop them.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        Button("Add Files…") { shelf.chooseFiles() }
                            .buttonStyle(PillButtonStyle())
                            .padding(.top, 2)
                    }
                    .foregroundColor(.white.opacity(0.75))
                )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                toolbar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url, shelf: shelf)
                        }
                    }
                }
                destinations
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(vm.isDropTargeted ? 0.12 : 0.05))
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(ShelfStore.countLabel(shelf.items.count))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            if shelf.isBusy {
                Spinner().controlSize(.mini)
            } else if let message = shelf.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                    .lineLimit(1)
            }
            Spacer()
            IconButton(symbol: "plus", help: "Add files") { shelf.chooseFiles() }
            IconButton(symbol: "doc.on.clipboard", help: "Copy to clipboard") { shelf.copyToClipboard() }
            IconButton(symbol: "dot.radiowaves.left.and.right", help: "AirDrop") { shelf.airDropAll() }
            SharePickerButton(items: shelf.items)
                .frame(width: 18, height: 18)
                .compatHelp("Share")
            IconButton(symbol: "trash", help: "Clear the drop zone") { shelf.clear() }
        }
    }

    private var destinations: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Copy to")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                ForEach(shelf.destinations) { destination in
                    DestinationChip(name: destination.name, symbol: destination.symbol) {
                        shelf.copy(to: destination.url)
                    }
                    .contextMenu {
                        Button("Copy Here") { shelf.copy(to: destination.url) }
                        Button("Move Here") { shelf.copy(to: destination.url, move: true) }
                    }
                }
                DestinationChip(name: "Other…", symbol: "folder.badge.plus") {
                    shelf.chooseFolder(move: false)
                }
                .contextMenu {
                    Button("Copy to Folder…") { shelf.chooseFolder(move: false) }
                    Button("Move to Folder…") { shelf.chooseFolder(move: true) }
                }
            }
        }
        .disabled(shelf.isBusy)
    }
}

private struct ShelfItemView: View {
    let url: URL
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 36, height: 36)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .frame(width: 66)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            if #available(macOS 11, *) {
                Menu("Copy To") {
                    ForEach(shelf.destinations) { destination in
                        Button(destination.name) { shelf.copy([url], to: destination.url) }
                    }
                }
                Menu("Move To") {
                    ForEach(shelf.destinations) { destination in
                        Button(destination.name) { shelf.copy([url], to: destination.url, move: true) }
                    }
                }
            } else {
                // No submenus before macOS 11: list each destination directly.
                ForEach(shelf.destinations) { destination in
                    Button("Copy to \(destination.name)") { shelf.copy([url], to: destination.url) }
                }
                ForEach(shelf.destinations) { destination in
                    Button("Move to \(destination.name)") { shelf.copy([url], to: destination.url, move: true) }
                }
            }
            Divider()
            Button("Remove from Drop Zone") { shelf.remove(url) }
        }
        .compatHelp(url.path)
    }
}

private struct DestinationChip: View {
    let name: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                SymbolImage(symbol)
                    .font(.system(size: 10))
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SymbolImage(symbol)
                .font(.system(size: 12))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .compatHelp(help)
    }
}

/// AppKit share button: shows the system share menu (Mail, Messages, Notes, AirDrop,
/// and any installed share extensions such as cloud storage apps).
struct SharePickerButton: NSViewRepresentable {
    let items: [URL]

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage.symbol("square.and.arrow.up", description: "Share") ?? NSImage(named: NSImage.shareTemplateName) ?? NSImage()
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.isBordered = false
        button.contentTintColor = .white
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.items = items
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items)
    }

    @MainActor
    final class Coordinator: NSObject {
        var items: [URL]

        init(items: [URL]) {
            self.items = items
        }

        @objc func share(_ sender: NSButton) {
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
