**v01 — 2026-05-08 09:00 PT**

# MikePDFViewer v6 — Rich Markdown Reader

**Plan version:** v01 — 2026-05-08 09:00 PT
**Author:** Claude (Opus 4.7) for Michael Ashe
**Status:** Initial design — needs Mike's review before any code

---

## 1. Goal

In v5.8.4, MikePDFViewer can open `.md` files but the rendering is utilitarian — one fixed style, no theming, no reading-comfort controls. v6 turns that into a proper "MD reading experience" so Mike can read long markdown documents (handover files, plan docs, transcripts, README files) with the kind of comfort Typora, iA Writer, and Marked 2 provide.

This is **viewer-only**. No editing. No Markdown source mode. The viewer just makes already-written `.md` files easier to read.

---

## 2. What's out there (research summary)

These are the meaningful Mac/Web markdown reader products. I drew the v6 feature list from common patterns across them.

| Product | Strengths relevant to a reader | What we'd want to copy |
|---|---|---|
| **Typora** | "Live" rendering, ~10 built-in themes (GitHub, Newsprint, Pixyll, Whitey, Night, etc.), custom CSS support, math + Mermaid + code highlighting | Theme switcher; CSS-driven styling |
| **iA Writer** | Focus mode (current sentence highlighted, rest dimmed), typewriter scrolling (cursor stays centered), 3 monochrome typefaces (Mono/Duo/Quattro), reading-time estimate, word/char count | Focus mode; reading-time stat; typewriter scrolling (less critical for read-only) |
| **Marked 2** | Preview-only (paired with external editor), 24+ themes, custom CSS, statistics panel (keyword density, reading level), TOC sidebar with click-to-jump, find-in-document | Theme variety; TOC sidebar; statistics |
| **Obsidian** | Reader/edit toggle, customizable line width, multi-color highlighting, outline panel | Reader-mode polish; outline panel |
| **MacDown** (open source) | Split source/preview, dozens of themes via CSS bundles | CSS theme architecture |
| **GitHub web reader** | Familiar GitHub style, anchor links, code blocks with copy button, table-of-contents auto-generated for long files | Auto TOC; code copy button; familiar default |
| **Bear** | Theme + typography combos (3 fonts × 4 themes), reading width slider, focus mode | Typography presets; width slider |
| **MarkText** (open source) | Multiple themes, focus + typewriter modes | Open implementation reference |
| **Quiver / Mou** | Custom CSS injection, font + line-height controls | Granular font controls |

Open-source reference repos worth a closer look during implementation:
- **github.com/marked-app/Marked** — proprietary but Marked's CSS theme structure is well-documented in their docs.
- **github.com/marktext/marktext** — Electron app, MIT licensed, has 30+ themes as CSS bundles we can study.
- **github.com/MacDownApp/macdown** — Objective-C, MIT, mature MD-rendering pipeline using bundled CSS.
- **github.com/iaolo/iA-Fonts** — iA's monospace + duospace + quattrospace fonts, free for personal use, would let us match iA Writer's look without licensing.
- **github.com/sindresorhus/github-markdown-css** — the canonical "looks like GitHub" stylesheet.

---

## 3. Goals & non-goals

### v6 in-scope
- Switch between built-in reading **themes** (GitHub, Newsprint, Sepia, Dark, High-contrast, Mono).
- Adjust **typography**: font family (system / serif / mono / iA fonts), font size, line spacing, content width.
- **Focus mode**: dim everything except the paragraph currently in the middle of the viewport.
- **TOC sidebar**: auto-generated from headings, click to jump.
- **Reading stats**: word count, estimated reading time, current section name.
- **Find in document** (already in app for PDFs; extend to MD).
- **Anchor links** continue to work (already in v5.8.2).
- **External links** open in browser (already works).
- **Theme/typography settings persist** across launches per file extension (UserDefaults).
- **Render-as-PDF** (already in v5.8) respects the current theme — saved PDF looks like the chosen theme.

