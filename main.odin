package main

import "base:runtime"
import win "core:sys/windows"
import "core"
import "services"
import "ui"
import "platform"

APP_ICON_ID :: 1

BAR_CALLBACK_MSG :: 0x8000 + 2
MA_ACTIVATE      :: 1
MA_NOACTIVATE    :: 3

load_app_icon :: proc(hinstance: win.HINSTANCE, cx, cy: i32) -> win.HICON {
	name := win.LPCWSTR(win.MAKEINTRESOURCEW(APP_ICON_ID))
	handle := win.LoadImageW(
		hinstance,
		name,
		win.IMAGE_ICON,
		cx,
		cy,
		win.LR_DEFAULTCOLOR | win.LR_SHARED,
	)
	return win.HICON(handle)
}

main :: proc() {
	_ = win.SetProcessDPIAware()

	screen_dc := win.GetDC(nil)
	dpi := win.GetDeviceCaps(screen_dc, core.LOGPIXELSY)
	_ = win.ReleaseDC(nil, screen_dc)
	if dpi <= 0 {
		dpi = 96
	}
	core.app.scale = f32(dpi) / 96.0
	core.app.bar_h = core.dip(core.BAR_HEIGHT_DIP)
	core.app.standalone_w = core.dip(core.STANDALONE_WIDTH_DIP)
	core.app.standalone_h = core.dip(core.STANDALONE_HEIGHT_DIP)
	update_screen_metrics()

	core.load_settings()

	startup: platform.Gdiplus_Startup_Input
	startup.version = 1
	if platform.GdiplusStartup(&core.app.gdiplus_token, &startup, nil) != 0 {
		core.app.gdiplus_token = 0
	}

	core.app.class_brush = win.CreateSolidBrush(core.colorref(core.theme_bg()))
	defer _ = win.DeleteObject(win.HGDIOBJ(core.app.class_brush))

hinstance := win.HINSTANCE(win.GetModuleHandleW(nil))
	class_name := win.utf8_to_wstring_alloc("MiniTaskManagerBar")
	window_title := win.utf8_to_wstring_alloc("mini-task-manager")

	large_icon := load_app_icon(hinstance, 0, 0)
	small_icon := load_app_icon(
		hinstance,
		win.GetSystemMetrics(win.SM_CXSMICON),
		win.GetSystemMetrics(win.SM_CYSMICON),
	)

	wc := win.WNDCLASSEXW {
		cbSize        = u32(size_of(win.WNDCLASSEXW)),
		style         = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_DROPSHADOW,
		lpfnWndProc   = win.WNDPROC(window_proc),
		hInstance     = hinstance,
		hIcon         = large_icon,
		hCursor       = win.LoadCursorA(nil, win.IDC_ARROW),
		hbrBackground = core.app.class_brush,
		lpszMenuName  = nil,
		lpszClassName = class_name,
		hIconSm       = small_icon,
	}
	if u16(win.RegisterClassExW(&wc)) == 0 {
		return
	}

	services.get_core_count()
	services.refresh_processes()
	services.update_metrics()

	ex_style := win.WS_EX_TOOLWINDOW | win.WS_EX_TOPMOST
	start_w := core.app.screen_w
	if core.settings.dock == .standalone {
		start_w = core.app.standalone_w
	}
	hwnd := win.CreateWindowExW(
		ex_style,
		class_name,
		window_title,
		win.WS_POPUP,
		0, 0, start_w, core.app.bar_h,
		nil, nil, hinstance, nil,
	)
	if hwnd == nil {
		return
	}
	core.app.hwnd = hwnd

	if core.settings.dock == .top {
		register_appbar(hwnd)
		position_appbar(hwnd)
	} else {
		enter_standalone(hwnd)
	}

	_ = win.ShowWindow(hwnd, win.SW_SHOWNOACTIVATE)
	_ = win.UpdateWindow(hwnd)

	msg: win.MSG
	for {
		ret := win.GetMessageW(&msg, nil, 0, 0)
		if ret <= 0 {
			break
		}
		_ = win.TranslateMessage(&msg)
		_ = win.DispatchMessageW(&msg)
	}
}

