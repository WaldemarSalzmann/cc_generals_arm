# Generals Zero Hour auf dem ODROID-N2+ – Vorgehen und Erkenntnisse

Bericht über die Portierung von *Command & Conquer Generals – Die Stunde Null* auf einen ODROID-N2+
(Oktober 2026). Ziel war, das Spiel auf vier Kiosk-Geräten nativ laufen zu lassen, ohne Windows-Emulation.

## Ausgangslage

| | |
|---|---|
| Gerät | ODROID-N2+ (Amlogic S922X: 4× Cortex-A73 + 2× Cortex-A53, 4 GB RAM, eMMC) |
| GPU | Mali-G52 MC2 (Bifrost v7), Mesa-Treiber Panfrost (OpenGL) / PanVK (Vulkan) |
| System | DietPi auf Debian 13 (Trixie), arm64, GCC 14.2, CMake 3.31, Mesa 25.0.7 |
| Einsatz | Chromium-Kiosk; Spiele werden bei Bedarf gestartet und geben den Bildschirm danach zurück |
| Spieldaten | Generals und Zero Hour aus Steam (deutsche Fassung) |

EAs veröffentlichter Quellcode ist ein Win32-Programm für DirectX 8 und Visual C++ 6. Lauffähig auf Linux ist er
nur über Community-Forks.

## 1. Sackgasse Vulkan

Die bekannten Linux-Portierungen (z. B. GeneralsX) übersetzen DirectX über **DXVK** nach Vulkan. Auch der hier
verwendete Fork rendert unter Linux standardmäßig über Vulkan.

**Debian-Mesa 25.0.7:** PanVK verweigert die Mali-G52 (Bifrost v7) ganz. Erst mit
`PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` meldet es sich – als nicht konformes **Vulkan 1.0.305**.

**Selbst gebautes Mesa 26.2.6** (neueste stabile Version, nur PanVK, getrennt vom System-Mesa installiert):
weiterhin nur **Vulkan 1.0.354**, experimentell. Abgleich mit den Pflichtfunktionen von DXVK:

- **21 Pflicht-Features fehlen:** fillModeNonSolid, geometryShader, multiDrawIndirect, multiViewport,
  shaderClipDistance, shaderCullDistance, textureCompressionBC, shaderDrawParameters, descriptorIndexing,
  descriptorBindingSampledImageUpdateAfterBind, descriptorBindingUpdateUnusedWhilePending,
  descriptorBindingPartiallyBound, runtimeDescriptorArray, samplerMirrorClampToEdge, computeFullSubgroups,
  maintenance4, subgroupSizeControl, robustBufferAccess2, nullDescriptor, maintenance5, maintenance6
- **Fehlende Erweiterungen:** VK_KHR_maintenance5, VK_KHR_maintenance6, VK_EXT_robustness2

Geometry Shader bietet auch der OpenGL-Treiber nicht (dafür wäre OpenGL 3.2 nötig); die übrigen Lücken hat PanVK
für Bifrost schlicht noch nicht umgesetzt. Sie selbst zu schließen, wäre Treiberentwicklung im Umfang von Monaten.
**Ergebnis: Vulkan/DXVK ist auf diesem Gerät nicht machbar.** Das
Test-Mesa wurde danach vollständig entfernt.

## 2. Der Weg über OpenGL

Panfrost bietet auf der Mali-G52 **OpenGL 3.1** (Core und Compatibility) und **OpenGL ES 3.1**, inklusive
S3TC/DXT-, BPTC- und RGTC-Texturen – Generals nutzt DXT-Texturen.

