# Prüfstand vom 11. Oktober 2026

Das Paket enthält Quellcode, ein Xcode-Projekt und zwei Schemes. Das Quellcode-Paket enthält keine Signatur, Zugangsdaten oder persönlichen Texte. Eine separat herunterladbare, unsignierte iPhone-IPA wurde mit Apples SDK gebaut und muss vor der Installation signiert werden.

## Ausgeführt

- Speicherkern mit Swift 6.2.3 unter Linux im Swift-5-Sprachmodus kompiliert.
- `swift test`: 24 XCTest-Tests bestanden, keine Fehler. Geprüft wurden unter anderem echte gleichzeitige Dateizugriffe, atomare Änderungen, Unicode und Zeilenumbrüche, Suche, Favoriten, Web-Sicherungen, ungültige Importe und Erhalt beschädigter Dateien.
- Swift-Syntaxprüfung für App, Tastatur und Widget mit `swiftc -frontend -parse` bestanden. Diese Prüfung prüft keine Apple-API-Typen.
- Xcode-Projekt mit Python erzeugt und mit Foundation als OpenStep-Plist eingelesen: fünf Targets, 123 Objekte. Projektverweise, Eingabedateien und Abhängigkeitszyklen geprüft.
- XML-Plists und die beiden gemeinsamen Schemes eingelesen; wiederholte Projekterzeugung liefert dieselben Dateien.
- ZIP-Inhalt und SHA-256-Prüfsummen beim Verpacken geprüft.

- GitHub-Mac: Xcode 16.4 / Swift 6.1.2, SDK 18.5, erfolgreicher Simulator-Build und iPhone-Gerätearchiv für **Textablage** mit Tastatur. [Build 38155451294](https://github.com/norobbc-wq/Textablage/actions/runs/38155451294), Commit `09e2c1a441031aedabcc8ba9bc127096676a93f2`. Die 24 Speichertests bestehen auch auf dem Mac.
- Echte IPA nach Download geprüft: App und Tastatur mit ARM64/iPhoneOS, minimale iOS-Version 17.0, ZIP-Integrität, ausführbare Dateirechte, SHA-256 und Status `requiresSigningBeforeInstallation: true`.
- IPA SHA-256: `a42fbf07305d2b1f76c5491aad4b97749b6f8d1ff117a03d3e0581e18a955d99`.
- IPA-Verpackung außerdem mit 19 temporären Test-/Fehlerfällen geprüft; diese Testdateien werden nicht ausgeliefert.

- Auch **Textablage-Gemeinsam** mit App, Tastatur und Widget hat Simulator-Build, Gerätearchiv und IPA-Verpackung bestanden: [Build 38156678536](https://github.com/norobbc-wq/Textablage/actions/runs/38156678536). Die separate IPA enthält drei geprüfte ARM64/iPhoneOS-Bundles, alle mit Mindestversion iOS 17.0.
- Widget-IPA SHA-256: `0bdf3d6f949c607a955f2e588feb4bc8f70f42d227d8e6bba11b32d133e34d05`.

## Noch offen

- Signieren, Installieren und Ausführen auf einem iPhone.
- Bedienung, Darstellung bei großen Schriften, Tastaturgröße und Verhalten in verschiedenen Host-Apps.
- iOS-Einfügeberechtigungen, freiwillige Übernahme beim Öffnen und Reihenfolge von Widget-Link und App-Aktivierung.
- App-Group-Berechtigung und gemeinsamer Speicher in der zusätzlichen Variante mit Widget.

Die kostenlose Variante benötigt zum regulären Installieren einen Mac, Xcode und ein Personal Team. Ein vorhandenes IPA-Installationswerkzeug auf dem iPhone muss eine gültige Apple-Signatur bereitstellen; der Entwicklermodus allein ersetzt diese nicht. Die gemeinsame Sammlung benötigt eine App-Group-Berechtigung; deren kostenlose Bereitstellung mit einem Personal Team wurde hier nicht bestätigt.
