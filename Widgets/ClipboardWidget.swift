import Foundation
import SwiftUI
import WidgetKit

private struct ClipboardWidgetEntry: TimelineEntry {
    let date: Date
    let clips: [ClipEntry]
    let unavailable: Bool
}

private struct ClipboardWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipboardWidgetEntry {
        ClipboardWidgetEntry(date: .now, clips: [], unavailable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClipboardWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClipboardWidgetEntry>) -> Void) {
        let current = entry()
        completion(Timeline(entries: [current], policy: .after(current.date.addingTimeInterval(3_600))))
    }

    private func entry() -> ClipboardWidgetEntry {
        // Widgets only read the shared collection. Copying happens after the user
        // follows a clip's link and the app becomes active.
        let repository = ClipRepository()
        guard repository.usesSharedContainer else {
            return ClipboardWidgetEntry(date: .now, clips: [], unavailable: true)
        }
        do {
            let all = try repository.load().sorted { $0.updatedAt > $1.updatedAt }
            let favorites = all.filter(\.favorite)
            let selected = favorites.isEmpty ? all : favorites
            return ClipboardWidgetEntry(date: .now, clips: Array(selected.prefix(4)), unavailable: false)
        } catch {
            return ClipboardWidgetEntry(date: .now, clips: [], unavailable: true)
        }
    }
}

private enum ClipboardWidgetStyle {
    static let background = Color(red: 0.045, green: 0.065, blue: 0.075)
    static let card = Color(red: 0.085, green: 0.11, blue: 0.12)
    static let accent = Color(red: 0.79, green: 0.94, blue: 0.52)
    static let openApp = URL(string: "textablage://open")!

    static func copyURL(for id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "textablage"
        components.host = "copy"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url!
    }
}

private struct ClipboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClipboardWidgetEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                smallWidget
            } else {
                collectionWidget
            }
        }
        .padding(10)
        .containerBackground(ClipboardWidgetStyle.background, for: .widget)
    }

    // Small widgets have one URL target for the whole widget.
    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            if entry.unavailable {
                unavailableContent
            } else if let clip = entry.clips.first {
                clipContent(clip)
                    .accessibilityLabel(Text("Kopieren: \(clip.text)"))
            } else {
                emptyContent
            }
        }
        .widgetURL(smallDestination)
    }

    private var smallDestination: URL {
        guard !entry.unavailable, let clip = entry.clips.first else {
            return ClipboardWidgetStyle.openApp
        }
        return ClipboardWidgetStyle.copyURL(for: clip.id)
    }

    private var collectionWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: ClipboardWidgetStyle.openApp) { heading }
            if entry.unavailable {
                Link(destination: ClipboardWidgetStyle.openApp) { unavailableContent }
                    .accessibilityLabel("Sammlung nicht verfügbar. Zwischenablage öffnen")
            } else if entry.clips.isEmpty {
                Link(destination: ClipboardWidgetStyle.openApp) { emptyContent }
                    .accessibilityLabel("Zwischenablage öffnen")
            } else {
                let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(entry.clips.prefix(4))) { clip in
                        Link(destination: ClipboardWidgetStyle.copyURL(for: clip.id)) {
                            clipContent(clip)
                        }
                        .frame(height: 52)
                        .accessibilityLabel(Text("Kopieren: \(clip.text)"))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(ClipboardWidgetStyle.accent)
            Text("Zwischenablage")
                .fontWeight(.semibold)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
    }

    private var unavailableContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
            Text("Sammlung nicht verfügbar")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(ClipboardWidgetStyle.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
            Text("Meine Sammlung")
                .font(.system(size: 12))
        }
        .foregroundStyle(ClipboardWidgetStyle.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClipboardWidgetStyle.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func clipContent(_ clip: ClipEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(clip.text)
                .font(.system(size: 12))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
            if clip.favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(ClipboardWidgetStyle.accent)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClipboardWidgetStyle.card, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct ClipboardWidget: Widget {
    let kind = "TextablageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClipboardWidgetProvider()) { entry in
            ClipboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Zwischenablage")
        .description("Favoriten und zuletzt gespeicherte Texte.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct TextablageWidgets: WidgetBundle {
    var body: some Widget {
        ClipboardWidget()
    }
}
