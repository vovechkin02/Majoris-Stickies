namespace Stickies {
    /**
     * Presents a note's text, formatting, attachments and window preferences.
     * The repository remains the only writer of durable note records.
     */
    [GtkTemplate (ui = "/com/majoris/stickies/note-window.ui")]
    public class NoteWindow : Adw.ApplicationWindow {
        private const int MAX_IMPORT_BYTES = 2 * 1024 * 1024;

        /** Executes a short, synchronous menu command. */
        private delegate void MenuCommand ();

        [GtkChild]
        private unowned Gtk.Button manager_button;
        [GtkChild]
        private unowned Gtk.MenuButton color_button;
        [GtkChild]
        private unowned Gtk.Button duplicate_button;
        [GtkChild]
        private unowned Gtk.Button delete_button;
        [GtkChild]
        private unowned Gtk.MenuButton more_button;
        [GtkChild]
        private unowned Gtk.Box paper_box;
        [GtkChild]
        private unowned Gtk.Entry title_entry;
        [GtkChild]
        private unowned Gtk.TextView body_view;
        [GtkChild]
        private unowned Gtk.Label save_label;
        [GtkChild]
        private unowned Gtk.Box attachments_box;
        [GtkChild]
        private unowned Gtk.Button bold_button;
        [GtkChild]
        private unowned Gtk.Button italic_button;
        [GtkChild]
        private unowned Gtk.Button underline_button;
        [GtkChild]
        private unowned Gtk.Button strike_button;
        [GtkChild]
        private unowned Gtk.Button mono_button;
        [GtkChild]
        private unowned Gtk.Button large_button;
        [GtkChild]
        private unowned Gtk.Button small_button;

        private StickiesApp owner;
        private NoteRepository repository;
        private Note note;
        private GLib.Cancellable attachment_cancellable;
        private bool is_syncing_view = false;
        private string current_color = "";
        private string last_rendered_formatting = "";
        private Gtk.Button? collapse_button;
        private Gtk.Button? float_button;
        private Gtk.Button? translucent_button;

        /** Constructs the independent editor without leaking storage operations into GTK. */
        public NoteWindow (StickiesApp owner, NoteRepository repository, Note note) {
            Object (application: owner);
            this.owner = owner;
            this.repository = repository;
            this.note = note;
            attachment_cancellable = new GLib.Cancellable ();
            RichTextCodec.prepare (body_view.buffer);
            paper_box.add_css_class ("note-paper");
            set_default_size (note.window_width, note.is_collapsed ? 90 : note.window_height);
            apply_color (note.color);
            populate_editor ();
            create_color_menu ();
            create_options_menu ();
            connect_format_buttons ();
            refresh_attachments ();

            title_entry.changed.connect (on_title_changed);
            body_view.buffer.changed.connect (on_body_changed);
            manager_button.clicked.connect (() => owner.show_manager ());
            duplicate_button.clicked.connect (() => owner.duplicate_and_open_note (note.id));
            delete_button.clicked.connect (() => owner.confirm_delete_note (note.id, this));
            repository.note_updated.connect (on_note_updated);
            repository.note_saved.connect (on_note_saved);
            repository.attachment_changed.connect (on_attachment_changed);
            repository.save_failed.connect (on_save_failed);
            this.close_request.connect (on_close_request);
        }

        /** Returns this window's note identity. */
        public string note_id () {
            return note.id;
        }

        /** Shows a save failure without dropping unsaved editor data. */
        public void show_save_failure (string message) {
            save_label.label = "Not saved — " + message;
            save_label.tooltip_text = message;
        }

        /** Renders current state without recursively issuing repository edits. */
        private void populate_editor () {
            is_syncing_view = true;
            title = note.title + " — Stickies";
            if (title_entry.text != note.title) {
                title_entry.text = note.title;
            }
            if (body_view.buffer.text != note.content ||
                last_rendered_formatting != note.formatting) {
                RichTextCodec.load (body_view.buffer, note.content, note.formatting);
                last_rendered_formatting = note.formatting;
            }
            apply_color (note.color);
            apply_presentation ();
            is_syncing_view = false;
        }

        /** Changes only paper styling; system chrome remains owned by the theme. */
        private void apply_color (string color) {
            if (current_color != "") {
                paper_box.remove_css_class ("note-" + current_color);
            }
            paper_box.add_css_class ("note-" + color);
            current_color = color;
        }

        /** Applies the supported in-window presentation preferences. */
        private void apply_presentation () {
            paper_box.visible = !note.is_collapsed;
            paper_box.opacity = note.is_translucent ? 0.87 : 1.0;
            if (collapse_button != null) {
                collapse_button.label = note.is_collapsed ? "Expand Note" : "Collapse Note";
            }
            if (float_button != null) {
                float_button.label = note.is_floating ? "Disable Always on Top" : "Always on Top";
            }
            if (translucent_button != null) {
                translucent_button.label = note.is_translucent ? "Opaque Paper" : "Translucent Paper";
            }
        }

        /** Builds the palette popover from the single shared list of paper colors. */
        private void create_color_menu () {
            var popover = new Gtk.Popover ();
            var grid = new Gtk.Grid ();
            grid.column_spacing = 6;
            grid.row_spacing = 6;
            grid.margin_top = 10;
            grid.margin_bottom = 10;
            grid.margin_start = 10;
            grid.margin_end = 10;
            int index = 0;
            foreach (var color in NotePalette.all_colors ()) {
                var selection = color;
                var button = new Gtk.Button.with_label (NotePalette.label_for (selection));
                button.add_css_class ("color-chip");
                button.add_css_class ("note-" + selection);
                button.tooltip_text = NotePalette.label_for (selection);
                button.clicked.connect (() => {
                    repository.set_color (note.id, selection);
                    popover.popdown ();
                });
                grid.attach (button, index % 2, index / 2, 1, 1);
                index++;
            }
            popover.set_child (grid);
            color_button.popover = popover;
        }

        /** Creates explicit note commands in the existing Majoris menu style. */
        private void create_options_menu () {
            var popover = new Gtk.Popover ();
            var menu = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            menu.margin_top = 8;
            menu.margin_bottom = 8;
            menu.margin_start = 8;
            menu.margin_end = 8;

            collapse_button = menu_item (menu, "Collapse Note", () => {
                toggle_collapsed ();
                popover.popdown ();
            });
            float_button = menu_item (menu, "Always on Top", () => {
                toggle_floating ();
                popover.popdown ();
            });
            translucent_button = menu_item (menu, "Translucent Paper", () => {
                toggle_translucent ();
                popover.popdown ();
            });
            menu.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            menu_item (menu, "Attach Image or PDF…", () => {
                popover.popdown ();
                choose_attachment ();
            });
            menu_item (menu, "Import Plain Text…", () => {
                popover.popdown ();
                choose_import ();
            });
            menu_item (menu, "Export Plain Text…", () => {
                popover.popdown ();
                choose_export ();
            });
            popover.set_child (menu);
            more_button.popover = popover;
            apply_presentation ();
        }

        /** Adds a text-only item, leaving menu item styling to the global theme. */
        private Gtk.Button menu_item (Gtk.Box menu, string label, owned MenuCommand action) {
            var button = new Gtk.Button.with_label (label);
            button.halign = Gtk.Align.FILL;
            button.add_css_class ("flat");
            button.clicked.connect (() => {
                action ();
            });
            menu.append (button);
            return button;
        }

        /** Wires formatting controls through a single tag-selection operation. */
        private void connect_format_buttons () {
            bold_button.clicked.connect (() => format_selection ("bold"));
            italic_button.clicked.connect (() => format_selection ("italic"));
            underline_button.clicked.connect (() => format_selection ("underline"));
            strike_button.clicked.connect (() => format_selection ("strikethrough"));
            mono_button.clicked.connect (() => format_selection ("monospace"));
            large_button.clicked.connect (() => format_selection ("large"));
            small_button.clicked.connect (() => format_selection ("small"));

            var key_controller = new Gtk.EventControllerKey ();
            key_controller.key_pressed.connect ((keyval, keycode, modifiers) => {
                if ((modifiers & Gdk.ModifierType.CONTROL_MASK) == 0) {
                    return false;
                }
                if (keyval == Gdk.Key.b) {
                    format_selection ("bold");
                    return true;
                }
                if (keyval == Gdk.Key.i) {
                    format_selection ("italic");
                    return true;
                }
                if (keyval == Gdk.Key.u) {
                    format_selection ("underline");
                    return true;
                }
                return false;
            });
            body_view.add_controller (key_controller);
        }

        /** Changes supported formatting on selected text only. */
        private void format_selection (string style) {
            if (!RichTextCodec.toggle_selected (body_view.buffer, style)) {
                save_label.label = "Select text to format";
                return;
            }
            persist_editor_body ();
        }

        /** Sends both rich-text runs and text through one repository update. */
        private void persist_editor_body () {
            var text = body_view.buffer.text;
            var formatting = RichTextCodec.serialize (body_view.buffer);
            if (!NoteFormatting.is_valid (text, formatting)) {
                show_save_failure ("Formatting exceeds the supported note limits");
                return;
            }
            last_rendered_formatting = formatting;
            repository.set_body (note.id, text, formatting);
        }

        /** Sends title changes without issuing SQL writes per key press. */
        private void on_title_changed () {
            if (!is_syncing_view) {
                repository.set_title (note.id, title_entry.text);
            }
        }

        /** Sends text changes with style positions preserved by GtkTextBuffer. */
        private void on_body_changed () {
            if (!is_syncing_view) {
                persist_editor_body ();
            }
        }

        /** Refreshes presentation and file cards when this note changes. */
        private void on_note_updated (Note changed_note) {
            if (changed_note.id != note.id) {
                return;
            }
            populate_editor ();
            save_label.label = "Saving…";
        }

        /** Refreshes only this note's file cards after attachment operations. */
        private void on_attachment_changed (string id) {
            if (id == note.id) {
                refresh_attachments ();
            }
        }

        /** Marks a durable save and clears any prior error tooltip. */
        private void on_note_saved (Note saved_note) {
            if (saved_note.id == note.id) {
                save_label.label = "Saved";
                save_label.tooltip_text = null;
            }
        }

        /** Reports an asynchronous database failure for this editor. */
        private void on_save_failed (string id, string message) {
            if (id == note.id) {
                show_save_failure (message);
            }
        }

        /** Collapses the editable paper while keeping prior dimensions for restoration. */
        private void toggle_collapsed () {
            var collapsed = !note.is_collapsed;
            int width = note.window_width;
            int height = note.window_height;
            if (!note.is_collapsed) {
                width = (get_width () > 240 ? get_width () : 240);
                height = (get_height () > 120 ? get_height () : 120);
            }
            repository.set_presentation (
                note.id, collapsed, note.is_floating, note.is_translucent,
                width, height, true
            );
            set_default_size (width, collapsed ? 90 : height);
        }

        /** Stores the floating preference and requests compositor integration. */
        private void toggle_floating () {
            var requested = !note.is_floating;
            owner.request_floating (this, requested);
        }

        /** Applies semitransparent paper without changing the window's chrome. */
        private void toggle_translucent () {
            repository.set_presentation (
                note.id, note.is_collapsed, note.is_floating, !note.is_translucent,
                note.window_width, note.window_height, true
            );
        }

        /** Prompts for a local image/PDF to copy into private attachment storage. */
        private void choose_attachment () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Attach Image or PDF";
            dialog.open.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.open.end (result);
                    attach_selected.begin (file);
                } catch (Error error) {
                    if (!attachment_cancellable.is_cancelled ()) {
                        save_label.label = "Attachment selection canceled";
                    }
                }
            });
        }

        /** Copies an attachment asynchronously and reloads its file card. */
        private async void attach_selected (GLib.File file) {
            try {
                yield repository.attach_file (note.id, file, attachment_cancellable);
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

        /** Rebuilds file cards with an ImageKit viewer for images, when available. */
        private void refresh_attachments () {
            Gtk.Widget? child = attachments_box.get_first_child ();
            while (child != null) {
                attachments_box.remove (child);
                child = attachments_box.get_first_child ();
            }
            try {
                foreach (var attachment in repository.list_attachments (note.id)) {
                    var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                    var icon = new Gtk.Image.from_icon_name (
                        attachment.is_image () ? "image-x-generic-symbolic" :
                        "application-pdf-symbolic"
                    );
                    row.append (icon);
                    var open_button = new Gtk.Button.with_label (attachment.display_name);
                    open_button.hexpand = true;
                    row.append (open_button);
                    open_button.clicked.connect (() => open_attachment (attachment));
                    var remove_button = new Gtk.Button.from_icon_name ("edit-delete-symbolic");
                    remove_button.tooltip_text = "Remove Attachment";
                    remove_button.clicked.connect (() => {
                        try {
                            repository.remove_attachment (note.id, attachment.id);
                        } catch (Error error) {
                            show_save_failure (error.message);
                        }
                    });
                    row.append (remove_button);
                    attachments_box.append (row);
#if HAVE_IMAGEKIT
                    if (attachment.is_image ()) {
                        var viewer = new ImageKit.ImageView ();
                        viewer.set_size_request (-1, 120);
                        attachments_box.append (viewer);
                        var file = GLib.File.new_for_path (attachment.path);
                        viewer.load_file.begin (
                            file, null, attachment_cancellable, (object, result) => {
                            try {
                                viewer.load_file.end (result);
                            } catch (IOError.CANCELLED error) {
                                return;
                            } catch (Error error) {
                                warning ("Attachment preview failed: %s", error.message);
                            }
                        });
                    }
#endif
                }
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

        /** Opens the original copy in the user's default external application. */
        private void open_attachment (NoteAttachment attachment) {
            try {
                var file = GLib.File.new_for_path (attachment.path);
                GLib.AppInfo.launch_default_for_uri (file.get_uri (), null);
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

        /** Shows a native plain-text import chooser. */
        private void choose_import () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Import Plain Text";
            dialog.open.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.open.end (result);
                    import_text_async.begin (file);
                } catch (Error error) {
                    save_label.label = "Import canceled";
                }
            });
        }

        /** Imports bounded UTF-8 off the GTK main loop without executing markup. */
        private async void import_text_async (GLib.File file) {
            try {
                var info = yield file.query_info_async (
                    "standard::size,standard::type",
                    GLib.FileQueryInfoFlags.NONE,
                    GLib.Priority.DEFAULT,
                    attachment_cancellable
                );
                if (info.get_file_type () != GLib.FileType.REGULAR ||
                    info.get_size () < 0 || info.get_size () > MAX_IMPORT_BYTES) {
                    throw new IOError.INVALID_DATA ("Only text files up to 2 MiB are supported");
                }
                uint8[] bytes;
                string? etag;
                yield file.load_contents_async (attachment_cancellable, out bytes, out etag);
                if (bytes.length > MAX_IMPORT_BYTES) {
                    throw new IOError.INVALID_DATA ("The imported text is too large");
                }
                foreach (uint8 value in bytes) {
                    if (value == 0) {
                        throw new IOError.INVALID_DATA ("The imported text contains binary data");
                    }
                }
                string text = (string) bytes;
                if (!text.validate ()) {
                    throw new IOError.INVALID_DATA ("The text file must be valid UTF-8");
                }
                is_syncing_view = true;
                RichTextCodec.load (body_view.buffer, text, "");
                last_rendered_formatting = "";
                is_syncing_view = false;
                repository.set_body (note.id, text, "");
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure (error.message);
            } finally {
                is_syncing_view = false;
            }
        }

        /** Opens a native plain-text export destination chooser. */
        private void choose_export () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Export Plain Text";
            dialog.initial_name = "note.txt";
            dialog.save.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.save.end (result);
                    export_text_async.begin (file);
                } catch (Error error) {
                    save_label.label = "Export canceled";
                }
            });
        }

        /** Exports UTF-8 asynchronously without changing the note's stored text. */
        private async void export_text_async (GLib.File file) {
            try {
                var text = body_view.buffer.text;
                string? new_etag;
                yield file.replace_contents_async (
                    text.data,
                    null,
                    false,
                    GLib.FileCreateFlags.REPLACE_DESTINATION,
                    attachment_cancellable,
                    out new_etag
                );
                save_label.label = "Exported";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

        /** Flushes pending edits before closing and records the last editor size. */
        private bool on_close_request () {
            if (repository.find_note (note.id) != null) {
                int width = note.is_collapsed ? note.window_width :
                    (get_width () > 240 ? get_width () : 240);
                int height = note.is_collapsed ? note.window_height :
                    (get_height () > 120 ? get_height () : 120);
                repository.set_presentation (
                    note.id, note.is_collapsed, note.is_floating, note.is_translucent,
                    width, height, false
                );
                try {
                    repository.flush_note (note.id);
                } catch (Error error) {
                    show_save_failure (error.message);
                    return true;
                }
            }
            attachment_cancellable.cancel ();
            repository.note_updated.disconnect (on_note_updated);
            repository.note_saved.disconnect (on_note_saved);
            repository.attachment_changed.disconnect (on_attachment_changed);
            repository.save_failed.disconnect (on_save_failed);
            owner.note_window_was_closed (note.id, this);
            return false;
        }
    }
}
