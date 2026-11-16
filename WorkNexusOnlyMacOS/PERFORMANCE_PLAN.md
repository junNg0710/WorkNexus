# Plan: app performance and a smoother TBChat character

Status (2026-11-17): steps **1, 2 and 3** of the table at the end are **done**; step 0 (measuring with Instruments) and steps 4, 5, 6 are **not done**.

Done:
- Step 1: a ZenTao board is computed once per change (`ZentaoBoardCache`, `BoardController.revision`); each ticket's deadline is parsed once for every chip/count/workload (`ZenTaoLeaderFacts`). Tests: 20 redraws = 4 computations; counting 5,000 tickets takes < 0.5 s.
- Step 2: the character — position is a function of time with ease-in/out, read at the display's refresh rate (`TimelineView(.animation)`, running only while it walks); the sprite is one `CALayer` whose `contentsRect` changes; speed is in pt/second (90), not a share of the window width; it stops completely while the window is not visible. Not done: stride sync (6.4), inertia on drop (6.5), size option (6.7).
- Step 3: the board of a hidden section is not recomputed (`BoardController.isActive`); Dock-badge reading and the character's frames stop while the window is hidden.

Not measured with Instruments on the real app: the numbers above come from unit tests, not from the running app. The "counted" figures were read from the code on 2026-11-17; every claim about slowness is a **hypothesis until measured** (step 0).

## 0. Measure first (required, do this first)

No optimising by feel. Take a baseline to learn what is really slow and to compare against after each change.

- Instruments on a Release build: **Time Profiler**, **SwiftUI** (view body / update count), **Hangs**, **Allocations**.
- Scenarios (record a number for each): launch until usable; switch Tasks ↔ Bugs ↔ Chat; open the 892-task board (execution `VN_Daily_Tasks`); click a filter chip; type in the filter field; scroll the list; open a ticket's detail; leave the app in the background for 10 minutes (idle CPU); the character walking.
- Add `os_signpost` around: `BoardController.recompute`, `ZentaoBoards.taskBoard/bugBoard`, `GRDBTicketRepository.upsertTickets`, decoding `TicketRow.entity`.
- Pass criteria: no hang > 100 ms on a chip click or tab switch; idle CPU < 1–2 % without interaction; the character drops no frames while walking.

## 1. Ticket data: too much reading and decoding (the main suspect)

Counted in the code:
- `watchTickets()` has **11 subscribers**. Each time the `tickets` table changes, every one of them receives **all** rows again and decodes `providerEntityJson` (JSON) for each row (`GRDBTicketRepository.watchTickets` → `TicketRow.entity`).
- `BoardController` (two for ZenTao: tasks, bugs) calls `recompute()` whenever `tickets`/`accounts`/`filter` change: scoping + `BuildBoard` over everything.

To do:
1. **One shared ticket source**: a `TicketStore` (actor/@Observable) holding the decoded snapshot; everything else reads from it instead of running its own `ValueObservation`. One decode per change.
2. **Incremental decoding**: keep a cache `id → (rowVersion, Ticket)`; decode only rows whose content changed (compare `providerEntityJson`/`updatedAt`), not 100 % of them after every upserted page.
3. **Scoped queries**: a board needs only the tickets of one account + kind + execution/product. Add columns/indexes (`accountId` exists; add `externalType`, and a side table `ticketMemberships(ticketId, label)` instead of filtering labels in memory), then `watchTickets(scope:)`.
4. **Batched writes**: a page of 50–100 tickets is one transaction (already so), but "Load all" and per-group reads write many pages in a row → debounce the notifications (GRDB `ValueObservation` with `scheduling`/throttle ~100 ms) so the UI does not recompute after every page.

## 2. ZenTao boards: the same thing computed several times per redraw

Counted: `ZentaoBoards.taskBoard/bugBoard/taskTable/bugTable/bugShownCount` are called from **7 places** in the views; the leader bar also calls `workload`, `quickCounts`, `leaderPool`, `shownTickets` (**4 places**). Each call reruns `FilterTickets` + `ApplyLeaderFilter` + sorting over every ticket in scope; `quickCounts` walks 8 chips × N tickets and parses the deadline each time.

To do:
1. **Memoise by revision**: keep a `boardRevision` in `ZentaoUIState` (bumped when scope/filter/leader/sort change) and cache `taskBoard`, `bugBoard`, `leaderPool`, `workload`, `quickCounts` by revision. Views only read the cache.
2. **Precompute deadlines**: parse `deadline` once when a ticket is decoded (keep the `Date?` in a side cache by id), not inside the filter loop.
3. **One pass for the chips**: `CountQuickFilters` walks N once and counts all 8 chips.
4. **Narrow the redraw scope**: `ZentaoBoardCard` takes values (ticket, selected, pending) instead of reading the @Observable `controller` → only a changed card redraws. Check with Instruments' SwiftUI template.
5. Long columns: already a `LazyVStack`? Check `BoardColumnFrame`; if not lazy, make it so, and cap how many cards are drawn at first.
6. Compute boards off the main actor when N is large (> ~2000): run filter/sort in a `Task.detached` and apply the result by revision.

