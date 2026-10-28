package main

import win "core:sys/windows"

// 布局与命中区域：绘制和点击共用这些矩形。

tasks_button_rect :: proc() -> win.RECT {
	return win.RECT{dip(BAR_PADDING_DIP), 0, dip(BAR_PADDING_DIP) + dip(TASKS_BUTTON_W_DIP), app.bar_h}
}

exit_button_rect :: proc() -> win.RECT {
	return win.RECT{
		app.width - dip(BAR_PADDING_DIP) - dip(30),
		(app.bar_h - dip(30)) / 2,
		app.width - dip(BAR_PADDING_DIP),
		(app.bar_h - dip(30)) / 2 + dip(30),
	}
}

settings_button_rect :: proc() -> win.RECT {
	exit := exit_button_rect()
	left := exit.left - dip(10) - dip(30)
	return win.RECT{left, (app.bar_h - dip(30)) / 2, left + dip(30), (app.bar_h - dip(30)) / 2 + dip(30)}
}

Tasks_Geometry :: struct {
	panel:       win.RECT,
	list_top:    i32,
	list_bottom: i32,
	visible:     int,
}

tasks_panel_width :: proc() -> i32 {
	if app.width <= 0 {
		return 0
	}
	w := app.width * 27 / 100
	min_w := dip(320)
	max_w := dip(430)
	if w < min_w {
		w = min_w
	}
	if w > max_w {
		w = max_w
	}
	hard_max := (app.width - dip(3*TASK_PANEL_PADDING_DIP)) / 2
	if hard_max > 0 && w > hard_max {
		w = hard_max
	}
	return w
}

// The window hosts the bar at its top (pinned top) or at its bottom (pinned
// bottom); the drawer fills the remainder.
bar_top :: proc() -> i32 {
	if settings.dock == .bottom {
		return app.height - app.bar_h
	}
	return 0
}

drawer_top :: proc() -> i32 {
	if settings.dock == .bottom {
		return 0
	}
	return app.bar_h
}

drawer_bottom :: proc() -> i32 {
	if settings.dock == .bottom {
		return app.height - app.bar_h
	}
	return app.height
}

tasks_geometry :: proc() -> Tasks_Geometry {
	pad := dip(TASK_PANEL_PADDING_DIP)
	panel_w := tasks_panel_width()
	if panel_w <= 0 || app.drawer_h <= 0 {
		return {}
	}

	bottom := drawer_top() + app.drawer_h
	if app.view != .none && app.height > app.bar_h {
		bottom = drawer_bottom()
	}
	top := drawer_top() + pad
	band_h := core_band_height()
	if band_h > 0 {
		top += band_h + dip(14)
	}
	panel_bottom := bottom - pad
	if panel_bottom <= top {
		return {}
	}

	panel := win.RECT{pad, top, pad + panel_w, panel_bottom}
	list_top := panel.top + dip(TASK_PANEL_HEADER_DIP)
	list_bottom := panel.bottom - dip(14)
	visible := 0
	if list_bottom > list_top {
		visible = int((list_bottom - list_top) / dip(TASK_ROW_HEIGHT_DIP))
	}
	return Tasks_Geometry{panel = panel, list_top = list_top, list_bottom = list_bottom, visible = visible}
}

// Full-width band above the task list and the monitoring column showing one
// curve per CPU core.
core_band_height :: proc() -> i32 {
	if !settings.modules.cores || app.cores <= 0 || app.drawer_h <= 0 {
		return 0
	}
	return clamp(app.drawer_h * 19 / 100, dip(80), dip(108))
}

Core_Band_Layout :: struct {
	rect:   win.RECT,
	header: win.RECT,
	charts: win.RECT,
	prev:   win.RECT,
	next:   win.RECT,
}

