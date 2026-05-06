# OSC 9 / OSC 777 Passthrough — Phase 1 Research

Branch: `claude/osc-notification-passthrough-WMI63`
Base: upstream/main `5ef8176c` (post PR #4931 merge)

This document maps the existing OSC 99 plumbing introduced by PR #4931 and identifies every touch-point needed to add OSC 9 / OSC 777 support. All file paths are repo-relative.

---

## 1. Existing OSC 99 dispatch flow (the chain we will piggy-back on)

### 1.1 Grid-level dispatch — where the OSC sequence is parsed

`zellij-server/src/panes/grid.rs:3520-3785` (`fn osc_dispatch`)

The relevant slice for OSC 99 (`zellij-server/src/panes/grid.rs:3762-3777`):

```rust
b"99" => {
    if params.len() > 1 {
        let payload = params
            .get(1..)
            .unwrap_or_default()
            .iter()
            .flat_map(|x| str::from_utf8(x))
            .collect::<Vec<&str>>()
            .join(";");
        if !payload.is_empty() {
            // Store raw payload and terminator; namespacing applied at Tab level
            self.pending_desktop_notifications
                .push((payload, terminator.to_string()));
        }
    }
},
```

The terminator is decided at the top of the function (`zellij-server/src/panes/grid.rs:3521`):

```rust
let terminator = if bell_terminated { "\x07" } else { "\x1b\\" };
```

So both BEL- and ST-terminated OSC sequences are already discriminated for us by the VTE parser through `bell_terminated`.

### 1.2 The pending queue — field and initialization

* Definition: `zellij-server/src/panes/grid.rs:646-648`

```rust
/// Pending desktop notifications: (payload, terminator)
/// Payload is the semicolon-joined params after "99", terminator is "\x07" or "\x1b\\"
pub pending_desktop_notifications: Vec<(String, String)>,
```

* Initialization: `zellij-server/src/panes/grid.rs:972`

```rust
pending_desktop_notifications: Vec::new(),
```

### 1.3 Drain methods

* Default trait stub on `Pane`: `zellij-server/src/tab/mod.rs:452-454`

```rust
fn drain_desktop_notifications(&mut self) -> Vec<(String, String)> {
    vec![]
}
```

* Real impl on `TerminalPane`: `zellij-server/src/panes/terminal_pane.rs:646-648`

```rust
fn drain_desktop_notifications(&mut self) -> Vec<(String, String)> {
    self.grid.pending_desktop_notifications.drain(..).collect()
}
```

* Caller (the only one): `zellij-server/src/tab/mod.rs:2840`, inside `Tab::handle_pty_bytes`. After every PTY chunk:

```rust
let desktop_notifications = terminal_output.drain_desktop_notifications();
…
if !desktop_notifications.is_empty() {
    self.forward_desktop_notifications(desktop_notifications, pid)
        .with_context(err_context)?;
}
```

### 1.4 Tab-level forwarding (where namespacing happens)

`zellij-server/src/tab/mod.rs:4815-4856` (`fn forward_desktop_notifications`):

```rust
fn forward_desktop_notifications(
    &self,
    notifications: Vec<(String, String)>,
    pane_id: u32,
) -> Result<()> {
    let err_context = || "failed to forward desktop notifications to host terminal".to_string();
    let mut output = Output::default();
    let all_clients: HashSet<ClientId> = {
        self.connected_clients_in_app
            .borrow()
            .keys()
            .copied()
            .collect()
    };
    output.add_clients(&all_clients, self.link_handler.clone(), None);
    for (payload, terminator) in notifications {
        // Apply identifier namespacing (Phase 3)
        let (metadata, rest) = match payload.find(';') {
            Some(idx) => (
                payload.get(..idx).unwrap_or_default(),
                payload.get(idx..).unwrap_or_default(),
            ),
            None => (payload.as_str(), ""),
        };
        let namespaced_metadata = namespace_notification_id(metadata, pane_id);
        let raw = if rest.is_empty() {
            format!("\x1b]99;{}{}", namespaced_metadata, terminator)
        } else {
            format!("\x1b]99;{}{}{}", namespaced_metadata, rest, terminator)
        };
        output.add_post_vte_instruction_to_multiple_clients(all_clients.iter().copied(), &raw);
    }
    let serialized_output = output.serialize().with_context(err_context)?;
    self.senders
        .send_to_server(ServerInstruction::Render(Some(serialized_output)))
        .with_context(err_context)?;
    Ok(())
}
```

Two key facts for our work:

1. The function is **OSC 99 specific** today — it always wraps with `\x1b]99;…` and runs `namespace_notification_id`. We will branch on payload prefix to add OSC 9 / 777 wrappers without refactoring the OSC 99 path.
2. It targets **all clients in the app**, not just the focused tab's clients (line 4825-4831). So a notification from a background tab still reaches the host. Same property is what we want for OSC 9 / 777.

### 1.5 IPC and host delivery

`forward_desktop_notifications` does **not** speak the `DesktopNotificationResponse` IPC message. That message is only used for the response path (host terminal → client → server → pane). The forward path uses the ordinary render channel:

```
Tab::forward_desktop_notifications
    └─ Output::add_post_vte_instruction_to_multiple_clients (post-VTE = raw bytes)
    └─ Output::serialize → Vec<(ClientId, String)>
    └─ ServerInstruction::Render(Some(client_map))
    └─ Server::route_thread (zellij-server/src/route.rs handles render → client)
    └─ Client writes the bytes to its own stdout (the host terminal)
    └─ Host terminal receives `\x1b]99;…\x07` and pops the notification
```

