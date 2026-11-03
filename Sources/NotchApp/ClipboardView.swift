import SwiftUI

struct ClipboardPopup: View {
    let history: ClipboardHistory
    let close: () -> Void
    @State private var showFavorites = false
    @State private var query = ""

    @Environment(\.accent) private var customAccent
    private var accent: Color { customAccent ?? .notchBlue }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                tabButton("History", symbol: "clock", count: history.items.count, selected: !showFavorites) { showFavorites = false }
                tabButton("Favorites", symbol: "heart.fill", count: nil, selected: showFavorites) { showFavorites = true }
                Spacer()
                if !showFavorites {
                    Button(action: history.clearHistory) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PressableStyle())
                    .help("Clear history (keeps favorites)")
                    .accessibilityLabel("Clear history")
                }
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close clipboard")
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search clipboard…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.07)))

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            if filtered.isEmpty {
                Spacer()
                Text(emptyText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in
                            ClipRow(item: item, history: history, accent: accent)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.12))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        )
    }

    private var filtered: [ClipItem] {
        let base = showFavorites ? history.items.filter(\.favorite) : history.items
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(trimmed) || $0.content.localizedCaseInsensitiveContains(trimmed) }
    }

    private var emptyText: String {
        if !query.isEmpty { return "No matches" }
        return showFavorites ? "Heart an item to keep it here" : "Copy something to start"
    }

    private func tabButton(_ title: String, symbol: String, count: Int?, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .semibold))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(selected ? 0.25 : 0.1)))
                }
            }
            .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let history: ClipboardHistory
    let accent: Color
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                HStack {
                    Text(item.typeLabel)
                    Spacer()
                    Text(copied ? "Copied" : relativeTime(item.date))
                        .foregroundStyle(copied ? Color.green : .white.opacity(0.4))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            }
            Button { history.toggleFavorite(item) } label: {
                Image(systemName: item.favorite ? "heart.fill" : "heart")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.favorite ? Color.pink : .white.opacity(0.4))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PressableStyle())
            .opacity(hovering || item.favorite ? 1 : 0)
            .accessibilityLabel(item.favorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            history.copy(item)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        }
        .contextMenu {
            Button("Copy") { history.copy(item) }
            Button(item.favorite ? "Remove from Favorites" : "Add to Favorites") { history.toggleFavorite(item) }
            Divider()
            Button("Delete") { history.remove(item) }
        }
        .help(item.kind == .text ? String(item.content.prefix(500)) : item.title)
    }
}

func relativeTime(_ date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(seconds / 60)m ago"
    case ..<86_400: return "\(seconds / 3600)h ago"
    default: return "\(seconds / 86_400)d ago"
    }
}
