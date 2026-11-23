namespace Stickies {
    /**
     * Draws eight visible crop handles over the true image rectangle.
     * Selection percentages are independent of GTK device scaling and image
     * dimensions; the caller owns persistence and native preview rendering.
     */
    public class CropSelectionOverlay : Gtk.DrawingArea {
        /** Notifies the XML-backed percentage controls after pointer editing. */
        public signal void selection_changed (int left, int top, int width, int height);

        private const double HANDLE_RADIUS = 6.0;
        private int left = 10;
        private int top = 10;
        private int width_percent = 80;
        private int height_percent = 80;
        private int initial_left;
        private int initial_top;
        private int initial_width;
        private int initial_height;
        private double start_x;
        private double start_y;
        private int horizontal_edge;
        private int vertical_edge;

        /** Installs an independent pointer gesture and accessible crop feedback. */
        public CropSelectionOverlay () {
            set_content_width (640);
            set_content_height (330);
            set_draw_func ((area, context, allocated_width, allocated_height) => {
                draw_selection (context, allocated_width, allocated_height);
            });
            tooltip_text = "Drag handles to resize, or drag inside to move the crop";
            var drag = new Gtk.GestureDrag ();
            drag.drag_begin.connect ((x, y) => begin_move (x, y));
            drag.drag_update.connect ((dx, dy) => move_selection (dx, dy));
            drag.drag_end.connect ((dx, dy) => move_selection (dx, dy));
            add_controller (drag);
        }

        /** Synchronizes the view from precise keyboard-accessible spin buttons. */
        public void set_selection (int x, int y, int width, int height) {
            if (x < 0 || y < 0 || width < 1 || height < 1 ||
                x + width > 100 || y + height > 100) {
                return;
            }
            left = x;
            top = y;
            width_percent = width;
            height_percent = height;
            queue_draw ();
        }

        /** Determines which edges/handles the pointer is moving. */
        private void begin_move (double x, double y) {
            double sx = x * 100.0 / get_allocated_width ();
            double sy = y * 100.0 / get_allocated_height ();
            double margin_x = HANDLE_RADIUS * 100.0 / get_allocated_width ();
            double margin_y = HANDLE_RADIUS * 100.0 / get_allocated_height ();
            start_x = sx;
            start_y = sy;
            initial_left = left;
            initial_top = top;
            initial_width = width_percent;
            initial_height = height_percent;
            horizontal_edge = Math.fabs (sx - left) <= margin_x ? -1 :
                (Math.fabs (sx - (left + width_percent)) <= margin_x ? 1 : 0);
            vertical_edge = Math.fabs (sy - top) <= margin_y ? -1 :
                (Math.fabs (sy - (top + height_percent)) <= margin_y ? 1 : 0);
            if (horizontal_edge == 0 && vertical_edge == 0 &&
                (sx < left || sx > left + width_percent ||
                sy < top || sy > top + height_percent)) {
                // Clicking outside begins a small new selection.
                horizontal_edge = 2;
                vertical_edge = 2;
                initial_left = (int) Math.round (sx);
                initial_top = (int) Math.round (sy);
                initial_width = 1;
                initial_height = 1;
            }
        }

        /** Adjusts a selection while enforcing a nonempty rectangle in bounds. */
        private void move_selection (double dx, double dy) {
            int shift_x = (int) Math.round (dx * 100.0 / get_allocated_width ());
            int shift_y = (int) Math.round (dy * 100.0 / get_allocated_height ());
            int x = initial_left;
            int y = initial_top;
            int right = initial_left + initial_width;
            int bottom = initial_top + initial_height;
            if (horizontal_edge == 0 && vertical_edge == 0) {
                x = (int) Math.fmax (0, Math.fmin (100 - initial_width,
                    initial_left + shift_x));
                y = (int) Math.fmax (0, Math.fmin (100 - initial_height,
                    initial_top + shift_y));
                right = x + initial_width;
                bottom = y + initial_height;
            } else {
                if (horizontal_edge == -1) {
                    x = (int) Math.fmax (0, Math.fmin (right - 1, x + shift_x));
                } else if (horizontal_edge != 0) {
                    right = (int) Math.fmax (x + 1, Math.fmin (100, right + shift_x));
                }
                if (vertical_edge == -1) {
                    y = (int) Math.fmax (0, Math.fmin (bottom - 1, y + shift_y));
                } else if (vertical_edge != 0) {
                    bottom = (int) Math.fmax (y + 1, Math.fmin (100, bottom + shift_y));
                }
            }
            set_selection (x, y, right - x, bottom - y);
            selection_changed (left, top, width_percent, height_percent);
        }

        /** Renders shaded exclusion and visible corner/edge handles. */
        private void draw_selection (Cairo.Context cr, int allocated_width, int allocated_height) {
            double sx = allocated_width / 100.0;
            double sy = allocated_height / 100.0;
            double x = left * sx;
            double y = top * sy;
            double width = width_percent * sx;
            double height = height_percent * sy;
            cr.set_source_rgba (0.0, 0.0, 0.0, 0.35);
            cr.rectangle (0, 0, allocated_width, allocated_height);
            cr.rectangle (x, y, width, height);
            cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
            cr.fill ();
            cr.set_source_rgb (1.0, 1.0, 1.0);
            cr.set_line_width (2.0);
            cr.rectangle (x, y, width, height);
            cr.stroke ();
            for (int index = 0; index < 9; index++) {
                if (index == 4) {
                    continue;
                }
                double px = x + (index % 3) * width / 2.0;
                double py = y + (index / 3) * height / 2.0;
                cr.set_source_rgb (1, 1, 1);
                cr.rectangle (px - HANDLE_RADIUS, py - HANDLE_RADIUS,
                    HANDLE_RADIUS * 2, HANDLE_RADIUS * 2);
                cr.fill_preserve ();
                cr.set_source_rgb (0.2, 0.2, 0.2);
                cr.set_line_width (1);
                cr.stroke ();
            }
        }
    }
}
