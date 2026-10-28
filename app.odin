package main

import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"

MAX_PROCESSES      :: 1024
MAX_NAME_U16       :: 96
MAX_GROUPS         :: 512
MAX_TASK_ROWS      :: MAX_PROCESSES + MAX_GROUPS
SAMPLE_COUNT       :: 120
MAX_CORES          :: 128
MAX_NET_INTERFACES :: 512
GPU_ENGINE_COUNT   :: 6

LOGPIXELSY :: 88
GIB        :: 1024.0 * 1024.0 * 1024.0

BAR_HEIGHT_DIP          :: 60
BAR_PADDING_DIP         :: 16
TASKS_BUTTON_W_DIP      :: 160
BAR_RIGHT_RESERVE_DIP   :: 158
BAR_SECTION_GAP_DIP     :: 16
DRAWER_HEIGHT_DIP       :: 540
TASK_PANEL_PADDING_DIP  :: 18
TASK_PANEL_HEADER_DIP   :: 82
TASK_ROW_HEIGHT_DIP     :: 52
TASK_SORT_ROW_DIP       :: 44
TASK_SORT_CHIP_H_DIP    :: 22
TASK_SORT_CHIP_GAP_DIP  :: 6

Color :: [3]u8

COL_TEXT       :: Color{236, 236, 242}
COL_MUTED      :: Color{148, 148, 163}
COL_BADGE_TEXT :: Color{15, 15, 19}

Theme :: struct {
	name:    string,
	bg:      Color,
	sidebar: Color,
	card:    Color,
	line:    Color,
	border:  Color,
}

THEMES := [3]Theme{
	{
		"Midnight",
		Color{23, 23, 28},
		Color{18, 18, 22},
		Color{30, 30, 36},
		Color{38, 38, 46},
		Color{44, 44, 53},
	},
	{
		"Graphite",
		Color{25, 25, 26},
		Color{19, 19, 20},
		Color{34, 34, 36},
		Color{43, 43, 46},
		Color{50, 50, 54},
	},
	{
		"Navy",
		Color{16, 21, 31},
		Color{11, 15, 22},
		Color{23, 30, 42},
		Color{31, 39, 52},
		Color{38, 47, 62},
	},
}

ACCENT_PALETTE := [8]Color{
	{78, 195, 255},
	{96, 165, 250},
	{94, 214, 143},
	{45, 212, 191},
	{167, 139, 250},
	{244, 114, 182},
	{251, 146, 60},
	{250, 204, 21},
}

MEMORY_PALETTE := [6]Color{
	{171, 142, 250},
	{96, 165, 250},
	{244, 114, 182},
	{45, 212, 191},
	{251, 191, 36},
	{134, 239, 172},
}

GPU_PALETTE := [6]Color{
	{251, 191, 36},
	{251, 113, 133},
	{96, 165, 250},
	{45, 212, 191},
	{167, 139, 250},
	{94, 214, 143},
}

GPU_ENGINE_NAMES := [GPU_ENGINE_COUNT]string{"3D", "COPY", "DEC", "ENC", "COMP", "OTHER"}

Module_Flags :: struct {
	cpu:     bool,
	cores:   bool,
	memory:  bool,
	disk:    bool,
	network: bool,
	gpu:     bool,
	uptime:  bool,
}

Dock_Mode :: enum {
	top,
	bottom,
}

DOCK_LABELS :: [2]string{"TOP", "BOTTOM"}
DOCK_HINTS :: [2]string{
	"Pinned to the top edge and reserves it.",
	"Pinned to the bottom edge; the drawer opens upward.",
}

Settings :: struct {
	modules:           Module_Flags,
	accent:            Color,
	memory_color:      Color,
	gpu_color:         Color,
	theme:             int,
	cores_per_page:    int,
	cores_custom:      int,
	cores_custom_mode: bool,
	sort_field:        Sort_Field,
	sort_desc:         bool,
	refresh_ms:        int,
	refresh_custom:    int,
	refresh_custom_mode: bool,
	dock:              Dock_Mode,
}

Sort_Field :: enum {
	cpu,
	memory,
	gpu,
	disk,
}

SORT_FIELD_LABELS :: [4]string{"CPU", "MEM", "GPU", "DISK"}

// 0 means "all cores" (Max); -1 is the custom entry, which uses
// settings.cores_custom instead of a fixed value.
CORE_PAGE_OPTIONS :: [6]int{4, 6, 8, 16, 0, -1}

// Sample interval choices in milliseconds; -1 is the custom entry. The curves
// keep SAMPLE_COUNT samples, so the visible history is refresh_ms * SAMPLE_COUNT.
REFRESH_OPTIONS :: [6]int{250, 500, 1000, 2000, 5000, -1}
REFRESH_MIN_MS  :: 100
REFRESH_MAX_MS  :: 10000
REFRESH_STEP_MS :: 100

// The process list is re-enumerated on its own cadence so a fast sample
// interval does not multiply the cost of the Toolhelp snapshot walk.
PROCESS_REFRESH_MS :: 2000

settings: Settings

default_settings :: proc() -> Settings {
	return Settings{
		modules = Module_Flags{
			cpu = true,
			cores = true,
			memory = true,
			disk = true,
			network = true,
			gpu = true,
			uptime = true,
		},
		accent = ACCENT_PALETTE[0],
		memory_color = MEMORY_PALETTE[0],
		gpu_color = GPU_PALETTE[0],
		theme = 0,
		cores_per_page = CORE_PAGE_OPTIONS[0],
		cores_custom = 5,
		sort_field = .cpu,
		sort_desc = true,
		refresh_ms = 1000,
		refresh_custom = 750,
		dock = .top,
	}
}

Module_Id :: enum {
	cpu,
	cores,
	memory,
	disk,
	network,
	gpu,
	uptime,
}

module_label :: proc(id: Module_Id) -> string {
	switch id {
	case .cpu:     return "CPU"
	case .cores:   return "Per-core CPU"
	case .memory:  return "Memory"
	case .disk:    return "Disk"
	case .network: return "Network"
	case .gpu:     return "GPU"
	case .uptime:  return "Uptime"
	}
	return ""
}

module_enabled :: proc(id: Module_Id) -> bool {
	switch id {
	case .cpu:     return settings.modules.cpu
	case .cores:   return settings.modules.cores
	case .memory:  return settings.modules.memory
	case .disk:    return settings.modules.disk
	case .network: return settings.modules.network
	case .gpu:     return settings.modules.gpu
	case .uptime:  return settings.modules.uptime
	}
	return false
}

module_set :: proc(id: Module_Id, on: bool) {
	switch id {
	case .cpu:
		settings.modules.cpu = on
		if !on {
			settings.modules.cores = false
		}
	case .cores:   settings.modules.cores = on
	case .memory:  settings.modules.memory = on
	case .disk:    settings.modules.disk = on
	case .network: settings.modules.network = on
	case .gpu:     settings.modules.gpu = on
	case .uptime:  settings.modules.uptime = on
	}
}

Drawer_View :: enum {
	none,
	tasks,
	settings,
}

If_Counter :: struct {
	index:     u32,
	bytes_in:  u32,
	bytes_out: u32,
}

wrapped_delta_u32 :: proc(cur, prev: u32) -> u32 {
	if cur >= prev {
		return cur - prev
	}
	// The counters are 32-bit and reset to zero when the adapter is
	// re-initialized (link down, driver reload). A real wrap only steps back
	// by the bytes moved since the previous sample, so the old value must be
	// close to the upper bound. Anything else is a reset and carries no
	// measurable traffic.
	if prev >= 0xFFFF_FFFF - u32(1 << 30) {
		return (0xFFFF_FFFF - prev) + cur + 1
	}
	return 0
}

