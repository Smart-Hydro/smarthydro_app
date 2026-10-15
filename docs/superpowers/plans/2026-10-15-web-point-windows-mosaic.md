# Web point windows mosaic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On web HOME (≥980), open compact per-point windows that auto-tile in a bottom mosaic so several stay open for the session; keep mobile single-card UX.

**Architecture:** Pure `layoutPointWindows` places equal-sized rects in bottom rows. Wide map state holds an ordered list of open point keys; logger tap toggles membership and reflows. Shared `_FocusedPoint` body powers both the narrow `_ViewRecords` card and each wide `_PointWindow`.

**Tech Stack:** Flutter, existing `CaptureNetworkMap` / `HydroGlassLight`, widget + unit tests in `test/capture_network_map_test.dart`.

**Spec:** `docs/superpowers/specs/2026-10-15-web-point-windows-mosaic-design.md`

## Global Constraints

- Wide threshold: `MediaQuery.sizeOf(context).width >= 980` (same as dashboard).
- Window size: width `340`, height `228`; gap `12`.
- No drag/resize; no disk persistence (in-memory session only).
- Narrow (&lt;980): at most one floating card; existing keys `capture-view-records` / behavior preserved.
- Mosaic uses the **map pane** size (not scaffold including side Resumen).
- Spanish UI copy unchanged (`Entrar`, `Pedir soporte`, status labels).

## Review Focus

- Zero open windows → mosaic empty, all logger opacities idle.
- Opening the same logger twice toggles closed (wide).
- Mosaic width is the map pane after side panel (~380 Resumen); windows must not assume full scaffold width.
- Point removed from `points` while its window is open → drop that key from the open set.
- Page flip with open windows on another page → windows for off-page points still show (keyed by point id), or drop off-page keys — **drop keys whose point is not in `widget.points`**; keep open if still in list even if on another page.

---

## File map

| File | Responsibility |
|------|----------------|
| `lib/features/dashboard/widgets/capture_network_map.dart` | `layoutPointWindows`, multi-open state (wide), `_PointWindow`, single card (narrow) |
| `test/capture_network_map_test.dart` | Unit + widget tests for layout and multi-open |

No new files required unless the map file becomes unmanageable mid-task; prefer staying in-place.

---

### Task 1: `layoutPointWindows` helper

**Files:**
- Modify: `lib/features/dashboard/widgets/capture_network_map.dart` (near other `@visibleForTesting` layout helpers)
- Test: `test/capture_network_map_test.dart`

**Interfaces:**
- Consumes: none
- Produces:

```dart
@visibleForTesting
List<Rect> layoutPointWindows({
  required Size area,
  required int count,
  double windowWidth = 340,
  double windowHeight = 228,
  double gap = 12,
  double bottomInset = 8,
})
```

- [ ] **Step 1: Write failing unit tests**

Names and asserts:
- `layoutPointWindows con 0 no emite rects` → `isEmpty`
- `layoutPointWindows un panel abajo a la izquierda` → one rect; `bottom == area.height - bottomInset`; `left` near 0; `width == 340`; `height == 228`
- `layoutPointWindows tres paneles caben en una fila` (area width ≥ 3*340 + 2*12) → same `top` for all three; increasing `left`
- `layoutPointWindows el cuarto pasa a la fila de arriba` → index 3 has `bottom <=` row0 `top - gap`
- `layoutPointWindows nunca es más ancho que windowWidth` → every `rect.width == windowWidth`

- [ ] **Step 2: Run tests — expect FAIL**

Run: `flutter test test/capture_network_map_test.dart --name "layoutPointWindows"`

Expected: FAIL (function not defined)

- [ ] **Step 3: Implement `layoutPointWindows`**

Bottom-up rows, left→right; `columns = max(1, ((area.width + gap) / (windowWidth + gap)).floor())`; place `count` rects; if `area` is empty or non-positive, return `[]`.

- [ ] **Step 4: Run tests — expect PASS**