So the entire transport stack is reusable for OSC 9 / 777 — we only need to choose the right OSC opener (`\x1b]9;` or `\x1b]777;`) and skip namespacing.

The response path that PR #4931 wired up — `ClientToServerMsg::DesktopNotificationResponse` (`zellij-server/src/route.rs:2601`, `zellij-utils/src/ipc.rs:156`), `ScreenInstruction::DesktopNotificationResponse` (`zellij-server/src/screen.rs:840, 9401`), and `denormalize_notification_response` — is **only relevant to OSC 99**, since OSC 9 / 777 are one-way notifications. We do not touch any of it.

---

## 2. How OSC 9 / OSC 777 get dropped today

`zellij-server/src/panes/grid.rs:3779-3783`:

```rust
_ => {
    if self.debug {
        log::warn!("Unhandled osc: {:?}", params);
    }
},
```

The `_ =>` arm is the catch-all. With debug off (the default), the OSC is silently swallowed.

Verification of `params[0]` for the two sequences:

* For `ESC ] 9 ; <body> BEL` the VTE parser splits on `;`, so `params[0] == b"9"` and `params[1] == b"<body>"`.
* For `ESC ] 777 ; notify ; <title> ; <body> BEL` we get `params[0] == b"777"`, `params[1] == b"notify"`, `params[2] == b"<title>"`, `params[3..] = [<body parts split by ';'>]`.

(Confirmed by the existing dispatch table: `b"0" | b"2"`, `b"4"`, `b"7"`, `b"8"`, `b"10" | b"11"`, `b"12"`, `b"50"`, `b"52"`, `b"99"`, `b"104"`, `b"110"`, `b"111"`, `b"112"` are matched as exact byte slices on `params[0]`. Same convention applies to OSC 9 and OSC 777.)

---

## 3. BEL → visual bell trigger path

We want OSC 9 / 777 to fire the same visual feedback the existing BEL byte does (pane frame flash + `[!]` suffix in the tab name + folded stacked-pane title bar indicator).

### 3.1 BEL byte handling

`zellij-server/src/panes/grid.rs:3435-3469` — `Grid::execute(byte)`:

```rust
fn execute(&mut self, byte: u8) {
    match byte {
        7 => {
            self.ring_bell = true;
        },
        …
    }
}
```

So **the entire visual-bell pipeline is gated on a single boolean field `Grid::ring_bell`** (declared at `zellij-server/src/panes/grid.rs:632`, initialized to `false` at `zellij-server/src/panes/grid.rs:961`).

