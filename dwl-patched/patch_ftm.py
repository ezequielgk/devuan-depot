import re

with open('Makefile', 'r') as f: makefile = f.read()
makefile = makefile.replace("client.h drwl.h", "client.h drwl.h wlr-foreign-toplevel-management-unstable-v1-protocol.h")
makefile += "\nwlr-foreign-toplevel-management-unstable-v1-protocol.h:\n\t$(WAYLAND_SCANNER) server-header \\\n\t\tprotocols/wlr-foreign-toplevel-management-unstable-v1.xml $@\n"
with open('Makefile', 'w') as f: f.write(makefile)

with open('dwl.c', 'r') as f: text = f.read()

# Hunk 1: Includes (make sure to include wlroots header)
text = text.replace(
    '#include <wlr/types/wlr_export_dmabuf_v1.h>', 
    '#include <wlr/types/wlr_export_dmabuf_v1.h>\n#include <wlr/types/wlr_foreign_toplevel_management_v1.h>'
)

# Hunk 2: Struct declarations (Client structure)
struct_listen = r'''	struct wl_listener set_decoration_mode;
	struct wl_listener destroy_decoration;'''
struct_listen_new = r'''	struct wl_listener set_decoration_mode;
	struct wl_listener destroy_decoration;
	struct wlr_foreign_toplevel_handle_v1 *foreign_toplevel;
	struct wl_listener factivate;
	struct wl_listener fclose;
	struct wl_listener ffullscreen;
	struct wl_listener fdestroy;'''
text = text.replace(struct_listen, struct_listen_new)

# Hunk 3: Static decls
static_decl = r'''static void xytonode(double x, double y, struct wlr_surface **psurface,
		Client **pc, LayerSurface **pl, double *nx, double *ny);
static void zoom(const Arg *arg);'''
static_decl_new = r'''static void xytonode(double x, double y, struct wlr_surface **psurface,
		Client **pc, LayerSurface **pl, double *nx, double *ny);
static void zoom(const Arg *arg);
static void createforeigntoplevel(Client *c);
static void factivatenotify(struct wl_listener *listener, void *data);
static void fclosenotify(struct wl_listener *listener, void *data);
static void fdestroynotify(struct wl_listener *listener, void *data);
static void ffullscreennotify(struct wl_listener *listener, void *data);'''
text = text.replace(static_decl, static_decl_new)

# Hunk 4: Global manager
text = text.replace(
    'static struct wlr_session_lock_v1 *cur_lock;\nstatic struct wl_listener lock_listener = {.notify = locksession};',
    'static struct wlr_session_lock_v1 *cur_lock;\nstatic struct wl_listener lock_listener = {.notify = locksession};\n\nstatic struct wlr_foreign_toplevel_manager_v1 *foreign_toplevel_mgr;'
)

# Hunk 5: applyrules (set title/appid)
applyrules = r'''	if (!(title = client_get_title(c)))
		title = broken;'''
applyrules_new = applyrules + r'''

	if (c->foreign_toplevel) {
		wlr_foreign_toplevel_handle_v1_set_app_id(c->foreign_toplevel, appid);
		wlr_foreign_toplevel_handle_v1_set_title(c->foreign_toplevel, title);
	}'''
text = text.replace(applyrules, applyrules_new)

# Hunk 6 & 7: focusclient
focusclient_1 = r'''			client_set_border_color(old_c, (float[])COLOR(colors[SchemeNorm][2]));

			client_activate_surface(old, 0);'''
focusclient_1_new = focusclient_1 + r'''
			if (old_c->foreign_toplevel)
				wlr_foreign_toplevel_handle_v1_set_activated(old_c->foreign_toplevel, 0);'''
text = text.replace(focusclient_1, focusclient_1_new)

focusclient_2 = r'''	/* Activate the new client */
	client_activate_surface(client_surface(c), 1);'''
focusclient_2_new = focusclient_2 + r'''
	if (c->foreign_toplevel)
		wlr_foreign_toplevel_handle_v1_set_activated(c->foreign_toplevel, 1);'''
text = text.replace(focusclient_2, focusclient_2_new)

# Hunk 8: mapnotify (call createforeigntoplevel)
mapnotify = r'''		c->border[i]->node.data = c;
	}'''
