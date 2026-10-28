package ui

import win "core:sys/windows"
import "../core"
import "../services"

// 布局与命中区域：绘制和点击共用这些矩形。

tasks_button_rect :: proc() -> win.RECT {
	return win.RECT{core.dip(core.BAR_PADDING_DIP), 0, core.dip(core.BAR_PADDING_DIP) + core.dip(core.TASKS_BUTTON_W_DIP), core.app.bar_h}
}

exit_button_rect :: proc() -> win.RECT {
	return win.RECT{
		core.app.width - core.dip(core.BAR_PADDING_DIP) - core.dip(30),
		(core.app.bar_h - core.dip(30)) / 2,
		core.app.width - core.dip(core.BAR_PADDING_DIP),
		(core.app.bar_h - core.dip(30)) / 2 + core.dip(30),
	}
}

settings_button_rect :: proc() -> win.RECT {
	exit := exit_button_rect()
	left := exit.left - core.dip(10) - core.dip(30)
	return win.RECT{left, (core.app.bar_h - core.dip(30)) / 2, left + core.dip(30), (core.app.bar_h - core.dip(30)) / 2 + core.dip(30)}
}

Tasks_Geometry :: struct {
	panel:       win.RECT,
	list_top:    i32,
	list_bottom: i32,
	visible:     int,
}

tasks_panel_width :: proc() -> i32 {
	if core.app.width <= 0 {
		return 0
	}
	w := core.app.width * 27 / 100
	min_w := core.dip(320)
	max_w := core.dip(430)
	if w < min_w {
		w = min_w
	}
	if w > max_w {
		w = max_w
	}
	hard_max := (core.app.width - core.dip(3*core.TASK_PANEL_PADDING_DIP)) / 2
	if hard_max > 0 && w > hard_max {
		w = hard_max
	}
	return w
}

// The bar sits at the top of the window and the drawer fills the remainder.
drawer_top :: proc() -> i32 {
	return core.app.bar_h
}

drawer_bottom :: proc() -> i32 {
	return core.app.layout_h
}

tasks_geometry :: proc() -> Tasks_Geometry {
	pad := core.dip(core.TASK_PANEL_PADDING_DIP)
	panel_w := tasks_panel_width()
	if panel_w <= 0 || core.app.drawer_h <= 0 {
		return {}
	}

	bottom := drawer_top() + core.app.drawer_h
	if core.app.view != .none && core.app.layout_h > core.app.bar_h {
		bottom = drawer_bottom()
	}
	top := drawer_top() + pad
	band_h := core_band_height()
	if band_h > 0 {
		top += band_h + core.dip(14)
	}
	panel_bottom := bottom - pad
	if panel_bottom <= top {
		return {}
	}

	panel := win.RECT{pad, top, pad + panel_w, panel_bottom}
	list_top := panel.top + core.dip(core.TASK_PANEL_HEADER_DIP)
	list_bottom := panel.bottom - core.dip(14)
	visible := 0
	if list_bottom > list_top {
		visible = int((list_bottom - list_top) / core.dip(core.TASK_ROW_HEIGHT_DIP))
	}
	return Tasks_Geometry{panel = panel, list_top = list_top, list_bottom = list_bottom, visible = visible}
}

// Full-width band above the task list and the monitoring column showing one
// curve per CPU core.
core_band_height :: proc() -> i32 {
	if !core.settings.modules.cores || core.app.cores <= 0 || core.app.drawer_h <= 0 {
		return 0
	}
	return clamp(core.app.drawer_h * 19 / 100, core.dip(80), core.dip(108))
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
	if height <= 0 || core.app.width <= 0 {
		return layout
	}

	pad := core.dip(core.TASK_PANEL_PADDING_DIP)
	top := drawer_top() + pad
	layout.rect = win.RECT{pad, top, core.app.width - pad, top + height}

	inner := core.dip(16)
	btn := core.dip(22)
	header_y := layout.rect.top + core.dip(7)
	layout.next = win.RECT{layout.rect.right - inner - btn, header_y, layout.rect.right - inner, header_y + btn}
	layout.prev = win.RECT{layout.next.left - core.dip(6) - btn, header_y, layout.next.left - core.dip(6), header_y + btn}
	layout.header = win.RECT{
		layout.rect.left + inner,
		layout.rect.top + core.dip(7),
		layout.prev.left - core.dip(10),
		layout.rect.top + core.dip(29),
	}
	layout.charts = win.RECT{
		layout.rect.left + inner,
		layout.rect.top + core.dip(32),
		layout.rect.right - inner,
		layout.rect.bottom - core.dip(10),
	}
	return layout
}

visible_process_rows :: proc() -> int {
	return tasks_geometry().visible
}