> Important nuance: when the OSC sequence is BEL-terminated, the trailing `\x07` is consumed by VTE as the OSC string terminator, **not** dispatched as an `execute(7)`. So OSC 9 / 777 will not implicitly trigger `ring_bell` — we must set it explicitly inside the OSC dispatch arms.

### 3.2 How `ring_bell` propagates upward

* `TerminalPane::has_bell` reads it: `zellij-server/src/panes/terminal_pane.rs:849-851`

```rust
fn has_bell(&self) -> bool {
    self.grid.ring_bell
}
```

* Consumed in render tick by `Tab::check_and_handle_bell_notifications` (`zellij-server/src/tab/mod.rs:2551-2596`):
  * Iterates all panes (tiled + floating) with `has_bell()` (line 2566-2572).
  * Calls `pane.consume_bell()` (line 2577) which clears `Grid::ring_bell`.
  * For unfocused panes: `pane.set_bell_notification(true)` (line 2582), inserts into `panes_with_pending_bell` (line 2584), pushes to `newly_notified_panes`.
  * Sets `tab_bell_ring` and `tab_has_pending_bell` (line 2587-2593).

* Driver: `zellij-server/src/screen.rs:2541-2574`. On render, when `self.visual_bell` is on, it calls `tab.check_and_handle_bell_notifications(is_active)` per tab and dispatches `BackgroundJob::FlashPaneBell` / `BackgroundJob::FlashTabBell` for the newly notified ids. When `visual_bell` is off, `check_and_consume_bells_without_visual_notification` is used to clear the flag without flashing (line 2576-2580).

* `[!]` suffix in tab/pane name: `zellij-server/src/panes/terminal_pane.rs:429` reads `self.has_bell_notification` (set in step above) when rendering the pane title.

### 3.3 What this means for OSC 9 / 777

Setting `self.ring_bell = true;` inside the new `b"9"` / `b"777"` arms is **all** the visual-feedback wiring we need. The pre-existing pipeline takes care of:

* Pane frame flash (for tiled + floating panes).
* Tab-name flash + `[!]` suffix.
* Folded stacked-pane indicator (it uses the same `panes_with_pending_bell` set + `set_bell_notification` flag, so a folded child pane gets the indicator on its title bar via the regular bell renderer).

No new instruction types or new render passes are required.

---

## 4. Config system — `allow_osc_passthrough`

### 4.1 Closest existing template

`visual_bell` is the most directly comparable option (boolean, ergonomic default `true`, gates a terminal-side passthrough behavior, lives in `Options` and is plumbed into `Screen` only — does **not** propagate down to `Tab` / `Grid`).

Definition: `zellij-utils/src/input/options.rs:244-248`

```rust
/// Whether to show visual bell indicators (pane/tab frame flash and [!] suffix)
/// default is true
#[clap(long, value_parser)]
#[serde(default)]
pub visual_bell: Option<bool>,
```

### 4.2 Where the gate lives — gate at `Tab::forward_desktop_notifications`

I deliberately recommend **not** plumbing `allow_osc_passthrough` all the way into `Grid` (the OSC dispatch site). Reasoning:

* `Grid::new` has 12 positional parameters and is constructed from **125 sites in `zellij-server/src/panes/unit/grid_tests.rs`** alone (plus a handful in `tab_integration_tests.rs` and `screen_tests.rs`). Adding a 13th positional bool means ~135 mechanical churn lines that bloat the patch and complicate upstream rebases.
* The behavioral cost of letting `Grid` always populate the queue and gating one level up is one allocation per OSC 9 / 777 hit when the user has the feature off — negligible.
* The forwarder already inspects every queued entry; branching on payload prefix there is a natural single-site change.

Plan: store the flag on `Tab` (similar to `osc8_hyperlinks: bool` at `zellij-server/src/tab/mod.rs:208`) and consult it in `forward_desktop_notifications`.

### 4.3 Touch-points for the new option