window_proc :: proc "system" (
	hwnd: win.HWND,
	msg: win.UINT,
	wparam: win.WPARAM,
	lparam: win.LPARAM,
) -> win.LRESULT {
	context = runtime.default_context()

	if msg == BAR_CALLBACK_MSG {
		notification := u16(lparam & 0xffff)
		if notification == win.ABN_POSCHANGED {
			position_appbar(hwnd)
		}
		return 0
	}

	switch msg {
	case win.WM_CREATE:
		core.app.hwnd = hwnd
		core.init_resources()
		_ = win.SetTimer(hwnd, core.TIMER_ID, u32(core.settings.refresh_ms), nil)
		return 0

	case win.WM_SIZE:
		update_client_size(hwnd)
		return 0

	case win.WM_MOVE:
		if core.settings.dock == .standalone {
			update_standalone_rect(hwnd)
		}
		return 0

	case win.WM_GETMINMAXINFO:
		if core.settings.dock == .standalone {
			apply_standalone_limits(cast(^win.MINMAXINFO)(uintptr(lparam)))
			return 0
		}

	case win.WM_NCHITTEST:
		return standalone_hit_test(hwnd, lparam)

	case win.WM_PAINT:
		paint_window(hwnd)
		return 0

	case win.WM_TIMER:
		if wparam == core.ANIM_TIMER_ID {
			step_drawer_anim()
			return 0
		}
		if wparam == core.TIMER_ID {
			if !core.app.pdh_attempted {
				services.init_pdh_counters()
				core.app.pdh_attempted = true
			}
			services.update_metrics()
			if platform.GetTickCount64() - core.app.last_process_ms >= core.PROCESS_REFRESH_MS {
				services.refresh_processes()
				ui.clamp_scroll()
			}
			services.refresh_window_preview()
			_ = win.InvalidateRect(hwnd, nil, win.FALSE)
		}
		return 0

	case win.WM_ERASEBKGND:
		return 1

	case win.WM_MOUSEACTIVATE:
		if core.app.anim.active {
			return MA_ACTIVATE
		}
		pt: win.POINT
		_ = win.GetCursorPos(&pt)
		_ = win.ScreenToClient(hwnd, &pt)
		if pt.y >= 0 && pt.y < core.app.bar_h &&
		   !core.point_in_rect(pt.x, pt.y, ui.tasks_button_rect()) &&
		   !core.point_in_rect(pt.x, pt.y, ui.settings_button_rect()) &&
		   !core.point_in_rect(pt.x, pt.y, ui.exit_button_rect()) {
			return MA_NOACTIVATE
		}
		return MA_ACTIVATE

	case win.WM_LBUTTONDOWN:
		handle_click(lparam)
		return 0

	case win.WM_MOUSEWHEEL:
		handle_wheel(wparam)
		return 0

	case win.WM_ACTIVATE:
		if u16(wparam & 0xffff) == win.WA_INACTIVE && core.app.view != .none &&
		   !core.app.color_dialog_open && platform.GetTickCount64() >= core.app.deactivate_guard_until {
			close_view()
		}
		return 0

	case win.WM_CHAR:
		if core.app.view == .settings && core.app.refresh_edit {
			handle_refresh_edit_char(int(wparam))
			return 0
		}

	case win.WM_KEYDOWN:
		if int(wparam) == win.VK_ESCAPE {
			if core.app.refresh_edit {
				core.cancel_refresh_edit()
				return 0
			}
			if core.app.view != .none {
				close_view()
				return 0
			}
		}

	case win.WM_DISPLAYCHANGE:
		hide_view_now()
		services.destroy_window_preview()
		update_screen_metrics()
		if core.settings.dock == .top {
			position_appbar(hwnd)
		} else {
			enter_standalone(hwnd)
		}
		return 0

	case win.WM_DESTROY:
		remove_appbar(hwnd)
		_ = win.KillTimer(hwnd, core.TIMER_ID)
		_ = win.KillTimer(hwnd, core.ANIM_TIMER_ID)
		services.destroy_window_preview()
		core.destroy_backbuffer()
		destroy_resources()
		win.PostQuitMessage(0)
		return 0

	case win.WM_CLOSE:
		win.DestroyWindow(hwnd)
		return 0
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

update_screen_metrics :: proc() {
	core.app.screen_w = win.GetSystemMetrics(win.SM_CXSCREEN)
	core.app.screen_h = win.GetSystemMetrics(win.SM_CYSCREEN)

	drawer_h := core.dip(core.DRAWER_HEIGHT_DIP)
	max_h := core.app.screen_h - core.app.bar_h - core.dip(40)
	if drawer_h > max_h {
		drawer_h = max_h
	}
	min_h := core.dip(260)
	if drawer_h < min_h {
		drawer_h = min_h
	}
	core.app.drawer_h = drawer_h
}

register_appbar :: proc(hwnd: win.HWND) {
	abd: win.APPBARDATA
	abd.cbSize = u32(size_of(win.APPBARDATA))
	abd.hWnd = hwnd
	abd.uCallbackMessage = BAR_CALLBACK_MSG
	if win.SHAppBarMessage(win.ABM_NEW, &abd) != 0 {
		core.app.appbar_registered = true
	}
}

remove_appbar :: proc(hwnd: win.HWND) {
	if !core.app.appbar_registered {
		return
	}
	abd: win.APPBARDATA
	abd.cbSize = u32(size_of(win.APPBARDATA))
	abd.hWnd = hwnd
	_ = win.SHAppBarMessage(win.ABM_REMOVE, &abd)
	core.app.appbar_registered = false
}

// Room below the bar. A standalone window dragged down leaves less of it.
drawer_room :: proc() -> i32 {
	return core.app.screen_h - core.app.bar_rect.top
}

// Full height of the open drawer: the appbar adds the drawer to the bar, a
// standalone window is already the drawer.
drawer_open_height :: proc() -> i32 {
	if core.settings.dock == .standalone {
		return core.app.standalone_h
	}
	height := core.app.bar_h + core.app.drawer_h
	room := drawer_room()
	if height > room {
		height = room
	}
	if height < core.app.bar_h {
		height = core.app.bar_h
	}
	return height
}

set_window_height :: proc(height: i32) {
	if core.app.hwnd == nil || height <= 0 {
		return
	}
	_ = win.SetWindowPos(
		core.app.hwnd,
		win.HWND_TOPMOST,
		core.app.bar_rect.left,
		core.app.bar_rect.top,
		core.app.bar_rect.right - core.app.bar_rect.left,
		height,
		win.SWP_NOACTIVATE,
	)
}

// A mode switch can change the open height, so the layout is refitted to the
// new window rect instead of holding a stale frame.
apply_window_rect :: proc() {
	if core.app.hwnd == nil {
		return
	}

	height := core.app.bar_h
	if core.app.view != .none {
		height = drawer_open_height()
	}
	set_window_height(height)
	if !core.app.anim.active {
		core.app.layout_h = height
		resize_backbuffer()
	}
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

position_appbar :: proc(hwnd: win.HWND) {
	if core.settings.dock != .top {
		return
	}
	if core.app.appbar_moving {
		return
	}
	core.app.appbar_moving = true
	defer core.app.appbar_moving = false

	abd: win.APPBARDATA
	abd.cbSize = u32(size_of(win.APPBARDATA))
	abd.hWnd = hwnd
	abd.uEdge = win.ABE_TOP
	abd.rc = win.RECT{0, 0, core.app.screen_w, core.app.bar_h}

	if core.app.appbar_registered {
		_ = win.SHAppBarMessage(win.ABM_QUERYPOS, &abd)
		abd.rc.bottom = abd.rc.top + core.app.bar_h
		_ = win.SHAppBarMessage(win.ABM_SETPOS, &abd)
	}

	if abd.rc.right <= abd.rc.left || abd.rc.bottom <= abd.rc.top {
		abd.rc = win.RECT{0, 0, core.app.screen_w, core.app.bar_h}
	}
	core.app.bar_rect = abd.rc

	apply_window_rect()
}

// Leaves the appbar and restores the last standalone position and size. The
// width spans the window, not the display, so the bar reflows on its own.
enter_standalone :: proc(hwnd: win.HWND) {
	remove_appbar(hwnd)
	x := i32(0)
	w := clamp(core.app.standalone_w, core.dip(core.STANDALONE_MIN_WIDTH_DIP), core.app.screen_w)
	h := clamp(core.app.standalone_h, core.dip(core.STANDALONE_MIN_HEIGHT_DIP), core.app.screen_h)
	// An open drawer has to fit on screen, so the bar moves up instead of the
	// remembered height being cut down.
	room := core.app.bar_h
	if core.app.view != .none {
		room = h
	}
	y := clamp(core.app.standalone_pos.y, 0, max(core.app.screen_h - room, 0))
	core.app.standalone_pos = win.POINT{x = x, y = y}
	core.app.standalone_w = w
	core.app.standalone_h = h
	core.app.drawer_h = h - core.app.bar_h
	core.app.bar_rect = win.RECT{x, y, x + w, y + core.app.bar_h}
	apply_window_rect()
}

// Dragging moves the window itself, so the bar rect follows it.
update_standalone_rect :: proc(hwnd: win.HWND) {
	rect: win.RECT
	if !win.GetWindowRect(hwnd, &rect) {
		return
	}
	core.app.bar_rect = win.RECT{rect.left, rect.top, rect.right, rect.top + core.app.bar_h}
	core.app.standalone_pos = win.POINT{x = rect.left, y = rect.top}
}

// The closed window is only the bar, so its height is locked; an open one may
// shrink until the drawer gets too cramped.
apply_standalone_limits :: proc(mmi: ^win.MINMAXINFO) {
	min_w := core.dip(core.STANDALONE_MIN_WIDTH_DIP)
	if core.app.view == .none {
		mmi.ptMinTrackSize = win.POINT{x = min_w, y = core.app.bar_h}
		mmi.ptMaxTrackSize = win.POINT{x = core.app.screen_w, y = core.app.bar_h}
		return
	}
	mmi.ptMinTrackSize = win.POINT{x = min_w, y = core.dip(core.STANDALONE_MIN_HEIGHT_DIP)}
	mmi.ptMaxTrackSize = win.POINT{x = core.app.screen_w, y = core.app.screen_h}
}

// Borderless windows have no resize frame, so the edges are offered here.
// The top edge stays with the bar, which drags the window.
standalone_hit_test :: proc(hwnd: win.HWND, lparam: win.LPARAM) -> win.LRESULT {
	if core.settings.dock != .standalone || core.app.anim.active {
		return win.HTCLIENT
	}

	// Non-client hit tests arrive in screen coordinates.
	pt := win.POINT {
		x = i32(i16(u16(lparam & 0xffff))),
		y = i32(i16(u16((lparam >> 16) & 0xffff))),
	}
	_ = win.ScreenToClient(hwnd, &pt)
	rect: win.RECT
	_ = win.GetClientRect(hwnd, &rect)

	border := core.dip(5)
	left := pt.x < border
	right := pt.x >= rect.right - border
	bottom := pt.y >= rect.bottom - border
	switch {
	case bottom && left:
		return win.HTBOTTOMLEFT
	case bottom && right:
		return win.HTBOTTOMRIGHT
	case bottom:
		return win.HTBOTTOM
	case left:
		return win.HTLEFT
	case right:
		return win.HTRIGHT
	}
	return win.HTCLIENT
}

open_view :: proc(view: core.Drawer_View) {
	if core.app.view != view {
		core.app.view = view
		core.app.refresh_edit = false
		core.app.settings_scroll = 0
		core.app.layout_h = drawer_open_height()
		resize_backbuffer()
	}
	if core.settings.dock == .standalone {
		lift_standalone_open()
	}
	start_drawer_anim(true)
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

// A bar dragged near the bottom of the screen would open the drawer past the
// edge, so the window moves up until the whole drawer fits.
lift_standalone_open :: proc() {
	if core.app.hwnd == nil {
		return
	}
	height := drawer_open_height()
	max_y := max(core.app.screen_h - height, 0)
	if core.app.bar_rect.top <= max_y {
		return
	}
	core.app.bar_rect.top = max_y
	core.app.standalone_pos.y = max_y
	_ = win.SetWindowPos(
		core.app.hwnd,
		win.HWND_TOPMOST,
		core.app.bar_rect.left,
		max_y,
		core.app.bar_rect.right - core.app.bar_rect.left,
		core.app.height,
		win.SWP_NOACTIVATE,
	)
}

close_view :: proc() {
	if core.app.view == .none && !core.app.anim.active {
		return
	}
	// The preview is a separate top-level window, so it must not linger over
	// the drawer while it shrinks.
	services.destroy_window_preview()
	start_drawer_anim(false)
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

hide_view_now :: proc() {
	core.app.anim.active = false
	core.app.anim.frozen = false
	_ = win.KillTimer(core.app.hwnd, core.ANIM_TIMER_ID)
	core.app.view = .none
	core.app.layout_h = core.app.bar_h
}

toggle_view :: proc(view: core.Drawer_View) {
	// A click during the closing animation reopens instead of doing nothing.
	closing := core.app.anim.active && !core.app.anim.opening
	if core.app.view == view && !closing {
		close_view()
		return
	}
	_ = win.SetForegroundWindow(core.app.hwnd)
	open_view(view)
}

// Height moves along an ease-out curve: fast at first, settling at the end.
start_drawer_anim :: proc(opening: bool) {
	anim := &core.app.anim
	target := opening ? core.app.layout_h : core.app.bar_h
	anim.active = true
	anim.opening = opening
	anim.from_h = core.app.height
	anim.to_h = target

	// Render the full frame once, so the steps only copy a slice of it. Doing
	// this before the clock starts keeps the first frame from swallowing most
	// of the animation.
	if anim.from_h == target {
		finish_drawer_anim()
		return
	}
	if core.app.mem_dc != nil {
		ui.paint(core.app.mem_dc)
		anim.frozen = true
	} else {
		anim.frozen = false
	}
	anim.start_ms = platform.GetTickCount64()
	_ = win.SetTimer(core.app.hwnd, core.ANIM_TIMER_ID, 15, nil)
}

step_drawer_anim :: proc() {
	anim := &core.app.anim
	if !anim.active {
		_ = win.KillTimer(core.app.hwnd, core.ANIM_TIMER_ID)
		return
	}

	elapsed := platform.GetTickCount64() - anim.start_ms
	t := min(f32(elapsed) / f32(core.DRAWER_ANIM_MS), 1.0)
	eased := 1.0 - (1.0 - t)*(1.0 - t)*(1.0 - t)
	height := anim.from_h + i32(f32(anim.to_h - anim.from_h) * eased)
	if height != core.app.height {
		set_window_height(height)
		// Paint synchronously so a shrinking window never shows the desktop
		// through the part that has not been blitted yet.
		_ = win.UpdateWindow(core.app.hwnd)
	}
	if t >= 1.0 {
		finish_drawer_anim()
	}
}

finish_drawer_anim :: proc() {
	anim := &core.app.anim
	opening := anim.opening
	anim.active = false
	anim.frozen = false
	_ = win.KillTimer(core.app.hwnd, core.ANIM_TIMER_ID)

	if opening {
		services.refresh_window_preview()
	} else {
		core.app.view = .none
		core.app.layout_h = core.app.bar_h
		apply_window_rect()
		resize_backbuffer()
		services.refresh_window_preview()
	}
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

update_client_size :: proc(hwnd: win.HWND) {
	rect: win.RECT
	_ = win.GetClientRect(hwnd, &rect)
	core.app.width = rect.right - rect.left
	core.app.height = rect.bottom - rect.top
	if core.app.layout_h <= 0 {
		core.app.layout_h = core.app.height
	}
	adopt_standalone_size(hwnd)
	ui.clamp_scroll()
	ui.clamp_settings_scroll()
	// While the drawer animates, the window is shorter than the layout; the
	// backbuffer already has the full size.
	if core.app.layout_h == core.app.height && !core.app.anim.active {
		resize_backbuffer()
	}
	_ = win.InvalidateRect(hwnd, nil, win.FALSE)
}

// A standalone window owns its size: resizing it while the drawer is open is
// how the drawer gets a new height, and the bar keeps the new width.
adopt_standalone_size :: proc(hwnd: win.HWND) {
	if core.settings.dock != .standalone {
		return
	}
	update_standalone_rect(hwnd)
	core.app.standalone_w = core.app.width
	if core.app.anim.active || core.app.view == .none {
		return
	}
	core.app.standalone_h = core.app.height
	core.app.drawer_h = max(core.app.height - core.app.bar_h, 0)
	core.app.layout_h = core.app.height
}

paint_window :: proc(hwnd: win.HWND) {
	ps: win.PAINTSTRUCT
	hdc := win.BeginPaint(hwnd, &ps)
	defer _ = win.EndPaint(hwnd, &ps)

	if core.app.width <= 0 || core.app.layout_h <= 0 {
		return
	}
	if core.app.mem_dc == nil {
		resize_backbuffer()
	}
	if core.app.mem_dc == nil {
		return
	}

	if !(core.app.anim.active && core.app.anim.frozen) {
		ui.paint(core.app.mem_dc)
	}

	// The bar is anchored to the top of the layout, so the window shows the
	// matching top slice while the drawer animates.
	client_h := min(core.app.height, core.app.layout_h)
	if client_h <= 0 {
		return
	}
	_ = win.BitBlt(hdc, 0, 0, core.app.width, client_h, core.app.mem_dc, 0, 0, win.SRCCOPY)
}

resize_backbuffer :: proc() {
	core.destroy_backbuffer()
	if core.app.width <= 0 || core.app.layout_h <= 0 {
		return
	}

	screen := win.GetDC(core.app.hwnd)
	if screen == nil {
		return
	}
	dc := win.CreateCompatibleDC(screen)
	bmp := win.CreateCompatibleBitmap(screen, core.app.width, core.app.layout_h)
	_ = win.ReleaseDC(core.app.hwnd, screen)

	if dc == nil || bmp == nil {
		if dc != nil {
			_ = win.DeleteDC(dc)
		}
		if bmp != nil {
			_ = win.DeleteObject(win.HGDIOBJ(bmp))
		}
		return
	}

	_ = win.SelectObject(dc, win.HGDIOBJ(bmp))
	core.app.mem_dc = dc
	core.app.mem_bmp = bmp
}

// destroy_resources releases GDI, PDH and icon-cache handles at shutdown.
destroy_resources :: proc() {
	services.destroy_icon_cache()

	if core.app.pdh_query != nil {
		_ = platform.PdhCloseQuery(core.app.pdh_query)
		core.app.pdh_query = nil
		core.app.pdh_read = nil
		core.app.pdh_write = nil
		core.app.gpu_counter = nil
		core.app.gpu_mem_counter = nil
	}

	core.delete_gdi(core.app.fonts.title)
	core.delete_gdi(core.app.fonts.heading)
	core.delete_gdi(core.app.fonts.huge)
	core.delete_gdi(core.app.fonts.med)
	core.delete_gdi(core.app.fonts.stat)
	core.delete_gdi(core.app.fonts.body)
	core.delete_gdi(core.app.fonts.small)
	core.delete_gdi(core.app.fonts.tiny)
	core.delete_gdi(core.app.fonts.badge)

	core.delete_visual_objects()

	if core.app.gdiplus_token != 0 {
		platform.GdiplusShutdown(core.app.gdiplus_token)
		core.app.gdiplus_token = 0
	}
}
