using Gee;

namespace Stickies {
    /** One integer-coordinate point within a bounded vector ink stroke. */
    internal class InkPoint : GLib.Object {
        /** Horizontal coordinate in canvas pixels. */
        public int x { get; private set; }

        /** Vertical coordinate in canvas pixels. */
        public int y { get; private set; }

        /** Constructs a point after canvas bounds have been applied. */
        public InkPoint (int x, int y) {
            this.x = x;
            this.y = y;
        }
    }

    /** One separate pen stroke captured by the desktop drag gesture. */
    internal class InkStroke : GLib.Object {
        /** Ordered points drawn without pen lifts. */
        public Gee.ArrayList<InkPoint> points { get; private set; }

        /** Allocates a new stroke with no coordinates yet. */
        public InkStroke () {
            points = new Gee.ArrayList<InkPoint> ();
        }
    }

    /**
     * Captures pressure-independent mouse or tablet pointer handwriting.
     * The fixed canvas exports bounded, inert SVG paths without scripts or URLs.
     */
    public class InkCanvas : Gtk.DrawingArea {
        private const int CANVAS_WIDTH = 640;
        private const int CANVAS_HEIGHT = 360;
        private const int MAX_STROKES = 128;
        private const int MAX_POINTS_PER_STROKE = 500;
        private const double PEN_WIDTH = 3.0;
        private const double DOT_RADIUS = 1.5;

        private Gee.ArrayList<InkStroke> strokes;
        private InkStroke? current_stroke;
        private double start_x;
        private double start_y;
        private int content_left = 0;
        private int content_top = 0;
        private int content_right = CANVAS_WIDTH - 1;
        private int content_bottom = CANVAS_HEIGHT - 1;

        /** Sets up a finite drawing surface and installs the pointer gesture. */
        public InkCanvas () {
            strokes = new Gee.ArrayList<InkStroke> ();
            set_content_width (CANVAS_WIDTH);
            set_content_height (CANVAS_HEIGHT);
            set_draw_func ((area, context, width, height) => {
                ((InkCanvas) area).draw_strokes (context);
            });

            var drag = new Gtk.GestureDrag ();
            weak InkCanvas weak_canvas = this;
            drag.drag_begin.connect ((x, y) => {
                InkCanvas? canvas = weak_canvas;
                if (canvas != null) {
                    canvas.begin_stroke (x, y);
                }
            });
            drag.drag_update.connect ((offset_x, offset_y) => {
                InkCanvas? canvas = weak_canvas;
                if (canvas != null) {
                    canvas.continue_stroke (offset_x, offset_y);
                }
            });
            drag.drag_end.connect ((offset_x, offset_y) => {
                InkCanvas? canvas = weak_canvas;
                if (canvas != null) {
                    canvas.end_stroke (offset_x, offset_y);
                }
            });
            add_controller (drag);
        }

        /** Constrains ink to the letterboxed content shown by ImageKit. */
        public void set_image_geometry (int width, int height) {
            if (width < 1 || height < 1) {
                return;
            }
            double scale = Math.fmin (
                (double) CANVAS_WIDTH / width, (double) CANVAS_HEIGHT / height
            );
            double fitted_width = width * scale;
            double fitted_height = height * scale;
            content_left = (int) Math.ceil ((CANVAS_WIDTH - fitted_width) / 2.0);
            content_top = (int) Math.ceil ((CANVAS_HEIGHT - fitted_height) / 2.0);
            content_right = (int) Math.floor ((CANVAS_WIDTH + fitted_width) / 2.0) - 1;
            content_bottom = (int) Math.floor ((CANVAS_HEIGHT + fitted_height) / 2.0) - 1;
            clear_ink ();
        }

        /** Converts widget device coordinates to the stable 640×360 ink space. */
        private double scale_x (double value) {
            return value * CANVAS_WIDTH / get_allocated_width ();
        }

        /** Converts widget device coordinates to the stable 640×360 ink space. */
        private double scale_y (double value) {
            return value * CANVAS_HEIGHT / get_allocated_height ();
        }