core_band_layout :: proc() -> Core_Band_Layout {
	layout := Core_Band_Layout{}
	height := core_band_height()
	if height <= 0 || app.width <= 0 {
		return layout
	}

	pad := dip(TASK_PANEL_PADDING_DIP)
	top := drawer_top() + pad
	layout.rect = win.RECT{pad, top, app.width - pad, top + height}

	inner := dip(16)
	btn := dip(22)
	header_y := layout.rect.top + dip(7)
	layout.next = win.RECT{layout.rect.right - inner - btn, header_y, layout.rect.right - inner, header_y + btn}
	layout.prev = win.RECT{layout.next.left - dip(6) - btn, header_y, layout.next.left - dip(6), header_y + btn}
	layout.header = win.RECT{
		layout.rect.left + inner,
		layout.rect.top + dip(7),
		layout.prev.left - dip(10),
		layout.rect.top + dip(29),
	}
	layout.charts = win.RECT{
		layout.rect.left + inner,
		layout.rect.top + dip(32),
		layout.rect.right - inner,
		layout.rect.bottom - dip(10),
	}
	return layout
}

visible_process_rows :: proc() -> int {
	return tasks_geometry().visible
}

core_page_count :: proc() -> int {
	per := core_page_per_core()
	if per <= 0 || app.cores <= 0 {
		return 1
	}
	return (app.cores + per - 1) / per
}

is_core_page_max :: proc() -> bool {
	return settings.cores_per_page <= 0
}

is_core_page_custom :: proc() -> bool {
	if settings.cores_per_page <= 0 {
		return false
	}
	if settings.cores_custom_mode {
		return true
	}
	v := settings.cores_per_page
	return v != 4 && v != 6 && v != 8 && v != 16
}

core_page_per_core :: proc() -> int {
	if app.cores <= 0 {
		return 1
	}
	if is_core_page_max() {
		return app.cores
	}
	return clamp(settings.cores_per_page, 1, app.cores)
}

clamp_core_page :: proc() {
	pages := core_page_count()
	if app.core_page >= pages {
		app.core_page = pages - 1
	}
	if app.core_page < 0 {
		app.core_page = 0
	}
}

Task_View_Layout :: struct {
	preview:      win.RECT,
	detail:       win.RECT,
	show_preview: bool,
}

// Right-hand area of the tasks drawer while a task is selected: the window
// preview on the left, the task's monitoring column on the right.
task_view_layout :: proc() -> Task_View_Layout {
	geo := tasks_geometry()
	layout := Task_View_Layout{}
	left := geo.panel.right + dip(18)
	right := app.width - dip(18)
	if geo.panel.right <= geo.panel.left || right - left <= dip(220) {
		return layout
	}

	layout.detail = win.RECT{left, geo.panel.top, right, geo.panel.bottom}
	if preview_is_alive() {
		gap := dip(18)
		preview_w := clamp((right - left) * 46 / 100, dip(320), dip(900))
		if right - left - preview_w - gap >= dip(420) {
			layout.preview = win.RECT{left, geo.panel.top, left + preview_w, geo.panel.bottom}
			layout.detail = win.RECT{left + preview_w + gap, geo.panel.top, right, geo.panel.bottom}
			layout.show_preview = true
		}
	}
	return layout
}

Task_Detail_Layout :: struct {
	title:    win.RECT,
	cpu:      win.RECT,
	memory:   win.RECT,
	gpu:      win.RECT,
	io_read:  win.RECT,
	io_write: win.RECT,
	threads:  win.RECT,
	handles:  win.RECT,
}

