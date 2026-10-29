package core

import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"
import "../platform"

// 设置读写、主题/颜色、字体与 GDI 资源生命周期。

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
	cc: platform.CHOOSECOLORW
	cc.lStructSize = u32(size_of(platform.CHOOSECOLORW))
	cc.hwndOwner = app.hwnd
	cc.rgbResult = colorref(current)
	cc.lpCustColors = &color_custom_colors[0]
	cc.Flags = platform.CC_RGBINIT | platform.CC_FULLOPEN | platform.CC_ANYCOLOR

	app.modal_open = true
	ok := platform.ChooseColorW(&cc)
	app.modal_open = false

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

// Keeps at least one tier visible so the task list never goes blank by accident.
settings_toggle_risk_tier :: proc(tier: Risk_Tier) {
	if settings.risk_show[int(tier)] && risk_tiers_visible_count() <= 1 {
		return
	}
	settings.risk_show[int(tier)] = !settings.risk_show[int(tier)]
	save_settings()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

// Unsafe mode widens the detail page's end-task button to blocked tasks. It is
// the only setting that can damage the running system, so turning it on asks
// first; turning it off is always allowed and needs no prompt.
settings_toggle_unsafe_kill :: proc() {
	kill_arm_clear()

	if settings.unsafe_kill {
		settings.unsafe_kill = false
		save_settings()
		_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
		return
	}

	if !confirm_unsafe_kill() {
		return
	}
	settings.unsafe_kill = true
	save_settings()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

confirm_unsafe_kill :: proc() -> bool {
	text := "Unsafe mode lets you end blocked tasks.\r\n\r\n" +
		"Blocked tasks include critical and protected system processes. " +
		"Ending them can freeze the desktop, crash Windows, or force a restart.\r\n\r\n" +
		"Turn on unsafe mode?"
	text_buf: [512]u16
	title_buf: [64]u16
	message := win.utf8_to_wstring_buf(text_buf[:], text)
	caption := win.utf8_to_wstring_buf(title_buf[:], "MiniTaskManager")
	if message == nil || caption == nil {
		return false
	}

	// A message box takes the focus away from the drawer, which would otherwise
	// read as "clicked elsewhere" and close it.
	app.modal_open = true
	result := win.MessageBoxW(
		app.hwnd,
		message,
		caption,
		win.MB_YESNO | win.MB_ICONWARNING | win.MB_DEFBUTTON2,
	)
	app.modal_open = false
	return result == win.IDYES
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
		case "risk_show_unknown":
			settings.risk_show[int(Risk_Tier.unknown)] = parse_bool(value)
		case "risk_show_safe":
			settings.risk_show[int(Risk_Tier.safe)] = parse_bool(value)
		case "risk_show_risky":
			settings.risk_show[int(Risk_Tier.risky)] = parse_bool(value)
		case "risk_show_blocked":
			settings.risk_show[int(Risk_Tier.blocked)] = parse_bool(value)
		case "unsafe_kill":
			settings.unsafe_kill = parse_bool(value)
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
	// A hand-edited file hiding every tier would leave an empty list; restore
	// the default (safe only) instead.
	if risk_tiers_visible_count() == 0 {
		settings.risk_show = RISK_SHOW_DEFAULT
	}
	// Version 4 moved the filter to the task panel and defaults to safe only.
	// Files from the earlier settings-page filter start from that default once.
	if version < 4 {
		settings.risk_show = RISK_SHOW_DEFAULT
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
		"version=5\nshow_cpu=%d\nshow_cores=%d\nshow_memory=%d\nshow_disk=%d\nshow_network=%d\nshow_gpu=%d\nshow_uptime=%d\n" +
		"accent=%02X%02X%02X\nmemory_color=%02X%02X%02X\ngpu_color=%02X%02X%02X\ntheme=%d\ncores_per_page=%d\ncores_custom=%d\ncores_custom_mode=%d\nsort_field=%d\nsort_desc=%d\nrefresh_ms=%d\n" +
		"refresh_custom=%d\nrefresh_custom_mode=%d\ndock=%d\n" +
		"risk_show_unknown=%d\nrisk_show_safe=%d\nrisk_show_risky=%d\nrisk_show_blocked=%d\nunsafe_kill=%d\n",
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
		int(settings.risk_show[int(Risk_Tier.unknown)]),
		int(settings.risk_show[int(Risk_Tier.safe)]),
		int(settings.risk_show[int(Risk_Tier.risky)]),
		int(settings.risk_show[int(Risk_Tier.blocked)]),
		int(settings.unsafe_kill),
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

	selected_color := mix_color(theme.bg, accent, 0.16)
	badge_color := mix_color(theme.card, COL_TEXT, 0.04)
	cpu_fill_color := mix_color(theme.card, accent, 0.22)
	mem_fill_color := mix_color(theme.card, mem_color, 0.22)
	gpu_fill_color := mix_color(theme.card, gpu_color, 0.22)

	brush_color_count = 0
	pen_style_count = 0

	app.brushes.bg = win.CreateSolidBrush(colorref(theme.bg))
	register_brush(app.brushes.bg, theme.bg)
	app.brushes.sidebar = win.CreateSolidBrush(colorref(theme.sidebar))
	register_brush(app.brushes.sidebar, theme.sidebar)
	app.brushes.card = win.CreateSolidBrush(colorref(theme.card))
	register_brush(app.brushes.card, theme.card)
	app.brushes.selected = win.CreateSolidBrush(colorref(selected_color))
	register_brush(app.brushes.selected, selected_color)
	app.brushes.badge = win.CreateSolidBrush(colorref(badge_color))
	register_brush(app.brushes.badge, badge_color)
	app.brushes.accent = win.CreateSolidBrush(colorref(accent))
	register_brush(app.brushes.accent, accent)
	app.brushes.track = win.CreateSolidBrush(colorref(theme.line))
	register_brush(app.brushes.track, theme.line)
	app.brushes.thumb = win.CreateSolidBrush(colorref(theme.border))
	register_brush(app.brushes.thumb, theme.border)
	app.brushes.cpu_fill = win.CreateSolidBrush(colorref(cpu_fill_color))
	register_brush(app.brushes.cpu_fill, cpu_fill_color)
	app.brushes.mem_fill = win.CreateSolidBrush(colorref(mem_fill_color))
	register_brush(app.brushes.mem_fill, mem_fill_color)
	app.brushes.gpu_fill = win.CreateSolidBrush(colorref(gpu_fill_color))
	register_brush(app.brushes.gpu_fill, gpu_fill_color)
	app.brushes.line = win.CreateSolidBrush(colorref(theme.line))
	register_brush(app.brushes.line, theme.line)
	app.brushes.dark = win.CreateSolidBrush(colorref(COL_BADGE_TEXT))
	register_brush(app.brushes.dark, COL_BADGE_TEXT)
	app.brushes.light = win.CreateSolidBrush(colorref(COL_TEXT))
	register_brush(app.brushes.light, COL_TEXT)
	app.brushes.muted = win.CreateSolidBrush(colorref(COL_MUTED))
	register_brush(app.brushes.muted, COL_MUTED)
	app.brushes.risk_safe = win.CreateSolidBrush(colorref(COL_RISK_SAFE))
	register_brush(app.brushes.risk_safe, COL_RISK_SAFE)
	app.brushes.risk_risky = win.CreateSolidBrush(colorref(COL_RISK_RISKY))
	register_brush(app.brushes.risk_risky, COL_RISK_RISKY)
	app.brushes.risk_blocked = win.CreateSolidBrush(colorref(COL_RISK_BLOCKED))
	register_brush(app.brushes.risk_blocked, COL_RISK_BLOCKED)
	app.brushes.risk_unknown = win.CreateSolidBrush(colorref(COL_RISK_UNKNOWN))
	register_brush(app.brushes.risk_unknown, COL_RISK_UNKNOWN)

	line_w := max(dip(2), 1)
	app.pens.border = win.CreatePen(win.PS_SOLID, 1, colorref(theme.border))
	register_pen(app.pens.border, theme.border, 1)
	app.pens.cpu = win.CreatePen(win.PS_SOLID, line_w, colorref(accent))
	register_pen(app.pens.cpu, accent, line_w)
	app.pens.mem = win.CreatePen(win.PS_SOLID, line_w, colorref(mem_color))
	register_pen(app.pens.mem, mem_color, line_w)
	app.pens.gpu = win.CreatePen(win.PS_SOLID, line_w, colorref(gpu_color))
	register_pen(app.pens.gpu, gpu_color, line_w)
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
	delete_gdi(app.brushes.risk_safe)
	delete_gdi(app.brushes.risk_risky)
	delete_gdi(app.brushes.risk_blocked)
	delete_gdi(app.brushes.risk_unknown)

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

destroy_backbuffer :: proc() {
	if app.mem_dc != nil {
		_ = win.DeleteDC(app.mem_dc)
		app.mem_dc = nil
	}
	if app.mem_bmp != nil {
		_ = win.DeleteObject(win.HGDIOBJ(app.mem_bmp))
		app.mem_bmp = nil
	}
}

create_font :: proc(face: win.LPCWSTR, size: i32, weight: i32) -> win.HFONT {
	return win.CreateFontW(
		-dip(size), 0, 0, 0, weight,
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
