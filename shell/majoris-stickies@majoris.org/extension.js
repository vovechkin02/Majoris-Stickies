import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {arrangeRects, chooseWorkArea, clampRect, validRectangle} from './layout.js';
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
    <method name="SetTranslucent">
      <arg type="u" name="windowId" direction="in"/>
      <arg type="b" name="enabled" direction="in"/>
    </method>
    <method name="ToggleSticky">
      <arg type="u" name="windowId" direction="in"/>
      <arg type="b" name="enabled" direction="out"/>
    </method>
    <method name="RestoreLayout"/>
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
        this._monitorsChangedId = Main.layoutManager.connect('monitors-changed', () => {
            this._reconcileMonitors();
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
        Main.layoutManager.disconnect(this._monitorsChangedId);
        for (const tracked of this._tracked.values()) {
            const actor = tracked.window.get_compositor_private();
            if (actor) {
                actor.opacity = 255;
            }
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

    /** Enumerate compositor work areas without assuming one active display. */
    _workAreas() {
        const workspace = global.workspace_manager.get_active_workspace();
        const areas = [];
        for (let index = 0; index < global.display.get_n_monitors(); index++) {
            const area = workspace.get_work_area_for_monitor(index);
            areas.push({index, x: area.x, y: area.y,
                width: area.width, height: area.height});
        }
        return areas;
    }

    /** Keep registered notes reachable when display topology changes. */
    _reconcileMonitors() {
        const areas = this._workAreas();
        for (const tracked of this._tracked.values()) {
            const rect = tracked.window.get_frame_rect();
            if (areas.some(area => validRectangle(rect) &&
                // A visible part of the titlebar is enough to keep the note there.
                rect.x < area.x + area.width && rect.x + rect.width > area.x &&
                rect.y < area.y + area.height && rect.y + 85 > area.y)) {
                continue;
            }
            const area = chooseWorkArea(this._layouts[tracked.noteId],
                areas, tracked.window.get_monitor());
            const placement = area ? clampRect(rect, area) : null;
            if (placement) {
                tracked.window.move_resize_frame(true, placement.x, placement.y,
                    placement.width, placement.height);
            }
        }
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
        const area = this._workAreas().find(entry =>
            entry.index === tracked.window.get_monitor());
        this._layouts[tracked.noteId] = {
            x: rect.x, y: rect.y, width: rect.width, height: rect.height,
            monitorArea: area ?? null,
            sticky: this._layouts[tracked.noteId]?.sticky === true,
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
            if (validRectangle(saved)) {
                const area = chooseWorkArea(saved, this._workAreas(), window.get_monitor());
                const rect = area ? clampRect(saved, area) : null;
                if (rect) {
                    window.move_resize_frame(true, rect.x, rect.y, rect.width, rect.height);
                }
            }
            if (registration.floating) {
                window.make_above();
            }
            if (saved?.sticky === true) {
                window.stick();
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

    /** Applies whole-window translucency through the compositor, not GTK CSS. */
    SetTranslucent(windowId, enabled) {
        const window = this._findWindow(windowId);
        if (!window || !this._registered.has(windowId)) {
            throw new Error('Stickies note window has not been registered');
        }
        const actor = window.get_compositor_private();
        if (!actor) {
            throw new Error('The note has no compositor surface');
        }
        actor.opacity = enabled ? 220 : 255;
    }

    /** Toggle workspace visibility without exposing a non-Stickies window. */
    ToggleSticky(windowId) {
        const window = this._findWindow(windowId);
        const registration = this._registered.get(windowId);
        if (!window || !registration) {
            throw new Error('Stickies note window has not been registered');
        }
        const saved = this._layouts[registration.noteId] ?? {};
        const enabled = saved.sticky !== true;
        if (enabled) {
            window.stick();
        } else {
            window.unstick();
        }
        this._layouts[registration.noteId] = {...saved, sticky: enabled};
        this._queueSave();
        return enabled;
    }

    /** Restore saved positions for currently tracked notes, monitor by monitor. */
    RestoreLayout() {
        const areas = this._workAreas();
        for (const tracked of this._tracked.values()) {
            const saved = this._layouts[tracked.noteId];
            if (!validRectangle(saved)) {
                continue;
            }
            const area = chooseWorkArea(saved, areas, tracked.window.get_monitor());
            const rect = area ? clampRect(saved, area) : null;
            if (rect) {
                tracked.window.move_resize_frame(
                    true, rect.x, rect.y, rect.width, rect.height
                );
            }
        }
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
        const windows = tokens
            .map(token => Number(token))
            .filter(windowId => this._registered.has(windowId))
            .map(windowId => this._findWindow(windowId))
            .filter(window => window !== undefined && window !== null);
        if (windows.length === 0) {
            return;
        }
        const areas = this._workAreas();
        for (const area of areas) {
            const group = windows.filter(window => window.get_monitor() === area.index);
            const placements = arrangeRects(group.length, area, mode);
            group.forEach((window, index) => {
                if (window.is_maximized()) {
                    window.unmaximize(Meta.MaximizeFlags.BOTH);
                }
                const rect = placements[index];
                if (rect) {
                    window.move_resize_frame(true, rect.x, rect.y, rect.width, rect.height);
                }
            });
        }
        this._recordAllPositions();
    }
}