| File | What changes |
| --- | --- |
| `zellij-utils/src/input/options.rs` | Add `pub allow_osc_passthrough: Option<bool>` field on `Options` (next to `osc8_hyperlinks`); add to `merge` and `merge_from_cli`; add to both final `Options { … }` constructors. ~6 lines. |
| `zellij-utils/src/kdl/mod.rs` | Parse `allow_osc_passthrough` from KDL at `mod.rs:2717-2718` style block (search `osc8_hyperlinks` for the model); add KDL serialization in `*_to_kdl` (mirrors `osc8_hyperlinks_to_kdl` at `mod.rs:2912`); add a parsing test (mirrors `osc8_hyperlinks_config_parsing` at `mod.rs:7238`). ~25 lines. |
| `zellij-utils/src/ipc/protobuf_conversion.rs:696, 789` | Two sites that map `Options ↔ Protobuf`. ~2 lines each. |
| `zellij-utils/assets/prost_ipc/client_server_contract.rs` | Generated; regenerate via `prost-build` if needed (the existing OSC 99 PR did this already; verify whether build script runs at compile time or whether the file is hand-maintained). |
| `zellij-server/src/lib.rs:437` (the block reading `new_config.options.visual_bell.unwrap_or(true)`) | Read `allow_osc_passthrough.unwrap_or(true)` and forward as a parameter to the screen-creation path. |
| `zellij-server/src/screen.rs` | Add `allow_osc_passthrough: bool` field on `Screen` (mirrors `visual_bell` at line 1413 — but we only need it inside `Tab`, so we may bypass storing on `Screen` and forward straight through `Tab::new`); add field/param to `Screen::new` (~5 mechanical sites, follow `visual_bell` at lines 742, 1413, 1541, 1599, 4553, 5697, 5738, 8778, 8802). |
| `zellij-server/src/tab/mod.rs` | Add `allow_osc_passthrough: bool` field on `Tab` (mirror `osc8_hyperlinks` at line 208); add to `Tab::new` parameter list (mirror line 753, 861); read it in `forward_desktop_notifications`. |
| `zellij-server/src/tab/unit/tab_tests.rs`, `zellij-server/src/tab/unit/tab_integration_tests.rs:14310-14349`, `zellij-server/src/unit/screen_tests.rs` | Mechanical: add the new bool to every `Tab::new` / `Screen::new` test helper invocation. The integration test helper is at `tab_integration_tests.rs:14281-14361`. There are ~15-20 tab-construction sites and ~20+ screen-construction sites total. |

The KDL side is the only meaningful new code; everything else is one-line plumbing.

---

## 5. Test landscape

### 5.1 Existing OSC 99 tests (templates)

In `zellij-server/src/tab/unit/tab_integration_tests.rs`:

| Test | Line | What it validates |
| --- | --- | --- |
| `osc99_notification_forwarded_through_tab_to_server_render` | 14378 | End-to-end Tab → ServerInstruction::Render carries the wrapped, namespaced OSC 99. |
| `osc99_notification_st_terminator_forwarded` | 14411 | ST terminator works alongside BEL. |
| `osc99_notification_without_identifier_gets_default` | 14434 | Default `i=` injection. |
| `osc99_multiple_notifications_forwarded` | 14457 | Multiple OSCs in one PTY chunk. |
| `osc99_notification_mixed_with_regular_output` | 14488 | OSC interleaved with `print` text. |
| `osc99_notification_preserves_metadata_keys` | 14514 | All metadata keys forwarded intact. |
| `osc99_grid_parses_and_stores_notification` | 14550 | Direct Grid-level test using `Grid::new` and a raw `vte::Parser`. |

The Tab-level tests use the helper `create_new_tab_with_server_receiver` (lines 14281-14361) and `collect_render_output` (lines 14365-14375), which together provide a real `Tab` connected to a real `crossbeam_channel` so we can inspect the wrapped `ServerInstruction::Render` bytes.

### 5.2 Closest model for OSC 9 / 777 unit tests

* For the queue-population assertion (no Tab needed): `osc99_grid_parses_and_stores_notification` (line 14550). It builds a bare `Grid`, runs a `vte::Parser`, and inspects `grid.pending_desktop_notifications` directly. We will reuse the same shape for `osc9_grid_parses_and_stores_notification` and `osc777_grid_parses_and_stores_notification` (and a `bel_vs_st_terminator` variant).

