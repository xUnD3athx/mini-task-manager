package main

import "base:runtime"
import win "core:sys/windows"

// Minimum size a window needs to be worth previewing; splash screens and
// tooltips aren't useful task previews.
PREVIEW_MIN_WINDOW_W :: 120
PREVIEW_MIN_WINDOW_H :: 80

Window_Preview :: struct {
	hwnd:      win.HWND,
	thumbnail: win.HANDLE,
	src_w:     i32,
	src_h:     i32,
	title:     [128]u16,
	visible:   bool,
}

Main_Window_Find :: struct {
	pids:      [MAX_PROCESSES]u32,
	pid_count: int,
	best:      win.HWND,
	best_area: i64,
}

pid_in_find :: proc(find: ^Main_Window_Find, pid: u32) -> bool {
	for i in 0..<find.pid_count {
		if find.pids[i] == pid {
			return true
		}
	}
	return false
}

window_class_is_shell :: proc(hwnd: win.HWND) -> bool {
	buf: [64]u16
	n := win.GetClassNameW(hwnd, raw_data(buf[:]), i32(len(buf)))
	if n <= 0 {
		return false
	}
	name := win.wstring(raw_data(buf[:]))
	if name == "Progman" || name == "WorkerW" || name == "Shell_TrayWnd" {
		return true
	}
	return false
}

find_main_window_callback :: proc "system" (hwnd: win.HWND, lparam: win.LPARAM) -> win.BOOL {
	context = runtime.default_context()
	find := cast(^Main_Window_Find)uintptr(lparam)

	pid: u32
	_ = win.GetWindowThreadProcessId(hwnd, &pid)
	if !pid_in_find(find, pid) {
		return win.TRUE
	}
	if win.IsWindowVisible(hwnd) == win.FALSE {
		return win.TRUE
	}
	if u32(win.GetWindowLongW(hwnd, win.GWL_EXSTYLE)) & win.WS_EX_TOOLWINDOW != 0 {
		return win.TRUE
	}
	if window_class_is_shell(hwnd) {
		return win.TRUE
	}
	// Windows that DWM is not composing (UWP apps suspended in the background)
	// would only produce an empty thumbnail.
	cloaked: win.DWORD
	if win.DwmGetWindowAttribute(
		hwnd,
		u32(win.DWMWINDOWATTRIBUTE.DWMWA_CLOAKED),
		rawptr(&cloaked),
		u32(size_of(cloaked)),
	) == 0 && cloaked != 0 {
		return win.TRUE
	}

	rect: win.RECT
	if win.GetWindowRect(hwnd, &rect) == win.FALSE {
		return win.TRUE
	}
	w := rect.right - rect.left
	h := rect.bottom - rect.top
	if w < dip(PREVIEW_MIN_WINDOW_W) || h < dip(PREVIEW_MIN_WINDOW_H) {
		return win.TRUE
	}

	// Prefer a restored window when the process also has minimised ones.
	area := i64(w) * i64(h)
	if win.IsIconic(hwnd) == win.FALSE {
		area *= 4
	}
	if area > find.best_area {
		find.best_area = area
		find.best = hwnd
	}
	return win.TRUE
}

find_window_for_pids :: proc(pids: []u32) -> win.HWND {
	if len(pids) == 0 {
		return nil
	}
	find := Main_Window_Find{}
	find.pid_count = min(len(pids), len(find.pids))
	for i in 0..<find.pid_count {
		find.pids[i] = pids[i]
	}
	_ = win.EnumWindows(find_main_window_callback, win.LPARAM(uintptr(&find)))
	return find.best
}

find_main_window :: proc(pid: u32) -> win.HWND {
	if pid == 0 {
		return nil
	}
	pids: [1]u32 = {pid}
	return find_window_for_pids(pids[:])
}

