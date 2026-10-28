package core

import win "core:sys/windows"
import "../platform"

// 全局状态、数据类型、设置结构和基础辅助。

TIMER_ID :: 1

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
TASK_PANEL_HEADER_DIP   :: 106
TASK_ROW_HEIGHT_DIP     :: 52
TASK_SORT_ROW_DIP       :: 44
TASK_SORT_CHIP_H_DIP    :: 22
TASK_SORT_CHIP_GAP_DIP  :: 6
TASK_RISK_ROW_DIP       :: 70
TASK_RISK_CHIP_H_DIP    :: 20

Color :: [3]u8

COL_TEXT       :: Color{236, 236, 242}
COL_MUTED      :: Color{148, 148, 163}
COL_BADGE_TEXT :: Color{15, 15, 19}

COL_RISK_SAFE    :: Color{94, 214, 143}
COL_RISK_RISKY   :: Color{251, 146, 60}
COL_RISK_BLOCKED :: Color{232, 90, 90}
COL_RISK_UNKNOWN :: Color{148, 148, 163}

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
	// Indexed by Risk_Tier; a tier set to false is hidden from the task list.
	risk_show:         [4]bool,
}

Sort_Field :: enum {
	cpu,
	memory,
	gpu,
	disk,
}

SORT_FIELD_LABELS :: [4]string{"CPU", "MEM", "GPU", "DISK"}

// Windows only exposes two hard facts about a process (critical and protected);
// everything else is inferred, so the tiers are ordered by how much damage
// ending the task is expected to do. `unknown` means no signal, not danger.
Risk_Tier :: enum u8 {
	unknown,
	safe,
	risky,
	blocked,
}

risk_label :: proc(tier: Risk_Tier) -> string {
	switch tier {
	case .unknown: return "UNKNOWN"
	case .safe:    return "SAFE"
	case .risky:   return "RISKY"
	case .blocked: return "BLOCKED"
	}
	return "UNKNOWN"
}

Risk_Reason :: enum u8 {
	none,
	no_signal,
	app_window,
	shell_component,
	system_session,
	inspect_denied,
	protected_process,
	critical_process,
}

risk_reason_label :: proc(reason: Risk_Reason) -> string {
	switch reason {
	case .none:              return ""
	case .no_signal:         return "no signal"
	case .app_window:        return "app window"
	case .shell_component:   return "shell"
	case .system_session:    return "system session"
	case .inspect_denied:    return "no access"
	case .protected_process: return "protected"
	case .critical_process:  return "critical"
	}
	return ""
}

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
		risk_show = RISK_SHOW_DEFAULT,
	}
}

RISK_TIERS := [4]Risk_Tier{.unknown, .safe, .risky, .blocked}

// The list starts focused on the tasks Windows considers normal user apps.
RISK_SHOW_DEFAULT :: [4]bool{false, true, false, false}

risk_tier_visible :: proc(tier: Risk_Tier) -> bool {
	return settings.risk_show[int(tier)]
}

risk_tiers_visible_count :: proc() -> int {
	count := 0
	for ok in settings.risk_show {
		if ok {
			count += 1
		}
	}
	return count
}

risk_filter_active :: proc() -> bool {
	return risk_tiers_visible_count() < len(settings.risk_show)
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
	risk:           Risk_Tier,
	risk_reason:    Risk_Reason,
	has_window:     bool,
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
	risk:        Risk_Tier,
	risk_reason: Risk_Reason,
	// The subset of members that passes the risk filter. The row is hidden when
	// this is zero and its dot reflects the strongest tier still shown.
	visible_count:       int,
	visible_risk:        Risk_Tier,
	visible_risk_reason: Risk_Reason,
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
	track, thumb, cpu_fill, mem_fill, gpu_fill, line, dark, light, muted,
	risk_safe, risk_risky, risk_blocked, risk_unknown: win.HBRUSH,
}

Pens :: struct {
	border, cpu, mem, gpu, null: win.HPEN,
}

// GDI+ draws shapes from colours, not GDI handles, so every theme brush/pen is
// registered with the colour it was created from. The UI resolves handles
// through this table when rendering anti-aliased geometry.
Brush_Color :: struct {
	handle: win.HBRUSH,
	color:  Color,
}

Pen_Style :: struct {
	handle: win.HPEN,
	color:  Color,
	width:  i32,
}

brush_colors: [24]Brush_Color
brush_color_count: int
pen_styles: [8]Pen_Style
pen_style_count: int

register_brush :: proc(handle: win.HBRUSH, color: Color) {
	if handle == nil || brush_color_count >= len(brush_colors) {
		return
	}
	brush_colors[brush_color_count] = Brush_Color{handle = handle, color = color}
	brush_color_count += 1
}

register_pen :: proc(handle: win.HPEN, color: Color, width: i32) {
	if handle == nil || pen_style_count >= len(pen_styles) {
		return
	}
	pen_styles[pen_style_count] = Pen_Style{handle = handle, color = color, width = width}
	pen_style_count += 1
}

brush_color_of :: proc(handle: win.HBRUSH) -> (Color, bool) {
	for i in 0..<brush_color_count {
		if brush_colors[i].handle == handle {
			return brush_colors[i].color, true
		}
	}
	return {}, false
}

pen_style_of :: proc(handle: win.HPEN) -> (Color, bool, i32) {
	for i in 0..<pen_style_count {
		if pen_styles[i].handle == handle {
			return pen_styles[i].color, true, pen_styles[i].width
		}
	}
	return {}, false, 0
}

Window_Preview :: struct {
	hwnd:      win.HWND,
	thumbnail: win.HANDLE,
	src_w:     i32,
	src_h:     i32,
	title:     [128]u16,
	visible:   bool,
}

App :: struct {
	hwnd:  win.HWND,
	scale: f32,
	gdiplus_token: uintptr,

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
	core_prev:      [MAX_CORES]platform.Core_Times,
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
	net_table:      platform.Mib_If_Table,

	cpu_samples: [SAMPLE_COUNT]f32,
	mem_samples: [SAMPLE_COUNT]f32,
	gpu_samples: [SAMPLE_COUNT]f32,

	last_idle, last_kernel, last_user: u64,
	have_last: bool,
}

app: App
next_processes: [MAX_PROCESSES]Process
color_custom_colors: [16]win.COLORREF

// dip converts 96-DPI logical pixels to physical pixels.
dip :: proc(v: i32) -> i32 {
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
