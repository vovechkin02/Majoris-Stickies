# GNOME Shell window integration

The `majoris-stickies@majoris.org` extension is an optional GNOME Shell 48–50
integration, not a GTK process plugin. It exports a narrow D-Bus interface on
the existing `org.gnome.Shell` bus name. Only windows identified with the
`com.majoris.stickies` GTK application ID and the Stickies note-title suffix
are candidates for changes. The extension cannot read note content.

To install for a user, copy `majoris-stickies@majoris.org` to
`~/.local/share/gnome-shell/extensions/`, then enable it with
`gnome-extensions enable majoris-stickies@majoris.org` after the shell has
loaded the extension (usually the next session on Wayland).

The optional integration must be qualified inside the exact Majoris GNOME
Shell build. Without it, ordinary note editing works, but the floating and
arrangement commands report an error and do not falsely claim success.

D-Bus object: `/org/gnome/Shell/Extensions/MajorisStickies`
Interface: `org.gnome.Shell.Extensions.MajorisStickies`
Methods: `RegisterWindow(u,s,b)`, `SetFloating(u,b)`, `Arrange(s,s)`.

Absolute window coordinates are compositor-owned on Wayland; GTK cannot
restore exact positions by itself. After a window is registered, the extension
restores compositor-managed positions from a local JSON snapshot at
`$XDG_DATA_HOME/majoris/stickies/window-positions.json`. Positions are clamped
to the current work area. This path and its data format are private to the
extension, not a published application API. Validate the extension on the exact
Majoris GNOME Shell build before enabling the Meson install option.

## Stage 4 multi-monitor behavior

`layout.js` is a pure geometry module used by `extension.js`. It selects a
surviving monitor using persisted monitor work-area overlap and clamps window
rectangles to the actual usable area. Grid/cascade arrangements are calculated
separately per monitor, including screens to the left of the primary display.
The extension responds to display topology changes by moving notes that would
otherwise be fully offscreen. Existing saved layouts lacking `monitorArea`
are still accepted.

The optional integration is **not qualified solely by Node.js geometry tests**;
run `docs/stage-4-qualification.md` on the shipping GNOME Shell version.

## Stage 8 workspace and restore commands

`ToggleSticky(u windowId) → b enabled` toggles visibility across GNOME
workspaces, for registered Stickies windows only. This state is persisted with
compositor-managed positions in `window-positions.json`. `RestoreLayout()`
repositions currently registered note windows within the active monitor work
areas. Neither command is available without the enabled Shell extension, and
neither pretends to be a GTK4/Wayland client-side window-management feature.
Maximum concurrently registered note windows: **64** (enforced by the app too).