contains_ascii_ci :: proc(haystack: []u8, needle: string) -> bool {
	if len(needle) == 0 || len(haystack) < len(needle) {
		return false
	}
	for i in 0 ..= len(haystack) - len(needle) {
		match := true
		for j in 0 ..< len(needle) {
			c := haystack[i + j]
			if 'A' <= c && c <= 'Z' {
				c += 'a' - 'A'
			}
			if c != needle[j] {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}

// Hypervisor switches, VPN clients and loopback shims stay "connected" and keep
// moving local traffic even when the machine has no network at all. Ignore them
// so the readout reflects traffic on real uplink adapters.
is_virtual_adapter :: proc(descr: []u8) -> bool {
	keywords := [?]string{
		"virtual",
		"vpn",
		"tunnel",
		"loopback",
		"pseudo",
		"tap-",
		"npcap",
		"wintun",
		"wireguard",
		"wsl",
	}
	for keyword in keywords {
		if contains_ascii_ci(descr, keyword) {
			return true
		}
	}
	return false
}

Process :: struct {
	pid:            u32,
	threads:        u32,
	name:           [MAX_NAME_U16]u16,
	working_set:    u64,
	cpu_time:       u64,
	cpu_percent:    f32,
	gpu_percent:    f32,
	handles:        u32,
	io_read_bps:    f64,
	io_write_bps:   f64,
	io_bps:         f64,
	io_read_total:  u64,
	io_write_total: u64,
}

// Processes that share an executable name are shown as one application in the
// tree, with aggregated metrics on the parent row.
Task_Group :: struct {
	name:        [MAX_NAME_U16]u16,
	count:       int,
	cpu_percent: f32,
	working_set: u64,
	gpu_percent: f32,
	io_bps:      f64,
}

List_Row_Kind :: enum {
	group,
	process,
}

List_Row :: struct {
	kind:  List_Row_Kind,
	index: int,
}

Expand_State :: struct {
	name:     [MAX_NAME_U16]u16,
	expanded: bool,
}

// Per-process GPU usage gathered from the GPU Engine counter instances, which
// carry the owning PID in their name.
GPU_PID_CAPACITY :: 128

Gpu_Pid_Usage :: struct {
	pid:   u32,
	usage: f32,
}

// Per-metrics of the current selection (a process or a whole application).
Task_Metrics :: struct {
	pid:             u32,
	group_mode:      bool,
	group:           [MAX_NAME_U16]u16,
	count:           int,
	cpu:             f32,
	mem_bytes:       u64,
	gpu:             f32,
	read_bps:        f64,
	write_bps:       f64,
	threads:         u32,
	handles:         u32,
	cpu_time:        u64,
	cpu_samples:     [SAMPLE_COUNT]f32,
	mem_samples:     [SAMPLE_COUNT]f32,
	gpu_samples:     [SAMPLE_COUNT]f32,
	read_samples:    [SAMPLE_COUNT]f32,
	write_samples:   [SAMPLE_COUNT]f32,
	threads_samples: [SAMPLE_COUNT]f32,
	handles_samples: [SAMPLE_COUNT]f32,
}

Fonts :: struct {
	title, heading, huge, med, stat, body, small, tiny, badge: win.HFONT,
}

Brushes :: struct {
	bg, sidebar, card, selected, badge, accent,
	track, thumb, cpu_fill, mem_fill, gpu_fill, line, dark, light, muted: win.HBRUSH,
}

Pens :: struct {
	border, cpu, mem, gpu, null: win.HPEN,
}

App :: struct {
	hwnd:  win.HWND,
	scale: f32,

	screen_w, screen_h: i32,
	bar_h:              i32,
	drawer_h:           i32,
	view:               Drawer_View,
	color_dialog_open:  bool,
	deactivate_guard_until: u64,
	refresh_edit:       bool,
	refresh_edit_buf:   [8]u8,
	refresh_edit_len:   int,
	refresh_edit_replace: bool,
	bar_rect:           win.RECT,
	appbar_registered:  bool,
	appbar_moving:      bool,

	width, height: i32,
	mem_dc:        win.HDC,
	mem_bmp:       win.HBITMAP,

	fonts:   Fonts,
	brushes: Brushes,
	pens:    Pens,

	class_brush: win.HBRUSH,

	processes:       [MAX_PROCESSES]Process,
	process_count:   int,
	groups:          [MAX_GROUPS]Task_Group,
	group_count:     int,
	task_rows:       [MAX_TASK_ROWS]List_Row,
	task_row_count:  int,
	expand_state:    [MAX_GROUPS]Expand_State,
	expand_count:    int,
	selected_pid:    u32,
	selected_group:  [MAX_NAME_U16]u16,
	group_selected:  bool,
	has_selection:   bool,
	scroll:          int,
	last_process_ms: u64,
	preview:         Window_Preview,
	task:            Task_Metrics,
	core_page:       int,
	core_samples:    [MAX_CORES][SAMPLE_COUNT]f32,

	cpu:         f32,
	mem_percent: f32,
	mem_used:    f32,
	mem_total:   f32,
	uptime_secs: u64,
	cores:       int,

	core_usage:     [MAX_CORES]f32,
	core_prev:      [MAX_CORES]Core_Times,
	have_core_prev: bool,

	gpu:            f32,
	gpu_vram:       f32,
	gpu_ok:         bool,
	gpu_mem_ok:     bool,
	gpu_counter:    rawptr,
	gpu_mem_counter: rawptr,
	gpu_pid_usage:  [GPU_PID_CAPACITY]Gpu_Pid_Usage,
	gpu_pid_count:  int,

	disk_read_bps:  f64,
	disk_write_bps: f64,
	pdh_query:      rawptr,
	pdh_read:       rawptr,
	pdh_write:      rawptr,
	pdh_ok:         bool,
	pdh_attempted:  bool,
	pdh_buffer:     [262144]u8,

	net_in_bps:     f64,
	net_out_bps:    f64,
	net_prev_if:    [MAX_NET_INTERFACES]If_Counter,
	net_prev_count: int,
	net_last_ms:    u64,
	net_have_prev:  bool,
	net_ok:         bool,
	net_online:     bool,
	net_table:      Mib_If_Table,

	cpu_samples: [SAMPLE_COUNT]f32,
	mem_samples: [SAMPLE_COUNT]f32,
	gpu_samples: [SAMPLE_COUNT]f32,

	last_idle, last_kernel, last_user: u64,
	have_last: bool,
}

app: App
next_processes: [MAX_PROCESSES]Process
color_custom_colors: [16]win.COLORREF

S :: proc(v: i32) -> i32 {
	return i32(f32(v)*app.scale + 0.5)
}

colorref :: proc(c: Color) -> win.COLORREF {
	return win.COLORREF(u32(c[0]) | u32(c[1]) << 8 | u32(c[2]) << 16)
}

mix_color :: proc(a, b: Color, t: f32) -> Color {
	tt := t
	if tt < 0 {
		tt = 0
	}
	if tt > 1 {
		tt = 1
	}
	return Color{
		u8(f32(a[0])*(1-tt) + f32(b[0])*tt),
		u8(f32(a[1])*(1-tt) + f32(b[1])*tt),
		u8(f32(a[2])*(1-tt) + f32(b[2])*tt),
	}
}

filetime_value :: proc(ft: win.FILETIME) -> u64 {
	return u64(ft.dwLowDateTime) | u64(ft.dwHighDateTime) << 32
}

point_in_rect :: proc(x, y: i32, rect: win.RECT) -> bool {
	return x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom
}

tasks_button_rect :: proc() -> win.RECT {
	return win.RECT{S(BAR_PADDING_DIP), 0, S(BAR_PADDING_DIP) + S(TASKS_BUTTON_W_DIP), app.bar_h}
}

exit_button_rect :: proc() -> win.RECT {
	return win.RECT{
		app.width - S(BAR_PADDING_DIP) - S(30),
		(app.bar_h - S(30)) / 2,
		app.width - S(BAR_PADDING_DIP),
		(app.bar_h - S(30)) / 2 + S(30),
	}
}

settings_button_rect :: proc() -> win.RECT {
	exit := exit_button_rect()
	left := exit.left - S(10) - S(30)
	return win.RECT{left, (app.bar_h - S(30)) / 2, left + S(30), (app.bar_h - S(30)) / 2 + S(30)}
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
	min_w := S(320)
	max_w := S(430)
	if w < min_w {
		w = min_w
	}
	if w > max_w {
		w = max_w
	}
	hard_max := (app.width - S(3*TASK_PANEL_PADDING_DIP)) / 2
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
	pad := S(TASK_PANEL_PADDING_DIP)
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
		top += band_h + S(14)
	}
	panel_bottom := bottom - pad
	if panel_bottom <= top {
		return {}
	}

	panel := win.RECT{pad, top, pad + panel_w, panel_bottom}
	list_top := panel.top + S(TASK_PANEL_HEADER_DIP)
	list_bottom := panel.bottom - S(14)
	visible := 0
	if list_bottom > list_top {
		visible = int((list_bottom - list_top) / S(TASK_ROW_HEIGHT_DIP))
	}
	return Tasks_Geometry{panel = panel, list_top = list_top, list_bottom = list_bottom, visible = visible}
}

// Full-width band above the task list and the monitoring column showing one
// curve per CPU core.
core_band_height :: proc() -> i32 {
	if !settings.modules.cores || app.cores <= 0 || app.drawer_h <= 0 {
		return 0
	}
	return clamp(app.drawer_h * 19 / 100, S(80), S(108))
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

	pad := S(TASK_PANEL_PADDING_DIP)
	top := drawer_top() + pad
	layout.rect = win.RECT{pad, top, app.width - pad, top + height}

	inner := S(16)
	btn := S(22)
	header_y := layout.rect.top + S(7)
	layout.next = win.RECT{layout.rect.right - inner - btn, header_y, layout.rect.right - inner, header_y + btn}
	layout.prev = win.RECT{layout.next.left - S(6) - btn, header_y, layout.next.left - S(6), header_y + btn}
	layout.header = win.RECT{
		layout.rect.left + inner,
		layout.rect.top + S(7),
		layout.prev.left - S(10),
		layout.rect.top + S(29),
	}
	layout.charts = win.RECT{
		layout.rect.left + inner,
		layout.rect.top + S(32),
		layout.rect.right - inner,
		layout.rect.bottom - S(10),
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
	left := geo.panel.right + S(18)
	right := app.width - S(18)
	if geo.panel.right <= geo.panel.left || right - left <= S(220) {
		return layout
	}

	layout.detail = win.RECT{left, geo.panel.top, right, geo.panel.bottom}
	if preview_is_alive() {
		gap := S(18)
		preview_w := clamp((right - left) * 46 / 100, S(320), S(900))
		if right - left - preview_w - gap >= S(420) {
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
	if width < S(260) || height < S(200) {
		return layout
	}

	gap := S(12)
	title_h := S(30)
	cpu_h := clamp(height * 22 / 100, S(60), S(124))

	row_h := (height - title_h - cpu_h - 3*gap) / 3
	if row_h < S(40) {
		row_h = S(40)
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
	outer := win.RECT{S(18), drawer_top() + S(18), app.width - S(18), drawer_bottom() - S(18)}
	reset := win.RECT{outer.right - S(24) - S(138), outer.top + S(16), outer.right - S(24), outer.top + S(46)}

	inner_left := outer.left + S(24)
	inner_right := outer.right - S(24)
	body_top := outer.top + S(86)
	body_bottom := outer.bottom - S(24)
	gap := S(24)
	total := inner_right - inner_left

	modules_w := total * 31 / 100
	colors_w := total * 40 / 100
	appearance_w := total - modules_w - colors_w - gap*2
	if appearance_w < S(150) {
		appearance_w = S(150)
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
	y := layout.modules.top + S(42) + i32(index)*S(36)
	return win.RECT{layout.modules.left, y, layout.modules.right, y + S(36)}
}

settings_cores_label_y :: proc(layout: Settings_Layout) -> i32 {
	return layout.modules.top + S(42) + 7*S(36) + S(14)
}

settings_cores_page_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	gap := S(6)
	avail := layout.modules.right - layout.modules.left
	w := clamp((avail - gap*5) / 6, S(34), S(52))
	h := S(26)
	x := layout.modules.left + i32(index)*(w + gap)
	y := settings_cores_label_y(layout) + S(18)
	return win.RECT{x, y, x + w, y + h}
}

settings_custom_row_y :: proc(layout: Settings_Layout) -> i32 {
	return settings_cores_label_y(layout) + S(18) + S(26) + S(14)
}

settings_custom_minus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	y := settings_custom_row_y(layout)
	x := layout.modules.left + S(84)
	return win.RECT{x, y, x + S(26), y + S(24)}
}

settings_custom_plus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	minus := settings_custom_minus_rect(layout)
	x := minus.right + S(44) + S(6)
	return win.RECT{x, minus.top, x + S(26), minus.bottom}
}

settings_color_label_y :: proc(layout: Settings_Layout, role: int) -> i32 {
	return layout.colors.top + S(42) + i32(role)*S(70)
}

settings_swatch_rect :: proc(layout: Settings_Layout, role, index: int) -> win.RECT {
	size := S(24)
	gap := S(8)
	x := layout.colors.left + i32(index)*(size + gap)
	y := settings_color_label_y(layout, role) + S(20)
	return win.RECT{x, y, x + size, y + size}
}

settings_custom_rect :: proc(layout: Settings_Layout, role: int) -> win.RECT {
	palette := palette_for_role(role)
	size := S(24) + S(8)
	x := layout.colors.left + i32(len(palette))*size + S(18)
	y := settings_color_label_y(layout, role) + S(18)
	return win.RECT{x, y, x + S(100), y + S(28)}
}

settings_theme_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	y := layout.appearance.top + S(42) + i32(index)*(S(76) + S(10))
	return win.RECT{layout.appearance.left, y, layout.appearance.right, y + S(76)}
}

settings_refresh_label_y :: proc(layout: Settings_Layout) -> i32 {
	last := settings_theme_rect(layout, len(THEMES)-1)
	return last.bottom + S(14)
}

settings_refresh_chip_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	count := len(REFRESH_OPTIONS)
	gap := S(6)
	avail := layout.appearance.right - layout.appearance.left
	w := clamp((avail - gap*i32(count-1)) / i32(count), S(44), S(64))
	h := S(26)
	x := layout.appearance.left + i32(index)*(w + gap)
	y := settings_refresh_label_y(layout) + S(18)
	return win.RECT{x, y, x + w, y + h}
}

settings_refresh_row_y :: proc(layout: Settings_Layout) -> i32 {
	chip := settings_refresh_chip_rect(layout, 0)
	return chip.bottom + S(6)
}

settings_refresh_minus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	y := settings_refresh_row_y(layout)
	x := layout.appearance.left + S(74)
	return win.RECT{x, y, x + S(26), y + S(24)}
}

settings_refresh_value_rect :: proc(layout: Settings_Layout) -> win.RECT {
	minus := settings_refresh_minus_rect(layout)
	x := minus.right + S(6)
	return win.RECT{x, minus.top, x + S(66), minus.bottom}
}

settings_refresh_plus_rect :: proc(layout: Settings_Layout) -> win.RECT {
	value := settings_refresh_value_rect(layout)
	x := value.right + S(6)
	return win.RECT{x, value.top, x + S(26), value.bottom}
}

settings_dock_label_y :: proc(layout: Settings_Layout) -> i32 {
	return settings_color_label_y(layout, 2) + S(68)
}

settings_dock_chip_rect :: proc(layout: Settings_Layout, index: int) -> win.RECT {
	count := len(DOCK_LABELS)
	gap := S(8)
	avail := layout.colors.right - layout.colors.left
	w := clamp((avail - gap*i32(count-1)) / i32(count), S(90), S(150))
	x := layout.colors.left + i32(index)*(w + gap)
	y := settings_dock_label_y(layout) + S(18)
	return win.RECT{x, y, x + w, y + S(26)}
}

get_core_count :: proc() {
	info: win.SYSTEM_INFO
	win.GetSystemInfo(&info)
	app.cores = min(int(info.dwNumberOfProcessors), MAX_CORES)
	if app.cores < 1 {
		app.cores = 1
	}
}

lower_wide :: proc(c: u16) -> u16 {
	if c >= 'A' && c <= 'Z' {
		return c + 32
	}
	return c
}

same_task_name :: proc(a, b: [MAX_NAME_U16]u16) -> bool {
	for i in 0..<MAX_NAME_U16 {
		if a[i] != b[i] {
			return false
		}
		if a[i] == 0 {
			return true
		}
	}
	return true
}

task_name_less :: proc(a, b: [MAX_NAME_U16]u16) -> bool {
	for i in 0..<MAX_NAME_U16 {
		ca := a[i]
		cb := b[i]
		if ca == 0 {
			return cb != 0
		}
		if cb == 0 {
			return false
		}
		la := lower_wide(ca)
		lb := lower_wide(cb)
		if la != lb {
			return la < lb
		}
	}
	return false
}

process_name_less :: proc(a, b: ^Process) -> bool {
	return task_name_less(a.name, b.name)
}

process_order_less :: proc(a, b: ^Process) -> bool {
	switch settings.sort_field {
	case .cpu:
		if a.cpu_percent != b.cpu_percent {
			if settings.sort_desc {
				return a.cpu_percent > b.cpu_percent
			}
			return a.cpu_percent < b.cpu_percent
		}
	case .memory:
		if a.working_set != b.working_set {
			if settings.sort_desc {
				return a.working_set > b.working_set
			}
			return a.working_set < b.working_set
		}
	case .gpu:
		if a.gpu_percent != b.gpu_percent {
			if settings.sort_desc {
				return a.gpu_percent > b.gpu_percent
			}
			return a.gpu_percent < b.gpu_percent
		}
	case .disk:
		if a.io_bps != b.io_bps {
			if settings.sort_desc {
				return a.io_bps > b.io_bps
			}
			return a.io_bps < b.io_bps
		}
	}
	// Ties keep an alphabetical order so the list doesn't shuffle per sample.
	return process_name_less(a, b)
}

sort_processes :: proc(list: []Process) {
	for i in 1..<len(list) {
		p := list[i]
		j := i - 1
		for j >= 0 && process_order_less(&p, &list[j]) {
			list[j+1] = list[j]
			j -= 1
		}
		list[j+1] = p
	}
}

group_order_less :: proc(a, b: ^Task_Group) -> bool {
	switch settings.sort_field {
	case .cpu:
		if a.cpu_percent != b.cpu_percent {
			if settings.sort_desc {
				return a.cpu_percent > b.cpu_percent
			}
			return a.cpu_percent < b.cpu_percent
		}
	case .memory:
		if a.working_set != b.working_set {
			if settings.sort_desc {
				return a.working_set > b.working_set
			}
			return a.working_set < b.working_set
		}
	case .gpu:
		if a.gpu_percent != b.gpu_percent {
			if settings.sort_desc {
				return a.gpu_percent > b.gpu_percent
			}
			return a.gpu_percent < b.gpu_percent
		}
	case .disk:
		if a.io_bps != b.io_bps {
			if settings.sort_desc {
				return a.io_bps > b.io_bps
			}
			return a.io_bps < b.io_bps
		}
	}
	return task_name_less(a.name, b.name)
}

group_is_expanded :: proc(name: [MAX_NAME_U16]u16) -> bool {
	for i in 0..<app.expand_count {
		if same_task_name(app.expand_state[i].name, name) {
			return app.expand_state[i].expanded
		}
	}
	return false
}

group_set_expanded :: proc(name: [MAX_NAME_U16]u16, expanded: bool) {
	for i in 0..<app.expand_count {
		if same_task_name(app.expand_state[i].name, name) {
			app.expand_state[i].expanded = expanded
			return
		}
	}
	if app.expand_count < MAX_GROUPS {
		app.expand_state[app.expand_count] = Expand_State{name = name, expanded = expanded}
		app.expand_count += 1
	}
}

append_task_row :: proc(kind: List_Row_Kind, index: int) {
	if app.task_row_count < MAX_TASK_ROWS {
		app.task_rows[app.task_row_count] = List_Row{kind = kind, index = index}
		app.task_row_count += 1
	}
}

rebuild_task_rows :: proc() {
	app.task_row_count = 0
	for gi in 0..<app.group_count {
		g := &app.groups[gi]
		append_task_row(.group, gi)
		if !group_is_expanded(g.name) {
			continue
		}
		for pi in 0..<app.process_count {
			if same_task_name(app.processes[pi].name, g.name) {
				append_task_row(.process, pi)
			}
		}
	}
}

build_task_groups :: proc() {
	app.group_count = 0
	for pi in 0..<app.process_count {
		p := &app.processes[pi]
		gi := -1
		for j in 0..<app.group_count {
			if same_task_name(app.groups[j].name, p.name) {
				gi = j
				break
			}
		}
		if gi < 0 {
			if app.group_count >= MAX_GROUPS {
				continue
			}
			gi = app.group_count
			app.groups[gi] = Task_Group{name = p.name}
			app.group_count += 1
		}

		g := &app.groups[gi]
		g.count += 1
		g.cpu_percent += p.cpu_percent
		g.working_set += p.working_set
		g.gpu_percent += p.gpu_percent
		g.io_bps += p.io_bps
	}

	for i in 1..<app.group_count {
		g := app.groups[i]
		j := i - 1
		for j >= 0 && group_order_less(&g, &app.groups[j]) {
			app.groups[j+1] = app.groups[j]
			j -= 1
		}
		app.groups[j+1] = g
	}

	rebuild_task_rows()
}

task_sort_chip_rect :: proc(panel: win.RECT, index: int) -> win.RECT {
	gap := S(TASK_SORT_CHIP_GAP_DIP)
	inner := (panel.right - panel.left) - S(40)
	w := (inner - gap*(len(SORT_FIELD_LABELS)-1)) / len(SORT_FIELD_LABELS)
	if w < S(40) {
		w = S(40)
	}
	if w > S(70) {
		w = S(70)
	}
	x := panel.left + S(20) + i32(index)*(w + gap)
	y := panel.top + S(TASK_SORT_ROW_DIP)
	return win.RECT{x, y, x + w, y + S(TASK_SORT_CHIP_H_DIP)}
}

find_old_process :: proc(pid: u32) -> (p: ^Process, found: bool) {
	for i in 0..<app.process_count {
		if app.processes[i].pid == pid {
			return &app.processes[i], true
		}
	}
	return nil, false
}

gpu_usage_add :: proc(pid: u32, usage: f32) {
	if pid == 0 || usage <= 0 {
		return
	}
	for i in 0..<app.gpu_pid_count {
		if app.gpu_pid_usage[i].pid == pid {
			app.gpu_pid_usage[i].usage += usage
			return
		}
	}
	if app.gpu_pid_count < GPU_PID_CAPACITY {
		app.gpu_pid_usage[app.gpu_pid_count] = Gpu_Pid_Usage{pid = pid, usage = usage}
		app.gpu_pid_count += 1
	}
}

gpu_usage_for_pid :: proc(pid: u32) -> f32 {
	if pid == 0 {
		return 0
	}
	for i in 0..<app.gpu_pid_count {
		if app.gpu_pid_usage[i].pid == pid {
			v := app.gpu_pid_usage[i].usage
			if v > 100 {
				return 100
			}
			return v
		}
	}
	return 0
}

find_process :: proc(pid: u32) -> (p: ^Process, found: bool) {
	for i in 0..<app.process_count {
		if app.processes[i].pid == pid {
			return &app.processes[i], true
		}
	}
	return nil, false
}

refresh_processes :: proc() {
	now := GetTickCount64()
	elapsed_ms := now - app.last_process_ms
	app.last_process_ms = now

	snap := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0)
	if snap == win.INVALID_HANDLE_VALUE {
		return
	}
	defer win.CloseHandle(snap)

	entry: win.PROCESSENTRY32W
	entry.dwSize = u32(size_of(win.PROCESSENTRY32W))

	count := 0

	for status := win.Process32FirstW(snap, &entry); status; status = win.Process32NextW(snap, &entry) {
		if count >= MAX_PROCESSES {
			break
		}

		p := &next_processes[count]
		p^ = Process{}
		p.pid = entry.th32ProcessID
		p.threads = entry.cntThreads

		n := 0
		for n < MAX_NAME_U16-1 {
			c := entry.szExeFile[n]
			if c == 0 {
				break
			}
			p.name[n] = u16(c)
			n += 1
		}
		p.name[n] = 0

		old, has_old := find_old_process(p.pid)

		handle := win.OpenProcess(
			PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
			win.FALSE,
			p.pid,
		)
		if handle != nil {
			counters: Process_Memory_Counters
			counters.cb = u32(size_of(Process_Memory_Counters))
			if GetProcessMemoryInfo(handle, &counters, counters.cb) {
				p.working_set = u64(counters.working_set_size)
			}

			creation, exit_time, kernel_time, user_time: win.FILETIME
			if win.GetProcessTimes(handle, &creation, &exit_time, &kernel_time, &user_time) {
				p.cpu_time = filetime_value(kernel_time) + filetime_value(user_time)
			}

			io: Io_Counters
			if GetProcessIoCounters(handle, &io) {
				p.io_read_total = io.read_bytes
				p.io_write_total = io.write_bytes
			}

			handles: u32
			if GetProcessHandleCount(handle, &handles) {
				p.handles = handles
			}
			_ = win.CloseHandle(handle)
		}

		if has_old && elapsed_ms > 0 {
			if p.cpu_time > old.cpu_time && app.cores > 0 {
				delta := p.cpu_time - old.cpu_time
				units := f64(elapsed_ms) * 10000.0 * f64(app.cores)
				pct := f32(f64(delta) / units * 100.0)
				if pct < 0 {
					pct = 0
				}
				if pct > 100 {
					pct = 100
				}
				p.cpu_percent = pct
			}
			if p.io_read_total >= old.io_read_total {
				p.io_read_bps = f64(p.io_read_total - old.io_read_total) * 1000.0 / f64(elapsed_ms)
			}
			if p.io_write_total >= old.io_write_total {
				p.io_write_bps = f64(p.io_write_total - old.io_write_total) * 1000.0 / f64(elapsed_ms)
			}
			p.io_bps = p.io_read_bps + p.io_write_bps
		}

		p.gpu_percent = gpu_usage_for_pid(p.pid)

		count += 1
	}

	sort_processes(next_processes[:count])

	for i in 0..<count {
		app.processes[i] = next_processes[i]
	}
	app.process_count = count

	if app.has_selection {
		alive := false
		for i in 0..<count {
			if app.group_selected {
				if same_task_name(app.processes[i].name, app.selected_group) {
					alive = true
					break
				}
			} else if app.processes[i].pid == app.selected_pid {
				alive = true
				break
			}
		}
		if !alive {
			app.has_selection = false
			app.group_selected = false
			app.task = {}
			refresh_window_preview()
		}
	}

	build_task_groups()
	clamp_scroll()
}

