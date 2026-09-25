#include <wlr/types/wlr_input_method_v2.h>
#include <wlr/types/wlr_text_input_v3.h>

struct input_method_relay {
	struct wl_list text_inputs; /* struct text_input.link */
	struct wlr_input_method_v2 *input_method;

	struct wlr_surface *focused_surface;
	struct text_input *active_text_input;

	struct wl_list popups; /* input_method_popup.link */
	struct wlr_scene_tree *popup_tree;

	struct wl_listener new_text_input;
	struct wl_listener new_input_method;

	struct wl_listener input_method_commit;
	struct wl_listener input_method_grab_keyboard;
	struct wl_listener input_method_destroy;
	struct wl_listener input_method_new_popup_surface;

	struct wl_listener keyboard_grab_destroy;
	struct wl_listener focused_surface_destroy;
};

struct input_method_popup {
	struct wlr_input_popup_surface_v2 *popup_surface;
	struct wlr_scene_tree *tree;
	struct wlr_scene_tree *scene_surface;
	struct input_method_relay *relay;
	struct wl_list link; /* input_method_relay.popups */

	struct wl_listener destroy;
	struct wl_listener commit;
};

struct text_input {
	struct input_method_relay *relay;
	struct wlr_text_input_v3 *input;
	struct wl_list link;

	struct wl_listener enable;
	struct wl_listener commit;
	struct wl_listener disable;
	struct wl_listener destroy;
};

struct wlr_input_method_manager_v2 *input_method_manager;
struct wlr_text_input_manager_v3 *text_input_manager;
struct input_method_relay *input_method_relay;

/* functions used in dwl.c */
static int input_method_keyboard_grab_forward_key(
		KeyboardGroup *keyboard, struct wlr_keyboard_key_event *event);
static int input_method_keyboard_grab_forward_modifiers(KeyboardGroup *keyboard);
static struct input_method_relay *input_method_relay_create(void);
static void input_method_relay_finish(struct input_method_relay *relay);
static void input_method_relay_set_focus(struct input_method_relay *relay,
		struct wlr_surface *surface);

/* internal functions */
static struct text_input *get_active_text_input(struct input_method_relay *relay);
static struct wlr_input_method_keyboard_grab_v2 *get_keyboard_grab(KeyboardGroup *keyboard);
static int keyboard_is_emulated_by_input_method(struct wlr_keyboard *keyboard,
		struct wlr_input_method_v2 *input_method);
static void handle_focused_surface_destroy(struct wl_listener *listener, void *data);
static void handle_input_method_commit(struct wl_listener *listener, void *data);
static void handle_input_method_destroy(struct wl_listener *listener, void *data);
static void handle_input_method_grab_keyboard(struct wl_listener *listener, void *data);
static void handle_input_method_new_popup_surface(struct wl_listener *listener, void *data);
static void handle_keyboard_grab_destroy(struct wl_listener *listener, void *data);
static void handle_new_input_method(struct wl_listener *listener, void *data);
static void handle_new_text_input(struct wl_listener *listener, void *data);
static void handle_popup_surface_commit(struct wl_listener *listener, void *data);
static void handle_popup_surface_destroy(struct wl_listener *listener, void *data);
static void handle_text_input_commit(struct wl_listener *listener, void *data);
static void handle_text_input_destroy(struct wl_listener *listener, void *data);
static void handle_text_input_disable(struct wl_listener *listener, void *data);
static void handle_text_input_enable(struct wl_listener *listener, void *data);
static Monitor *output_from_wlr_output(struct wlr_output *wlr_output);
static Monitor *output_nearest_to(int lx, int ly);
static void send_state_to_input_method(struct input_method_relay *relay);
static void update_active_text_input(struct input_method_relay *relay);
static void update_popup_position(struct input_method_popup *popup);
static void update_popups_position(struct input_method_relay *relay);
static void update_text_inputs_focused_surface(struct input_method_relay *relay);

Monitor *
output_from_wlr_output(struct wlr_output *wlr_output)
{
	Monitor *m = NULL;
	wl_list_for_each(m, &mons, link) {
		if (m->wlr_output == wlr_output)
			return m;
	}
	return NULL;
}

Monitor *
output_nearest_to(int lx, int ly)
{
	double closest_x, closest_y;
	wlr_output_layout_closest_point(output_layout, NULL, lx, ly, &closest_x,
			&closest_y);

	return output_from_wlr_output(
			wlr_output_layout_output_at(output_layout, closest_x, closest_y));
}

