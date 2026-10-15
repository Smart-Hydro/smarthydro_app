# Web point windows mosaic — design

**Date:** 2026-10-15  
**Branch:** `mapa-dashboard-map`  
**Status:** Draft for review  

## Problem

On wide/web HOME (≥980), selecting a capture opens a single `_ViewRecords` panel stretched edge-to-edge (`left`/`right: captureEdgePad`, fixed height). That card is ultra-wide, only one point can be inspected at a time, and closing it loses the context when opening another.

## Goal

On web, open **compact windows** per point that **auto-tile** in a bottom mosaic so several can stay open in real time during the dashboard session. Mobile keeps the current single floating card.

## Non-goals

- Dragging, resizing, or free-floating z-order windows  
- Persisting open windows across app restarts or logouts (session-only)  
- Changing mobile/narrow (&lt;980) behavior beyond sharing the same card content widget  
- Changing the side Resumen panel on web  

## Behavior

### Wide / web (`width >= 980`)

1. Tap a logger: if that point’s window is closed → **open** it; if already open → **close** it (toggle).  
2. Multiple windows may be open at once; **no hard cap**.  
3. Windows are compact (~**340×228**). They must **not** span the full map width.  
4. **Auto-mosaic only:** windows lay out in rows from the bottom of the map area, left-to-right, wrapping when the next window would exceed available width. Max columns ≈ `floor((contentWidth + gap) / (windowWidth + gap))` (typically 3–4 on desktop). Gap ≈ **12–16** px, aligned with the workstation feel.  
5. Opening/closing **reflows** the mosaic; order follows open order (stable insertion order).  
6. Each window shows the existing focused profile (logger plate, `Nombre · estado`, profile rows, Soporte, Entrar / Pedir soporte, close).  
7. Close via **X** or by tapping the same logger again.  
8. **Entrar** still opens point detail for that window’s point (existing dive/open flow for that point).  
9. Map selection highlight: loggers with an open window read as selected/emphasized; others stay dimmed as today when any window is open (or keep current “selected vs others” opacity rules applied to the open set).

### Narrow / mobile (`width < 980`)

- Unchanged: at most one floating card; open/replace on select; peek Resumen strip unchanged.

### Session persistence

- The ordered set of open point keys lives in widget state on the HOME map (or `_DashboardTab` if needed for rebuilds).  
- Survives while the user stays on HOME in the same Flutter session.  
- Cleared on leaving HOME / disposing the map, or full page reload.  
- No `SharedPreferences` / localStorage in v1.

## Layout algorithm

Pure helper (testable):

```text
layoutPointWindows({
  required Size area,          // map content rect (or stack size minus side panel)
  required int count,
  required double windowWidth, // ~340
  required double windowHeight,// ~228
  required double gap,         // ~12
  required double bottomInset, // nav / clearance
}) -> List<Rect>
```

Rules:

- Place windows in rows anchored to the **bottom** of `area` (above `bottomInset`).  
- Fill left → right; when the next window would overflow, start a new row above.  
- If rows would overflow the top of `area`, keep tiling upward (map may be partially covered); do not shrink windows below the compact size in v1.  
- All windows same size; no spanning full width.

## Components

| Piece | Role |
|-------|------|
| `Set` / ordered list of open point keys in `_CaptureNetworkMapState` (or equivalent) | Session open set |
| `layoutPointWindows` | Pure mosaic geometry |
| `_PointWindow` | One glass card; wraps shared focus content |
| Shared focus body (refactor of `_FocusedPoint` / `_ViewRecords` content) | Same fields on mobile single card and web windows |
| Wide branch in map `Stack` | N positioned windows via layout helper |
| Narrow branch | Existing single `_ViewRecords` path |

Primary file: `lib/features/dashboard/widgets/capture_network_map.dart`  
Tests: `test/capture_network_map_test.dart`  
Dashboard wiring: only if open-set must lift for tab switches; prefer keeping state inside the map.

## Interaction details

- **Toggle open set** on logger tap (wide). Narrow keeps single-select.  
- Closing the last window restores idle map emphasis (all loggers normal opacity).  
- Support / Entrar callbacks keep current signatures; they receive the window’s point.  
- No drag handles in v1.

## Testing

1. Unit: `layoutPointWindows` — 1 window bottom-left; 3 windows one row; overflow wraps to second row; respects `bottomInset`; never returns a rect wider than `windowWidth`.  
2. Widget (wide surface, e.g. 1200×800): open two loggers → two `capture-point-window-*` (or equivalent keys); panel width ≤ ~360; open third → still mosaic; toggle same logger closes that window; close via X removes it.  
3. Widget (narrow 390): still a single `capture-view-records`; opening another replaces (existing behavior).  
4. Existing ficha/perfil/margen tests remain green (adjust only if keys/height constants change).

## Risks / limits

- Many open windows will cover much of the map; accepted for v1 (user chose no hard cap).  
- Side Resumen (~380) reduces mosaic width on web Row layout; layout uses the **map pane** size, not the full scaffold.  
- Taller mosaic may collide with pagination chrome; keep windows above page controls / use existing bottom clearance.

## Acceptance

- Web: cards are compact, not edge-to-edge.  
- Web: several points stay open and reflow automatically.  
- Web: open set lasts for the HOME session.  
- Mobile: unchanged single-card UX.  
- Tests above pass.

## PR plan (high level)

1. Add `layoutPointWindows` + unit tests.  
2. Refactor focus content for reuse; introduce `_PointWindow`.  
3. Wide: multi-open + mosaic; narrow: keep single card.  
4. Widget tests for multi-open / width / toggle / mobile unchanged.  
5. Manual Hot Restart check on Edge at desktop width and responsive mobile width.