core_page_count :: proc() -> int {
	per := core_page_per_core()
	if per <= 0 || core.app.cores <= 0 {
		return 1
	}
	return (core.app.cores + per - 1) / per
}

is_core_page_max :: proc() -> bool {
	return core.settings.cores_per_page <= 0
}

is_core_page_custom :: proc() -> bool {
	if core.settings.cores_per_page <= 0 {
		return false
	}
	if core.settings.cores_custom_mode {
		return true
	}
	v := core.settings.cores_per_page
	return v != 4 && v != 6 && v != 8 && v != 16
}

core_page_per_core :: proc() -> int {
	if core.app.cores <= 0 {
		return 1
	}
	if is_core_page_max() {
		return core.app.cores
	}
	return clamp(core.settings.cores_per_page, 1, core.app.cores)
}

clamp_core_page :: proc() {
	pages := core_page_count()
	if core.app.core_page >= pages {
		core.app.core_page = pages - 1
	}
	if core.app.core_page < 0 {
		core.app.core_page = 0
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
	left := geo.panel.right + core.dip(18)
	right := core.app.width - core.dip(18)
	if geo.panel.right <= geo.panel.left || right - left <= core.dip(220) {
		return layout
	}

	layout.detail = win.RECT{left, geo.panel.top, right, geo.panel.bottom}
	if services.preview_is_alive() {
		gap := core.dip(18)
		preview_w := clamp((right - left) * 46 / 100, core.dip(320), core.dip(900))
		if right - left - preview_w - gap >= core.dip(420) {
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
	if width < core.dip(260) || height < core.dip(200) {
		return layout
	}

	gap := core.dip(12)
	title_h := core.dip(30)
	cpu_h := clamp(height * 22 / 100, core.dip(60), core.dip(124))

	row_h := (height - title_h - cpu_h - 3*gap) / 3
	if row_h < core.dip(40) {
		row_h = core.dip(40)
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
	max_scroll := max(core.app.task_row_count - visible, 0)
	if core.app.scroll > max_scroll {
		core.app.scroll = max_scroll
	}
	if core.app.scroll < 0 {
		core.app.scroll = 0
	}
}

Settings_Mode :: enum {
	// Three columns, the layout the page was designed for.
	wide,
	// Modules on the left, colors and appearance stacked on the right.
	two,
	// Everything stacked.
	one,
}

Settings_Layout :: struct {
	mode: Settings_Mode,
	outer, reset, modules, colors, appearance: win.RECT,
	// Visible part of the page; the groups are clipped to it.
	body: win.RECT,
	body_top, body_bottom: i32,
	content_h:  i32,
	scroll:     i32,
	scroll_max: i32,
}

// Column heights in unscrolled page coordinates. They mirror the offsets the
// rect helpers below use.
settings_group_heights :: proc() -> (modules_h, colors_h, appearance_h: i32) {
	modules_h = core.dip(42) + 7*core.dip(36) + core.dip(14) + core.dip(18) +
		core.dip(26) + core.dip(14) + core.dip(24)
	colors_h = core.dip(42) + 2*core.dip(70) + core.dip(68) + core.dip(18) +
		core.dip(26) + core.dip(10) + core.dip(14)
	appearance_h = core.dip(42) + 2*(core.dip(76) + core.dip(10)) + core.dip(76) +
		core.dip(14) + core.dip(18) + core.dip(26) + core.dip(6) + core.dip(24)
	return
}

// Places the groups for the current width. Narrow windows stack them instead
// of squeezing three columns into each other.
settings_metrics :: proc() -> Settings_Layout {
	layout := Settings_Layout{}
	if core.app.width <= 0 || core.app.layout_h <= 0 {
		return layout
	}

	outer := win.RECT{core.dip(18), drawer_top() + core.dip(18), core.app.width - core.dip(18), drawer_bottom() - core.dip(18)}
	layout.outer = outer
	layout.reset = win.RECT{outer.right - core.dip(24) - core.dip(138), outer.top + core.dip(16), outer.right - core.dip(24), outer.top + core.dip(46)}

	inner_left := outer.left + core.dip(24)
	inner_right := outer.right - core.dip(24)
	body_top := outer.top + core.dip(86)
	// The footer sits in the card padding, so the scrolling body stops above it.
	body_bottom := outer.bottom - core.dip(40)
	if inner_right <= inner_left || body_bottom <= body_top {
		return layout
	}
	layout.body = win.RECT{inner_left, body_top, inner_right, body_bottom}
	layout.body_top = body_top
	layout.body_bottom = body_bottom

	gap := core.dip(24)
	total := inner_right - inner_left
	modules_h, colors_h, appearance_h := settings_group_heights()

	switch {
	case total >= core.dip(core.SETTINGS_WIDE_MIN_DIP):
		layout.mode = .wide
		modules_w := max(total*31/100, core.dip(260))
		appearance_w := max(total*29/100, core.dip(300))
		colors_w := total - modules_w - appearance_w - gap*2
		// Swatches and the custom button need a fixed width; the shortfall is
		// taken from the two flexible columns, modules first.
		if colors_w < core.dip(374) {
			short := core.dip(374) - colors_w
			take := min(short, max(modules_w - core.dip(260), 0))
			modules_w -= take
			short -= take
			appearance_w -= short
			colors_w = total - modules_w - appearance_w - gap*2
		}
		layout.modules = win.RECT{inner_left, body_top, inner_left + modules_w, body_top + modules_h}
		layout.colors = win.RECT{layout.modules.right + gap, body_top, layout.modules.right + gap + colors_w, body_top + colors_h}
		layout.appearance = win.RECT{layout.colors.right + gap, body_top, layout.colors.right + gap + appearance_w, body_top + appearance_h}
		layout.content_h = max(modules_h, max(colors_h, appearance_h))

	case total >= core.dip(core.SETTINGS_TWO_COL_MIN_DIP):
		layout.mode = .two
		modules_w := clamp(total*44/100, core.dip(260), total - gap - core.dip(374))
		layout.modules = win.RECT{inner_left, body_top, inner_left + modules_w, body_top + modules_h}
		layout.colors = win.RECT{layout.modules.right + gap, body_top, inner_right, body_top + colors_h}
		// Appearance goes under the colors, so the two columns stay balanced
		// instead of leaving a gap under the shorter one.
		below := layout.colors.bottom + gap
		layout.appearance = win.RECT{layout.colors.left, below, inner_right, below + appearance_h}
		layout.content_h = max(layout.modules.bottom, layout.appearance.bottom) - body_top

	case:
		layout.mode = .one
		layout.modules = win.RECT{inner_left, body_top, inner_right, body_top + modules_h}
		below := layout.modules.bottom + gap
		layout.colors = win.RECT{inner_left, below, inner_right, below + colors_h}
		below = layout.colors.bottom + gap
		layout.appearance = win.RECT{inner_left, below, inner_right, below + appearance_h}
		layout.content_h = layout.appearance.bottom - body_top
	}
	return layout
}

// The page itself: the metrics, shifted by how far it has been scrolled.
settings_layout :: proc() -> Settings_Layout {
	layout := settings_metrics()
	body_h := layout.body_bottom - layout.body_top
	if body_h <= 0 {
		return layout
	}
	layout.scroll_max = max(layout.content_h - body_h, 0)
	layout.scroll = clamp(core.app.settings_scroll, 0, layout.scroll_max)
	if layout.scroll == 0 {
		return layout
	}
	dy := -layout.scroll
	layout.modules = shift_rect(layout.modules, 0, dy)
	layout.colors = shift_rect(layout.colors, 0, dy)
	layout.appearance = shift_rect(layout.appearance, 0, dy)
	return layout
}

clamp_settings_scroll :: proc() {
	core.app.settings_scroll = settings_layout().scroll
}

shift_rect :: proc(rect: win.RECT, dx, dy: i32) -> win.RECT {
	return win.RECT{rect.left + dx, rect.top + dy, rect.right + dx, rect.bottom + dy}
}

settings_module_row :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	y := layout.modules.top + core.dip(42) + i32(index)*core.dip(36)
	return win.RECT{layout.modules.left, y, layout.modules.right, y + core.dip(36)}
}

settings_cores_label_y :: proc(layout: Settings_Layout) -> i32 {
	return layout.modules.top + core.dip(42) + 7*core.dip(36) + core.dip(14)
}

settings_cores_page_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	gap := core.dip(6)
	avail := layout.modules.right - layout.modules.left
	w := clamp((avail - gap*5) / 6, core.dip(34), core.dip(52))
	h := core.dip(26)
	x := layout.modules.left + i32(index)*(w + gap)
	y := settings_cores_label_y(layout) + core.dip(18)
	return win.RECT{x, y, x + w, y + h}
}

settings_custom_row_y :: proc(layout: Settings_Layout) -> i32 {
	return settings_cores_label_y(layout) + core.dip(18) + core.dip(26) + core.dip(14)
}

settings_custom_minus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	y := settings_custom_row_y(layout)
	x := layout.modules.left + core.dip(84)
	return win.RECT{x, y, x + core.dip(26), y + core.dip(24)}
}

settings_custom_plus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	minus := settings_custom_minus_rect(layout)
	x := minus.right + core.dip(44) + core.dip(6)
	return win.RECT{x, minus.top, x + core.dip(26), minus.bottom}
}

