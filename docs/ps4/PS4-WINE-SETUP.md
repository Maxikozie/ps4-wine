# PS4 Wine-port — setupgids

**Doel:** het ontwerp van prospero-win (Wine op de PS5) porten naar een jailbroken **PS4 Slim** (GoldHEN). Zo draait *Vampire: The Masquerade – Bloodlines* (GOG + Unofficial Patch) native. Gebouwd met Claude Code.

---

## 0. Eerst doen

- Reageer op **issue #455** van prospero-win of contacteer **plastikman**. Hij heeft prospero-win al op een PS4 Pro draaien (Oblivion, Fallout NV). Met zijn Orbis-patchset spaar je maanden werk.
  → https://github.com/mpereiraesaa/prospero-win/issues/455

---

## 1. Hardware en netwerk

| Wat | Setup |
|---|---|
| PS4 Slim | Naast je pc. Vast IP **192.168.8.184** (DHCP-reservatie op de Flint 2) |
| Netwerk | Kort kabeltje in de LAN-poort van de AP. Anders de 60 Mbps-kabel. Wifi 5 GHz alleen als laatste optie |
| Beeld | PS4 op een tweede HDMI-ingang van je monitor |
| Capture stick | USB HDMI-capture (±€10–15). Toont het PS4-beeld op Kubuntu, en Claude Code kan er zelf screenshots mee nemen |
| Input | DS4 via USB, plus een USB-toetsenbord en -muis voor games |

Stabiliteit is belangrijker dan snelheid. Payloads en klog zijn piepklein, en Bloodlines (±4 GB) kopieer je maar één keer.

---

## 2. PS4 klaarzetten

1. GoldHEN draait en de firmware is **≤ 13.52**. Laat de Pi-hole DNS-blokkering aan, zodat de PS4 niet kan updaten.
2. Zet in GoldHEN aan: **FTP (poort 2121)**, **BinLoader (poort 9090)** en **klog**. Zet ook de **Debug Settings** aan, nodig om fake PKG's te installeren.
3. Test vanaf Kubuntu:
   ```bash
   nc -zv 192.168.8.184 2121   # FTP
   nc -zv 192.168.8.184 9090   # BinLoader
   ```

---

## 3. Kubuntu en Claude Code

```bash
claude update
sudo apt install git gh ffmpeg v4l-utils
```

- Gebruik de **CLI in Konsole**, niet de Code-tab van de desktop-app. Die is nog beta op Linux.
- Kijk in `/model` of er bij Fable **"Requires usage credits"** staat. Zo ja, dan kost Fable echt geld en plan je met **Opus 5.5 op xhigh**.
- Test de capture stick:
  ```bash
  v4l2-ctl --list-devices                               # zoek het device, bv. /dev/video0
  ffmpeg -f v4l2 -i /dev/video0 -frames:v 1 shot.png    # één screenshot van het PS4-beeld
  ```
- De PS4-toolchain (OpenOrbis, clang/lld, mingw-w64, meson, …) laat je **Claude Code installeren in milestone a**.

---

## 4. Repo opzetten

```bash
mkdir ps4-wine && cd ps4-wine && git init
mkdir -p docs/ps4 refs scripts/ps4
echo "refs/" > .gitignore

cd refs
git clone https://github.com/mpereiraesaa/prospero-win
git clone https://github.com/orbis-ports/mesa-ps4
git clone https://github.com/orbis-ports/orbis-compat
git clone https://github.com/orbis-ports/ps4-mesa-docs
git clone https://github.com/alechurri/nx-on-orbis
git clone https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain
git clone https://github.com/leolobato/playden-ps5
cd ..
```

- Plak het researchrapport in **`docs/ps4/RESEARCH.md`**.
- Zet een **LGPL-2.1**-licentie in de repo, omdat je code uit prospero-win hergebruikt.
- Optioneel: `gh repo create ps4-wine --private --source . --push`

**Regels voor `refs/`:**
- Alleen-lezen, alleen ter studie.
- **nx-on-orbis is GPL-3**: nooit code uit kopiëren.
- prospero-win is LGPL: hergebruik mag.

---

## 5. Sessie 1: plannen (Fable)

```bash
cd ps4-wine
claude --model fable --effort high
```

Druk op **Shift+Tab** om naar plan mode te gaan, en plak dan deze prompt:

```text
Read docs/ps4/RESEARCH.md and everything in refs/.

Goal: a PS4 (Orbis OS, OpenOrbis toolchain, GoldHEN) Wine runtime based on
prospero-win's design that runs 32-bit D3D9 Windows games. Target: Vampire:
The Masquerade – Bloodlines (GOG + Unofficial Patch) on my PS4 Slim.

This is homebrew porting on a console I own, using the existing GoldHEN
jailbreak. No exploit development.

Environment:
- PS4 Slim at 192.168.8.184: GoldHEN FTP on 2121, BinLoader on 9090, klog enabled.
- Build host: Kubuntu (this machine).
- PS4 screen is visible through a USB HDMI capture device; use ffmpeg to grab
  frames for visual pass/fail checks.
- I launch apps on the PS4 by hand; everything else (build, package, deploy,
  logs, screenshots) you do yourself.

Use C to match Wine, bash for tooling.

Produce:
1. CLAUDE.md — goal, hard rules (repo is GPL-3.0: code from refs/ may be reused, with source repo +       file noted in a comment and in THIRD_PARTY.md; code meant for upstream PRs to prospero-win must not contain nx-on-orbis code)
2. docs/ps4/ARCHITECTURE.md — what carries over from prospero-win, what gets
   rewritten for Orbis, and how the subsystems fit together.
3. docs/ps4/MILESTONES.md — milestones a–h, each with ONE scriptable pass/fail check.
4. docs/ps4/LOG.md — empty, with the line format for console runs.
5. Skeleton scripts in scripts/ps4/: build, pkg, deploy (FTP), logs (klog),
   shot (ffmpeg capture).

Don't write port code yet.
```

Daarna lees je de plannen na, stuur je bij waar nodig, en commit je.

---

## 6. Bouwsessies (één per milestone)

```bash
claude --model opus        # Opus 5.5, standaard op medium effort
```

Begin elke sessie met: *"Work on milestone X from docs/ps4/MILESTONES.md."*

**De loop:**

1. Claude bouwt en test eerst op de host.
2. Claude packaget en deployt naar 192.168.8.184.
3. **Jij start de app op de PS4** met de DS4.
4. Claude leest de klog en neemt een screenshot via de capture stick.
5. Claude voegt één regel toe aan `docs/ps4/LOG.md`, bijvoorbeeld:
   `2026-11-02 | b | build 7 | PASS | triangle visible, Vulkan 1.3, maintenance5 ok`
6. Commit.

Is de milestone gehaald, doe dan `/clear` en start een nieuwe sessie voor de volgende.

---

## 7. Modellen en effort

| Fase | Model | Effort |
|---|---|---|
| Architectuur en plan | Fable 5.1 (of Opus 5.5 als Fable credits kost) | high (Opus: xhigh) |
| Milestones bouwen | Opus 5.5 | medium |
| Crashes en hangs debuggen | Opus 5.5 | high, of `ultrathink` in de prompt |
| Root cause vinden als je vastzit | Fable 5.1 | high |
| Scripts, packaging, docs | Sonnet 5.5 (subagent) | standaard |

**Geen `opusplan`** gebruiken: dat voert uit op Sonnet. Bij low-level systeemcode kost elke fout een extra PS4-testrun.

---

## 8. Problemen en tips

- **Viel hij terug naar Opus 4.8?** Dat is de cybersecurity-classifier: woorden als jailbreak, kernel of sandbox kunnen hem triggeren. Zet hem terug met `/model`.
- **Permissies:** kies bij build- en deploycommando's "don't ask again". Dan bouwt `.claude/settings.json` zichzelf op.
- **Context:** houd `CLAUDE.md` kort, details horen in `docs/ps4/`. Gebruik één sessie per milestone.
- **Meerdere hypotheses per testrun:** laat Claude in één console-build meerdere dingen tegelijk testen, met één machine-leesbare resultaatregel per run.
- **Vastgelopen op dezelfde crash?** Laat de logs en `LOG.md` analyseren door een Fable-sessie in plan mode.

---

## 9. Milestones

| # | Milestone | Pass/fail |
|---|---|---|
| a | Toolchain + hello-world PKG met klog | Logregel komt binnen via klog |
| b | Vulkan-driehoek via mesa-ps4 + capability dump | Driehoek op scherm (screenshot); Vulkan 1.3, `maintenance5`, `robustness2` gemeld |
| c | Wine-core start een 64-bit console-exe | `hello.exe` print via netlog; wineserver blijft draaien |
| d | Minesweeper / Notepad (GDI) | Minesweeper speelbaar met DS4 |
| e | 64-bit D3D11-sample via DXVK 2.6.2 | Frame gepresenteerd, geen GPU-hang |
| f | 32-bit exe via translator, daarna native WoW64-probe | Space Cadet Pinball draait |
| g | 32-bit D3D9 Source-game (HL2) met Vulkan-batching | Stabiel speelbaar, crossings per frame gelogd |
| h | **Bloodlines** (GOG + UP) | Nieuw spel → Santa Monica-hub, save/load, sessie van 30 min |

Sla er geen over: elke milestone test de basis van de volgende.

---

## 10. Vaste regels

- Gebruik de **GOG-versie** van Bloodlines (DRM-vrij) met de Unofficial Patch.
- **Geen gamebestanden** in de repo.
- **Geen gelekte Sony-SDK**: alleen OpenOrbis.
- **Geen exploitwerk**: je gebruikt de bestaande GoldHEN-jailbreak.
- Pin **DXVK 2.6.2**. Nieuwere versies vragen Vulkan-features die de PS4-GPU niet heeft.