// Monitoring column of the detail page: a headline CPU curve and three rows of
// two metric cards.
task_detail_layout :: proc(rect: win.RECT) -> Task_Detail_Layout {
	layout := Task_Detail_Layout{}
	width := rect.right - rect.left
	height := rect.bottom - rect.top
	if width < dip(260) || height < dip(200) {
		return layout
	}

	gap := dip(12)
	title_h := dip(30)
	cpu_h := clamp(height * 22 / 100, dip(60), dip(124))

	row_h := (height - title_h - cpu_h - 3*gap) / 3
	if row_h < dip(40) {
		row_h = dip(40)
	}

	half := (width - gap) / 2
	layout.title = win.RECT{rect.left, rect.top, rect.right, rect.top + title_h}

	y := rect.top + title_h
	layout.cpu = win.RECT{rect.left, y, rect.right, y + cpu_h}
	y += cpu_h + gap

	if y + row_h <= rect.bottom {
		layout.memory = win.RECT{rect.left, y, rect.left + half, y + row_h}
		layout.gpu = win.RECT{rect.left + half + gap, y, rect.right, y + row_h}
	}
	y += row_h + gap

	if y + row_h <= rect.bottom {
		layout.io_read = win.RECT{rect.left, y, rect.left + half, y + row_h}
		layout.io_write = win.RECT{rect.left + half + gap, y, rect.right, y + row_h}
	}
	y += row_h + gap

	if y + row_h <= rect.bottom {
		layout.threads = win.RECT{rect.left, y, rect.left + half, y + row_h}
		layout.handles = win.RECT{rect.left + half + gap, y, rect.right, y + row_h}
	}

	return layout
}

clamp_scroll :: proc() {
	visible := visible_process_rows()
	max_scroll := max(app.task_row_count - visible, 0)
	if app.scroll > max_scroll {
		app.scroll = max_scroll
	}
	if app.scroll < 0 {
		app.scroll = 0
	}
}

Settings_Layout :: struct {
	outer, reset, modules, colors, appearance: win.RECT,
	body_top, body_bottom: i32,
}

settings_layout :: proc() -> Settings_Layout {
	outer := win.RECT{dip(18), drawer_top() + dip(18), app.width - dip(18), drawer_bottom() - dip(18)}
	reset := win.RECT{outer.right - dip(24) - dip(138), outer.top + dip(16), outer.right - dip(24), outer.top + dip(46)}

	inner_left := outer.left + dip(24)
	inner_right := outer.right - dip(24)
	body_top := outer.top + dip(86)
	body_bottom := outer.bottom - dip(24)
	gap := dip(24)
	total := inner_right - inner_left

	modules_w := total * 31 / 100
	colors_w := total * 40 / 100
	appearance_w := total - modules_w - colors_w - gap*2
	if appearance_w < dip(150) {
		appearance_w = dip(150)
	}

	modules := win.RECT{inner_left, body_top, inner_left + modules_w, body_bottom}
	colors := win.RECT{modules.right + gap, body_top, modules.right + gap + colors_w, body_bottom}
	appearance := win.RECT{colors.right + gap, body_top, colors.right + gap + appearance_w, body_bottom}

	return Settings_Layout{
		outer = outer,
		reset = reset,
		modules = modules,
		colors = colors,
		appearance = appearance,
		body_top = body_top,
		body_bottom = body_bottom,
	}
}

settings_module_row :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	y := layout.modules.top + dip(42) + i32(index)*dip(36)
	return win.RECT{layout.modules.left, y, layout.modules.right, y + dip(36)}
}

settings_cores_label_y :: proc(layout: Settings_Layout) -> i32 {
	return layout.modules.top + dip(42) + 7*dip(36) + dip(14)
}

settings_cores_page_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	gap := dip(6)
	avail := layout.modules.right - layout.modules.left
	w := clamp((avail - gap*5) / 6, dip(34), dip(52))
	h := dip(26)
	x := layout.modules.left + i32(index)*(w + gap)
	y := settings_cores_label_y(layout) + dip(18)
	return win.RECT{x, y, x + w, y + h}
}

settings_custom_row_y :: proc(layout: Settings_Layout) -> i32 {
	return settings_cores_label_y(layout) + dip(18) + dip(26) + dip(14)
}

settings_custom_minus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	y := settings_custom_row_y(layout)
	x := layout.modules.left + dip(84)
	return win.RECT{x, y, x + dip(26), y + dip(24)}
}