push_sample :: proc(samples: []f32, v: f32) {
	if len(samples) == 0 {
		return
	}
	for i in 1..<len(samples) {
		samples[i-1] = samples[i]
	}
	samples[len(samples)-1] = v
}

update_task_metrics :: proc() {
	if !app.has_selection {
		if app.task.pid != 0 || app.task.group_mode {
			app.task = {}
		}
		return
	}

	// Start a fresh history when the selection changes.
	if app.group_selected {
		if !app.task.group_mode || !same_task_name(app.task.group, app.selected_group) {
			app.task = Task_Metrics{group_mode = true, group = app.selected_group}
		}
	} else if app.task.group_mode || app.task.pid != app.selected_pid {
		app.task = Task_Metrics{pid = app.selected_pid}
	}

	t := &app.task
	t.cpu = 0
	t.mem_bytes = 0
	t.gpu = 0
	t.read_bps = 0
	t.write_bps = 0
	t.threads = 0
	t.handles = 0
	t.cpu_time = 0
	t.count = 0

	if t.group_mode {
		for i in 0..<app.process_count {
			p := &app.processes[i]
			if !same_task_name(p.name, t.group) {
				continue
			}
			t.count += 1
			t.cpu += p.cpu_percent
			t.mem_bytes += p.working_set
			t.gpu += p.gpu_percent
			t.read_bps += p.io_read_bps
			t.write_bps += p.io_write_bps
			t.threads += p.threads
			t.handles += p.handles
			t.cpu_time += p.cpu_time
		}
	} else if p, found := find_process(t.pid); found {
		t.count = 1
		t.cpu = p.cpu_percent
		t.mem_bytes = p.working_set
		t.gpu = gpu_usage_for_pid(p.pid)
		t.read_bps = p.io_read_bps
		t.write_bps = p.io_write_bps
		t.threads = p.threads
		t.handles = p.handles
		t.cpu_time = p.cpu_time
	}
	if t.gpu > 100 {
		t.gpu = 100
	}

	push_sample(t.cpu_samples[:], t.cpu)
	push_sample(t.mem_samples[:], f32(f64(t.mem_bytes) / (1024.0*1024.0)))
	push_sample(t.threads_samples[:], f32(t.threads))
	push_sample(t.handles_samples[:], f32(t.handles))
	push_sample(t.gpu_samples[:], t.gpu)
	push_sample(t.read_samples[:], f32(t.read_bps))
	push_sample(t.write_samples[:], f32(t.write_bps))
}