mapnotify_new = mapnotify + r'''

	createforeigntoplevel(c);'''
text = text.replace(mapnotify, mapnotify_new)

# Hunk 9: setmon
# WAIT! Hunk 9 succeeded originally because it didn't conflict. 
# Did dwl upstream change setmon?
setmon = r'''	if (oldmon)
		arrange(oldmon);
	if (m) {'''
setmon_new = r'''	if (oldmon) {
		if (c->foreign_toplevel)
			wlr_foreign_toplevel_handle_v1_output_leave(c->foreign_toplevel, oldmon->wlr_output);
		arrange(oldmon);
	}
	if (m) {
		if (c->foreign_toplevel)
			wlr_foreign_toplevel_handle_v1_output_enter(c->foreign_toplevel, m->wlr_output);'''
text = text.replace(setmon, setmon_new)

# Hunk 10: setup
setup = r'''	foreign_toplevel_list = wlr_ext_foreign_toplevel_list_v1_create(dpy,1);'''
setup_new = r'''	/* Initializes foreign toplevel management */
	foreign_toplevel_mgr = wlr_foreign_toplevel_manager_v1_create(dpy);

	foreign_toplevel_list = wlr_ext_foreign_toplevel_list_v1_create(dpy,1);'''
text = text.replace(setup, setup_new)

# Hunk 11 & 12: unmapnotify
unmapnotify = r'''		setmon(c, NULL, 0);
		wl_list_remove(&c->flink);
	}

	if (c->foreign_toplevel_handle) {'''
unmapnotify_new = r'''		setmon(c, NULL, 0);
		wl_list_remove(&c->flink);
	}

	if (c->foreign_toplevel) {
		wlr_foreign_toplevel_handle_v1_destroy(c->foreign_toplevel);
		c->foreign_toplevel = NULL;
	}

	if (c->foreign_toplevel_handle) {'''
text = text.replace(unmapnotify, unmapnotify_new)


# Hunk 13: updatetitle -- ALSO REPLACE printstatus WITH drawbars
updatetitle = r'''updatetitle(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, set_title);
	if (c == focustop(c->mon))
		drawbars();'''
updatetitle_new = r'''updatetitle(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, set_title);
	if (c->foreign_toplevel) {
		const char *title;
		if (!(title = client_get_title(c)))
			title = broken;
		wlr_foreign_toplevel_handle_v1_set_title(c->foreign_toplevel, title);
	}
	if (c == focustop(c->mon))
		drawbars();'''
text = text.replace(updatetitle, updatetitle_new)

# NEW HUNK: ffullscreennotify (fullscreen from protocol)
ftm_functions = r'''
void
createforeigntoplevel(Client *c)
{
	c->foreign_toplevel = wlr_foreign_toplevel_handle_v1_create(foreign_toplevel_mgr);

	LISTEN(&c->foreign_toplevel->events.request_activate, &c->factivate, factivatenotify);
	LISTEN(&c->foreign_toplevel->events.request_close, &c->fclose, fclosenotify);
	LISTEN(&c->foreign_toplevel->events.request_fullscreen, &c->ffullscreen, ffullscreennotify);
	LISTEN(&c->foreign_toplevel->events.destroy, &c->fdestroy, fdestroynotify);
}

void
factivatenotify(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, factivate);
	if (c->mon == selmon) {
		c->tags = c->mon->tagset[c->mon->seltags];
	} else {
		setmon(c, selmon, 0);
	}
	focusclient(c, 1);
	arrange(c->mon);
}

void
fclosenotify(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, fclose);
	client_send_close(c);
}

void
fdestroynotify(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, fdestroy);
	wl_list_remove(&c->factivate.link);
	wl_list_remove(&c->fclose.link);
	wl_list_remove(&c->fdestroy.link);
	wl_list_remove(&c->ffullscreen.link);
}

void
ffullscreennotify(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, ffullscreen);
	struct wlr_foreign_toplevel_handle_v1_fullscreen_event *event = data;
	setfullscreen(c, event->fullscreen);
}
'''

text = text + ftm_functions

with open('dwl.c', 'w') as f: f.write(text)