int
keyboard_is_emulated_by_input_method(struct wlr_keyboard *keyboard,
		struct wlr_input_method_v2 *input_method)
{
	struct wlr_virtual_keyboard_v1 *virtual_keyboard;

	if (!keyboard || !input_method)
		return 0;

	virtual_keyboard = wlr_input_device_get_virtual_keyboard(&keyboard->base);

	return virtual_keyboard &&
			wl_resource_get_client(virtual_keyboard->resource) ==
				wl_resource_get_client(input_method->resource);
}

struct wlr_input_method_keyboard_grab_v2 *
get_keyboard_grab(KeyboardGroup *keyboard)
{
	struct wlr_input_method_v2 *input_method = input_method_relay->input_method;

	if (!input_method || !input_method->keyboard_grab || keyboard != kb_group ||
			keyboard_is_emulated_by_input_method(keyboard->virtual_keyboard,
				input_method))
		return NULL;

	return input_method->keyboard_grab;
}

int
input_method_keyboard_grab_forward_modifiers(KeyboardGroup *keyboard)
{
	struct wlr_input_method_keyboard_grab_v2 *keyboard_grab =
		get_keyboard_grab(keyboard);

	struct wlr_keyboard_modifiers *modifiers =
		&keyboard->wlr_group->keyboard.modifiers;

	if (keyboard_grab) {
		wlr_input_method_keyboard_grab_v2_set_keyboard(
				keyboard_grab, &keyboard->wlr_group->keyboard);
		wlr_input_method_keyboard_grab_v2_send_modifiers(keyboard_grab, modifiers);
		return 1;
	} else {
		return 0;
	}
}

int
input_method_keyboard_grab_forward_key(
		KeyboardGroup *keyboard, struct wlr_keyboard_key_event *event)
{
	struct wlr_input_method_keyboard_grab_v2 *keyboard_grab =
		get_keyboard_grab(keyboard);
	if (keyboard_grab) {
		wlr_input_method_keyboard_grab_v2_set_keyboard(
				keyboard_grab, &keyboard->wlr_group->keyboard);
		wlr_input_method_keyboard_grab_v2_send_key(keyboard_grab, event->time_msec,
				event->keycode, event->state);
		return 1;
	} else {
		return 0;
	}
}

struct text_input *
get_active_text_input(struct input_method_relay *relay)
{
	struct text_input *text_input;

	if (!relay->input_method)
		return NULL;

	wl_list_for_each(text_input, &relay->text_inputs, link) {
		if (text_input->input->focused_surface &&
				text_input->input->current_enabled)
			return text_input;
	}
	return NULL;
}

void
update_active_text_input(struct input_method_relay *relay)
{
	struct text_input *active_text_input = get_active_text_input(relay);

	if (relay->input_method && relay->active_text_input != active_text_input) {
		if (active_text_input)
			wlr_input_method_v2_send_activate(relay->input_method);
		else
			wlr_input_method_v2_send_deactivate(relay->input_method);
		wlr_input_method_v2_send_done(relay->input_method);
	}

	relay->active_text_input = active_text_input;
}

void
update_text_inputs_focused_surface(struct input_method_relay *relay)
{
	struct text_input *text_input;
	wl_list_for_each(text_input, &relay->text_inputs, link) {
		struct wlr_text_input_v3 *input = text_input->input;

		struct wlr_surface *new_focused_surface;
		if (relay->input_method && relay->focused_surface &&
			wl_resource_get_client(input->resource) ==
				wl_resource_get_client(relay->focused_surface->resource)) {
			new_focused_surface = relay->focused_surface;
		} else {
			new_focused_surface = NULL;
		}

		if (input->focused_surface == new_focused_surface)
			continue;
		if (input->focused_surface)
			wlr_text_input_v3_send_leave(input);
		if (new_focused_surface)
			wlr_text_input_v3_send_enter(input, new_focused_surface);
	}
}

