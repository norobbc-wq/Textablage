import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct CollectionView: View {
    @EnvironmentObject private var store: SharedClipStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("captureOnOpen") private var captureOnOpen = false
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var editor: ClipDraft?
    @State private var pendingDeletion: ClipEntry?
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var notice: ClipNotice?
    @State private var captureTask: Task<Void, Never>?
    @State private var capturedThisActivation = false
    @State private var skipCaptureThisActivation = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var visibleClips: [ClipEntry] {
        ClipSearch.filtered(store.clips, query: query, favoritesOnly: favoritesOnly)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            actionRow
            collectionRow
            if let message = store.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(message).font(.caption)
                    Spacer(minLength: 0)
                    Button("Erneut") { store.reload() }
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            ScrollView {
                if visibleClips.isEmpty {
                    Text(query.isEmpty ? "Keine Texte" : "Keine Treffer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 36)
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(visibleClips) { clip in
                            ClipCard(
                                clip: clip,
                                onCopy: { copy(clip) },
                                onFavorite: { perform { try store.toggleFavorite(id: clip.id) } },
                                onEdit: { editor = ClipDraft(entry: clip) },
                                onDelete: { pendingDeletion = clip }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(ClipColors.background.ignoresSafeArea())
        .tint(ClipColors.accent)
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ClipColors.background)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(ClipColors.accent, in: Capsule())
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task(id: notice?.id) {
            guard notice != nil else { return }
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                notice = nil
            } catch { }
        }
        .onAppear {
            store.reload()
            scheduleForegroundCapture()
        }
        .onDisappear { captureTask?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.reload()
                scheduleForegroundCapture()
            } else {
                captureTask?.cancel()
                if phase == .background {
                    capturedThisActivation = false
                    skipCaptureThisActivation = false
                }
            }
        }
        .onChange(of: captureOnOpen) { _, enabled in
            if enabled {
                scheduleForegroundCapture()
            } else {
                captureTask?.cancel()
            }
        }
        .onOpenURL(perform: handleURL)
        .sheet(item: $editor) { draft in
            ClipEditor(draft: draft) {
                editor = nil
                showNotice("Gespeichert")
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
        }
        .confirmationDialog(
            "Text löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                guard let clip = pendingDeletion else { return }
                perform {
                    try store.delete(id: clip.id)
                    showNotice("Gelöscht")
                }
                pendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "textablage-sicherung"
        ) { result in
            if case .failure(let error) = result { showFailure(error.localizedDescription) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            perform {
                let url = try result.get()
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                let count = try store.mergeBackupData(readBackup(from: url))
                showNotice(count == 1 ? "1 Text importiert" : "\(count) Texte importiert")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Zwischenablage")
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Menu {
                Toggle("Beim Öffnen übernehmen", isOn: $captureOnOpen)
                Divider()
                Button {
                    perform {
                        exportDocument = BackupDocument(data: try store.backupData())
                        showExporter = true
                    }
                } label: {
                    Label("Sicherung exportieren", systemImage: "square.and.arrow.up")
                }
                Button { showImporter = true } label: {
                    Label("Sicherung importieren", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Menü")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ClipboardPasteButton(
                onPaste: { text in
                    perform {
                        try store.add(text: text, title: "", favorite: false)
                        showNotice("Gespeichert")
                    }
                },
                onFailure: showFailure
            )
            .frame(width: 44, height: 44)

            Button { editor = ClipDraft() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(ClipColors.surface, in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Eigenen Text schreiben")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Suchen", text: $query)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Texte durchsuchen")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Suche leeren")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(ClipColors.surface, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var collectionRow: some View {
        HStack(spacing: 4) {
            Text("Meine Sammlung")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            filterButton("Alle", selected: !favoritesOnly) { favoritesOnly = false }
            filterButton("Favoriten", selected: favoritesOnly) { favoritesOnly = true }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? ClipColors.background : Color.secondary)
                .background(selected ? ClipColors.accent : ClipColors.surface, in: Capsule())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func copy(_ clip: ClipEntry) {
        UIPasteboard.general.string = clip.text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showNotice("Kopiert")
    }

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "textablage", url.host?.lowercased() == "copy" else { return }
        skipCaptureThisActivation = true
        captureTask?.cancel()
        store.reload()
        guard store.errorMessage == nil else {
            showFailure(store.errorMessage ?? "Sammlung nicht verfügbar.")
            return
        }
        let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value
        guard let idString, let id = UUID(uuidString: idString),
              let clip = store.clips.first(where: { $0.id == id }) else {
            showFailure("Dieser Text ist nicht mehr vorhanden.")
            return
        }
        copy(clip)
    }

    private func scheduleForegroundCapture() {
        guard captureOnOpen, scenePhase == .active,
              !capturedThisActivation, !skipCaptureThisActivation else { return }
        captureTask?.cancel()
        // Leave initial URL delivery time to cancel a widget-copy activation.
        captureTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 250_000_000) }
            catch { return }
            guard !Task.isCancelled, captureOnOpen,
                  UIApplication.shared.applicationState == .active,
                  !capturedThisActivation, !skipCaptureThisActivation else { return }
            capturedThisActivation = true
            guard let text = UIPasteboard.general.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            perform {
                try store.add(text: text, title: "", favorite: false)
                showNotice("Gespeichert")
            }
        }
    }

    private func readBackup(from url: URL) throws -> Data {
        let maximumBytes = 25 * 1_024 * 1_024
        let properties = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = properties.fileSize, size > maximumBytes { throw ClipError.fileTooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let remaining = maximumBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw ClipError.fileTooLarge }
        return data
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { showFailure(error.localizedDescription) }
    }

    private func showFailure(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func showNotice(_ text: String) {
        notice = ClipNotice(text: text)
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

private struct ClipNotice: Identifiable {
    let id = UUID()
    let text: String
}

private enum ClipColors {
    static let background = Color(red: 0.043, green: 0.063, blue: 0.070)
    static let surface = Color(red: 0.082, green: 0.102, blue: 0.110)
    static let accent = Color(red: 0.79, green: 0.94, blue: 0.50)
}

private struct ClipCard: View {
    let clip: ClipEntry
    let onCopy: () -> Void
    let onFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 3) {
                    if !clip.title.isEmpty {
                        Text(clip.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ClipColors.accent)
                            .lineLimit(1)
                    }
                    Text(clip.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(clip.title.isEmpty ? clip.text : clip.title)
            .accessibilityHint("Text vollständig kopieren")

            HStack(spacing: 0) {
                Button(action: onFavorite) {
                    Image(systemName: clip.favorite ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(clip.favorite ? ClipColors.accent : Color.secondary)
                        .frame(width: 44, height: 38)
                }
                .accessibilityLabel(clip.favorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
                Spacer(minLength: 0)
                Menu {
                    Button(action: onCopy) { Label("Kopieren", systemImage: "doc.on.doc") }
                    Button(action: onEdit) { Label("Bearbeiten", systemImage: "pencil") }
                    Button(role: .destructive, action: onDelete) {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 38)
                }
                .accessibilityLabel("Textmenü")
            }
        }
        .background(ClipColors.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ClipDraft: Identifiable {
    let id = UUID()
    var entryID: UUID?
    var title = ""
    var text = ""
    var favorite = false

    init() { }

    init(entry: ClipEntry) {
        entryID = entry.id
        title = entry.title
        text = entry.text
        favorite = entry.favorite
    }
}

@MainActor
private struct ClipEditor: View {
    @EnvironmentObject private var store: SharedClipStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var favorite: Bool
    @State private var errorMessage = ""
    @State private var showError = false
    @FocusState private var textFocused: Bool
    let draft: ClipDraft
    let onSaved: () -> Void

    init(draft: ClipDraft, onSaved: @escaping () -> Void) {
        self.draft = draft
        self.onSaved = onSaved
        _title = State(initialValue: draft.title)
        _text = State(initialValue: draft.text)
        _favorite = State(initialValue: draft.favorite)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Titel (optional)", text: $title)
                    .padding(12)
                    .background(ClipColors.surface, in: RoundedRectangle(cornerRadius: 10))
                TextEditor(text: $text)
                    .font(.body)
                    .focused($textFocused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(ClipColors.surface, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Text")
                Toggle("Favorit", isOn: $favorite)
            }
            .padding(12)
            .background(ClipColors.background)
            .navigationTitle(draft.entryID == nil ? "Neuer Text" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(ClipColors.accent)
            .alert("Nicht gespeichert", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear { if draft.entryID == nil { textFocused = true } }
        }
    }

    private func save() {
        do {
            if let id = draft.entryID {
                try store.update(id: id, title: title, text: text, favorite: favorite)
            } else {
                try store.add(text: text, title: title, favorite: favorite)
            }
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
