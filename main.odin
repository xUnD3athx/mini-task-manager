package main

import "base:runtime"
import win "core:sys/windows"

TIMER_ID :: 1
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
	dpi := win.GetDeviceCaps(screen_dc, LOGPIXELSY)
	_ = win.ReleaseDC(nil, screen_dc)
	if dpi <= 0 {
		dpi = 96
	}
	app.scale = f32(dpi) / 96.0
	app.bar_h = dip(BAR_HEIGHT_DIP)
	update_screen_metrics()

	load_settings()

	app.class_brush = win.CreateSolidBrush(colorref(theme_bg()))
	defer _ = win.DeleteObject(win.HGDIOBJ(app.class_brush))

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
		hbrBackground = app.class_brush,
		lpszMenuName  = nil,
		lpszClassName = class_name,
		hIconSm       = small_icon,
	}
	if u16(win.RegisterClassExW(&wc)) == 0 {
		return
	}

	get_core_count()
	refresh_processes()
	update_metrics()

	ex_style := win.WS_EX_TOOLWINDOW | win.WS_EX_TOPMOST
	hwnd := win.CreateWindowExW(
		ex_style,
		class_name,
		window_title,
		win.WS_POPUP,
		0, 0, app.screen_w, app.bar_h,
		nil, nil, hinstance, nil,
	)
	if hwnd == nil {
		return
	}
	app.hwnd = hwnd

	register_appbar(hwnd)
	position_appbar(hwnd)

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
		app.hwnd = hwnd
		init_resources()
		_ = win.SetTimer(hwnd, TIMER_ID, u32(settings.refresh_ms), nil)
		return 0

	case win.WM_SIZE:
		update_client_size(hwnd)
		return 0

	case win.WM_PAINT:
		paint_window(hwnd)
		return 0

	case win.WM_TIMER:
		if wparam == TIMER_ID {
			if !app.pdh_attempted {
				init_pdh_counters()
				app.pdh_attempted = true
			}
			update_metrics()
			if GetTickCount64() - app.last_process_ms >= PROCESS_REFRESH_MS {
				refresh_processes()
			}
			refresh_window_preview()
			_ = win.InvalidateRect(hwnd, nil, win.FALSE)
		}
		return 0

	case win.WM_ERASEBKGND:
		return 1

	case win.WM_MOUSEACTIVATE:
		pt: win.POINT
		_ = win.GetCursorPos(&pt)
		_ = win.ScreenToClient(hwnd, &pt)
		if bar_y := pt.y - bar_top(); bar_y >= 0 && bar_y < app.bar_h &&
		   !point_in_rect(pt.x, bar_y, tasks_button_rect()) &&
		   !point_in_rect(pt.x, bar_y, settings_button_rect()) &&
		   !point_in_rect(pt.x, bar_y, exit_button_rect()) {
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
		if u16(wparam & 0xffff) == win.WA_INACTIVE && app.view != .none &&
		   !app.color_dialog_open && GetTickCount64() >= app.deactivate_guard_until {
			set_view(.none)
		}
		return 0

	case win.WM_CHAR:
		if app.view == .settings && app.refresh_edit {
			handle_refresh_edit_char(int(wparam))
			return 0
		}

	case win.WM_KEYDOWN:
		if int(wparam) == win.VK_ESCAPE {
			if app.refresh_edit {
				cancel_refresh_edit()
				return 0
			}
			if app.view != .none {
				set_view(.none)
				return 0
			}
		}

	case win.WM_DISPLAYCHANGE:
		app.view = .none
		destroy_window_preview()
		update_screen_metrics()
		position_appbar(hwnd)
		return 0

	case win.WM_DESTROY:
		remove_appbar(hwnd)
		_ = win.KillTimer(hwnd, TIMER_ID)
		destroy_window_preview()
		destroy_backbuffer()
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
	app.screen_w = win.GetSystemMetrics(win.SM_CXSCREEN)
	app.screen_h = win.GetSystemMetrics(win.SM_CYSCREEN)

	drawer_h := dip(DRAWER_HEIGHT_DIP)
	max_h := app.screen_h - app.bar_h - dip(40)
	if drawer_h > max_h {
		drawer_h = max_h
	}
	min_h := dip(260)
	if drawer_h < min_h {
		drawer_h = min_h
	}
	app.drawer_h = drawer_h
}

register_appbar :: proc(hwnd: win.HWND) {
	abd: win.APPBARDATA
	abd.cbSize = u32(size_of(win.APPBARDATA))
	abd.hWnd = hwnd
	abd.uCallbackMessage = BAR_CALLBACK_MSG
	if win.SHAppBarMessage(win.ABM_NEW, &abd) != 0 {
		app.appbar_registered = true
	}
}