// The window shown for an application is the largest one owned by any of its
// processes, so renderer/helper tasks don't hide the main window.
find_group_window :: proc(name: [MAX_NAME_U16]u16) -> win.HWND {
	pids: [MAX_PROCESSES]u32
	count := 0
	for i in 0..<app.process_count {
		if count >= len(pids) {
			break
		}
		if same_task_name(app.processes[i].name, name) {
			pids[count] = app.processes[i].pid
			count += 1
		}
	}
	return find_window_for_pids(pids[:count])
}

refresh_window_preview :: proc() {
	wanted := app.view == .tasks && app.has_selection

	hwnd: win.HWND = nil
	if wanted {
		if app.group_selected {
			hwnd = find_group_window(app.selected_group)
		} else {
			hwnd = find_main_window(app.selected_pid)
		}
	}

	if hwnd != nil && hwnd == app.preview.hwnd && app.preview.thumbnail != nil {
		update_preview_source_rect()
		return
	}

	destroy_window_preview()
	if hwnd == nil {
		return
	}
	if DwmRegisterThumbnail(app.hwnd, hwnd, &app.preview.thumbnail) != 0 {
		app.preview.thumbnail = nil
		return
	}
	app.preview.hwnd = hwnd
	app.preview.title = {}
	_ = win.GetWindowTextW(hwnd, raw_data(app.preview.title[:]), i32(len(app.preview.title)))
	update_preview_source_rect()
}

destroy_window_preview :: proc() {
	if app.preview.thumbnail != nil {
		_ = DwmUnregisterThumbnail(app.preview.thumbnail)
	}
	app.preview = {}
}

update_preview_source_rect :: proc() {
	if app.preview.hwnd == nil {
		return
	}
	rect: win.RECT
	if win.GetWindowRect(app.preview.hwnd, &rect) == win.FALSE {
		return
	}
	app.preview.src_w = rect.right - rect.left
	app.preview.src_h = rect.bottom - rect.top
}

preview_is_alive :: proc() -> bool {
	if app.preview.thumbnail == nil || app.preview.hwnd == nil {
		return false
	}
	if win.IsWindow(app.preview.hwnd) == win.FALSE {
		destroy_window_preview()
		return false
	}
	return true
}

// draw_preview_thumbnail lets DWM composite the selected window into `bounds`.
// The letterboxed destination rect is recomputed every paint so the preview
// follows layout changes without us capturing anything ourselves.
draw_preview_thumbnail :: proc(bounds: win.RECT) {
	if !preview_is_alive() {
		return
	}
	if app.preview.src_w <= 0 || app.preview.src_h <= 0 {
		update_preview_source_rect()
	}
	if app.preview.src_w <= 0 || app.preview.src_h <= 0 {
		return
	}

	w := bounds.right - bounds.left
	h := bounds.bottom - bounds.top
	if w <= 0 || h <= 0 {
		return
	}

	scale := min(f32(w) / f32(app.preview.src_w), f32(h) / f32(app.preview.src_h))
	dw := i32(f32(app.preview.src_w) * scale)
	dh := i32(f32(app.preview.src_h) * scale)
	dest := win.RECT {
		left   = bounds.left + (w - dw) / 2,
		top    = bounds.top + (h - dh) / 2,
		right  = bounds.left + (w - dw) / 2 + dw,
		bottom = bounds.top + (h - dh) / 2 + dh,
	}

	props := Dwm_Thumbnail_Properties {
		dw_flags       = DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE | DWM_TNP_OPACITY,
		rc_destination = dest,
		opacity        = 255,
		visible        = win.TRUE,
	}
	if DwmUpdateThumbnailProperties(app.preview.thumbnail, &props) == 0 {
		app.preview.visible = true
	}
}

hide_preview_thumbnail :: proc() {
	if app.preview.thumbnail == nil {
		app.preview.visible = false
		return
	}
	if !app.preview.visible {
		return
	}
	props := Dwm_Thumbnail_Properties {
		dw_flags = DWM_TNP_VISIBLE,
		visible  = win.FALSE,
	}
	_ = DwmUpdateThumbnailProperties(app.preview.thumbnail, &props)
	app.preview.visible = false
}