push_cpu_sample :: proc(v: f32) {
	for i in 1..<SAMPLE_COUNT {
		app.cpu_samples[i-1] = app.cpu_samples[i]
	}
	app.cpu_samples[SAMPLE_COUNT-1] = v
}

push_mem_sample :: proc(v: f32) {
	for i in 1..<SAMPLE_COUNT {
		app.mem_samples[i-1] = app.mem_samples[i]
	}
	app.mem_samples[SAMPLE_COUNT-1] = v
}

push_gpu_sample :: proc(v: f32) {
	for i in 1..<SAMPLE_COUNT {
		app.gpu_samples[i-1] = app.gpu_samples[i]
	}
	app.gpu_samples[SAMPLE_COUNT-1] = v
}

update_core_usage :: proc() {
	if app.cores <= 0 {
		return
	}

	times: [MAX_CORES]Core_Times
	status := NtQuerySystemInformation(
		SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION,
		rawptr(&times[0]),
		u32(app.cores * size_of(Core_Times)),
		nil,
	)
	if status != 0 {
		return
	}

	if app.have_core_prev {
		for i in 0..<app.cores {
			prev := app.core_prev[i]
			cur := times[i]
			delta_idle := cur.idle - prev.idle
			delta_total := (cur.kernel + cur.user) - (prev.kernel + prev.user)
			if delta_total > 0 {
				busy := delta_total - delta_idle
				if busy < 0 {
					busy = 0
				}
				pct := f32(f64(busy) / f64(delta_total) * 100.0)
				if pct < 0 {
					pct = 0
				}
				if pct > 100 {
					pct = 100
				}
				app.core_usage[i] = pct
			}
		}
	}

	for i in 0..<app.cores {
		app.core_prev[i] = times[i]
		push_sample(app.core_samples[i][:], app.core_usage[i])
	}
	app.have_core_prev = true
}

