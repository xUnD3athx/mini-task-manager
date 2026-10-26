package main

import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"

MAX_PROCESSES      :: 1024
MAX_NAME_U16       :: 96
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
TASK_PANEL_HEADER_DIP   :: 68
TASK_ROW_HEIGHT_DIP     :: 52

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

Settings :: struct {
	modules:      Module_Flags,
	accent:       Color,
	memory_color: Color,
	gpu_color:    Color,
	theme:        int,
}

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
	pid:         u32,
	threads:     u32,
	name:        [MAX_NAME_U16]u16,
	working_set: u64,
	cpu_time:    u64,
	cpu_percent: f32,
}

// Per-metrics of the task selected in the drawer, refreshed independently of
// the process list so the detail page can show IO rates and GPU usage.
Task_Metrics :: struct {
	pid:          u32,
	handles:      u32,
	gpu:          f32,
	read_bps:     f64,
	write_bps:    f64,
	prev_read:    u64,
	prev_write:   u64,
	prev_ms:      u64,
	have_io_prev: bool,
	cpu_samples:  [SAMPLE_COUNT]f32,
}

Fonts :: struct {
	title, heading, huge, med, stat, body, small, tiny, badge: win.HFONT,
}

Brushes :: struct {
	bg, sidebar, card, selected, badge, accent,
	track, thumb, cpu_fill, mem_fill, gpu_fill, gpu, grid, line, dark, light, muted: win.HBRUSH,
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
	thread_count:    u32,
	selected_pid:    u32,
	has_selection:   bool,
	scroll:          int,
	last_process_ms: u64,
	preview:         Window_Preview,
	task:            Task_Metrics,

	cpu:         f32,
	mem_percent: f32,
	mem_used:    f32,
	mem_total:   f32,
	uptime_secs: u64,
	cores:       int,

	core_usage:     [MAX_CORES]f32,
	core_prev:      [MAX_CORES]Core_Times,
	have_core_prev: bool,

	mem_available:    f32,
	mem_committed:    f32,
	mem_commit_limit: f32,
	mem_cached:       f32,
	mem_details_ok:   bool,
	handle_count:     u32,

	gpu:            f32,
	gpu_vram:       f32,
	gpu_ok:         bool,
	gpu_mem_ok:     bool,
	gpu_counter:    rawptr,
	gpu_mem_counter: rawptr,
	gpu_engine_usage: [GPU_ENGINE_COUNT]f32,

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
	tick:      u64,
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

tasks_geometry :: proc() -> Tasks_Geometry {
	pad := S(TASK_PANEL_PADDING_DIP)
	panel_w := tasks_panel_width()
	if panel_w <= 0 || app.drawer_h <= 0 {
		return {}
	}

	bottom := app.bar_h + app.drawer_h
	if app.view != .none && app.height > app.bar_h {
		bottom = app.height
	}
	top := app.bar_h + pad
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

visible_process_rows :: proc() -> int {
	return tasks_geometry().visible
}

clamp_scroll :: proc() {
	visible := visible_process_rows()
	max_scroll := max(app.process_count - visible, 0)
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
	outer := win.RECT{S(18), app.bar_h + S(18), app.width - S(18), app.height - S(18)}
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
	y := layout.appearance.top + S(42) + i32(index)*(S(80) + S(12))
	return win.RECT{layout.appearance.left, y, layout.appearance.right, y + S(80)}
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

process_name_less :: proc(a, b: ^Process) -> bool {
	for i in 0..<MAX_NAME_U16 {
		ca := a.name[i]
		cb := b.name[i]
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

find_old_process :: proc(pid: u32) -> (cpu_time: u64, found: bool) {
	for i in 0..<app.process_count {
		if app.processes[i].pid == pid {
			return app.processes[i].cpu_time, true
		}
	}
	return 0, false
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
	threads: u32 = 0

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
			_ = win.CloseHandle(handle)
		}

		if app.cores > 0 && elapsed_ms > 0 && p.cpu_time > 0 {
			old_cpu, found := find_old_process(p.pid)
			if found && p.cpu_time > old_cpu {
				delta := p.cpu_time - old_cpu
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
		}

		count += 1
		threads += p.threads
	}

	for i in 1..<count {
		p := next_processes[i]
		j := i - 1
		for j >= 0 && process_name_less(&p, &next_processes[j]) {
			next_processes[j+1] = next_processes[j]
			j -= 1
		}
		next_processes[j+1] = p
	}

	for i in 0..<count {
		app.processes[i] = next_processes[i]
	}
	app.process_count = count
	app.thread_count = threads

	if app.has_selection {
		alive := false
		for i in 0..<count {
			if app.processes[i].pid == app.selected_pid {
				alive = true
				break
			}
		}
		if !alive {
			app.has_selection = false
			app.task = {}
			refresh_window_preview()
		}
	}

	if app.has_selection && app.task.pid == app.selected_pid {
		if p, found := find_process(app.selected_pid); found {
			push_task_cpu_sample(p.cpu_percent)
		}
	}

	clamp_scroll()
}

push_task_cpu_sample :: proc(v: f32) {
	for i in 1..<SAMPLE_COUNT {
		app.task.cpu_samples[i-1] = app.task.cpu_samples[i]
	}
	app.task.cpu_samples[SAMPLE_COUNT-1] = v
}

update_task_metrics :: proc(now: u64) {
	if !app.has_selection {
		if app.task.pid != 0 {
			app.task = {}
		}
		return
	}
	if app.task.pid != app.selected_pid {
		app.task = Task_Metrics{pid = app.selected_pid}
	}

	handle := win.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, win.FALSE, app.selected_pid)
	if handle == nil {
		return
	}
	defer win.CloseHandle(handle)

	handles: u32
	if GetProcessHandleCount(handle, &handles) {
		app.task.handles = handles
	}

	io: Io_Counters
	if GetProcessIoCounters(handle, &io) {
		if app.task.have_io_prev && now > app.task.prev_ms {
			seconds := f64(now - app.task.prev_ms) / 1000.0
			if seconds > 0 {
				read_delta: u64 = 0
				if io.read_bytes >= app.task.prev_read {
					read_delta = io.read_bytes - app.task.prev_read
				}
				write_delta: u64 = 0
				if io.write_bytes >= app.task.prev_write {
					write_delta = io.write_bytes - app.task.prev_write
				}
				app.task.read_bps = f64(read_delta) / seconds
				app.task.write_bps = f64(write_delta) / seconds
			}
		}
		app.task.prev_read = io.read_bytes
		app.task.prev_write = io.write_bytes
		app.task.prev_ms = now
		app.task.have_io_prev = true
	}
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
						if app.has_selection && gpu_engine_pid(cast([^]u16)item.name) == app.selected_pid {
							app.task.gpu += f32(v)
						}
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
				app.gpu_engine_usage[i] = f32(v)
				if v > overall {
					overall = v
				}
			}
			app.gpu = f32(overall)
			app.gpu_ok = true
			if app.task.gpu > 100 {
				app.task.gpu = 100
			}
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

	perf: Performance_Information
	perf.cb = u32(size_of(Performance_Information))
	if GetPerformanceInfo(&perf, perf.cb) {
		page := f64(perf.page_size)
		app.mem_available = f32(f64(perf.physical_available) * page / GIB)
		app.mem_committed = f32(f64(perf.commit_total) * page / GIB)
		app.mem_commit_limit = f32(f64(perf.commit_limit) * page / GIB)
		app.mem_cached = f32(f64(perf.system_cache) * page / GIB)
		app.handle_count = perf.handle_count
		app.mem_details_ok = true
	}
	push_mem_sample(app.mem_percent)

	update_pdh_rates()
	push_gpu_sample(app.gpu)

	update_network_rates(now)
	update_task_metrics(now)

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

settings_toggle_module :: proc(id: Module_Id) {
	if id == .cores && !settings.modules.cpu {
		return
	}
	module_set(id, !module_enabled(id))
	save_settings()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

reset_settings :: proc() {
	settings = default_settings()
	save_settings()
	apply_visual_settings()
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
		}
	}

	if !settings.modules.cpu {
		settings.modules.cores = false
	}
	settings.theme = clamp(settings.theme, 0, len(THEMES)-1)
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
		"version=1\nshow_cpu=%d\nshow_cores=%d\nshow_memory=%d\nshow_disk=%d\nshow_network=%d\nshow_gpu=%d\nshow_uptime=%d\n" +
		"accent=%02X%02X%02X\nmemory_color=%02X%02X%02X\ngpu_color=%02X%02X%02X\ntheme=%d\n",
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
	app.brushes.gpu = win.CreateSolidBrush(colorref(gpu_color))
	app.brushes.grid = win.CreateSolidBrush(colorref(theme.line))
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
	delete_gdi(app.brushes.gpu)
	delete_gdi(app.brushes.grid)
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