Run: `flutter test test/capture_network_map_test.dart --name "layoutPointWindows"`

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/capture_network_map.dart test/capture_network_map_test.dart
git commit -m "feat: layoutPointWindows para mosaico de fichas en web"
```

---

### Task 2: Wide multi-open state + compact `_PointWindow`

**Files:**
- Modify: `lib/features/dashboard/widgets/capture_network_map.dart` (`_CaptureNetworkMapState`: `_selected` / `_select` / overlay; extract/reuse `_FocusedPoint` body)
- Test: `test/capture_network_map_test.dart`

**Interfaces:**
- Consumes: `layoutPointWindows` from Task 1
- Produces:
  - Ordered open keys: `List<String> _openKeys` (point id via existing `_pointKey`) on wide; narrow keeps `int? _selected`
  - Wide logger tap toggles key in `_openKeys`
  - Widget key per window: `ValueKey('capture-point-window-$key')`
  - `_PointWindow` closes via X → remove that key

Detection of wide inside the map: `MediaQuery.sizeOf(context).width >= 980` (or pass a `bool multiWindow` from parent if tests need override — prefer MediaQuery + large test surface).

- [ ] **Step 1: Write failing widget tests (wide surface ≥980)**

- `en web abre varias ventanas compactas en mosaico`: pump `SizedBox(width: 1200, height: 800)`; tap two nodes; find two `capture-point-window-*`; each window width ≤ 360; find `Nombre · Conectado` (or status) without a single edge-to-edge `capture-view-records`
- `en web el mismo logger cierra su ventana`: open then tap again → that window gone
- `en web la X cierra solo esa ventana`: open two; tap close on one → one remains

Also pin Review Focus: `si el punto desaparece se cae del mosaico` — pump with two points open, rebuild with one point removed → one window.

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/capture_network_map_test.dart --name "en web"`

- [ ] **Step 3: Implement multi-open + `_PointWindow`**

- Replace single bottom `Positioned(left/right, height: 228)` on wide with a loop over `_openKeys` → `layoutPointWindows` → `Positioned` + `_PointWindow`.
- Narrow path: keep existing single `_ViewRecords` + `_selected`.
- Share focus body; do not duplicate profile rows.
- Logger emphasis: selected if key ∈ `_openKeys` (wide) or index == `_selected` (narrow).
- Sync: when `widget.points` changes, drop open keys / selection not present.

- [ ] **Step 4: Run widget + prior ficha tests**

Run: `flutter test test/capture_network_map_test.dart --name "en web|ficha|layoutPointWindows|al elegir un punto"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/capture_network_map.dart test/capture_network_map_test.dart
git commit -m "feat: ventanas de punto en mosaico en HOME web"
```

---

### Task 3: Narrow regression + polish

**Files:**
- Modify: `lib/features/dashboard/widgets/capture_network_map.dart` only if gaps found
- Test: `test/capture_network_map_test.dart`

**Interfaces:**
- Consumes: Task 2 behavior
- Produces: confirmed narrow single-card path

- [ ] **Step 1: Write / extend narrow test**

- `en movil sigue una sola ficha ancha del panel`: surface 390×640; tap node → `capture-view-records` findsOne; `capture-point-window-` findsNothing; height ≥ 220 (existing taller card)

- [ ] **Step 2: Run — expect PASS after Task 2 (or FAIL if wide leaked)**

Run: `flutter test test/capture_network_map_test.dart --name "en movil|en web|layoutPointWindows"`

- [ ] **Step 3: Fix any narrow/wide bleed**

Ensure wide-only widgets are gated on width ≥ 980.

- [ ] **Step 4: Full map suite**

Run: `flutter test test/capture_network_map_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/capture_network_map.dart test/capture_network_map_test.dart
git commit -m "test: confirma ficha unica en movil y mosaico en web"
```

---

## Execution notes

- Prefer Hot Restart after UI changes on `:3001` / Edge.
- Manual check: desktop width open 2–3 loggers; responsive &lt;980 still one card.