wide_has_ascii :: proc(text: [^]u16, needle: string) -> bool {
	if text == nil || len(needle) == 0 {
		return false
	}
	for i := 0; text[i] != 0; i += 1 {
		ok := true
		for j in 0..<len(needle) {
			c := text[i+j]
			if c == 0 {
				ok = false
				break
			}
			cc := c
			if cc >= 'A' && cc <= 'Z' {
				cc += 32
			}
			n := needle[j]
			if n >= 'A' && n <= 'Z' {
				n += 32
			}
			if u8(cc) != n {
				ok = false
				break
			}
		}
		if ok {
			return true
		}
	}
	return false
}

// GPU Engine instance names look like
// "pid_1234_luid_0x00000000_0x0000CEFE_phys_0_eng_0_engtype_3D"; the leading
// pid is the process the engine usage belongs to.
gpu_engine_pid :: proc(name: [^]u16) -> u32 {
	if name == nil {
		return 0
	}
	prefix := [?]u16{'p', 'i', 'd', '_'}
	for i in 0..<len(prefix) {
		if name[i] != prefix[i] {
			return 0
		}
	}
	pid: u32 = 0
	for i := len(prefix); name[i] >= '0' && name[i] <= '9'; i += 1 {
		pid = pid*10 + u32(name[i] - '0')
	}
	return pid
}

gpu_engine_group :: proc(name: [^]u16) -> int {
	if wide_has_ascii(name, "engtype_3d") {
		return 0
	}
	if wide_has_ascii(name, "engtype_copy") {
		return 1
	}
	if wide_has_ascii(name, "engtype_videodecode") {
		return 2
	}
	if wide_has_ascii(name, "engtype_videoencode") {
		return 3
	}
	if wide_has_ascii(name, "engtype_compute") {
		return 4
	}
	return 5
}

update_pdh_rates :: proc() {
	app.task.gpu = 0
	app.gpu_pid_count = 0
	if app.pdh_query == nil {
		app.disk_read_bps = 0
		app.disk_write_bps = 0
		return
	}
	if PdhCollectQueryData(app.pdh_query) != 0 {
		app.disk_read_bps = 0
		app.disk_write_bps = 0
		return
	}

	if app.pdh_read != nil {
		value: Pdh_Fmt_Counter_Value
		if PdhGetFormattedCounterValue(app.pdh_read, PDH_FMT_DOUBLE, nil, &value) == 0 && value.status <= 1 {
			app.disk_read_bps = max(value.double_value, 0.0)
		}

		value = {}
		if PdhGetFormattedCounterValue(app.pdh_write, PDH_FMT_DOUBLE, nil, &value) == 0 && value.status <= 1 {
			app.disk_write_bps = max(value.double_value, 0.0)
		}
	}

	if app.gpu_counter != nil {
		buffer_size := u32(size_of(app.pdh_buffer))
		item_count: u32
		status := PdhGetFormattedCounterArrayW(
			app.gpu_counter,
			PDH_FMT_DOUBLE,
			&buffer_size,
			&item_count,
			rawptr(&app.pdh_buffer[0]),
		)
		if status == 0 {
			sums: [GPU_ENGINE_COUNT]f64
			ptr := uintptr(&app.pdh_buffer[0])
			for _ in 0..<item_count {
				item := cast(^Pdh_Fmt_Counter_Value_Item)ptr
				if item.value.status <= 1 {
					v := item.value.double_value
					if v > 0 {
						group := gpu_engine_group(cast([^]u16)item.name)
						sums[group] += v
						gpu_usage_add(gpu_engine_pid(cast([^]u16)item.name), f32(v))
					}
				}
				ptr += uintptr(size_of(Pdh_Fmt_Counter_Value_Item))
			}

			overall: f64 = 0
			for i in 0..<GPU_ENGINE_COUNT {
				v := sums[i]
				if v > 100 {
					v = 100
				}
				if v > overall {
					overall = v
				}
			}
			app.gpu = f32(overall)
			app.gpu_ok = true
		}
	}

	if app.gpu_mem_counter != nil {
		buffer_size := u32(size_of(app.pdh_buffer))
		item_count: u32
		status := PdhGetFormattedCounterArrayW(
			app.gpu_mem_counter,
			PDH_FMT_DOUBLE,
			&buffer_size,
			&item_count,
			rawptr(&app.pdh_buffer[0]),
		)
		if status == 0 {
			max_bytes: f64 = 0
			ptr := uintptr(&app.pdh_buffer[0])
			for _ in 0..<item_count {
				item := cast(^Pdh_Fmt_Counter_Value_Item)ptr
				if item.value.status <= 1 && item.value.double_value > max_bytes {
					max_bytes = item.value.double_value
				}
				ptr += uintptr(size_of(Pdh_Fmt_Counter_Value_Item))
			}
			app.gpu_vram = f32(max_bytes / GIB)
			app.gpu_mem_ok = true
		}
	}
}