settings_custom_plus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	minus := settings_custom_minus_rect(layout)
	x := minus.right + dip(44) + dip(6)
	return win.RECT{x, minus.top, x + dip(26), minus.bottom}
}

settings_color_label_y :: proc(layout: Settings_Layout, role: int) -> i32 {
	return layout.colors.top + dip(42) + i32(role)*dip(70)
}

settings_swatch_rect :: proc(layout: Settings_Layout, role, index: int) -> win.RECT {
	size := dip(24)
	gap := dip(8)
	x := layout.colors.left + i32(index)*(size + gap)
	y := settings_color_label_y(layout, role) + dip(20)
	return win.RECT{x, y, x + size, y + size}
}

settings_custom_rect :: proc(layout: Settings_Layout, role: int) -> win.RECT {
	palette := palette_for_role(role)
	size := dip(24) + dip(8)
	x := layout.colors.left + i32(len(palette))*size + dip(18)
	y := settings_color_label_y(layout, role) + dip(18)
	return win.RECT{x, y, x + dip(100), y + dip(28)}
}

settings_theme_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	y := layout.appearance.top + dip(42) + i32(index)*(dip(76) + dip(10))
	return win.RECT{layout.appearance.left, y, layout.appearance.right, y + dip(76)}
}

settings_refresh_label_y :: proc(layout: Settings_Layout) -> i32 {
	last := settings_theme_rect(layout, len(THEMES)-1)
	return last.bottom + dip(14)
}

settings_refresh_chip_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	count := len(REFRESH_OPTIONS)
	gap := dip(6)
	avail := layout.appearance.right - layout.appearance.left
	w := clamp((avail - gap*i32(count-1)) / i32(count), dip(44), dip(64))
	h := dip(26)
	x := layout.appearance.left + i32(index)*(w + gap)
	y := settings_refresh_label_y(layout) + dip(18)
	return win.RECT{x, y, x + w, y + h}
}

settings_refresh_row_y :: proc(layout: Settings_Layout) -> i32 {
	chip := settings_refresh_chip_rect(layout, 0)
	return chip.bottom + dip(6)
}

settings_refresh_minus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	y := settings_refresh_row_y(layout)
	x := layout.appearance.left + dip(74)
	return win.RECT{x, y, x + dip(26), y + dip(24)}
}

settings_refresh_value_rect :: proc(layout: Settings_Layout) -> win.RECT {
	minus := settings_refresh_minus_rect(layout)
	x := minus.right + dip(6)
	return win.RECT{x, minus.top, x + dip(66), minus.bottom}
}

settings_refresh_plus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	value := settings_refresh_value_rect(layout)
	x := value.right + dip(6)
	return win.RECT{x, value.top, x + dip(26), value.bottom}
}

settings_dock_label_y :: proc(layout: Settings_Layout) -> i32 {
	return settings_color_label_y(layout, 2) + dip(68)
}

settings_dock_chip_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	count := len(DOCK_LABELS)
	gap := dip(8)
	avail := layout.colors.right - layout.colors.left
	w := clamp((avail - gap*i32(count-1)) / i32(count), dip(90), dip(150))
	x := layout.colors.left + i32(index)*(w + gap)
	y := settings_dock_label_y(layout) + dip(18)
	return win.RECT{x, y, x + w, y + dip(26)}
}

task_sort_chip_rect :: proc(panel: win.RECT, index: int) -> win.RECT {
	gap := dip(TASK_SORT_CHIP_GAP_DIP)
	inner := (panel.right - panel.left) - dip(40)
	w := (inner - gap*(len(SORT_FIELD_LABELS)-1)) / len(SORT_FIELD_LABELS)
	if w < dip(40) {
		w = dip(40)
	}
	if w > dip(70) {
		w = dip(70)
	}
	x := panel.left + dip(20) + i32(index)*(w + gap)
	y := panel.top + dip(TASK_SORT_ROW_DIP)
	return win.RECT{x, y, x + w, y + dip(TASK_SORT_CHIP_H_DIP)}
}
