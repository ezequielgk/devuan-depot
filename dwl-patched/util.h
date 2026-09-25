/* See LICENSE.dwm file for copyright and license details. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <xkbcommon/xkbcommon.h>

#define MAX(A, B)               ((A) > (B) ? (A) : (B))
#define MIN(A, B)               ((A) < (B) ? (A) : (B))
#define LENGTH(X)               (sizeof X / sizeof X[0])
#define END(A)                  ((A) + LENGTH(A))

static void die(const char *fmt, ...);
static void *ecalloc(size_t nmemb, size_t size);
static int fd_set_nonblock(int fd);
xkb_keysym_t keymap_get_one_sym_by_level(struct xkb_keymap *keymap,
        xkb_keycode_t key, xkb_layout_index_t layout, xkb_level_index_t level);

void
die(const char *fmt, ...) {
	va_list ap;

	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);

	if (fmt[0] && fmt[strlen(fmt)-1] == ':') {
		fputc(' ', stderr);
		perror(NULL);
	} else {
		fputc('\n', stderr);
	}

	exit(1);
}

void *
ecalloc(size_t nmemb, size_t size)
{
	void *p;

	if (!(p = calloc(nmemb, size)))
		die("calloc:");
	return p;
}

int
fd_set_nonblock(int fd) {
	int flags = fcntl(fd, F_GETFL);
	if (flags < 0) {
		perror("fcntl(F_GETFL):");
		return -1;
	}
	if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
		perror("fcntl(F_SETFL):");
		return -1;
	}

	return 0;
}

xkb_keysym_t
keymap_get_one_sym_by_level(struct xkb_keymap *keymap, xkb_keycode_t key,
        xkb_layout_index_t layout, xkb_level_index_t level)
{
    const xkb_keysym_t *syms;
    int count = xkb_keymap_key_get_syms_by_level(keymap, key, layout, level, &syms);
    return count ? syms[0] : XKB_KEY_NoSymbol;
}