        /** Begins one bounded stroke with the initial pointer coordinates. */
        private void begin_stroke (double x, double y) {
            if (strokes.size >= MAX_STROKES) {
                return;
            }
            start_x = x;
            start_y = y;
            int px = (int) scale_x (x);
            int py = (int) scale_y (y);
            if (px < content_left || px > content_right ||
                py < content_top || py > content_bottom) {
                return;
            }
            current_stroke = new InkStroke ();
            strokes.add (current_stroke);
            append_point (x, y);
        }

        /** Extends the current stroke using GTK's start-relative drag offsets. */
        private void continue_stroke (double offset_x, double offset_y) {
            append_point (start_x + offset_x, start_y + offset_y);
        }

        /** Records the endpoint and releases ownership of the active stroke. */
        private void end_stroke (double offset_x, double offset_y) {
            append_point (start_x + offset_x, start_y + offset_y);
            current_stroke = null;
        }

        /** Returns true if at least one pen stroke has been recorded. */
        public bool has_ink () {
            return strokes.size > 0;
        }

        /** Clears the canvas without modifying any previously saved attachment. */
        public void clear_ink () {
            strokes.clear ();
            current_stroke = null;
            queue_draw ();
        }

        /** Exports only numeric paths, preserving the sketch as editable vectors. */
        public string to_svg () {
            var result = new GLib.StringBuilder (
                "<svg xmlns=\"http://www.w3.org/2000/svg\" " +
                "viewBox=\"0 0 640 360\" width=\"640\" height=\"360\">\n"
            );
            foreach (var stroke in strokes) {
                if (stroke.points.size == 0) {
                    continue;
                }
                if (stroke.points.size == 1) {
                    var dot = stroke.points[0];
                    result.append_printf (
                        "<circle cx=\"%d\" cy=\"%d\" r=\"1.5\" fill=\"#242424\"/>\n",
                        dot.x, dot.y
                    );
                    continue;
                }
                result.append ("<path fill=\"none\" stroke=\"#242424\" " +
                    "stroke-width=\"3\" stroke-linecap=\"round\" " +
                    "stroke-linejoin=\"round\" d=\"");
                bool first = true;
                foreach (var point in stroke.points) {
                    result.append_printf (
                        "%s%d %d", first ? "M " : " L ", point.x, point.y
                    );
                    first = false;
                }
                result.append ("\"/>\n");
            }
            result.append ("</svg>\n");
            return result.str;
        }

        /** Adds a clamped, deduplicated point with strict complexity bounds. */
        private void append_point (double x, double y) {
            var stroke = current_stroke;
            if (stroke == null || stroke.points.size >= MAX_POINTS_PER_STROKE) {
                return;
            }
            int px = (int) scale_x (x);
            int py = (int) scale_y (y);
            px = px < content_left ? content_left :
                (px > content_right ? content_right : px);
            py = py < content_top ? content_top :
                (py > content_bottom ? content_bottom : py);
            if (stroke.points.size > 0) {
                var last = stroke.points[stroke.points.size - 1];
                if (last.x == px && last.y == py) {
                    return;
                }
            }
            stroke.points.add (new InkPoint (px, py));
            queue_draw ();
        }

        /** Draws captured vectors within the widget's GTK snapshot. */
        private void draw_strokes (Cairo.Context context) {
            context.scale (
                (double) get_allocated_width () / CANVAS_WIDTH,
                (double) get_allocated_height () / CANVAS_HEIGHT
            );
            context.set_source_rgb (0.14, 0.14, 0.14);
            context.set_line_width (PEN_WIDTH);
            context.set_line_cap (Cairo.LineCap.ROUND);
            context.set_line_join (Cairo.LineJoin.ROUND);
            foreach (var stroke in strokes) {
                if (stroke.points.size == 1) {
                    var dot = stroke.points[0];
                    context.arc (dot.x, dot.y, DOT_RADIUS, 0.0, 2.0 * Math.PI);
                    context.fill ();
                    continue;
                }
                bool first = true;
                foreach (var point in stroke.points) {
                    if (first) {
                        context.move_to (point.x, point.y);
                        first = false;
                    } else {
                        context.line_to (point.x, point.y);
                    }
                }
                context.stroke ();
            }
        }
    }
}
