# Textablage für iPhone

Native App mit einer kompakten Textsammlung und eigener Tastatur. Die Oberfläche hat oben Einfügen, eigene Eingabe und Suche; darunter stehen Alle/Favoriten und zwei Spalten mit kurzen Vorschauen. Antippen kopiert den vollständigen Text. In der Tastatur setzt ein Antippen den Text direkt in das aktive Eingabefeld ein.

## Was enthalten ist

- SwiftUI-App: Texte speichern, suchen, bearbeiten, löschen und als Favorit markieren.
- Übernahme aus der Zwischenablage über den System-Einfügeknopf; optional „Beim Öffnen übernehmen“ im Menü. Diese Option ist anfangs ausgeschaltet und kann iOS-Einfügeberechtigungen benötigen.
- Eigene Tastatur mit Sammlung, Favoriten, Suche, eigener Texteingabe und deutschen/arabischen Tasten. Die Globustaste wechselt zurück zu anderen Tastaturen.
- Sicherungen im gleichen JSON-Format wie die bisherige Web-App. Bestehende Texte lassen sich damit importieren und exportieren.
- Widget-Erweiterung für die Variante mit gemeinsamer Sammlung. Antippen eines Textes öffnet die App und kopiert ihn.
- Xcode-Projekt, Generator ohne zusätzliche Python-Pakete, Swift-Paket für den Speicherkern, Tests und optionaler GitHub-Buildablauf.

Der ausführliche Prüfstand steht in `PRUEFBERICHT.md`. `python3 scripts/package_source.py` erzeugt das Quellcode-ZIP mit Prüfsummen.

## Stand und Installation

Dies ist ein vollständiges **Quellcode-Projekt**. Es liegt noch keine mit Apples SDK gebaute, signierte und auf dem iPhone getestete Installationsdatei vor. Das ZIP lässt sich auf einem iPhone herunterladen, aber nicht als App installieren. Für die normale kostenlose Installation einer eigenen App benötigt man einen Mac mit Xcode und eine Apple-ID. Mit einem kostenlosen Personal Team läuft die Bereitstellung nach sieben Tagen ab und muss erneuert werden.

Du musst für den Quellcode nichts kaufen. Eine dauerhafte kostenlose Installation ausschließlich mit dem iPhone kann dieses Projekt nicht bereitstellen. Es enthält keine fremden Signaturzertifikate und benötigt beim Entwickeln keine Zahlung oder Anmeldung an einem App-Backend.

### Variante „Textablage“

Das voreingestellte Scheme **Textablage** enthält die App und eine eigenständige Tastatur ohne App-Groups-Entitlement. Die App und die Tastatur haben getrennte Sammlungen. In der Tastatur lassen sich Texte direkt mit dem Stift erstellen oder mit dem Plus aus der Zwischenablage speichern. Für das Lesen der Zwischenablage verlangt Apple bei Drittanbieter-Tastaturen „Vollen Zugriff“. Schreiben und Einsetzen eigener Texte funktioniert auch ohne diesen Zugriff. Die App sendet keine Texte oder Tastatureingaben ins Netzwerk.

Bei späterem Zugriff auf einen Mac:

1. `Textablage.xcodeproj` in aktuellem Xcode öffnen.
2. Scheme **Textablage** wählen.
3. In „Signing & Capabilities“ bei **Textablage** und **TextablageKeyboard** dasselbe Personal Team auswählen. Die Bundle-IDs bei Bedarf mit einer eigenen eindeutigen Endung versehen; die Extension-ID muss mit der App-ID beginnen.
4. iPhone anschließen, dem Computer vertrauen, den Entwicklermodus aktivieren und in Xcode **Run** ausführen. Eventuelle Entwickler-Vertrauensabfragen in den iPhone-Einstellungen bestätigen.
5. Tastatur unter **Einstellungen → Allgemein → Tastatur → Tastaturen → Tastatur hinzufügen → Textablage** hinzufügen. Bei Bedarf „Vollen Zugriff“ aktivieren.

Diese Schritte wurden hier nicht auf einem Mac oder iPhone ausgeführt. Apples kostenlose Bereitstellung hat weitere Geräte-/App-Limits; Xcode zeigt die für das Konto geltenden Grenzen an.

### Variante „Textablage-Gemeinsam“

Dieses zusätzliche Scheme verbindet App, Tastatur und Widgets über eine App Group. Alle drei Targets verwenden `Config/Shared.entitlements` und den Buildwert `TEXTABLAGE_APP_GROUP`. Die Bundle-IDs sind getrennt von der eigenständigen Variante.

