# Changelog

* [0.9](#0.9)
* [0.8](#0.8)
* [0.7](#0.7)
* [0.6](#0.6)
* [0.5](#0.5)


## 0.9

### Added

* Add axis mouse bindings ([#652][652])
* Add support for the ext-data-control protocol ([#1184][1184])
* Add support for the ext-foreign-toplevel-list protocol ([#1223][1223])
* Add support for the ext-image-copy-capture and ext-image-capture-source protocols (screensharing) ([#1218][1218], [#1223][1223], [#1224][1224])
* Add support for version 4 of the layer shell protocol (on-demand keyboard interactivity) ([#674][674])
* Add support for wlr-text-input and wlr-input-method protocols (IME) ([#1219][1219])
* Snap windows to edges when moving or resizing them ([#608][608])

[1184]: https://codeberg.org/dwl/dwl/pulls/1184
[1218]: https://codeberg.org/dwl/dwl/pulls/1218
[1219]: https://codeberg.org/dwl/dwl/pulls/1219
[1223]: https://codeberg.org/dwl/dwl/pulls/1223
[1224]: https://codeberg.org/dwl/dwl/pulls/1224
[608]: https://codeberg.org/dwl/dwl/pulls/608
[652]: https://codeberg.org/dwl/dwl/pulls/652
[674]: https://codeberg.org/dwl/dwl/pulls/674


### Changed

* Update wlroots to version 0.20 ([#1218][1218])
* Use modifier-independent key symbols in config.h keybindings ([#1075][1075])

[1075]: https://codeberg.org/dwl/dwl/pulls/1075
[1218]: https://codeberg.org/dwl/dwl/pulls/1218


### Fixed

* Apply a minimum window size of 1x1 ([#1231][1231])
* Close Xwayland submenus when changing tag or focus ([#1233][1233])
* Don't make Firefox draw rounded corners when it is opened ([#d1ebf3c][d1ebf3c])
* Don't send key release events to the wrong client ([#1108][1108])
* Fix a crash when closing mpv ([#1220][1220])
* Fix a crash when destroying an idle-inhibitor ([#1214][1214])
* Fix choppy resizing on newer wlroots ([#1280][1280])
* Fix the position of certain sub-menus in Xwayland applications ([#1232][1232])
* Keep the focused border color on the regular client when opening a layer shell surface like wmenu ([#6013835][6013835])
* Let keybindings focus and tag monitors above and below ([#5fd19fe][5fd19fe])
* Preserve asleep disabled outputs in output config ([#1198][1198])
* Respect size hints ([#4de32d2][4de32d2])
* Set seat capabilities for virtual keyboards and pointers when there is no other input device ([#99cdc9a][99cdc9a])
* Show popups in fullscreen Xwayland applications ([#1fe1b4e][1fe1b4e])
* Show the correct cursor after moving and resizing ([#8ad2c92][8ad2c92])

[1108]: https://codeberg.org/dwl/dwl/pulls/1108
[1198]: https://codeberg.org/dwl/dwl/pulls/1198
[1214]: https://codeberg.org/dwl/dwl/pulls/1214
[1220]: https://codeberg.org/dwl/dwl/pulls/1220
[1231]: https://codeberg.org/dwl/dwl/pulls/1231
[1232]: https://codeberg.org/dwl/dwl/pulls/1232
[1233]: https://codeberg.org/dwl/dwl/pulls/1233
[1280]: https://codeberg.org/dwl/dwl/pulls/1280
[1fe1b4e]: https://codeberg.org/dwl/dwl/commit/1fe1b4e
[4de32d2]: https://codeberg.org/dwl/dwl/commit/4de32d2
[5fd19fe]: https://codeberg.org/dwl/dwl/commit/5fd19fe
[6013835]: https://codeberg.org/dwl/dwl/commit/6013835
[8ad2c92]: https://codeberg.org/dwl/dwl/commit/8ad2c92
[99cdc9a]: https://codeberg.org/dwl/dwl/commit/99cdc9a
[d1ebf3c]: https://codeberg.org/dwl/dwl/commit/d1ebf3c


### Contributors


* A Frederick Christensen
* Alex Denes
* Andrea Chiavazza
* Diego Viola
* Guido Cella
* Leonardo Hernández Hernández
* Peter Hofmann
* Siva Mahadevan
* julmajustus
* klim
* save196
* sewn
* thanatos


## 0.8

### Added

* Support for the linux-drm-syncobj-v1 protocol ([wlroots!4715][wlroots!4715], [#685][685])
* Allow the use of non-system wlroots library ([#646][646])

[wlroots!4715]: https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/4715
[685]: https://codeberg.org/dwl/dwl/pulls/685
[646]: https://codeberg.org/dwl/dwl/pulls/646


### Fixed

* Crash when a client is created while all outputs are disabled.


Most changes in this release are not listed. See the commits for details.


## 0.7

This version is just 0.6 with wlroots 0.18 compatibility.

### Added

* Add support for the alpha-modifier-v1 protocol ([wlroots!4616][wlroots!4616]).
* dwl now will survive GPU resets ([#601][601]).

[wlroots!4616]: https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/4616
[601]: https://codeberg.org/dwl/dwl/issues/601


### Contributors

Guido Cella


## 0.6

### Added

* Add `rootcolor` to change the default background color ([#544][544]).
* Implement the wlr-virtual-pointer-unstable-v1 protocol ([#574][574]).
* Implement the pointer-constraints and relative-pointer protocols ([#317][317])
* Implement the wlr-output-power-management protocol ([#599][599])

[544]: https://codeberg.org/dwl/dwl/pulls/544
[574]: https://codeberg.org/dwl/dwl/pulls/574
[317]: https://codeberg.org/dwl/dwl/issues/317
[599]: https://codeberg.org/dwl/dwl/issues/559


### Changed

* Keyboards are now managed through keyboard groups ([#549][549]).
* Only the first matched keybinding is executed.
* Allow toggling the layout before selecting a different one ([#570][570]).
* Fullscreen clients are now rendered above wlr_layer_surfaces in the top layer
  ([#609][609]).
* The default menu was changed from `bemenu-run` to `wmenu-run` ([#553][553]).
* The option `sloppyfocus` now replicates the dwm behavior ([#599][599]).
* Allow configure position of monitors with negative values. (-1, -1) is
  used to auto-configure them ([#635][635]).
* dwl now kills the entire process group of `startup_cmd`
* The O_NONBLOCK flag is set for stdout.

[549]: https://codeberg.org/dwl/dwl/pulls/549
[570]: https://codeberg.org/dwl/dwl/pulls/570
[609]: https://codeberg.org/dwl/dwl/pulls/609
[553]: https://codeberg.org/dwl/dwl/issues/553
[599]: https://codeberg.org/dwl/dwl/pulls/599
[635]: https://codeberg.org/dwl/dwl/pulls/635


### Removed

* The SLOC limit is now removed ([#497][497]).

[497]: https://codeberg.org/dwl/dwl/pulls/497


### Fixed

* Clients not having the correct border color when mapping.
* Compliance with the xdg-decoration-unstable-v1 ([#546][546]).
* dwl no longer sends negative values in xdg_toplevel.configure events.
* Crashes with disabled monitors ([#472][472]).

[546]: https://codeberg.org/dwl/dwl/pulls/546
[472]: https://codeberg.org/dwl/dwl/issues/472


### Contributors

Ben Jargowsky
Benjamin Chausse
David Donahue
Devin J. Pohly
Dima Krasner
Emil Miler
Forrest Bushstone
Guido Cella
Peter Hofmann
Rutherther
Squibid
choc
fictitiousexistence
korei999
sewn
thanatos


## 0.5

### Added

* Allow configure x and y position of outputs ([#301][301])
* Implement repeatable keybindings ([#368][368])
* Print app id in printstatus() output ([#381][381])
* Display client count in monocle symbol ([#387][387])
* Export XCURSOR_SIZE to fix apps using an older version of Qt ([#425][425])
* Support for wp-fractional-scale-v1 (through wlr_scene: [wlroots!3511][wlroots!3511])
* dwl now sends `wl_surface.preferred_buffer_scale` (through wlr_scene: [wlroots!4269][wlroots!4269])
* Add support for xdg-shell v6 ([#465][465])
* Add support for wp-cursor-shape-v1 ([#444][444])
* Add desktop file ([#484][484])
* Add macro to easily configure colors ([#466][466])
* Color of urgent clients are now red ([#494][494])
* New flag `-d` and option `log_level` to change the wlroots debug level
* Add CHANGELOG.md ([#501][501])

[301]: https://github.com/djpohly/dwl/pull/301
[368]: https://github.com/djpohly/dwl/pull/368
[381]: https://github.com/djpohly/dwl/pull/381
[387]: https://github.com/djpohly/dwl/issues/387
[425]: https://github.com/djpohly/dwl/pull/425
[wlroots!4269]: https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/4269
[wlroots!3511]: https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/3511
[465]: https://github.com/djpohly/dwl/pull/465
[444]: https://github.com/djpohly/dwl/pull/444
[484]: https://github.com/djpohly/dwl/pull/484
[466]: https://github.com/djpohly/dwl/issues/466
[494]: https://github.com/djpohly/dwl/pull/494
[501]: https://github.com/djpohly/dwl/pull/501


### Changed

* Replace `tags` with `TAGCOUNT` in config.def.h ([#403][403])
* Pop ups are now destroyed when focusing another client ([#408][408])
* dwl does not longer respect size hints, instead clip windows if they are
  larger than they should be ([#455][455])
* The version of wlr-layer-shell-unstable-v1 was lowered to 3 (from 4)
* Use the same border color as dwm ([#494][494])

[403]: https://github.com/djpohly/dwl/pull/403
[408]: https://github.com/djpohly/dwl/pull/409
[455]: https://github.com/djpohly/dwl/pull/455
[494]: https://github.com/djpohly/dwl/pull/494


### Removed

* Remove unused `rootcolor` option ([#401][401])
* Remove support for wlr-input-inhibitor-unstable-v1 ([#430][430])
* Remove support for KDE idle protocol ([#431][431])

[401]: https://github.com/djpohly/dwl/pull/401
[430]: https://github.com/djpohly/dwl/pull/430
[431]: https://github.com/djpohly/dwl/pull/431


### Fixed

* Fix crash when creating a layer surface with all outputs disabled
  ([#421][421])
* Fix other clients being shown as focused if the focused client have pop ups
  open ([#408][408])
* Resize fullscreen clients when updating monitor mode
* dwl no longer crash at exit like sometimes did
* Fullscreen background appearing above clients ([#487][487])
* Fix a segfault when user provides invalid xkb_rules ([#518][518])

[421]: https://github.com/djpohly/dwl/pull/421
[408]: https://github.com/djpohly/dwl/issues/408
[487]: https://github.com/djpohly/dwl/issues/487
[518]: https://github.com/djpohly/dwl/pull/518


### Contributors

* A Frederick Christensen
* Angelo Antony
* Ben Collerson
* Devin J. Pohly
* Forrest Bushstone
* gan-of-culture
* godalming123
* Job79
* link2xt
* Micah Gorrell
* Nikita Ivanov
* Palanix
* pino-desktop
* Weiseguy
* Yves Zoundi