settings_color_label_y :: proc(layout: Settings_Layout, role: int) -> i32 {
	return layout.colors.top + core.dip(42) + i32(role)*core.dip(70)
}

settings_swatch_rect :: proc(layout: Settings_Layout, role, index: int) -> win.RECT {
	size := core.dip(24)
	gap := core.dip(8)
	x := layout.colors.left + i32(index)*(size + gap)
	y := settings_color_label_y(layout, role) + core.dip(20)
	return win.RECT{x, y, x + size, y + size}
}

settings_custom_rect :: proc(layout: Settings_Layout, role: int) -> win.RECT {
	palette := core.palette_for_role(role)
	size := core.dip(24) + core.dip(8)
	x := layout.colors.left + i32(len(palette))*size + core.dip(18)
	y := settings_color_label_y(layout, role) + core.dip(18)
	return win.RECT{x, y, x + core.dip(100), y + core.dip(28)}
}

settings_theme_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	y := layout.appearance.top + core.dip(42) + i32(index)*(core.dip(76) + core.dip(10))
	return win.RECT{layout.appearance.left, y, layout.appearance.right, y + core.dip(76)}
}

settings_refresh_label_y :: proc(layout: Settings_Layout) -> i32 {
	last := settings_theme_rect(layout, len(core.THEMES)-1)
	return last.bottom + core.dip(14)
}