update_network_rates :: proc(now: u64) {
	size := u32(size_of(app.net_table))
	status := GetIfTable(rawptr(&app.net_table), &size, win.FALSE)
	if status != 0 {
		app.net_ok = false
		app.net_online = false
		app.net_in_bps = 0
		app.net_out_bps = 0
		app.net_have_prev = false
		app.net_prev_count = 0
		return
	}
	app.net_ok = true

	next_prev: [MAX_NET_INTERFACES]If_Counter
	next_count := 0
	max_in: f64 = 0
	max_out: f64 = 0
	online := false
	has_prev := app.net_have_prev && now > app.net_last_ms
	seconds := f64(now - app.net_last_ms) / 1000.0

	count := min(int(app.net_table.count), len(app.net_table.rows))
	for i in 0..<count {
		row := &app.net_table.rows[i]
		if row.type_ != IF_TYPE_ETHERNET_CSMACD && row.type_ != IF_TYPE_IEEE80211 {
			continue
		}
		// Adapters without media (WAN Miniports, unplugged NICs) still show up as
		// connected but never report a link speed.
		if row.speed == 0 {
			continue
		}
		// Only adapters that are enabled and actually attached to a network can
		// move traffic. Disconnected adapters keep their last counters around,
		// so including them keeps reporting stale rates while offline.
		if row.admin_status != IF_ADMIN_STATUS_UP {
			continue
		}
		if row.oper_status != IF_OPER_STATUS_CONNECTED && row.oper_status != IF_OPER_STATUS_OPERATIONAL {
			continue
		}
		descr_len := min(int(row.descr_len), len(row.descr))
		if is_virtual_adapter(row.descr[:descr_len]) {
			continue
		}
		online = true

		if has_prev && seconds > 0 {
			for j in 0..<app.net_prev_count {
				prev := app.net_prev_if[j]
				if prev.index != row.index {
					continue
				}
				delta_in := wrapped_delta_u32(row.in_octets, prev.bytes_in)
				delta_out := wrapped_delta_u32(row.out_octets, prev.bytes_out)
				limit := f64(row.speed) / 8.0 * seconds * 2.0 + 1_000_000.0
				if f64(delta_in) <= limit && f64(delta_out) <= limit {
					in_rate := f64(delta_in) / seconds
					out_rate := f64(delta_out) / seconds
					if in_rate > max_in {
						max_in = in_rate
					}
					if out_rate > max_out {
						max_out = out_rate
					}
				}
				break
			}
		}

		if next_count < MAX_NET_INTERFACES {
			next_prev[next_count] = If_Counter{index = row.index, bytes_in = row.in_octets, bytes_out = row.out_octets}
			next_count += 1
		}
	}

	for i in 0..<next_count {
		app.net_prev_if[i] = next_prev[i]
	}
	app.net_prev_count = next_count

	app.net_online = online
	if !online {
		app.net_in_bps = 0
		app.net_out_bps = 0
	} else if has_prev && seconds > 0 {
		app.net_in_bps = max(max_in, 0)
		app.net_out_bps = max(max_out, 0)
	}

	app.net_last_ms = now
	app.net_have_prev = true
}

update_metrics :: proc() {
	now := GetTickCount64()

	idle, kernel, user: win.FILETIME
	GetSystemTimes(&idle, &kernel, &user)

	idle_now := filetime_value(idle)
	kernel_now := filetime_value(kernel)
	user_now := filetime_value(user)

	if app.have_last {
		delta_idle := idle_now - app.last_idle
		delta_total := (kernel_now - app.last_kernel) + (user_now - app.last_user)
		if delta_total > 0 {
			busy := delta_total > delta_idle ? delta_total - delta_idle : 0
			pct := f32(busy) / f32(delta_total) * 100.0
			if pct < 0 {
				pct = 0
			}
			if pct > 100 {
				pct = 100
			}
			app.cpu = pct
		}
	}

	app.last_idle = idle_now
	app.last_kernel = kernel_now
	app.last_user = user_now
	app.have_last = true
	push_cpu_sample(app.cpu)

	update_core_usage()

	mem: win.MEMORYSTATUSEX
	mem.dwLength = u32(size_of(win.MEMORYSTATUSEX))
	if win.GlobalMemoryStatusEx(&mem) {
		total := f32(mem.ullTotalPhys)
		avail := f32(mem.ullAvailPhys)
		if total > 0 {
			used := total - avail
			app.mem_total = total / f32(GIB)
			app.mem_used = used / f32(GIB)
			app.mem_percent = used / total * 100.0
		}
	}

	push_mem_sample(app.mem_percent)

	update_pdh_rates()
	push_gpu_sample(app.gpu)

	update_network_rates(now)
	update_task_metrics()

	app.uptime_secs = now / 1000
}

format_uptime :: proc(buf: []u8) -> string {
	secs := app.uptime_secs
	days := secs / 86400
	hours := (secs % 86400) / 3600
	mins := (secs % 3600) / 60

	if days > 0 {
		return fmt.bprintf(buf, "%dd %dh %dm", days, hours, mins)
	}
	if hours > 0 {
		return fmt.bprintf(buf, "%dh %dm", hours, mins)
	}
	return fmt.bprintf(buf, "%dm", mins)
}

format_memory :: proc(buf: []u8, bytes: u64) -> string {
	if bytes == 0 {
		return "—"
	}
	mb := f64(bytes) / (1024.0*1024.0)
	if mb >= 1024.0 {
		return fmt.bprintf(buf, "%.1f GB", mb/1024.0)
	}
	return fmt.bprintf(buf, "%.0f MB", mb)
}

format_cpu_time :: proc(buf: []u8, ticks: u64) -> string {
	secs := ticks / 10_000_000
	hours := secs / 3600
	mins := (secs % 3600) / 60
	rem := secs % 60
	if hours > 0 {
		return fmt.bprintf(buf, "%dh %dm %ds", hours, mins, rem)
	}
	if mins > 0 {
		return fmt.bprintf(buf, "%dm %ds", mins, rem)
	}
	return fmt.bprintf(buf, "%ds", rem)
}

rate_scale :: proc(bps: f64) -> (factor: f64, suffix: string) {
	if bps >= 1e9 {
		return 1e9, "GB/s"
	}
	if bps >= 1e6 {
		return 1e6, "MB/s"
	}
	if bps >= 1e3 {
		return 1e3, "KB/s"
	}
	return 1.0, "B/s"
}

palette_for_role :: proc(role: int) -> []Color {
	switch role {
	case 0: return ACCENT_PALETTE[:]
	case 1: return MEMORY_PALETTE[:]
	case 2: return GPU_PALETTE[:]
	}
	return nil
}

color_for_role :: proc(role: int) -> Color {
	switch role {
	case 1: return settings.memory_color
	case 2: return settings.gpu_color
	}
	return settings.accent
}