void
update_popup_position(struct input_method_popup *popup)
{
	struct input_method_relay *relay = popup->relay;
	struct text_input *text_input = relay->active_text_input;
	struct wlr_box cursor_rect;
	struct wlr_xdg_surface *xdg_surface;
	struct wlr_layer_surface_v1 *layer_surface;
	struct wlr_scene_tree *tree;
	int lx, ly;
	Monitor *output;
	struct wlr_box output_box;
	struct wlr_xdg_positioner_rules positioner_rules;
	struct wlr_box popup_box;

	if (!text_input || !relay->focused_surface ||
			!popup->popup_surface->surface->mapped)
		return;

	xdg_surface = wlr_xdg_surface_try_from_wlr_surface(relay->focused_surface);
	layer_surface = wlr_layer_surface_v1_try_from_wlr_surface(relay->focused_surface);

	if ((text_input->input->current.features &
				WLR_TEXT_INPUT_V3_FEATURE_CURSOR_RECTANGLE) &&
			(xdg_surface || layer_surface)) {
		cursor_rect = text_input->input->current.cursor_rectangle;

		tree = relay->focused_surface->data;
		wlr_scene_node_coords(&tree->node, &lx, &ly);
		cursor_rect.x += lx;
		cursor_rect.y += ly;

		if (xdg_surface) {
			cursor_rect.x -= xdg_surface->geometry.x;
			cursor_rect.y -= xdg_surface->geometry.y;
		}
	} else {
		cursor_rect = (struct wlr_box){0};
	}

	output = output_nearest_to(cursor_rect.x, cursor_rect.y);
	if (!output || !output->wlr_output->enabled)
		return;

	wlr_output_layout_get_box(output_layout, output->wlr_output, &output_box);

	positioner_rules = (struct wlr_xdg_positioner_rules) {
		.anchor_rect = cursor_rect,
		.anchor = XDG_POSITIONER_ANCHOR_BOTTOM_LEFT,
		.gravity = XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT,
		.size =
		{
			.width = popup->popup_surface->surface->current.width,
			.height = popup->popup_surface->surface->current.height,
		},
		.constraint_adjustment = XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y |
			XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X,
	};

	wlr_xdg_positioner_rules_get_geometry(&positioner_rules, &popup_box);
	wlr_xdg_positioner_rules_unconstrain_box(&positioner_rules, &output_box, &popup_box);

	wlr_scene_node_set_position(&popup->tree->node, popup_box.x, popup_box.y);
	wlr_scene_node_raise_to_top(&relay->popup_tree->node);

	wlr_input_popup_surface_v2_send_text_input_rectangle(
			popup->popup_surface, &(struct wlr_box){
			.x = cursor_rect.x - popup_box.x,
			.y = cursor_rect.y - popup_box.y,
			.width = cursor_rect.width,
			.height = cursor_rect.height,
			});
}

void
update_popups_position(struct input_method_relay *relay)
{
	struct input_method_popup *popup;
	wl_list_for_each(popup, &relay->popups, link) {
		update_popup_position(popup);
	}
}

void
handle_input_method_commit(struct wl_listener *listener,
		void *data)
{
	struct input_method_relay *relay =
		wl_container_of(listener, relay, input_method_commit);
	struct wlr_input_method_v2 *input_method = relay->input_method;
	struct text_input *text_input = relay->active_text_input;

	if (!text_input)
		return;

	if (input_method->current.preedit.text) {
		wlr_text_input_v3_send_preedit_string(text_input->input,
				input_method->current.preedit.text,
				input_method->current.preedit.cursor_begin,
				input_method->current.preedit.cursor_end);
	}
	if (input_method->current.commit_text) {
		wlr_text_input_v3_send_commit_string(text_input->input,
				input_method->current.commit_text);
	}
	if (input_method->current.delete.before_length ||
			input_method->current.delete.after_length) {
		wlr_text_input_v3_send_delete_surrounding_text(text_input->input,
				input_method->current.delete.before_length,
				input_method->current.delete.after_length);
	}
	wlr_text_input_v3_send_done(text_input->input);
}

void
handle_keyboard_grab_destroy(struct wl_listener *listener,
		void *data)
{
	struct input_method_relay *relay =
		wl_container_of(listener, relay, keyboard_grab_destroy);
	struct wlr_input_method_keyboard_grab_v2 *keyboard_grab =
		relay->input_method->keyboard_grab;
	wl_list_remove(&relay->keyboard_grab_destroy.link);

	if (keyboard_grab->keyboard) {
		/* Send modifier state to original client */
		wlr_seat_keyboard_notify_modifiers(keyboard_grab->input_method->seat,
				&keyboard_grab->keyboard->modifiers);
	}
}

