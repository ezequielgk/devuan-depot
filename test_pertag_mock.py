import re

with open("dwl-test/dwl.c", "r") as f:
    text = f.read()

mock_code = """
static int test_pertag_cb(void *data) {
    if (!selmon) return 0;
    fprintf(stderr, "=== PERTAG TEST ===\\n");
    fprintf(stderr, "DEBUG: Tag 1 layout: %s\\n", selmon->lt[selmon->sellt]->symbol);
    view(&((Arg){.ui = 2})); 
    setlayout(&((Arg){.v = &layouts[2]})); // monocle
    fprintf(stderr, "DEBUG: Tag 2 layout: %s\\n", selmon->lt[selmon->sellt]->symbol);
    view(&((Arg){.ui = 1}));
    fprintf(stderr, "DEBUG: Back to Tag 1 layout: %s\\n", selmon->lt[selmon->sellt]->symbol);
    fprintf(stderr, "===================\\n");
    return 0;
}
"""

text = text.replace("static void setup(void);", "static void setup(void);\n" + mock_code)

text = text.replace("	wlr_seat_set_capabilities(seat, WL_SEAT_CAPABILITY_POINTER", "	struct wl_event_source *t = wl_event_loop_add_timer(wl_display_get_event_loop(dpy), test_pertag_cb, NULL);\n	wl_event_source_timer_update(t, 1000);\n\twlr_seat_set_capabilities(seat, WL_SEAT_CAPABILITY_POINTER")

with open("dwl-test/dwl.c", "w") as f:
    f.write(text)
