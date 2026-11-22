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