void
handle_input_method_grab_keyboard(struct wl_listener *listener,
		void *data)
{
	struct input_method_relay *relay =
		wl_container_of(listener, relay, input_method_grab_keyboard);
	struct wlr_input_method_keyboard_grab_v2 *keyboard_grab = data;

	struct wlr_keyboard *active_keyboard = &kb_group->wlr_group->keyboard;

	if (!keyboard_is_emulated_by_input_method(active_keyboard,
				relay->input_method)) {
		/* Send modifier state to grab */
		wlr_input_method_keyboard_grab_v2_set_keyboard(keyboard_grab,
				active_keyboard);
	}

	relay->keyboard_grab_destroy.notify = handle_keyboard_grab_destroy;
	wl_signal_add(&keyboard_grab->events.destroy, &relay->keyboard_grab_destroy);
}

void
handle_input_method_destroy(struct wl_listener *listener,
		void *data)
{
	struct input_method_relay *relay =
		wl_container_of(listener, relay, input_method_destroy);
	wl_list_remove(&relay->input_method_commit.link);
	wl_list_remove(&relay->input_method_grab_keyboard.link);
	wl_list_remove(&relay->input_method_new_popup_surface.link);
	wl_list_remove(&relay->input_method_destroy.link);
	relay->input_method = NULL;

	update_text_inputs_focused_surface(relay);
	update_active_text_input(relay);
}

void
handle_popup_surface_destroy(struct wl_listener *listener,
		void *data)
{
	struct input_method_popup *popup = wl_container_of(listener, popup, destroy);
	wlr_scene_node_destroy(&popup->tree->node);
	wl_list_remove(&popup->destroy.link);
	wl_list_remove(&popup->commit.link);
	wl_list_remove(&popup->link);
	free(popup);
}

void
handle_popup_surface_commit(struct wl_listener *listener,
		void *data)
{
	struct input_method_popup *popup = wl_container_of(listener, popup, commit);
	update_popup_position(popup);
}

void
handle_input_method_new_popup_surface(struct wl_listener *listener,
		void *data)
{
	struct input_method_relay *relay =
		wl_container_of(listener, relay, input_method_new_popup_surface);

	struct input_method_popup *popup = ecalloc(1, sizeof(*popup));
	popup->popup_surface = data;
	popup->relay = relay;

	popup->destroy.notify = handle_popup_surface_destroy;
	wl_signal_add(&popup->popup_surface->events.destroy, &popup->destroy);

	popup->commit.notify = handle_popup_surface_commit;
	wl_signal_add(&popup->popup_surface->surface->events.commit, &popup->commit);

	popup->tree = wlr_scene_tree_create(layers[LyrIMPopup]);
	popup->scene_surface = wlr_scene_subsurface_tree_create(
			popup->tree, popup->popup_surface->surface);
	popup->scene_surface->node.data = popup;

	wl_list_insert(&relay->popups, &popup->link);

	update_popup_position(popup);
}

void
handle_new_input_method(struct wl_listener *listener, void *data)
{
	struct input_method_relay *relay =
		wl_container_of(listener, relay, new_input_method);
	struct wlr_input_method_v2 *input_method = data;
	if (seat != input_method->seat)
		return;

	if (relay->input_method) {
		wlr_input_method_v2_send_unavailable(input_method);
		return;
	}

	relay->input_method = input_method;

	relay->input_method_commit.notify = handle_input_method_commit;
	wl_signal_add(&relay->input_method->events.commit,
			&relay->input_method_commit);

	relay->input_method_grab_keyboard.notify = handle_input_method_grab_keyboard;
	wl_signal_add(&relay->input_method->events.grab_keyboard,
			&relay->input_method_grab_keyboard);

	relay->input_method_destroy.notify = handle_input_method_destroy;
	wl_signal_add(&relay->input_method->events.destroy,
			&relay->input_method_destroy);

	relay->input_method_new_popup_surface.notify =
		handle_input_method_new_popup_surface;
	wl_signal_add(&relay->input_method->events.new_popup_surface,
			&relay->input_method_new_popup_surface);

	update_text_inputs_focused_surface(relay);
	update_active_text_input(relay);
}

void
send_state_to_input_method(struct input_method_relay *relay)
{
	struct wlr_input_method_v2 *input_method = relay->input_method;
	struct wlr_text_input_v3 *input = relay->active_text_input->input;

	if (input->active_features & WLR_TEXT_INPUT_V3_FEATURE_SURROUNDING_TEXT) {
		wlr_input_method_v2_send_surrounding_text(input_method,
				input->current.surrounding.text,
				input->current.surrounding.cursor,
				input->current.surrounding.anchor);
	}
	wlr_input_method_v2_send_text_change_cause(input_method,
			input->current.text_change_cause);
	if (input->active_features & WLR_TEXT_INPUT_V3_FEATURE_CONTENT_TYPE) {
		wlr_input_method_v2_send_content_type(input_method,
				input->current.content_type.hint,
				input->current.content_type.purpose);
	}
	wlr_input_method_v2_send_done(input_method);
}

