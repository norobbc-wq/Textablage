import UIKit

/// Snippets are inserted through the keyboard proxy, without replacing the clipboard.
/// Clipboard access happens only when the user presses the paste button.
final class KeyboardViewController: UIInputViewController {
    private enum Mode { case collection, search, compose, typing }
    private enum Alphabet { case latin, arabic, numbers }

    private var repository = ClipRepository(sharedAccess: false)
    private var entries: [ClipEntry] = []
    private var visibleEntries: [ClipEntry] = []
    private var mode: Mode = .collection
    private var alphabet: Alphabet = .latin
    private var query = ""
    private var draft = ""
    private var favoritesOnly = false
    private var capitalized = false
    private var noticeWorkItem: DispatchWorkItem?

    private let root = UIStackView()
    private let titleLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)
    private let pasteButton = UIButton(type: .system)
    private let composeButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let clearSearchButton = UIButton(type: .system)
    private let searchRow = UIStackView()
    private let emptyLabel = UILabel()
    private let noticeLabel = UILabel()
    private let collectionLayout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: collectionLayout)
    private let preview = UITextView()
    private let typingSpacer = UIView()
    private let letterRows = UIStackView()
    private let globeButton = UIButton(type: .system)
    private let typingButton = UIButton(type: .system)
    private let alphabetButton = UIButton(type: .system)
    private let shiftButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private var collectionHeight: NSLayoutConstraint!
    private var keyboardHeight: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        rebuildLetterRows()
        refreshMode()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Permission and App Group availability can change in Settings between uses.
        repository = ClipRepository(sharedAccess: hasFullAccess)
        reloadCollection()
        updateCollectionTitle()
        globeButton.isHidden = !needsInputModeSwitchKey
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = max(1, floor((collection.bounds.width - 6) / 2))
        let desiredSize = CGSize(width: width, height: 74)
        if collectionLayout.itemSize != desiredSize {
            collectionLayout.itemSize = desiredSize
            collectionLayout.invalidateLayout()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        globeButton.isHidden = !needsInputModeSwitchKey
    }

    private func buildInterface() {
        view.backgroundColor = .systemBackground
        view.tintColor = .systemGreen
        root.axis = .vertical
        root.spacing = 5
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        keyboardHeight = view.heightAnchor.constraint(equalToConstant: 320)
        keyboardHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 6),
            root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -6),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -5),
            keyboardHeight
        ])

        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 5
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        header.addArrangedSubview(titleLabel)
        configureSymbol(favoriteButton, image: "star", label: "Nur Favoriten", action: #selector(toggleFavorites))
        configureSymbol(pasteButton, image: "plus", label: "Zwischenablage speichern", action: #selector(captureClipboard))
        configureSymbol(composeButton, image: "square.and.pencil", label: "Eigenen Text schreiben", action: #selector(toggleCompose))
        for button in [favoriteButton, pasteButton, composeButton] {
            header.addArrangedSubview(button)
            activatePreferred(button.widthAnchor.constraint(equalToConstant: 35))
        }
        header.heightAnchor.constraint(equalToConstant: 33).isActive = true
        root.addArrangedSubview(header)

        searchRow.axis = .horizontal
        searchRow.spacing = 5
        searchButton.contentHorizontalAlignment = .leading
        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.titleLabel?.font = .systemFont(ofSize: 14)
        searchButton.titleLabel?.lineBreakMode = .byTruncatingTail
        searchButton.layer.cornerRadius = 8
        searchButton.backgroundColor = .secondarySystemBackground
        searchButton.addTarget(self, action: #selector(toggleSearch), for: .touchUpInside)
        searchRow.addArrangedSubview(searchButton)
        configureSymbol(clearSearchButton, image: "xmark.circle.fill", label: "Suche löschen", action: #selector(clearSearch))
        searchRow.addArrangedSubview(clearSearchButton)
        activatePreferred(clearSearchButton.widthAnchor.constraint(equalToConstant: 32))
        activatePreferred(searchRow.heightAnchor.constraint(equalToConstant: 31))
        root.addArrangedSubview(searchRow)

        noticeLabel.font = .systemFont(ofSize: 12)
        noticeLabel.numberOfLines = 2
        noticeLabel.textColor = .systemRed
        noticeLabel.isHidden = true
        noticeLabel.setContentHuggingPriority(.required, for: .vertical)
        root.addArrangedSubview(noticeLabel)

        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.delegate = self
        collection.dataSource = self
        collection.register(ClipCell.self, forCellWithReuseIdentifier: ClipCell.reuseIdentifier)
        collectionLayout.minimumInteritemSpacing = 6
        collectionLayout.minimumLineSpacing = 6
        collectionHeight = collection.heightAnchor.constraint(equalToConstant: 85)
        collectionHeight.priority = .required
        collectionHeight.isActive = false
        emptyLabel.text = "Keine Texte"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textAlignment = .center
        collection.backgroundView = emptyLabel
        root.addArrangedSubview(collection)

        // This is a preview, never a second text input. All editing uses our own keys.
        preview.isEditable = false
        preview.isSelectable = false
        preview.font = .systemFont(ofSize: 15)
        preview.backgroundColor = .secondarySystemBackground
        preview.layer.cornerRadius = 8
        preview.textContainerInset = UIEdgeInsets(top: 6, left: 5, bottom: 6, right: 5)
        activatePreferred(preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 75))
        root.addArrangedSubview(preview)

        // Without a collection or preview, the host typing layout still needs a
        // flexible area so fixed-height key rows never fight the keyboard height.
        typingSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(typingSpacer)

        letterRows.axis = .vertical
        letterRows.spacing = 4
        root.addArrangedSubview(letterRows)

        let controls = UIStackView()
        controls.axis = .horizontal
        controls.spacing = 4
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.accessibilityLabel = "Nächste Tastatur"
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        typingButton.setTitle("ABC", for: .normal)
        typingButton.accessibilityLabel = "Buchstaben oder Textsammlung anzeigen"
        typingButton.addTarget(self, action: #selector(toggleTyping), for: .touchUpInside)
        alphabetButton.accessibilityLabel = "Alphabet wechseln"
        alphabetButton.addTarget(self, action: #selector(changeAlphabet), for: .touchUpInside)
        shiftButton.setImage(UIImage(systemName: "shift"), for: .normal)
        shiftButton.accessibilityLabel = "Großschreibung umschalten"
        shiftButton.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
        spaceButton.setTitle("Leerzeichen", for: .normal)
        spaceButton.titleLabel?.font = .systemFont(ofSize: 13)
        spaceButton.addTarget(self, action: #selector(insertSpace), for: .touchUpInside)
        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.accessibilityLabel = "Letztes Zeichen löschen"
        deleteButton.addTarget(self, action: #selector(deleteCharacter), for: .touchUpInside)
        returnButton.setImage(UIImage(systemName: "return"), for: .normal)
        returnButton.accessibilityLabel = "Zeilenumbruch"
        returnButton.addTarget(self, action: #selector(insertReturn), for: .touchUpInside)
        saveButton.setTitle("Speichern", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        saveButton.addTarget(self, action: #selector(saveDraft), for: .touchUpInside)
        for button in [globeButton, typingButton, alphabetButton, shiftButton, spaceButton, deleteButton, returnButton, saveButton] {
            styleKey(button)
            controls.addArrangedSubview(button)
            if button != spaceButton && button != saveButton {
                activatePreferred(button.widthAnchor.constraint(equalToConstant: 35))
            }
        }
        spaceButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        saveButton.setContentHuggingPriority(.required, for: .horizontal)
        controls.heightAnchor.constraint(equalToConstant: 36).isActive = true
        root.addArrangedSubview(controls)
    }

    private func configureSymbol(_ button: UIButton, image: String, label: String, action: Selector) {
        button.setImage(UIImage(systemName: image), for: .normal)
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 8
    }

    private func styleKey(_ button: UIButton) {
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 6
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.65
    }

    /// UIStackView adds required zero-size constraints to hidden arranged views.
    /// Their preferred sizes must yield to those constraints when modes change.
    private func activatePreferred(_ constraint: NSLayoutConstraint) {
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
    }

    private func updateCollectionTitle() {
        titleLabel.text = repository.usesSharedContainer ? "Textablage" : "Tastatursammlung"
        titleLabel.accessibilityLabel = repository.usesSharedContainer
            ? "Textablage, mit der App geteilte Sammlung"
            : "Tastatursammlung, getrennt von der Sammlung in der App"
    }

    private func reloadCollection() {
        do {
            entries = try repository.load()
            updateVisibleEntries()
        } catch {
            // Keep any already loaded entries; failed reads must never reset the file.
            showNotice("Sammlung konnte nicht geladen werden.")
        }
    }

    private func updateVisibleEntries() {
        visibleEntries = ClipSearch.filtered(entries, query: query, favoritesOnly: favoritesOnly)
        emptyLabel.text = query.isEmpty ? "Keine Texte" : "Keine Treffer"
        emptyLabel.isHidden = !visibleEntries.isEmpty
        collection.reloadData()
    }

    private func refreshMode() {
        let showingKeys = mode != .collection
        searchRow.isHidden = mode == .compose || mode == .typing
        collection.isHidden = mode == .compose || mode == .typing
        collectionHeight.isActive = mode == .search
        preview.isHidden = mode != .compose
        typingSpacer.isHidden = mode != .typing
        letterRows.isHidden = !showingKeys
        alphabetButton.isHidden = !showingKeys
        shiftButton.isHidden = !showingKeys || alphabet != .latin
        spaceButton.isHidden = !showingKeys
        saveButton.isHidden = mode != .compose
        saveButton.isEnabled = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        returnButton.isHidden = mode == .search
        deleteButton.isHidden = false
        favoriteButton.isHidden = mode == .compose || mode == .typing
        pasteButton.isHidden = mode == .compose
        typingButton.setTitle(mode == .collection ? "ABC" : "Liste", for: .normal)
        searchButton.setTitle(query.isEmpty ? "  Suchen" : "  \(query)", for: .normal)
        searchButton.accessibilityLabel = query.isEmpty ? "Textsammlung durchsuchen" : "Suche: \(query)"
        clearSearchButton.isHidden = query.isEmpty
        preview.text = draft.isEmpty ? "Eigener Text …" : draft
        preview.textColor = draft.isEmpty ? .placeholderText : .label
        preview.textAlignment = .natural
        if !draft.isEmpty { preview.scrollRangeToVisible(NSRange(location: (draft as NSString).length, length: 0)) }
        alphabetButton.setTitle(alphabet == .latin ? "عربي" : alphabet == .arabic ? "123" : "ABC", for: .normal)
        shiftButton.tintColor = capitalized ? .systemGreen : .secondaryLabel
        updateCollectionTitle()
    }

    private func rebuildLetterRows() {
        for row in letterRows.arrangedSubviews { letterRows.removeArrangedSubview(row); row.removeFromSuperview() }
        let rows: [[String]]
        switch alphabet {
        case .latin:
            rows = [Array("qwertzuiop").map(String.init), Array("asdfghjklö").map(String.init), Array("yxcvbnmäüß").map(String.init)]
        case .arabic:
            rows = [["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج"],
                    ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "د"],
                    ["ئ", "ء", "ؤ", "ر", "ى", "ة", "و", "ز", "ظ", "ذ", "ط"]]
        case .numbers:
            rows = [Array("1234567890").map(String.init), ["@", "#", "€", "%", "&", "*", "-", "+", "(", ")"],
                    [".", ",", "?", "!", ":", ";", "/", "=", "\"", "'"]]
        }
        for symbols in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 3
            row.semanticContentAttribute = .forceLeftToRight
            for symbol in symbols {
                let button = UIButton(type: .system)
                let character = capitalized && alphabet == .latin ? symbol.uppercased() : symbol
                button.setTitle(character, for: .normal)
                button.accessibilityLabel = character
                button.addTarget(self, action: #selector(characterPressed(_:)), for: .touchUpInside)
                styleKey(button)
                row.addArrangedSubview(button)
            }
            activatePreferred(row.heightAnchor.constraint(equalToConstant: 30))
            letterRows.addArrangedSubview(row)
        }
    }

    private func enter(_ text: String) {
        switch mode {
        case .search:
            query += text
            updateVisibleEntries()
        case .compose:
            draft += text
        case .typing:
            textDocumentProxy.insertText(text)
        case .collection:
            return
        }
        refreshMode()
    }

    @objc private func characterPressed(_ sender: UIButton) { if let text = sender.currentTitle { enter(text) } }
    @objc private func insertSpace() { enter(" ") }
    @objc private func insertReturn() {
        if mode == .collection { textDocumentProxy.insertText("\n") }
        else { enter("\n") }
    }

    @objc private func deleteCharacter() {
        switch mode {
        case .search:
            if !query.isEmpty { query.removeLast() }
            updateVisibleEntries()
        case .compose:
            if !draft.isEmpty { draft.removeLast() }
        case .typing, .collection:
            textDocumentProxy.deleteBackward()
        }
        refreshMode()
    }

    @objc private func toggleSearch() {
        mode = mode == .search ? .collection : .search
        refreshMode()
    }

    @objc private func clearSearch() {
        query = ""
        updateVisibleEntries()
        refreshMode()
    }

    @objc private func toggleFavorites() {
        favoritesOnly.toggle()
        favoriteButton.setImage(UIImage(systemName: favoritesOnly ? "star.fill" : "star"), for: .normal)
        favoriteButton.accessibilityValue = favoritesOnly ? "Aktiv" : "Inaktiv"
        updateVisibleEntries()
    }

    @objc private func toggleCompose() {
        mode = mode == .compose ? .collection : .compose
        refreshMode()
    }

    @objc private func toggleTyping() {
        mode = mode == .collection ? .typing : .collection
        refreshMode()
    }

    @objc private func changeAlphabet() {
        alphabet = alphabet == .latin ? .arabic : alphabet == .arabic ? .numbers : .latin
        rebuildLetterRows()
        refreshMode()
    }

    @objc private func toggleShift() {
        capitalized.toggle()
        rebuildLetterRows()
        refreshMode()
    }

    @objc private func captureClipboard() {
        guard hasFullAccess else {
            showNotice("Zwischenablage speichern benötigt „Vollen Zugriff“ in den Tastatureinstellungen.")
            return
        }
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            showNotice("Kein Text in der Zwischenablage.")
            return
        }
        addEntry(text)
    }

    @objc private func saveDraft() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if addEntry(draft) {
            draft = ""
            mode = .collection
            refreshMode()
        }
    }

    @discardableResult private func addEntry(_ text: String) -> Bool {
        do {
            entries = try repository.mutate { clips in
                _ = try ClipOperations.add(&clips, text: text)
            }
            query = ""
            favoritesOnly = false
            favoriteButton.setImage(UIImage(systemName: "star"), for: .normal)
            updateVisibleEntries()
            refreshMode()
            return true
        } catch {
            showNotice("Text konnte nicht gespeichert werden.")
            return false
        }
    }

    private func toggleFavorite(id: UUID) {
        do {
            entries = try repository.mutate { clips in
                try ClipOperations.toggleFavorite(&clips, id: id)
            }
            updateVisibleEntries()
        } catch {
            showNotice("Favorit konnte nicht gespeichert werden.")
        }
    }

    private func insertEntry(id: UUID) {
        do {
            let latest = try repository.load()
            guard let entry = latest.first(where: { $0.id == id }) else {
                entries = latest
                updateVisibleEntries()
                showNotice("Dieser Text wurde entfernt.")
                return
            }
            // UIKit receives the entire saved string, including line breaks and Unicode.
            textDocumentProxy.insertText(entry.text)
            UISelectionFeedbackGenerator().selectionChanged()
        } catch {
            showNotice("Text konnte nicht geladen werden.")
        }
    }

    private func showNotice(_ text: String) {
        noticeWorkItem?.cancel()
        noticeLabel.text = text
        noticeLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
        let item = DispatchWorkItem { [weak self] in self?.noticeLabel.isHidden = true }
        noticeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
    }
}

extension KeyboardViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { visibleEntries.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ClipCell.reuseIdentifier, for: indexPath) as? ClipCell else {
            return UICollectionViewCell()
        }
        let entry = visibleEntries[indexPath.item]
        cell.configure(entry)
        cell.onFavorite = { [weak self] in self?.toggleFavorite(id: entry.id) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard visibleEntries.indices.contains(indexPath.item) else { return }
        insertEntry(id: visibleEntries[indexPath.item].id)
    }
}

private final class ClipCell: UICollectionViewCell {
    static let reuseIdentifier = "TextablageClip"
    var onFavorite: (() -> Void)?
    private let textLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 9
        textLabel.numberOfLines = 3
        textLabel.font = .systemFont(ofSize: 14)
        textLabel.textAlignment = .natural
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.addTarget(self, action: #selector(favoritePressed), for: .touchUpInside)
        contentView.addSubview(textLabel)
        contentView.addSubview(favoriteButton)
        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            textLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            textLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -6),
            textLabel.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -3),
            favoriteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3),
            favoriteButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            favoriteButton.widthAnchor.constraint(equalToConstant: 30),
            favoriteButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        favoriteButton.isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onFavorite = nil
        accessibilityCustomActions = nil
    }

    func configure(_ entry: ClipEntry) {
        textLabel.text = entry.text
        favoriteButton.setImage(UIImage(systemName: entry.favorite ? "star.fill" : "star"), for: .normal)
        favoriteButton.accessibilityLabel = entry.favorite ? "Favorit entfernen" : "Als Favorit markieren"
        accessibilityLabel = String((entry.title.isEmpty ? entry.text : entry.title).prefix(160))
        accessibilityHint = "Setzt den vollständigen Text ein."
        accessibilityValue = entry.favorite ? "Favorit" : nil
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: favoriteButton.accessibilityLabel ?? "Favorit") { [weak self] _ in
            self?.onFavorite?()
            return true
        }]
    }

    @objc private func favoritePressed() { onFavorite?() }
}