remove_appbar :: proc(hwnd: win.HWND) {
	if !app.appbar_registered {
		return
	}
	abd: win.APPBARDATA
	abd.cbSize = u32(size_of(win.APPBARDATA))
	abd.hWnd = hwnd
	_ = win.SHAppBarMessage(win.ABM_REMOVE, &abd)
	app.appbar_registered = false
}

drawer_room :: proc() -> i32 {
	if settings.dock == .bottom {
		return app.bar_rect.top
	}
	return app.screen_h - app.bar_rect.top
}

apply_window_rect :: proc() {
	if app.hwnd == nil {
		return
	}

	height := app.bar_h
	if app.view != .none {
		height += app.drawer_h
		room := drawer_room()
		if height > room {
			height = room
		}
	}
	if height < app.bar_h {
		height = app.bar_h
	}

	y := app.bar_rect.top
	if settings.dock == .bottom {
		y = app.bar_rect.bottom - height
	}

	_ = win.SetWindowPos(
		app.hwnd,
		win.HWND_TOPMOST,
		app.bar_rect.left,
		y,
		app.bar_rect.right - app.bar_rect.left,
		height,
		win.SWP_NOACTIVATE,
	)
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

position_appbar :: proc(hwnd: win.HWND) {
	if app.appbar_moving {
		return
	}
	app.appbar_moving = true
	defer app.appbar_moving = false

	abd: win.APPBARDATA
	abd.cbSize = u32(size_of(win.APPBARDATA))
	abd.hWnd = hwnd

	if settings.dock == .bottom {
		abd.uEdge = win.ABE_BOTTOM
		abd.rc = win.RECT{0, app.screen_h - app.bar_h, app.screen_w, app.screen_h}
	} else {
		abd.uEdge = win.ABE_TOP
		abd.rc = win.RECT{0, 0, app.screen_w, app.bar_h}
	}

	if app.appbar_registered {
		_ = win.SHAppBarMessage(win.ABM_QUERYPOS, &abd)
		if settings.dock == .bottom {
			abd.rc.top = abd.rc.bottom - app.bar_h
		} else {
			abd.rc.bottom = abd.rc.top + app.bar_h
		}
		_ = win.SHAppBarMessage(win.ABM_SETPOS, &abd)
	}

	if abd.rc.right <= abd.rc.left || abd.rc.bottom <= abd.rc.top {
		if settings.dock == .bottom {
			abd.rc = win.RECT{0, app.screen_h - app.bar_h, app.screen_w, app.screen_h}
		} else {
			abd.rc = win.RECT{0, 0, app.screen_w, app.bar_h}
		}
	}
	app.bar_rect = abd.rc

	apply_window_rect()
}

set_view :: proc(view: Drawer_View) {
	if app.view == view {
		return
	}
	app.view = view
	app.refresh_edit = false

	apply_window_rect()
	refresh_window_preview()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}

toggle_view :: proc(view: Drawer_View) {
	if app.view == view {
		set_view(.none)
		return
	}
	_ = win.SetForegroundWindow(app.hwnd)
	set_view(view)
}

update_client_size :: proc(hwnd: win.HWND) {
	rect: win.RECT
	_ = win.GetClientRect(hwnd, &rect)
	app.width = rect.right - rect.left
	app.height = rect.bottom - rect.top
	clamp_scroll()
	resize_backbuffer()
	_ = win.InvalidateRect(hwnd, nil, win.FALSE)
}

paint_window :: proc(hwnd: win.HWND) {
	ps: win.PAINTSTRUCT
	hdc := win.BeginPaint(hwnd, &ps)
	defer _ = win.EndPaint(hwnd, &ps)

	if app.width <= 0 || app.height <= 0 {
		return
	}
	if app.mem_dc == nil {
		resize_backbuffer()
	}
	if app.mem_dc == nil {
		return
	}

	paint(app.mem_dc)
	_ = win.BitBlt(hdc, 0, 0, app.width, app.height, app.mem_dc, 0, 0, win.SRCCOPY)
}

resize_backbuffer :: proc() {
	destroy_backbuffer()
	if app.width <= 0 || app.height <= 0 {
		return
	}

	screen := win.GetDC(app.hwnd)
	if screen == nil {
		return
	}
	dc := win.CreateCompatibleDC(screen)
	bmp := win.CreateCompatibleBitmap(screen, app.width, app.height)
	_ = win.ReleaseDC(app.hwnd, screen)

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
	app.mem_dc = dc
	app.mem_bmp = bmp
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