void
handle_text_input_enable(struct wl_listener *listener, void *data)
{
	struct text_input *text_input = wl_container_of(listener, text_input, enable);
	struct input_method_relay *relay = text_input->relay;

	update_active_text_input(relay);
	if (relay->active_text_input == text_input) {
		update_popups_position(relay);
		send_state_to_input_method(relay);
	}
	wlr_text_input_v3_send_done(text_input->input);
}

void
handle_text_input_disable(struct wl_listener *listener,
		void *data)
{
	struct text_input *text_input =
		wl_container_of(listener, text_input, disable);
	update_active_text_input(text_input->relay);
}

void
handle_text_input_commit(struct wl_listener *listener, void *data)
{
	struct text_input *text_input = wl_container_of(listener, text_input, commit);
	struct input_method_relay *relay = text_input->relay;

	if (relay->active_text_input == text_input) {
		update_popups_position(relay);
		send_state_to_input_method(relay);
	}
}

void
handle_text_input_destroy(struct wl_listener *listener,
		void *data)
{
	struct text_input *text_input =
		wl_container_of(listener, text_input, destroy);
	wl_list_remove(&text_input->enable.link);
	wl_list_remove(&text_input->disable.link);
	wl_list_remove(&text_input->commit.link);
	wl_list_remove(&text_input->destroy.link);
	wl_list_remove(&text_input->link);
	update_active_text_input(text_input->relay);
	free(text_input);
}

void
handle_new_text_input(struct wl_listener *listener, void *data)
{
	struct input_method_relay *relay =
		wl_container_of(listener, relay, new_text_input);
	struct wlr_text_input_v3 *wlr_text_input = data;
	struct text_input *text_input;

	if (seat != wlr_text_input->seat)
		return;

	text_input = ecalloc(1, sizeof(*text_input));
	text_input->input = wlr_text_input;
	text_input->relay = relay;
	wl_list_insert(&relay->text_inputs, &text_input->link);

	text_input->enable.notify = handle_text_input_enable;
	wl_signal_add(&text_input->input->events.enable, &text_input->enable);

	text_input->disable.notify = handle_text_input_disable;
	wl_signal_add(&text_input->input->events.disable, &text_input->disable);

	text_input->commit.notify = handle_text_input_commit;
	wl_signal_add(&text_input->input->events.commit, &text_input->commit);

	text_input->destroy.notify = handle_text_input_destroy;
	wl_signal_add(&text_input->input->events.destroy, &text_input->destroy);

	update_text_inputs_focused_surface(relay);
}

void
handle_focused_surface_destroy(struct wl_listener *listener,
		void *data)
{
	struct input_method_relay *relay =
		wl_container_of(listener, relay, focused_surface_destroy);
	input_method_relay_set_focus(relay, NULL);
}

struct input_method_relay *
input_method_relay_create()
{
	struct input_method_relay *relay = ecalloc(1, sizeof(*relay));
	wl_list_init(&relay->text_inputs);
	wl_list_init(&relay->popups);
	relay->popup_tree = wlr_scene_tree_create(&scene->tree);

	relay->new_text_input.notify = handle_new_text_input;
	wl_signal_add(&text_input_manager->events.new_text_input, &relay->new_text_input);

	relay->new_input_method.notify = handle_new_input_method;
	wl_signal_add(&input_method_manager->events.new_input_method,
			&relay->new_input_method);

	relay->focused_surface_destroy.notify = handle_focused_surface_destroy;

	return relay;
}

void
input_method_relay_finish(struct input_method_relay *relay)
{
	wl_list_remove(&relay->new_text_input.link);
	wl_list_remove(&relay->new_input_method.link);
	free(relay);
}

void
input_method_relay_set_focus(struct input_method_relay *relay,
		struct wlr_surface *surface)
{
	if (!relay || relay->focused_surface == surface)
		return;

	if (relay->focused_surface)
		wl_list_remove(&relay->focused_surface_destroy.link);
	relay->focused_surface = surface;
	if (surface)
		wl_signal_add(&surface->events.destroy, &relay->focused_surface_destroy);

	update_text_inputs_focused_surface(relay);
	update_active_text_input(relay);
}