open_color_picker :: proc(role: int) {
	current := color_for_role(role)
	cc: CHOOSECOLORW
	cc.lStructSize = u32(size_of(CHOOSECOLORW))
	cc.hwndOwner = app.hwnd
	cc.rgbResult = colorref(current)
	cc.lpCustColors = &color_custom_colors[0]
	cc.Flags = CC_RGBINIT | CC_FULLOPEN | CC_ANYCOLOR

	app.color_dialog_open = true
	ok := ChooseColorW(&cc)
	app.color_dialog_open = false

	if ok {
		color := Color{
			u8(cc.rgbResult & 0xff),
			u8(cc.rgbResult >> 8 & 0xff),
			u8(cc.rgbResult >> 16 & 0xff),
		}
		settings_set_color(role, color)
	}

	_ = win.SetForegroundWindow(app.hwnd)
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

settings_set_color :: proc(role: int, color: Color) {
	switch role {
	case 0: settings.accent = color
	case 1: settings.memory_color = color
	case 2: settings.gpu_color = color
	}
	save_settings()
	apply_visual_settings()
}

settings_set_theme :: proc(index: int) {
	settings.theme = clamp(index, 0, len(THEMES)-1)
	save_settings()
	apply_visual_settings()
}

settings_set_dock :: proc(mode: Dock_Mode) {
	if settings.dock == mode {
		return
	}
	settings.dock = mode
	// Moving an AppBar can hand activation away long enough for the drawer to
	// close itself; ignore that deactivation while the window is re-anchored.
	app.deactivate_guard_until = GetTickCount64() + 600
	save_settings()

	if !app.appbar_registered {
		register_appbar(app.hwnd)
	}
	position_appbar(app.hwnd)
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

settings_toggle_module :: proc(id: Module_Id) {
	if id == .cores && !settings.modules.cpu {
		return
	}
	module_set(id, !module_enabled(id))
	save_settings()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

settings_set_sort :: proc(field: Sort_Field) {
	if settings.sort_field == field {
		settings.sort_desc = !settings.sort_desc
	} else {
		settings.sort_field = field
		settings.sort_desc = true
	}
	sort_processes(app.processes[:app.process_count])
	build_task_groups()
	save_settings()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

apply_refresh_timer :: proc() {
	if app.hwnd != nil {
		_ = win.SetTimer(app.hwnd, TIMER_ID, u32(settings.refresh_ms), nil)
	}
}

settings_set_refresh_ms :: proc(ms: int) {
	value := clamp(ms, REFRESH_MIN_MS, REFRESH_MAX_MS)
	if settings.refresh_ms == value && !settings.refresh_custom_mode {
		return
	}
	settings.refresh_ms = value
	settings.refresh_custom_mode = false
	save_settings()
	apply_refresh_timer()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

refresh_is_preset :: proc(ms: int) -> bool {
	for option in REFRESH_OPTIONS {
		if option > 0 && option == ms {
			return true
		}
	}
	return false
}

is_refresh_custom :: proc() -> bool {
	return settings.refresh_custom_mode
}

settings_use_custom_refresh :: proc() {
	settings.refresh_ms = clamp(settings.refresh_custom, REFRESH_MIN_MS, REFRESH_MAX_MS)
	settings.refresh_custom = settings.refresh_ms
	settings.refresh_custom_mode = true
	save_settings()
	apply_refresh_timer()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

settings_adjust_custom_refresh :: proc(delta: int) {
	value := clamp(settings.refresh_ms + delta, REFRESH_MIN_MS, REFRESH_MAX_MS)
	if value == settings.refresh_ms && settings.refresh_custom_mode {
		return
	}
	settings.refresh_ms = value
	settings.refresh_custom = value
	settings.refresh_custom_mode = true
	save_settings()
	apply_refresh_timer()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

begin_refresh_edit :: proc() {
	app.refresh_edit = true
	app.refresh_edit_replace = true
	app.refresh_edit_len = 0

	buf: [8]u8
	s := fmt.bprintf(buf[:], "%d", settings.refresh_ms)
	n := min(len(s), len(app.refresh_edit_buf))
	copy(app.refresh_edit_buf[:], s[:n])
	app.refresh_edit_len = n
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

commit_refresh_edit :: proc() {
	if !app.refresh_edit {
		return
	}
	app.refresh_edit = false
	app.refresh_edit_replace = false

	if app.refresh_edit_len > 0 {
		value := clamp(
			parse_int(string(app.refresh_edit_buf[:app.refresh_edit_len])),
			REFRESH_MIN_MS,
			REFRESH_MAX_MS,
		)
		settings.refresh_ms = value
		settings.refresh_custom = value
		settings.refresh_custom_mode = true
		save_settings()
		apply_refresh_timer()
	}
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

cancel_refresh_edit :: proc() {
	app.refresh_edit = false
	app.refresh_edit_replace = false
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

refresh_label :: proc(buf: []u8, ms: int) -> string {
	if ms >= 1000 && ms % 1000 == 0 {
		return fmt.bprintf(buf, "%ds", ms/1000)
	}
	return fmt.bprintf(buf, "%dms", ms)
}

refresh_history_label :: proc(buf: []u8, ms: int) -> string {
	total := SAMPLE_COUNT * ms / 1000
	if total >= 60 {
		if total % 60 == 0 {
			return fmt.bprintf(buf, "%dm history", total/60)
		}
		return fmt.bprintf(buf, "%dm %ds history", total/60, total%60)
	}
	return fmt.bprintf(buf, "%ds history", total)
}

settings_set_cores_per_page :: proc(per: int) {
	if per < 0 || per > MAX_CORES {
		return
	}
	settings.cores_per_page = per
	if per <= 0 {
		settings.cores_custom_mode = false
	} else if per == 4 || per == 6 || per == 8 || per == 16 {
		settings.cores_custom_mode = false
	} else {
		settings.cores_custom_mode = true
		settings.cores_custom = per
	}
	app.core_page = 0
	clamp_core_page()
	save_settings()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

settings_use_custom_cores :: proc() {
	max_per := max(app.cores, 1)
	settings.cores_custom_mode = true
	settings.cores_custom = clamp(settings.cores_custom, 1, max_per)
	settings.cores_per_page = settings.cores_custom
	app.core_page = 0
	clamp_core_page()
	save_settings()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

settings_adjust_custom_cores :: proc(delta: int) {
	max_per := max(app.cores, 1)
	base := clamp(settings.cores_per_page, 1, max_per)
	per := clamp(base + delta, 1, max_per)
	settings.cores_custom = per
	settings.cores_per_page = per
	settings.cores_custom_mode = true
	app.core_page = 0
	clamp_core_page()
	save_settings()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

reset_settings :: proc() {
	settings = default_settings()
	app.core_page = 0
	save_settings()
	apply_visual_settings()
	apply_refresh_timer()
}

parse_bool :: proc(s: string) -> bool {
	return len(s) > 0 && (s[0] == '1' || s[0] == 't' || s[0] == 'T')
}

parse_int :: proc(s: string) -> int {
	value := 0
	for c in s {
		if c < '0' || c > '9' {
			break
		}
		value = value*10 + int(c - '0')
	}
	return value
}

hex_digit :: proc(c: byte) -> (u8, bool) {
	if c >= '0' && c <= '9' {
		return c - '0', true
	}
	if c >= 'a' && c <= 'f' {
		return c - 'a' + 10, true
	}
	if c >= 'A' && c <= 'F' {
		return c - 'A' + 10, true
	}
	return 0, false
}

parse_hex_color :: proc(s: string) -> (Color, bool) {
	if len(s) < 6 {
		return {}, false
	}
	values: [6]u8
	for i in 0..<6 {
		v, ok := hex_digit(s[i])
		if !ok {
			return {}, false
		}
		values[i] = v
	}
	return Color{
		values[0]*16 + values[1],
		values[2]*16 + values[3],
		values[4]*16 + values[5],
	}, true
}

parse_settings :: proc(text: string) {
	version := 1
	lines, _ := strings.split_lines(text, context.temp_allocator)
	for raw in lines {
		line := strings.trim_space(raw)
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		eq := strings.index_byte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		value := strings.trim_space(line[eq+1:])

		switch key {
		case "version":
			version = parse_int(value)
		case "show_cpu":
			settings.modules.cpu = parse_bool(value)
		case "show_cores":
			settings.modules.cores = parse_bool(value)
		case "show_memory":
			settings.modules.memory = parse_bool(value)
		case "show_disk":
			settings.modules.disk = parse_bool(value)
		case "show_network":
			settings.modules.network = parse_bool(value)
		case "show_gpu":
			settings.modules.gpu = parse_bool(value)
		case "show_uptime":
			settings.modules.uptime = parse_bool(value)
		case "accent":
			if c, ok := parse_hex_color(value); ok {
				settings.accent = c
			}
		case "memory_color":
			if c, ok := parse_hex_color(value); ok {
				settings.memory_color = c
			}
		case "gpu_color":
			if c, ok := parse_hex_color(value); ok {
				settings.gpu_color = c
			}
		case "theme":
			settings.theme = clamp(parse_int(value), 0, len(THEMES)-1)
		case "cores_per_page":
			per := parse_int(value)
			if per >= 0 && per <= MAX_CORES {
				settings.cores_per_page = per
			}
		case "cores_custom":
			settings.cores_custom = clamp(parse_int(value), 1, MAX_CORES)
		case "cores_custom_mode":
			settings.cores_custom_mode = parse_bool(value)
		case "sort_field":
			settings.sort_field = Sort_Field(clamp(parse_int(value), 0, len(SORT_FIELD_LABELS)-1))
		case "sort_desc":
			settings.sort_desc = parse_bool(value)
		case "refresh_ms":
			ms := parse_int(value)
			if ms > 0 {
				settings.refresh_ms = clamp(ms, REFRESH_MIN_MS, REFRESH_MAX_MS)
			}
		case "refresh_custom":
			ms := parse_int(value)
			if ms > 0 {
				settings.refresh_custom = clamp(ms, REFRESH_MIN_MS, REFRESH_MAX_MS)
			}
		case "refresh_custom_mode":
			settings.refresh_custom_mode = parse_bool(value)
		case "dock":
			settings.dock = Dock_Mode(clamp(parse_int(value), 0, len(DOCK_LABELS)-1))
		}
	}

	if !settings.modules.cpu {
		settings.modules.cores = false
	}
	settings.theme = clamp(settings.theme, 0, len(THEMES)-1)
	settings.refresh_ms = clamp(settings.refresh_ms, REFRESH_MIN_MS, REFRESH_MAX_MS)
	settings.refresh_custom = clamp(settings.refresh_custom, REFRESH_MIN_MS, REFRESH_MAX_MS)
	if settings.refresh_custom_mode {
		settings.refresh_ms = settings.refresh_custom
	} else if !refresh_is_preset(settings.refresh_ms) {
		// A hand-edited interval that is not one of the chips is a custom value.
		settings.refresh_custom_mode = true
		settings.refresh_custom = settings.refresh_ms
	}
	if settings.cores_per_page <= 0 {
		settings.cores_custom_mode = false
	} else if settings.cores_custom_mode {
		settings.cores_custom = clamp(settings.cores_per_page, 1, MAX_CORES)
	}
	// Older builds persisted a different sort field set.
	if version < 2 {
		settings.sort_field = .cpu
		settings.sort_desc = true
	}
}

settings_file_path :: proc(dir_buf, path_buf: []u8) -> (dir: string, path: string) {
	appdata, ok := os.lookup_env("APPDATA", context.temp_allocator)
	if ok && len(appdata) > 0 {
		dir = fmt.bprintf(dir_buf, "%s\\MiniTaskManager", appdata)
		path = fmt.bprintf(path_buf, "%s\\settings.ini", dir)
		return
	}
	return "", "settings.ini"
}

load_settings :: proc() {
	settings = default_settings()

	for i in 0..<16 {
		color_custom_colors[i] = 0x00FFFFFF
	}

	dir_buf, path_buf: [512]u8
	_, path := settings_file_path(dir_buf[:], path_buf[:])
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return
	}
	parse_settings(string(data))
}

save_settings :: proc() {
	dir_buf, path_buf: [512]u8
	dir, path := settings_file_path(dir_buf[:], path_buf[:])
	if len(dir) > 0 {
		_ = os.make_directory_all(dir)
	}

	buf: [1024]u8
	content := fmt.bprintf(
		buf[:],
		"version=3\nshow_cpu=%d\nshow_cores=%d\nshow_memory=%d\nshow_disk=%d\nshow_network=%d\nshow_gpu=%d\nshow_uptime=%d\n" +
		"accent=%02X%02X%02X\nmemory_color=%02X%02X%02X\ngpu_color=%02X%02X%02X\ntheme=%d\ncores_per_page=%d\ncores_custom=%d\ncores_custom_mode=%d\nsort_field=%d\nsort_desc=%d\nrefresh_ms=%d\n" +
		"refresh_custom=%d\nrefresh_custom_mode=%d\ndock=%d\n",
		int(settings.modules.cpu),
		int(settings.modules.cores),
		int(settings.modules.memory),
		int(settings.modules.disk),
		int(settings.modules.network),
		int(settings.modules.gpu),
		int(settings.modules.uptime),
		settings.accent[0], settings.accent[1], settings.accent[2],
		settings.memory_color[0], settings.memory_color[1], settings.memory_color[2],
		settings.gpu_color[0], settings.gpu_color[1], settings.gpu_color[2],
		settings.theme,
		settings.cores_per_page,
		settings.cores_custom,
		int(settings.cores_custom_mode),
		int(settings.sort_field),
		int(settings.sort_desc),
		settings.refresh_ms,
		settings.refresh_custom,
		int(settings.refresh_custom_mode),
		int(settings.dock),
	)
	_ = os.write_entire_file(path, content)
}

theme_bg :: proc() -> Color {
	return THEMES[clamp(settings.theme, 0, len(THEMES)-1)].bg
}

init_resources :: proc() {
	face := win.utf8_to_wstring_alloc("Segoe UI")

	app.fonts.title = create_font(face, 19, win.FW_SEMIBOLD)
	app.fonts.heading = create_font(face, 24, win.FW_SEMIBOLD)
	app.fonts.huge = create_font(face, 36, win.FW_SEMIBOLD)
	app.fonts.med = create_font(face, 18, win.FW_SEMIBOLD)
	app.fonts.stat = create_font(face, 16, win.FW_SEMIBOLD)
	app.fonts.body = create_font(face, 13, win.FW_NORMAL)
	app.fonts.small = create_font(face, 11, win.FW_NORMAL)
	app.fonts.tiny = create_font(face, 10, win.FW_NORMAL)
	app.fonts.badge = create_font(face, 13, win.FW_SEMIBOLD)

	create_visual_objects()
}

create_visual_objects :: proc() {
	theme := THEMES[clamp(settings.theme, 0, len(THEMES)-1)]
	accent := settings.accent
	mem_color := settings.memory_color
	gpu_color := settings.gpu_color

	app.brushes.bg = win.CreateSolidBrush(colorref(theme.bg))
	app.brushes.sidebar = win.CreateSolidBrush(colorref(theme.sidebar))
	app.brushes.card = win.CreateSolidBrush(colorref(theme.card))
	app.brushes.selected = win.CreateSolidBrush(colorref(mix_color(theme.bg, accent, 0.16)))
	app.brushes.badge = win.CreateSolidBrush(colorref(mix_color(theme.card, COL_TEXT, 0.04)))
	app.brushes.accent = win.CreateSolidBrush(colorref(accent))
	app.brushes.track = win.CreateSolidBrush(colorref(theme.line))
	app.brushes.thumb = win.CreateSolidBrush(colorref(theme.border))
	app.brushes.cpu_fill = win.CreateSolidBrush(colorref(mix_color(theme.card, accent, 0.22)))
	app.brushes.mem_fill = win.CreateSolidBrush(colorref(mix_color(theme.card, mem_color, 0.22)))
	app.brushes.gpu_fill = win.CreateSolidBrush(colorref(mix_color(theme.card, gpu_color, 0.22)))
	app.brushes.line = win.CreateSolidBrush(colorref(theme.line))
	app.brushes.dark = win.CreateSolidBrush(colorref(COL_BADGE_TEXT))
	app.brushes.light = win.CreateSolidBrush(colorref(COL_TEXT))
	app.brushes.muted = win.CreateSolidBrush(colorref(COL_MUTED))

	app.pens.border = win.CreatePen(win.PS_SOLID, 1, colorref(theme.border))
	app.pens.cpu = win.CreatePen(win.PS_SOLID, max(S(2), 1), colorref(accent))
	app.pens.mem = win.CreatePen(win.PS_SOLID, max(S(2), 1), colorref(mem_color))
	app.pens.gpu = win.CreatePen(win.PS_SOLID, max(S(2), 1), colorref(gpu_color))
	app.pens.null = win.CreatePen(win.PS_NULL, 0, 0)
}

delete_visual_objects :: proc() {
	delete_gdi(app.brushes.bg)
	delete_gdi(app.brushes.sidebar)
	delete_gdi(app.brushes.card)
	delete_gdi(app.brushes.selected)
	delete_gdi(app.brushes.badge)
	delete_gdi(app.brushes.accent)
	delete_gdi(app.brushes.track)
	delete_gdi(app.brushes.thumb)
	delete_gdi(app.brushes.cpu_fill)
	delete_gdi(app.brushes.mem_fill)
	delete_gdi(app.brushes.gpu_fill)
	delete_gdi(app.brushes.line)
	delete_gdi(app.brushes.dark)
	delete_gdi(app.brushes.light)
	delete_gdi(app.brushes.muted)

	delete_gdi(app.pens.border)
	delete_gdi(app.pens.cpu)
	delete_gdi(app.pens.mem)
	delete_gdi(app.pens.gpu)
	delete_gdi(app.pens.null)
}

apply_visual_settings :: proc() {
	destroy_backbuffer()
	delete_visual_objects()
	create_visual_objects()
	if app.hwnd != nil {
		_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
	}
}

init_pdh_counters :: proc() {
	query: rawptr
	if PdhOpenQueryW(nil, 0, &query) != 0 {
		return
	}

	any_counter := false

	read_path := win.utf8_to_wstring_alloc("\\PhysicalDisk(_Total)\\Disk Read Bytes/sec")
	write_path := win.utf8_to_wstring_alloc("\\PhysicalDisk(_Total)\\Disk Write Bytes/sec")

	read_counter, write_counter: rawptr
	read_ok := PdhAddEnglishCounterW(query, read_path, 0, &read_counter) == 0
	write_ok := PdhAddEnglishCounterW(query, write_path, 0, &write_counter) == 0
	if read_ok && write_ok {
		app.pdh_read = read_counter
		app.pdh_write = write_counter
		app.pdh_ok = true
		any_counter = true
	}

	gpu_path := win.utf8_to_wstring_alloc("\\GPU Engine(*)\\Utilization Percentage")
	gpu_counter: rawptr
	if PdhAddEnglishCounterW(query, gpu_path, 0, &gpu_counter) == 0 {
		app.gpu_counter = gpu_counter
		any_counter = true
	}

	gpu_mem_path := win.utf8_to_wstring_alloc("\\GPU Adapter Memory(*)\\Dedicated Usage")
	gpu_mem_counter: rawptr
	if PdhAddEnglishCounterW(query, gpu_mem_path, 0, &gpu_mem_counter) == 0 {
		app.gpu_mem_counter = gpu_mem_counter
		any_counter = true
	}

	if !any_counter {
		_ = PdhCloseQuery(query)
		return
	}

	if PdhCollectQueryData(query) != 0 {
		_ = PdhCloseQuery(query)
		return
	}

	app.pdh_query = query
}

create_font :: proc(face: win.LPCWSTR, size: i32, weight: i32) -> win.HFONT {
	return win.CreateFontW(
		-S(size), 0, 0, 0, weight,
		0, 0, 0,
		win.DEFAULT_CHARSET, 0, 0, win.CLEARTYPE_QUALITY, 0,
		face,
	)
}

delete_gdi :: proc(handle: $T) {
	if handle == nil {
		return
	}
	_ = win.DeleteObject(win.HGDIOBJ(handle))
}

destroy_resources :: proc() {
	destroy_icon_cache()

	if app.pdh_query != nil {
		_ = PdhCloseQuery(app.pdh_query)
		app.pdh_query = nil
		app.pdh_read = nil
		app.pdh_write = nil
		app.gpu_counter = nil
		app.gpu_mem_counter = nil
	}

	delete_gdi(app.fonts.title)
	delete_gdi(app.fonts.heading)
	delete_gdi(app.fonts.huge)
	delete_gdi(app.fonts.med)
	delete_gdi(app.fonts.stat)
	delete_gdi(app.fonts.body)
	delete_gdi(app.fonts.small)
	delete_gdi(app.fonts.tiny)
	delete_gdi(app.fonts.badge)

	delete_visual_objects()
}
