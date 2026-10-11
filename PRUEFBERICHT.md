# Prüfstand vom 11. Oktober 2026

Das Paket enthält Quellcode, ein Xcode-Projekt und zwei Schemes. Es enthält keine installierbare IPA, Signatur, Zugangsdaten oder persönlichen Texte.

## Ausgeführt

- Speicherkern mit Swift 6.2.3 unter Linux im Swift-5-Sprachmodus kompiliert.
- `swift test`: 24 XCTest-Tests bestanden, keine Fehler. Geprüft wurden unter anderem echte gleichzeitige Dateizugriffe, atomare Änderungen, Unicode und Zeilenumbrüche, Suche, Favoriten, Web-Sicherungen, ungültige Importe und Erhalt beschädigter Dateien.
- Swift-Syntaxprüfung für App, Tastatur und Widget mit `swiftc -frontend -parse` bestanden. Diese Prüfung prüft keine Apple-API-Typen.
- Xcode-Projekt mit Python erzeugt und mit Foundation als OpenStep-Plist eingelesen: fünf Targets, 123 Objekte. Projektverweise, Eingabedateien und Abhängigkeitszyklen geprüft.
- XML-Plists und die beiden gemeinsamen Schemes eingelesen; wiederholte Projekterzeugung liefert dieselben Dateien.
- ZIP-Inhalt und SHA-256-Prüfsummen beim Verpacken geprüft.

## Noch offen

- Kompilieren und Archivieren mit Xcode und Apples iOS-SDK. Der enthaltene GitHub-Workflow wurde nicht ausgeführt.
- Signieren, Installieren und Ausführen auf einem iPhone.
- Bedienung, Darstellung bei großen Schriften, Tastaturgröße und Verhalten in verschiedenen Host-Apps.
- iOS-Einfügeberechtigungen, freiwillige Übernahme beim Öffnen und Reihenfolge von Widget-Link und App-Aktivierung.
- App-Group-Berechtigung und gemeinsamer Speicher in der zusätzlichen Variante mit Widget.

Die kostenlose Variante benötigt zum regulären Installieren einen Mac, Xcode und ein Personal Team. Das Projekt allein ermöglicht keine Installation nur mit einem iPhone. Die gemeinsame Sammlung benötigt eine App-Group-Berechtigung; deren kostenlose Bereitstellung mit einem Personal Team wurde hier nicht bestätigt.
