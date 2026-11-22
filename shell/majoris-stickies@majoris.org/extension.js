import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const APPLICATION_ID = 'com.majoris.stickies';
const OBJECT_PATH = '/org/gnome/Shell/Extensions/MajorisStickies';
const MAX_WINDOWS = 64;
const INTERFACE_XML = `
<node>
  <interface name="org.gnome.Shell.Extensions.MajorisStickies">
    <method name="RegisterWindow">
      <arg type="u" name="windowId" direction="in"/>
      <arg type="s" name="noteId" direction="in"/>
      <arg type="b" name="floating" direction="in"/>
    </method>
    <method name="SetFloating">
      <arg type="u" name="windowId" direction="in"/>
      <arg type="b" name="enabled" direction="in"/>
    </method>
    <method name="Arrange">
      <arg type="s" name="mode" direction="in"/>
      <arg type="s" name="windowIds" direction="in"/>
    </method>
  </interface>
</node>`;

/**
 * Restricts window controls to verified Majoris Stickies GTK windows.
 * Coordinates belong to the compositor, not to GTK or the SQLite repository.
 */
export default class StickiesExtension extends Extension {
    enable() {
        this._layouts = this._readLayouts();
        this._registered = new Map();
        this._tracked = new Map();
        this._saveSource = 0;
        this._windowCreatedId = global.display.connect('window-created', () => {
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                this._applyRegistrations();
                return GLib.SOURCE_REMOVE;
            });
        });
        this._exportedObject = Gio.DBusExportedObject.wrapJSObject(INTERFACE_XML, this);
        this._exportedObject.export(Gio.DBus.session, OBJECT_PATH);
    }

    disable() {
        this._recordAllPositions();
        this._writeLayouts();
        if (this._saveSource) {
            GLib.source_remove(this._saveSource);
            this._saveSource = 0;
        }
        global.display.disconnect(this._windowCreatedId);
        for (const tracked of this._tracked.values()) {
            for (const signalId of tracked.signals) {
                tracked.window.disconnect(signalId);
            }
        }
        this._tracked.clear();
        this._registered.clear();
        this._exportedObject?.unexport();
        this._exportedObject = null;
        this._layouts = null;
    }

    _filePath() {
        return GLib.build_filenamev([
            GLib.get_user_data_dir(), 'majoris', 'stickies', 'window-positions.json',
        ]);
    }

    _readLayouts() {
        try {
            const [ok, bytes] = GLib.file_get_contents(this._filePath());
            if (!ok || bytes.length > 131072) {
                return {};
            }
            const stored = JSON.parse(new TextDecoder().decode(bytes));
            return stored && typeof stored === 'object' && !Array.isArray(stored)
                ? stored : {};
        } catch (_error) {
            return {};
        }
    }

    _writeLayouts() {
        try {
            GLib.mkdir_with_parents(GLib.path_get_dirname(this._filePath()), 0o700);
            GLib.file_set_contents(this._filePath(), JSON.stringify(this._layouts));
        } catch (error) {
            logError(error, 'Unable to save Stickies window layout');
        }
    }

    _queueSave() {
        if (this._saveSource) {
            return;
        }
        this._saveSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
            this._saveSource = 0;
            this._writeLayouts();
            return GLib.SOURCE_REMOVE;
        });
    }

    _noteWindows() {
        return global.get_window_actors()
            .map(actor => actor.meta_window)
            .filter(window => window.get_gtk_application_id() === APPLICATION_ID &&
                window.get_title()?.endsWith(' — Stickies'));
    }

    _findWindow(windowId) {
        const suffix = `/${windowId}`;
        return this._noteWindows().find(window =>
            window.get_gtk_window_object_path()?.endsWith(suffix));
    }

    _recordPosition(windowId) {
        const tracked = this._tracked.get(windowId);
        if (!tracked) {
            return;
        }
        const rect = tracked.window.get_frame_rect();
        if (rect.width < 240 || rect.height < 85) {
            return;
        }
        this._layouts[tracked.noteId] = {
            x: rect.x, y: rect.y, width: rect.width, height: rect.height,
        };
        this._queueSave();
    }

    _recordAllPositions() {
        for (const windowId of this._tracked.keys()) {
            this._recordPosition(windowId);
        }
    }

    _applyRegistrations() {
        for (const [windowId, registration] of this._registered) {
            if (this._tracked.has(windowId)) {
                continue;
            }
            const window = this._findWindow(windowId);
            if (!window) {
                continue;
            }
            const saved = this._layouts[registration.noteId];
            if (saved && [saved.x, saved.y, saved.width, saved.height]
                .every(value => Number.isFinite(value))) {
                const area = global.workspace_manager.get_active_workspace()
                    .get_work_area_for_monitor(window.get_monitor());
                const width = Math.min(area.width, Math.max(240, saved.width));
                const height = Math.min(area.height, Math.max(85, saved.height));
                const x = Math.max(area.x, Math.min(saved.x, area.x + area.width - width));
                const y = Math.max(area.y, Math.min(saved.y, area.y + area.height - height));
                window.move_resize_frame(true, x, y, width, height);
            }
            if (registration.floating) {
                window.make_above();
            }
            const signals = [
                window.connect('position-changed', () => this._recordPosition(windowId)),
                window.connect('size-changed', () => this._recordPosition(windowId)),
                window.connect('unmanaged', () => {
                    this._recordPosition(windowId);
                    this._tracked.delete(windowId);
                    this._registered.delete(windowId);
                }),
            ];
            this._tracked.set(windowId, {
                window, noteId: registration.noteId, signals,
            });
        }
    }

    /** Pairs a transient GTK window ID with its stable repository note UUID. */
    RegisterWindow(windowId, noteId, floating) {
        if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(noteId)) {
            throw new Error('Invalid note identifier');
        }
        if (this._registered.size >= MAX_WINDOWS && !this._registered.has(windowId)) {
            throw new Error('Too many registered note windows');
        }
        this._registered.set(windowId, {noteId, floating});
        this._applyRegistrations();
    }

    /** Sets only a verified Stickies note above ordinary windows. */
    SetFloating(windowId, enabled) {
        const window = this._findWindow(windowId);
        if (!window || !this._registered.has(windowId)) {
            throw new Error('Stickies note window has not been registered');
        }
        if (enabled) {
            window.make_above();
        } else {
            window.unmake_above();
        }
        this._registered.get(windowId).floating = enabled;
    }

    /** Tiles or cascades only validated Stickies windows in caller order. */
    Arrange(mode, windowIds) {
        if (!['grid', 'cascade', 'by-title', 'by-date', 'by-color'].includes(mode)) {
            throw new Error('Unsupported Stickies arrangement');
        }
        if (windowIds.length > 1024) {
            throw new Error('Too many window identifiers');
        }
        const tokens = windowIds.split(',').filter(Boolean);
        if (tokens.length > MAX_WINDOWS || tokens.some(token => !/^\d{1,10}$/.test(token))) {
            throw new Error('Invalid window identifiers');
        }
        const windows = tokens.map(token => this._findWindow(Number(token)))
            .filter(window => window !== undefined && window !== null);
        if (windows.length === 0) {
            return;
        }
        const workspace = global.workspace_manager.get_active_workspace();
        const area = workspace.get_work_area_for_monitor(windows[0].get_monitor());
        const gap = 12;
        const columns = Math.min(windows.length,
            Math.max(1, Math.floor(area.width / (240 + gap))));
        const rows = Math.ceil(windows.length / columns);
        windows.forEach((window, index) => {
            if (window.is_maximized()) {
                window.unmaximize(Meta.MaximizeFlags.BOTH);
            }
            if (mode === 'cascade') {
                const width = Math.min(400, area.width - 2 * gap);
                const height = Math.min(340, area.height - 2 * gap);
                const x = area.x + gap + (index * 32) % Math.max(1, area.width - width - gap);
                const y = area.y + gap + (index * 32) % Math.max(1, area.height - height - gap);
                window.move_resize_frame(true, x, y, width, height);
                return;
            }
            const width = Math.floor((area.width - gap * (columns + 1)) / columns);
            const height = Math.floor((area.height - gap * (rows + 1)) / rows);
            const x = area.x + gap + (index % columns) * (width + gap);
            const y = area.y + gap + Math.floor(index / columns) * (height + gap);
            window.move_resize_frame(true, x, y, width, height);
        });
        this._recordAllPositions();
    }
}