Der Fork [bobtista/GeneralsGameCode](https://github.com/bobtista/GeneralsGameCode) ersetzt DirectX 8 durch
[bgfx](https://github.com/bkaradzic/bgfx), eine Render-Abstraktion mit Backends für D3D11/12, Vulkan, Metal und
OpenGL, und bringt einen nativen Linux-Build mit (SDL3, OpenAL, minimales FFmpeg). Zur Laufzeit konnte man
OpenGL schon auswählen (`GGC_BGFX_RENDERER=gl`), es fehlte aber ein Build-Ziel, das die Shader als GLSL übersetzt.
Das ergänzt `patches/00-gl-renderer.patch`:

- `GGC_BGFX_RENDERER=gl` als gültiger Wert in `cmake/render-backend.cmake`
- Shader-Übersetzung mit bgfx' `shaderc`, Profil `140` (GLSL 1.40 = OpenGL 3.1)
- Einbindung der 27 GLSL-Shader-Header und OpenGL als Standard-Renderer in `BgfxBackend.cpp`

Der Renderer-Code des Forks berücksichtigt die OpenGL-Unterschiede (Tiefenbereich −1…1, Texturursprung unten
links) bereits über bgfx' Fähigkeitsabfrage (`homogeneousDepth`, `originBottomLeft`).

## 3. Bauen auf dem Gerät

Gebaut wurde nativ auf dem ODROID, als systemd-Einheit mit `Nice=10`, damit der Kiosk nebenher weiterläuft:

- 4 GB Auslagerungsdatei und 3 parallele Jobs als Puffer für den knappen Arbeitsspeicher
- Ablauf: Build-Pakete (~2 min), minimales FFmpeg 6.1.2 (~5 min), CMake-Konfiguration inkl. Download von bgfx,
  SDL3 und OpenAL (~2 min), Kompilieren (2535 Schritte)
- Der Kompilierlauf des Spielcodes dauerte nach den Korrekturen **49 Minuten**; insgesamt etwa 1–1,5 Stunden
- Ergebnis: `generalszh` (205 MB, nicht gestrippt) plus 49 MB mitgelieferte Bibliotheken

Der Fork wurde für Linux bisher nur auf x86-64 gebaut (CI auf Ubuntu). Auf ARM64 mit GCC 14 traten diese
Probleme auf, in der Reihenfolge ihres Auftretens:

| # | Symptom | Ursache | Korrektur |
|---|---|---|---|
| 01 | Hunderte Fehler in `<cmath>`, `streambuf_iterator.h` („`__msg_inc_istreambuf` is not a member of `__gnu_debug`“) | Die Profiling-Bibliothek setzt `debug/Include` als `-I`-Pfad; dessen `debug/debug.h` verdeckt das gleichnamige Header von libstdc++, das GCC 14 über `<cmath>` einbindet | Pfad nur noch über `-iquote` (gilt nur für `#include "…"`) |
| 02 | „`wcspbrk` was not declared“ im vorkompilierten Header der Grundbibliothek – blockiert fast alles | `#include <wchar.h>` fehlt; auf x86 kam es zufällig über andere Header mit | Include ergänzt in `stringex.h` |
| 03 | (kein Fehler – vorsorglich) | Auf ARM ist `char` vorzeichenlos, auf x86 vorzeichenbehaftet; der Spielcode von 2003 geht von x86 aus | `-fsigned-char` für den Spielcode (nicht für die Fremdbibliotheken) |
| 04 | Warnung „no return statement in function returning non-void“ | `PrimitiveAnimationChannelClass::Set_Time()` hat kein `return`; GCC darf bei Optimierung annehmen, dass das Ende nie erreicht wird – auf ARM ein realistischer Absturz | `return m_Time;` |
| 05 | 439 × „undefined reference“ beim Linken (`TheKey_playerName`, `MapObject::TheMapObjectListPtr`, …) | Die Spielbibliotheken hängen ringförmig voneinander ab (`z_gameengine` braucht Symbole aus `z_gameenginedevice`, das vor ihm gelinkt wird); GNU ld durchsucht statische Bibliotheken nur einmal | Link-Regel mit `-Wl,--start-group … --end-group` |

Nach Patch 05 war das Programm gebaut. Zwei weitere Fehler zeigten sich erst beim Start:

| # | Symptom | Ursache | Korrektur |
|---|---|---|---|
| 06 | `bgfx FATAL: Failed to compile shader … no function with name 'textureGradARB'`, Log: „renderer=OpenGL 2.1“ | bgfx legt ohne Vorgabe einen OpenGL-2.1-Kontext an und schreibt die Shader dann auf GLSL 1.20/1.30 mit ARB-Namen um | `BGFX_OPENGL_VERSION=31`: OpenGL-3.1-Kontext über EGL, Shader laufen als GLSL 1.40 |
| 07 | Derselbe Fehler, jetzt unter OpenGL 3.1 | Der GLSL-Optimierer in `shaderc` übersetzt `texture2DGrad` in der 1.40-Ausgabe zu `textureGradARB` – ein Name, den kein Treiber kennt (betrifft das Anisotropie-Sampling in `fs_uber`) | Beim Laden der Shader wird `textureGradARB` durch `textureGrad   ` ersetzt (gleiche Länge, damit die Längenfelder im Shader-Binärformat gültig bleiben) |

## 4. Spieldaten

- Die `.big`-Archive bleiben getrennt in `/opt/cnc-gamedata/generals` und `/opt/cnc-gamedata/zerohour`; der Fork
  findet sie über `CNC_GENERALS_INSTALLPATH` und `CNC_ZH_INSTALLPATH` (Zero Hour hat Vorrang bei gleichen Namen
  wie `Music.big`, `PatchData.big`).
- Neben dem Programm braucht das Spiel die losen Dateien `Data/Scripts`, `Data/Cursors`, `Data/Movies` und
  `Data/<Sprache>/Movies`. Die Sprache erkennt der Fork selbst (Log: „detected language 'german' from GermanZH.big“).
- Kopie über plink-Tar-Strom vom PC: ~2,6 GB in etwa 7 Minuten.

## 5. Leistung

Die GPU ist der Engpass: Die Spiel-Threads lagen bei 10–18 % CPU, der GPU-Takt fest auf 800 MHz.

| Szene | Einstellung | fps |
|---|---|---|
| Hauptmenü (Seeschlacht über Wasser) | 1920×1080, Standard des Forks (4× MSAA, Schatten-Map, Post-Processing) | 4 |
| Hauptmenü | 1920×1080, `device/Bgfx.ini` | 9 |
| Hauptmenü | 1280×720, `device/Bgfx.ini` | 11 |
| Gefecht, Spielbeginn | 1280×720, `device/Bgfx.ini` | 24–25 (Spiellogik max. 30) |

Erkenntnisse dazu:

- Den größten Gewinn bringen das Abschalten von MSAA und des Szenen-Framebuffers
  (`BgfxNoSceneFramebuffer = Yes`, damit entfällt jede Nachbearbeitung) und der Verzicht auf die Schatten-Map.
- Die Auflösung in `Options.ini` ignoriert der Fork: Er nutzt immer die volle Größe des Bildschirms. Deshalb stellt
  der Starter das HDMI-Signal per `xrandr` auf 1280×720 um; der Fernseher skaliert. Der Kiosk startet danach mit
  seinem eigenen X-Server wieder in 1080p.
- Das Hauptmenü ist mit der Dauerschlacht über spiegelndem Wasser deutlich schwerer als ein normales Gefecht.

## 6. Kiosk-Integration

- `generals-zh` startet sich selbst als systemd-Einheit (überlebt das Schließen der SSH-Sitzung), beendet die
  Kiosk-Sitzung auf tty1, startet einen eigenen X-Server mit dem Spiel und holt den Kiosk per `ExecStopPost` zurück
  – egal, wie das Spiel endet. (Ein `trap` im Skript reicht dafür nicht: Er wird bei `systemctl stop` mit beendet.)
- Das fertige Spiel wird einmal gebaut und als Archiv (~107 MB) auf die anderen Geräte verteilt; Laufzeit-
  Bibliotheken sind auf einem Chromium-Kiosk bereits vorhanden.
- Installiert und geprüft auf vier Geräten; je Gerät ~3 GB (593 MB Programm + lose Dateien, 2,6 GB Archive).

## 7. Beobachtungen und offene Punkte

- Das Hauptmenü erscheint erst, wenn die Maus bewegt wird.
- Im deutschen Einzelspieler-Menü fehlt der Text für den vom Fork neu hinzugefügten Knopf („MISSING:
  'GUI:CustomMission'“).
- Ton über HDMI ist noch nicht geprüft (OpenAL startet, ALSA-Karte `axg-sound-card`).
- Generals braucht eine Maus; eine Controller-Steuerung gibt es nicht.
- Längere Partien und große Schlachten sind noch nicht vermessen.
- Möglich: Programm strippen (Debug-Informationen entfernen), OpenGL-ES-3.1-Pfad testen,
  die Korrekturen 01–05 und 07 dem Fork vorschlagen (sie betreffen jeden ARM64- bzw. GCC-14-Build).
