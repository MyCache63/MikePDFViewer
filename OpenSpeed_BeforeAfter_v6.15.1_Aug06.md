# Document open speed: before/after - v6.15.1 - 2026-08-06

Test files: your real MTN_GAM_Profiles_and_Mapping_2026-08-06.md (6 KB) and a synthetic
89 KB markdown. Harness compiles the app's own source files and times each stage of the
open path, 3 runs each. All "main thread" time = beachball time you feel.

## Where the lag came from (BEFORE, v6.15.0)

| Stage | 6 KB file | 89 KB file | Thread |
|---|---|---|---|
| WKWebView first render (cold app) | 1,703 ms | 1,462 ms | background |
| WKWebView render (warm) | 387-1,862 ms | 326-1,059 ms | background |
| Quick-view text build (unused in default Reader mode) | 50-138 ms | 906-1,782 ms | MAIN |
| Markdown to HTML render (ran TWICE per open) | 5 ms x2 | ~300 ms x2 | MAIN (one of them) |
| Recents bookmark write | 13-20 ms | 18-45 ms | MAIN |
| File read + parse, stats, theme | ~1 ms | ~45 ms | MAIN |

So a small file cost ~1.7 s on first open (WebKit process spawn) plus ~100 ms of main
thread work; an 89 KB file blocked the main thread for 1.5-2 s on top of the render.
Multiple open windows make WebKit slower still.

## What v6.15.1 changes

1. Quick-view text build removed from the open path entirely; it now builds in the
   background only when you actually switch to Quick view.
2. Markdown parse, TOC, and reading stats moved off the main thread (Loading spinner
   shows instead of a beachball).
3. HTML render is memoized: the second render of the same source (reader view, theme
   switches) is now 0 ms.
4. Recents bookmark creation moved to a background queue.
5. WebKit pre-warms at app launch, so your FIRST markdown/HTML open no longer pays the
   ~1.7 s WebContent process spawn.

## AFTER numbers (same harness, updated code)

| Stage | 6 KB file | 89 KB file |
|---|---|---|
| Main-thread work during open | ~1 ms | ~1 ms |
| HTML render, first / repeat | 5 / 0 ms | 93 / 0 ms |
| WKWebView render, warm (what a pre-warmed app sees) | 107-676 ms | 93-192 ms |
| Quick-view build (only if you use Quick view) | ~90 ms, background | ~150 ms, background |

Caveat: WKWebView timings vary with machine load (the two benchmark sessions ran
minutes apart, and macOS caches help the second session), so treat the webview rows as
indicative. The main-thread eliminations and the render memo are exact.

## Status

v6.15.1 built, committed, pushed, installed to /Applications. Quit (Cmd+Q), relaunch,
and reopen the MTN file: it should appear noticeably faster, and bigger .md files should
no longer freeze the app while opening. PDF opens were already async and are unchanged.

Benchmark harness (kept for future regressions):
scripts/benchmark_open_speed/main.swift (compile with the Markdown* sources; see handover)
