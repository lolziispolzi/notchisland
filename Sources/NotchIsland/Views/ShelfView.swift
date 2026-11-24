import SwiftUI

/// Temporary holding area for files: drop files in, drag them out later.
struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    let isTargeted: Bool

    var body: some View {
        if shelf.items.isEmpty {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(.white.opacity(isTargeted ? 0.8 : 0.3))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 22))
                        Text("Drop files here")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(shelf.items.count == 1 ? "1 item" : "\(shelf.items.count) items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("AirDrop") { shelf.airDropAll() }
                    Button("Clear") { shelf.clear() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url, shelf: shelf)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isTargeted ? 0.12 : 0.05))
            )
        }
    }
}

struct ShelfItemView: View {
    let url: URL
    let shelf: ShelfStore

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(url.path)
    }
}