## 3. Kept-alive screens and background work

- `Viewport.keepAliveLimit = 5`: 5 sections and 5 panes stay mounted while hidden. They still receive ticket changes and recompute.
  → Use the `sectionIsActive` flag (already in the environment) to **skip recomputing while hidden**, and recompute once when shown.
- Polling in place: the Dock badge every 4 s (new), the character's frames, chat/ticket sync, `SessionCookieKeeper`.
  → Stop all polling while the window is hidden/minimised (`NSWindow.occlusionState`, `NSApplication.didResignActive`), resume when it shows.
- Mini apps: each tab is a web process; the `liveLimit` cap exists. Background tabs are lazy (new). Consider putting tabs unused for > 15 minutes to sleep.

## 4. Chat

Measure first; the suspects: image/sticker decoding on the main thread (`NSImage(data:)`), animated stickers playing while out of sight (stopped once the view leaves the window, but inside a `LazyVStack` an off-screen row is not necessarily removed), Markdown/mentions parsed again on every redraw.
- Decode images off the main thread + downsample to the displayed size (done for ordinary images, not for stickers).
- Cache the parsed Markdown by `message.gid + edit`.
- Stop `FramePlayerView` while it is outside the scroll view's visible area (using the existing `onScrollTargetVisibilityChange`).

## 5. Launch

Measure `CompositionRoot.start()` and the time to the first frame. Defer: scanning installed apps, reading cookies/passwords, checking for updates, opening the first web view → until after the window is on screen.

## 6. A smoother TBChat character

As it was (read from `CoreUI/Widgets/Pet`):
- `PetView` ran a `Task.sleep(frameDuration)` loop, then `director.tick()`. **The position changed only on a tick**, and a tick lasted one sprite frame: 0.09 s while running (≈ 11 steps/second), 0.32 s while standing. So walking looked like a series of jumps.
- Every tick changed an `@Observable` → the whole overlay redrew; the 192×208 image was scaled to 84 pt by SwiftUI on every frame with `.interpolation(.high)`.
- The loop ran even while the window was hidden.

New design:
1. **Two separate rhythms**: the sprite frame changes at the animation's `frameDuration`; **the position is interpolated on the display clock** (60/120 Hz) with `TimelineView(.animation)` or an `NSView`'s `CADisplayLink` — position is a function of time, not something accumulated per tick.
2. **Draw with Core Animation**: one `CALayer` whose `contents` is the atlas and whose `contentsRect` changes per frame (GPU, no re-decoding or re-scaling), `magnificationFilter = .nearest`/`.trilinear` whichever looks better; move it through the layer's `position`. Nothing goes through SwiftUI per frame.
3. **Movement with acceleration**: ease-in/ease-out when starting and stopping, speed in pt/second (not a share of the window width as before — a wide window made it oddly fast), flip exactly when the direction changes, one "standing" frame before it starts to run.
4. **Stride sync**: the distance per running frame = the sprite's stride (measured from the sheet), so the feet do not slide on the ground.
5. **Drag and drop**: follow the pointer directly on the layer; on release, a little inertia, then fall to the bottom.
6. **Savings**: stop completely while the window is covered/minimised or the app is in the background, under "Reduce Motion", and while the character stands still run only a slow timer for blinking.
7. Options in Settings: character size (S/M/L), whether it walks around or stays put.

Verification: tests for the position-over-time function (even, no jumps, stops exactly at the target); Instruments for CPU while standing (< 0.5 %) and while walking; a 120 Hz screen recording to check for stutter.

## Suggested order

| Step | Work | Risk | Expected gain |
|---|---|---|---|
| 0 | Measure + signposts | low | know where it is really slow |
| 1 | Memoise boards by revision (2.1–2.3) | low | chip clicks and filter typing much faster |
| 2 | Character: interpolated position + CALayer (6.1–6.3, 6.6) | low | visibly smoother at once |
| 3 | Skip recompute for hidden sections + stop polling while the window is hidden (section 3) | low | less background CPU |
| 4 | One ticket source + incremental decoding (1.1–1.2) | medium | less stutter during sync |
| 5 | Scoped queries + indexes (1.3) | high (schema change) | needed once data exceeds a few thousand tickets |
| 6 | Chat + launch (sections 4, 5) | medium | per the measurements |

Each step: measure before/after with the same scenarios, keep every test passing, change no behaviour.
