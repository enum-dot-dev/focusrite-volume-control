# Remote protocol prototype (FC2 over TCP)

Status: **experimental, unwired, unverified.** Nobody has confirmed that it ever controlled
volume end to end. This page records what the code does so the work isn't lost.

## Why it exists

The shipping app controls Focusrite Control 2 (FC2) by operating its window through the
Accessibility API. FC2 also accepts remote-control clients over a local TCP socket, the same
mechanism Focusrite's own remote apps use. Talking that protocol directly would not need FC2's
window, the Direct tab, or the Accessibility permission for FC2 control.

## What's in the repo

| File | What it is |
|---|---|
| `Focusrite Volume Control/FocusriteClient.swift` | A working-looking client for FC2's XML-over-TCP protocol. Nothing creates it today. |
| `Focusrite Volume Control/FCServerBackend.swift` | A `VolumeBackend` stub. Every method returns "not yet implemented"; it does not use `FocusriteClient`. Its header says AES70/OCA, but no AES70 code exists; the client speaks the XML protocol below. |
| `Focusrite Volume ControlTests/FCServerBackendTests.swift` | Tests that the stub returns its errors. Nothing tests `FocusriteClient`. |
| `BackendType.fcServer` in `VolumeController.swift` | Selectable in code via `switchBackend(to:)`. There is no UI for it (a picker existed until `4d12ee2` removed it). |

## How the client works

**Transport.** TCP to `127.0.0.1` with `NWConnection`. No Bonjour, no UDP.

**Finding the port.** The client runs `lsof -i TCP -s TCP:LISTEN -n -P`, keeps lines from a
process containing "Focusrite" owned by the current user, and takes ports written as `*:PORT`.
It then appends fallback ports `58323, 58322, 49152, 30096` (a code comment guesses 58323 is
the control port) and tries each one, highest first, moving on when a connection fails or waits.

**Framing.** Each message is `Length=XXXXXX ` (six hex digits and a space) followed by an XML
body. The client counts characters rather than bytes, which only matters for non-ASCII text.

**Messages sent**

```xml
<client-details hostname="FocusriteVolumeControl" client-key="987654321"/>
<device-subscribe devid="X" subscribe="true"/>
<set devid="X"><item id="Y" value="Z"/></set>
<keep-alive/>   <!-- every 3 seconds -->
```

**Messages handled**

- `<client-details id="…">`: FC2 assigns the client an ID
- `<device-arrival model="…" id="…">`: the client parses the device's items and subscribes
- `<device-removal>`
- `<approval authorised="true|false">`: `setValue` refuses to send until this is `true`
- `<set …>`: live value updates for subscribed items

**Pairing.** There is no pairing code in the code. The client sends a fixed `client-key`
("like the original Focusrite Midi Control app", per a comment) and waits for FC2 to approve
it. The original UI told the user to approve the app in **FC2 → Settings → Remote Devices**,
where it appears as "FocusriteVolumeControl". Whether FC2 still offers that approval without a
paired phone is unknown.

## What's missing

- **Item IDs.** The client knows nothing about which item is the playback level, an input, or
  Direct Monitor. The first prototype guessed "the first item whose value is between -70 and 6".
- **Keep-alive probably never fires.** The timer is created on the connection's callback queue,
  which has no run loop.
- **No reconnect** when FC2 restarts.
- **`FCServerBackend` doesn't use the client** at all.

## History

All on January 26, 2026:

1. `17e3ff7` "add stuff..." wired `FocusriteClient` into the app.
2. `b314269` "we have a working solution!!! telinta style" added only the `VolumeBackend` protocol.
3. `d36006c` "something worked?" added the AppleScript backend and removed every use of
   `FocusriteClient`.

The TCP route was dropped about five hours after it was added, in favour of UI scripting. That
suggests, but doesn't prove, that it never worked end to end. A later roadmap item still listed
"Focusrite Control Protocol/Server support".

## Proposal: "Enable experimental remote protocol"

Not implemented. A sketch of what a settings toggle and setup wizard would need, based on the
code above:

1. **Toggle** in Preferences, off by default, labelled experimental. Turning it on opens the
   wizard; turning it off switches back to the Accessibility backend.
2. **Wizard steps**
   1. *Check FC2 is running* (port discovery reads FC2's live sockets).
   2. *Connect*: show the discovered and fallback ports and which one answered; allow a manual
      port as a fallback.
   3. *Approve*: tell the user to open FC2 → Settings → Remote Devices and approve
      "FocusriteVolumeControl"; wait for `<approval authorised="true">`, and explain what to do
      on `false` or a timeout.
   4. *Map controls*: list the device's items and identify playback level, mute and Direct
      Monitor, either automatically (by matching values the Accessibility backend reads) or by
      asking the user to move a slider in FC2 and watching which item changes.
   5. *Test*: nudge the volume one step and confirm FC2 reflects it, then save the mapping.
3. **Before shipping it:** fix the keep-alive timer, add reconnect, implement `FCServerBackend`
   on top of `FocusriteClient`, and add tests that feed recorded protocol traffic to the client.

The first thing to do is a manual spike on a real Mac: run the client, approve it in FC2, and
log the items a Scarlett exposes. That answers whether this works at all before any UI is built.