* For the forwarding assertion (Tab needed): `osc99_notification_forwarded_through_tab_to_server_render` (line 14378). We will mirror it for `osc9_…` and `osc777_…`, asserting that the rendered output contains `\x1b]9;<body>\x07` / `\x1b]777;notify;<title>;<body>\x07` and crucially **does not** contain the namespacing prefix `i=p1.` (because OSC 9 / 777 are not namespaced).

* For the `allow_osc_passthrough = false` gate: a new Tab-level test that flips the flag in the test helper and asserts the OSC bytes are absent from the render output, while bell pipeline still saw the OSC (we can assert on `grid.ring_bell` having been consumed by `check_and_handle_bell_notifications`, or simply check `tab.tab_bell_ring`).

* For non-interference between OSC 99 and OSC 9: a single test that feeds both `\x1b]99;i=x:p=t;A\x07\x1b]9;B\x07` and asserts the rendered output contains `i=p1.x` and `\x1b]9;B\x07` separately.

---

## 6. Revised effort estimate

| Phase 2 sub-task | Effort |
| --- | --- |
| Extend `osc_dispatch` with `b"9"` and `b"777"` arms (~25 lines) | 15 min |
| Add `allow_osc_passthrough` to `Options` + KDL (~30 lines + roundtrip test) | 30 min |
| Plumb through Server → Screen → Tab (~5 mechanical sites + Tab field) | 30 min |
| Branch in `forward_desktop_notifications` for OSC 9 / 777 wrapping (no namespacing) | 15 min |
| Update protobuf conversion (2 sites) | 10 min |
| Mechanical test-helper updates for new `Tab::new` / `Screen::new` arg (~30 sites) | 30 min |
| New unit tests (Grid-level x 3 + Tab-level x 4 + config gate test) | 45 min |
| `cargo fmt` + `cargo clippy` + `cargo test --workspace` (compile-watch + fix) | 45 min |
| **Phase 2 total** | **~3.5 hours** |

| Phase 3 sub-task | Effort |
| --- | --- |
| Write `VERIFY.md` per task spec (7 scenarios, expected outcomes) | 30 min |
| **Phase 3 total** | **~30 min** |

---

## 7. Open questions / clarifications worth flagging before Phase 2

1. **OSC 9 with empty body** (`ESC ] 9 ; BEL`). I propose to **still trigger visual bell** (the OSC was received) but **not push** to the queue (no payload to forward). Reasonable?

2. **OSC 777 sub-commands other than `notify`**. The rxvt OSC 777 protocol also defines other sub-commands (e.g. `Beep`, but no widely deployed apps use it). I propose to **only handle `notify`** and silently ignore other sub-commands (visual bell still fires, no passthrough). The user spec only mentions `notify`. Sound reasonable?

3. **`allow_osc_passthrough = false` and OSC 99**. The user spec explicitly scopes the new option to OSC 9/777 forwarding. I will leave OSC 99 unaffected by this flag (matches the "don't refactor OSC 99" constraint). Confirm?

4. **Disambiguation between OSC 99 and OSC 9 in the shared queue**. We will use a payload-prefix convention: OSC 9 entries start with `"9;"`, OSC 777 entries start with `"777;"`, OSC 99 entries (existing) keep the namespaced-metadata format which never starts with a digit followed by `;` (legitimate OSC 99 metadata is `key=value:key=value`, so the first segment always contains `=` or `:`). Edge case: a malformed OSC 99 with `params[1] == b"9"` would land in the queue as `"9;..."` and be misclassified. This is a malformed-input theoretical risk; I will document it in code comments rather than introducing a tagged-enum refactor that ripples through the OSC 99 path.

5. **CLI flag for `allow_osc_passthrough`**. `visual_bell` and `osc8_hyperlinks` both expose themselves as `--<name>` clap flags. I will follow suit so users can override via CLI as well as KDL.

If items 1-4 above are uncontroversial, no clarification round needed; otherwise please push back before I start Phase 2.