settings_refresh_chip_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	count := len(core.REFRESH_OPTIONS)
	gap := core.dip(6)
	avail := layout.appearance.right - layout.appearance.left
	w := clamp((avail - gap*i32(count-1)) / i32(count), core.dip(44), core.dip(64))
	h := core.dip(26)
	x := layout.appearance.left + i32(index)*(w + gap)
	y := settings_refresh_label_y(layout) + core.dip(18)
	return win.RECT{x, y, x + w, y + h}
}

settings_refresh_row_y :: proc(layout: Settings_Layout) -> i32 {
	chip := settings_refresh_chip_rect(layout, 0)
	return chip.bottom + core.dip(6)
}

settings_refresh_minus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	y := settings_refresh_row_y(layout)
	x := layout.appearance.left + core.dip(74)
	return win.RECT{x, y, x + core.dip(26), y + core.dip(24)}
}

settings_refresh_value_rect :: proc(layout: Settings_Layout) -> win.RECT {
	minus := settings_refresh_minus_rect(layout)
	x := minus.right + core.dip(6)
	return win.RECT{x, minus.top, x + core.dip(66), minus.bottom}
}

settings_refresh_plus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	value := settings_refresh_value_rect(layout)
	x := value.right + core.dip(6)
	return win.RECT{x, value.top, x + core.dip(26), value.bottom}
}

settings_dock_label_y :: proc(layout: Settings_Layout) -> i32 {
	return settings_color_label_y(layout, 2) + core.dip(68)
}

settings_dock_chip_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	count := len(core.DOCK_LABELS)
	gap := core.dip(8)
	avail := layout.colors.right - layout.colors.left
	w := clamp((avail - gap*i32(count-1)) / i32(count), core.dip(90), core.dip(150))
	x := layout.colors.left + i32(index)*(w + gap)
	y := settings_dock_label_y(layout) + core.dip(18)
	return win.RECT{x, y, x + w, y + core.dip(26)}
}

task_sort_chip_rect :: proc(panel: win.RECT, index: int) -> win.RECT {
	gap := core.dip(core.TASK_SORT_CHIP_GAP_DIP)
	inner := (panel.right - panel.left) - core.dip(40)
	w := (inner - gap*(len(core.SORT_FIELD_LABELS)-1)) / len(core.SORT_FIELD_LABELS)
	if w < core.dip(40) {
		w = core.dip(40)
	}
	if w > core.dip(70) {
		w = core.dip(70)
	}
	x := panel.left + core.dip(20) + i32(index)*(w + gap)
	y := panel.top + core.dip(core.TASK_SORT_ROW_DIP)
	return win.RECT{x, y, x + w, y + core.dip(core.TASK_SORT_CHIP_H_DIP)}
}

// Compact risk toggles under the sort chips: a "RISK" label and one small chip
// per tier. The chips share the remaining width.
task_risk_chip_rect :: proc(panel: win.RECT, index: int) -> win.RECT {
	count := len(core.RISK_TIERS)
	gap := core.dip(4)
	left := panel.left + core.dip(20) + core.dip(34)
	right := panel.right - core.dip(20)
	w := (right - left - gap*i32(count-1)) / i32(count)
	if w < core.dip(1) {
		w = core.dip(1)
	}
	if w > core.dip(96) {
		w = core.dip(96)
	}
	x := left + i32(index)*(w + gap)
	y := panel.top + core.dip(core.TASK_RISK_ROW_DIP)
	return win.RECT{x, y, x + w, y + core.dip(core.TASK_RISK_CHIP_H_DIP)}
}