### Out of scope for v6
- Editing markdown source.
- Live-reload watching the file on disk for changes.
- Math (LaTeX / KaTeX) — defer to v6.1 if Mike wants it.
- Mermaid diagrams — defer to v6.1.
- Custom user-supplied CSS — defer to v6.2 (most users won't use it).
- Wiki-links / cross-document linking.
- Plugins.
- Vault / multi-file management.

---

## 4. Architecture

### 4.1 Switch from NSTextView to WKWebView

Today's `MarkdownView` uses `NSTextView` with an `NSAttributedString`. That works but limits us — themes, custom typography, and focus mode are all dramatically simpler in HTML+CSS than in attributed-string land.

v6 keeps `NSTextView` rendering as a fast fallback ("Quick view") but adds a new **`MarkdownReaderView`** built on `WKWebView`. The MD source is rendered to HTML once, then the WebView swaps stylesheets on theme change without re-parsing.

```
.md file
   │
   ├─→ MarkdownDocument (existing)
   │       ├── .styledAttributedString()  → NSTextView   (Quick view, untouched)
   │       └── .renderedHTML()            → WKWebView    (NEW Reader view)
   │
   └─→ User picks Quick / Reader via toolbar segment control
```

### 4.2 Why WKWebView is the right host

- CSS does theming for free — one stylesheet per theme, swap with `document.documentElement.className = "theme-sepia"`.
- Typography changes (font / size / line-height / width) are CSS variables — change once in `:root`, the whole document reflows.
- Focus mode is a CSS rule (`.focus-mode p:not(.focused) { opacity: 0.3 }`) plus tiny JavaScript to track the paragraph nearest the viewport center.
- TOC + click-scroll already works via `#anchor` URLs.
- Reuses `HTMLToPDFRenderer` for "Render as PDF" with the user's current theme baked in — themed PDF export comes free.

### 4.3 Markdown → HTML

Reuse the same parser code we already have for `MarkdownToPDFConverter` — it walks `AttributedString(markdown:)` runs and emits clean HTML (h1-h6, p, ul, ol, li, pre, code, blockquote). Pull that emitter out of `MarkdownToPDFConverter.swift` into a shared `MarkdownToHTML.swift`.

```
MarkdownToHTML.swift  (NEW — extracted from MarkdownToPDFConverter)
  └── func render(_ source: String) -> String   // body HTML, no <html>/<head>
```

`MarkdownToPDFConverter` and the new `MarkdownReaderView` both call into it.

### 4.4 Theme system

A `MarkdownTheme` enum describes each preset. Each preset is a struct with:
- A unique CSS class name applied to `<html>` (e.g. `theme-github`).
- A bundled CSS file (or inline string) defining colors and structural styling.
- Display name for the menu.

```swift
enum MarkdownTheme: String, CaseIterable {
    case github          // canonical GitHub look
    case newsprint       // serif, narrow column, warm paper background
    case sepia           // warm, slightly tinted, e-reader feel
    case dark            // dark background, off-white text
    case highContrast    // pure black on white, larger spacing
    case mono            // iA-Writer-style monospace
}
```

Stored in UserDefaults keyed by `"markdown-theme"`.

### 4.5 Typography controls

Five orthogonal settings, each persisted:

| Control | Range | Default | UserDefaults key |
|---|---|---|---|
| Font family | system / serif / mono / iA Quattro | system | `markdown-font-family` |
| Font size | 11pt – 22pt (1pt steps) | 14pt | `markdown-font-size` |
| Line spacing | 1.3 – 2.0 | 1.55 | `markdown-line-height` |
| Content width | 60ch / 72ch / 90ch / full | 72ch | `markdown-content-width` |
| Paragraph spacing | tight / normal / loose | normal | `markdown-para-spacing` |

Each maps to a CSS variable on `:root` (e.g. `--md-font-size`, `--md-line-height`). The active theme stylesheet uses those variables, so theme + typography are independent.

### 4.6 Focus mode

CSS:
```css
.focus-mode p, .focus-mode li, .focus-mode blockquote {
    opacity: 0.25;
    transition: opacity 0.2s ease;
}
.focus-mode .md-focused {
    opacity: 1.0;
}
```

JS (~30 lines): on scroll, find the block-level element nearest the vertical viewport center, add `.md-focused` class to it, remove from siblings. Throttled to 100ms.

Toggle via toolbar button + Cmd+Shift+F shortcut.

### 4.7 TOC sidebar

The MD-to-HTML emitter already detects headings. While emitting, it builds a parallel JS array of `{level, text, id}` objects and inlines it as `window.__mdTOC = [...]` at the top of the HTML body.

A SwiftUI sidebar (`MarkdownTOCSidebar`) shows the TOC as a tree. Clicking sends `webView.evaluateJavaScript("location.hash = '#anchor'")` — instant scroll, native browser behavior.

Sidebar can be toggled (already established UI pattern with thumbnail and EML attachments sidebars).

### 4.8 Reading stats

While generating the HTML, count words via simple whitespace tokenization. Reading time = `ceil(words / 220)` minutes. Display in toolbar status area:

> **handover.md** — 2,141 words · ~10 min read · §3 of 11

Current-section detection uses the same scroll observer as focus mode.

### 4.9 Settings UI

Two surfaces:
- **Toolbar segment**: Quick / Reader (picks rendering mode).
- **Reader settings popover** (gear icon, only visible in Reader mode): theme picker + typography sliders. Live preview as user adjusts.

```
┌────────────────────────────────────┐
│ Reading Settings                    │
├────────────────────────────────────┤
│ Theme                               │
│ [GitHub▼]                           │
│                                     │
│ Font            [System ▼]          │
│ Size            ─────●───── 14pt    │
│ Line spacing    ────●────── 1.55    │
│ Width           60 [72] 90 Full     │
│ Paragraph gap   tight [normal] wide │
│                                     │
│ ☐ Focus mode (⇧⌘F)                  │
└────────────────────────────────────┘
```

---

## 5. New files

| File | Purpose |
|---|---|
| `MarkdownToHTML.swift` | Extracted from MarkdownToPDFConverter — markdown → body HTML, plus TOC array. |
| `MarkdownReaderView.swift` | WKWebView-based reader (replaces MarkdownView in Reader mode). |
| `MarkdownTheme.swift` | Theme enum + CSS bundle resolver. |
| `MarkdownTypography.swift` | Typography settings model + UserDefaults persistence. |
| `MarkdownReaderSettings.swift` | SwiftUI popover with theme/typography controls. |
| `MarkdownTOCSidebar.swift` | SwiftUI sidebar showing the TOC tree. |
| `Resources/MarkdownThemes/*.css` | One CSS file per theme (github.css, newsprint.css, sepia.css, dark.css, high-contrast.css, mono.css). |
| `Resources/focus-mode.js` | Tiny script for nearest-paragraph detection. |

## 6. Modified files

| File | Change |
|---|---|
| `MarkdownToPDFConverter.swift` | Use `MarkdownToHTML` instead of inline emission; thread theme through. |
| `MarkdownView.swift` | Stays as Quick mode renderer. |
| `ContentView.swift` | Add `markdownMode` state (Quick/Reader); render correct view; toolbar additions. |
| `MikePDFViewerApp.swift` | Add **View → Markdown Mode** menu (Quick / Reader); **View → Markdown Theme** submenu. |
| `MikePDFViewer.xcodeproj/project.pbxproj` | Register new files + Resources folder. |

---

## 7. Phased build plan

### Phase 1 — Refactor & WKWebView shell (1 h)
Extract `MarkdownToHTML.swift` from `MarkdownToPDFConverter`. Verify existing PDF render still works.

### Phase 2 — `MarkdownReaderView` with one default theme (2 h)
Build the WKWebView host with GitHub-style CSS bundled. Wire it to ContentView under a feature toggle. Verify rendering quality against current Quick view.

### Phase 3 — Theme switcher + CSS bundles (2 h)
Create the six CSS theme files. Add the `MarkdownTheme` model. Wire to a `View → Markdown Theme` submenu and a popover-level picker. Persist choice in UserDefaults.

### Phase 4 — Typography controls (2 h)
Add `MarkdownTypography` model with the five settings. Build the settings popover UI. Wire CSS variables. Persist all choices.

### Phase 5 — Focus mode (1 h)
Add `focus-mode.js`, the CSS rule, the toolbar toggle, and the keyboard shortcut.

### Phase 6 — TOC sidebar + reading stats (2 h)
Build `MarkdownTOCSidebar` and the stats display. Wire to existing sidebar pattern.

### Phase 7 — Render-as-PDF respects theme (1 h)
Update `MarkdownToPDFConverter` to bake in the user's current theme and typography settings before generating the PDF.

### Phase 8 — Polish & device test (1 h)
Edge cases (empty .md, very long .md, code-heavy, image-heavy). Bump version to 6.0. Device test all phases together. Update handover.

**Total estimate:** ~12 hours of Claude work, plus device testing per phase.

---

## 8. Default behavior decisions

These are choices Mike should weigh in on before implementation. Reasonable defaults proposed for each.

| Question | Proposed default |
|---|---|
| Default mode when opening a .md (Quick or Reader)? | Reader. Quick is for "I just want raw text view" power users. |
| Default theme? | GitHub — most familiar to Mike. |
| Default font? | System (San Francisco). |
| Per-file or global theme? | Global. One theme across all .md files. (Per-file gets messy fast.) |
| Save TOC sidebar visibility per-file? | No — one global preference. |
| Should "Find" use NSTextView's Find or WKWebView's? | WKWebView's native Cmd+F (gives in-page highlighting for free). |
| Default typography presets (font size etc.)? | 14pt body, 1.55 line-height, 72ch width — matches typical "book reading" comfort. |
| Should Focus Mode be on by default? | Off. Surprising default. Easy to toggle on. |

---

## 9. Risks & open questions

1. **WKWebView scroll smoothness** with very long markdown (10k+ lines). Mitigation: virtualize at the renderer level, or show a "this is a long file, give it a moment" placeholder for files over 5 MB.

2. **iA fonts licensing** — iA's Mono/Duo/Quattro fonts are free for personal use under SIL OFL but the bundle is ~3 MB. We can include them or just offer "iA fonts available on the iA website" as a link. **Recommend: bundle them. License allows it.**

3. **Custom CSS escape hatch** — power users might want their own. v6 ships without it; v6.2 can add a `~/Documents/MikePDFViewer/themes/*.css` lookup.

4. **Focus mode + selection conflict** — when user is selecting text, focus mode fighting them is annoying. Mitigation: pause focus mode while there's a non-empty selection.

5. **Typography settings popover vs. menu bar** — popover is more discoverable, menu bar is faster for power users. **Recommend: both.** Same data model, two surfaces.

6. **Reader mode for a .md that's currently being shown via Render-as-PDF** — what happens if Mike already rendered to PDF and then switches mode? **Recommend: switching to Reader mode discards the rendered PDF state and re-renders the source via WKWebView.**

---

## 10. Success criteria

- ☐ Open any `.md`. Default opens in Reader mode with GitHub theme — looks like reading on github.com.
- ☐ Cycle through all 6 themes via menu — instant visual swap, no reload flash.
- ☐ Bump font size to 18pt and line spacing to 1.8 — text reflows comfortably.
- ☐ Toggle focus mode — current paragraph stands out clearly.
- ☐ Open TOC sidebar — see all headings, click any, scroll to it.
- ☐ Cmd+F in Reader mode — WebView's native find UI highlights matches.
- ☐ "Render as PDF" produces a PDF in the chosen theme.
- ☐ Quit app, relaunch, open the same .md — settings persist.
- ☐ Existing v5.8.4 features (PDF, EML, DOCX, Open With, Render-as-PDF) all still work.

---

## 11. What this plan does NOT decide

- The exact CSS for each theme — those will be borrowed/adapted from `github-markdown-css`, `marktext`'s themes, and a sepia/newsprint approximation. Final visuals are an iteration phase.
- Whether to package iA fonts vs. ship without them — depends on Mike's tolerance for app size growing ~3 MB.
- Whether to add Math/Mermaid in 6.0 or wait for 6.1 — recommend wait, but Mike's call.

---

## 12. After Mike approves

1. Tag `before-md-reader-may8` for safety.
2. Bump MARKETING_VERSION → 6.0.
3. Work through phases 1-8.
4. Each phase commits + pushes + reinstalls before moving on (per Mike's commit rule).
5. Final handover.md update + device test.