Diese Variante benötigt eine App-Group-Berechtigung und passende eindeutige Bundle-IDs im Entwicklerkonto. **Dass sich diese Berechtigung mit einem kostenlosen Personal Team bereitstellen lässt, wurde hier nicht bestätigt.** Deshalb ist die gemeinsame Variante nicht als kostenlose Installationslösung zugesagt. Die voreingestellte Variante **Textablage** benötigt keine App Group und ist für die normale kostenlose Bereitstellung mit Xcode vorbereitet.

## Bauen und prüfen

```sh
python3 scripts/generate_project.py
swift test
xcodebuild -project Textablage.xcodeproj -scheme Textablage \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

`swift test` prüft den Speicherkern auch unter Linux. UI, Tastatur und Widgets benötigen zum vollständigen Kompilieren Apples SDK. `.github/workflows/ios-build.yml` enthält dafür einen optionalen Mac-Build auf GitHub. Der Workflow wurde hier nicht ausgeführt.

### IPA-Datei

Der GitHub-Workflow baut standardmäßig **Textablage** mit Apples iPhone-SDK, deaktiviert auch die Ad-hoc-Signierung des Linkers und erzeugt danach eine **unsignierte IPA** mit Prüfsumme und Statusdatei. Unter **Actions → iPhone-Projekt bauen → Run workflow** kann die Variante gewählt werden; das Ergebnis erscheint bei einem erfolgreichen Lauf unter **Artifacts → Textablage-IPA-unsigniert**. Das Projekt wird im Repository [norobbc-wq/Textablage](https://github.com/norobbc-wq/Textablage) bereitgestellt. Ein erfolgreicher Apple-Build ist noch nicht bestätigt.

Ein eigenes Installationswerkzeug muss diese IPA vor der Installation mit gültigen Apple-Berechtigungen signieren; der Entwicklermodus allein ersetzt das nicht. Für die gemeinsame Variante müssen diese Berechtigungen auch die App Group und alle Erweiterungen abdecken. Das Projekt verwaltet keine Zertifikate und enthält keine Signierungszugänge.

Ein bereits mit Apples SDK gebautes, unsigniertes Gerätearchiv lässt sich auch lokal verpacken:

```sh
python3 scripts/package_ipa.py build/Textablage.xcarchive \
  --output build/ipa/Textablage-unsigniert.ipa
```

Der Packager prüft die App und Erweiterungen auf ARM64-Mach-O-Dateien für **iPhoneOS**, Bundle-IDs und sichere Pfade. Er erhält Dateirechte und interne Symlinks. Simulator-Builds, reine Quellcode-Ordner, signierte Eingaben und ungültige Archive werden abgelehnt. Eine echte IPA wurde in dieser Umgebung noch nicht gebaut.

## Daten und Verhalten

Die Sammlung liegt als JSON im App- beziehungsweise App-Group-Container. Schreibvorgänge lesen den aktuellen Stand unter einer Dateisperre und ersetzen die Datei atomar. Fehler und beschädigte Dateien setzen die Sammlung nicht zurück. Sicherungen werden vollständig geprüft, bevor sie zusammengeführt werden. Grenzen: 10.000 Einträge, jeweils 200.000 UTF-16-Einheiten und insgesamt 25 MiB pro Sicherung/Speicherdatei. Vollständige Leerzeichen, Zeilenumbrüche und Unicode-Texte bleiben erhalten.

Die Tastatur liest die Zwischenablage nur nach Antippen des Plus. Sie zeichnet keine Eingaben anderer Apps auf und hat keinen Netzwerkteil. Die native App übernimmt nach opt-in beim Öffnen; eine systemweite Zwischenablage-Historie im Hintergrund wird dadurch nicht möglich. Sichere Eingabefelder und Apps, die Drittanbieter-Tastaturen ausschließen, verwenden Apples Tastatur.

## Prüfbericht

24 echte Swift-Tests bestehen: gleichzeitige Änderungen, vollständige Unicode-Texte, Suche, Favoriten, Sicherungen, fehlerhafte Importe und Erhalt beschädigter Dateien. Die Swift-Dateien der Oberfläche und Erweiterungen sind syntaktisch geprüft. Plists, Projektverweise und Schemes werden geprüft. Ein erfolgreicher Apple-SDK-Build und Tests auf einem iPhone sind noch offen; besonders Tastaturgröße, Zwischenablage-Berechtigungen und Widget-/App-Aktivierungsreihenfolge müssen dort geprüft werden.

## Apple-Quellen

- [Kostenlose Entwicklung und Personal Team](https://developer.apple.com/support/compare-memberships/)
- [Unterstützte Fähigkeiten](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
- [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Eigene Tastaturen](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [Entwicklermodus](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
