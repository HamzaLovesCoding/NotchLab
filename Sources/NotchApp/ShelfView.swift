import SwiftUI

struct ShelfView: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 12) {
            AirDropTile(highlighted: model.dropTarget == .airDrop)
                .frame(width: 128)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.airDropFrame = $0 }
            ShelfArea(shelf: model.shelf, highlighted: model.dropTarget == .shelf)
        }
        .onAppear { model.shelf.prune() }
        .onDisappear { model.airDropFrame = .zero }
    }
}

struct DropZoneBackground: View {
    let highlighted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.white.opacity(highlighted ? 0.7 : 0.18))
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(highlighted ? 0.08 : 0)))
            .animation(.easeOut(duration: 0.12), value: highlighted)
    }
}

struct AirDropTile: View {
    let highlighted: Bool
    private let icon = AirDrop.icon

    var body: some View {
        Button(action: AirDrop.chooseAndSend) {
            VStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(.white.opacity(0.08)))
                Text("AirDrop")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DropZoneBackground(highlighted: highlighted))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help("Choose files to AirDrop, or drop files here")
    }
}

struct ShelfArea: View {
    let shelf: Shelf
    let highlighted: Bool

    var body: some View {
        ZStack {
            DropZoneBackground(highlighted: highlighted)
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22))
                    Text("Drop files here")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(highlighted ? 0.8 : 0.35))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(shelf.items) { item in
                            ShelfItemView(item: item, shelf: shelf)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .overlay(alignment: .topTrailing) {
                    Button("Clear") { shelf.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
        }
    }
}

struct ShelfItemView: View {
    let item: ShelfItem
    let shelf: Shelf
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let thumbnail = shelf.thumbnails[item.url] {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06))
                }
            }
            .frame(width: 52, height: 52)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 78, height: 26, alignment: .top)
        }
        .frame(width: 84, height: 96)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.07 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.3))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove \(item.name)")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copy") { shelf.copyToPasteboard(item) }
            Button("AirDrop") { AirDrop.send([item.url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.name)
        .task(id: item.url) { await shelf.loadThumbnail(for: item) }
    }
}
