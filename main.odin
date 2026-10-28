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
	hwnd := win.CreateWindowExW(
		ex_style,
		class_name,
		window_title,
		win.WS_POPUP,
		0, 0, core.app.screen_w, core.app.bar_h,
		nil, nil, hinstance, nil,
	)
	if hwnd == nil {
		return
	}
	core.app.hwnd = hwnd

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
		core.app.hwnd = hwnd
		core.init_resources()
		_ = win.SetTimer(hwnd, core.TIMER_ID, u32(core.settings.refresh_ms), nil)
		return 0

	case win.WM_SIZE:
		update_client_size(hwnd)
		return 0

	case win.WM_PAINT:
		paint_window(hwnd)
		return 0

	case win.WM_TIMER:
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
		pt: win.POINT
		_ = win.GetCursorPos(&pt)
		_ = win.ScreenToClient(hwnd, &pt)
		if bar_y := pt.y - ui.bar_top(); bar_y >= 0 && bar_y < core.app.bar_h &&
		   !core.point_in_rect(pt.x, bar_y, ui.tasks_button_rect()) &&
		   !core.point_in_rect(pt.x, bar_y, ui.settings_button_rect()) &&
		   !core.point_in_rect(pt.x, bar_y, ui.exit_button_rect()) {
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
			set_view(.none)
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
				set_view(.none)
				return 0
			}
		}

	case win.WM_DISPLAYCHANGE:
		core.app.view = .none
		services.destroy_window_preview()
		update_screen_metrics()
		position_appbar(hwnd)
		return 0

	case win.WM_DESTROY:
		remove_appbar(hwnd)
		_ = win.KillTimer(hwnd, core.TIMER_ID)
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

drawer_room :: proc() -> i32 {
	if core.settings.dock == .bottom {
		return core.app.bar_rect.top
	}
	return core.app.screen_h - core.app.bar_rect.top
}

apply_window_rect :: proc() {
	if core.app.hwnd == nil {
		return
	}

	height := core.app.bar_h
	if core.app.view != .none {
		height += core.app.drawer_h
		room := drawer_room()
		if height > room {
			height = room
		}
	}
	if height < core.app.bar_h {
		height = core.app.bar_h
	}

	y := core.app.bar_rect.top
	if core.settings.dock == .bottom {
		y = core.app.bar_rect.bottom - height
	}

	_ = win.SetWindowPos(
		core.app.hwnd,
		win.HWND_TOPMOST,
		core.app.bar_rect.left,
		y,
		core.app.bar_rect.right - core.app.bar_rect.left,
		height,
		win.SWP_NOACTIVATE,
	)
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

position_appbar :: proc(hwnd: win.HWND) {
	if core.app.appbar_moving {
		return
	}
	core.app.appbar_moving = true
	defer core.app.appbar_moving = false

	abd: win.APPBARDATA
	abd.cbSize = u32(size_of(win.APPBARDATA))
	abd.hWnd = hwnd

	if core.settings.dock == .bottom {
		abd.uEdge = win.ABE_BOTTOM
		abd.rc = win.RECT{0, core.app.screen_h - core.app.bar_h, core.app.screen_w, core.app.screen_h}
	} else {
		abd.uEdge = win.ABE_TOP
		abd.rc = win.RECT{0, 0, core.app.screen_w, core.app.bar_h}
	}

	if core.app.appbar_registered {
		_ = win.SHAppBarMessage(win.ABM_QUERYPOS, &abd)
		if core.settings.dock == .bottom {
			abd.rc.top = abd.rc.bottom - core.app.bar_h
		} else {
			abd.rc.bottom = abd.rc.top + core.app.bar_h
		}
		_ = win.SHAppBarMessage(win.ABM_SETPOS, &abd)
	}

	if abd.rc.right <= abd.rc.left || abd.rc.bottom <= abd.rc.top {
		if core.settings.dock == .bottom {
			abd.rc = win.RECT{0, core.app.screen_h - core.app.bar_h, core.app.screen_w, core.app.screen_h}
		} else {
			abd.rc = win.RECT{0, 0, core.app.screen_w, core.app.bar_h}
		}
	}
	core.app.bar_rect = abd.rc

	apply_window_rect()
}

set_view :: proc(view: core.Drawer_View) {
	if core.app.view == view {
		return
	}
	core.app.view = view
	core.app.refresh_edit = false

	apply_window_rect()
	services.refresh_window_preview()
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

toggle_view :: proc(view: core.Drawer_View) {
	if core.app.view == view {
		set_view(.none)
		return
	}
	_ = win.SetForegroundWindow(core.app.hwnd)
	set_view(view)
}

update_client_size :: proc(hwnd: win.HWND) {
	rect: win.RECT
	_ = win.GetClientRect(hwnd, &rect)
	core.app.width = rect.right - rect.left
	core.app.height = rect.bottom - rect.top
	ui.clamp_scroll()
	resize_backbuffer()
	_ = win.InvalidateRect(hwnd, nil, win.FALSE)
}

paint_window :: proc(hwnd: win.HWND) {
	ps: win.PAINTSTRUCT
	hdc := win.BeginPaint(hwnd, &ps)
	defer _ = win.EndPaint(hwnd, &ps)

	if core.app.width <= 0 || core.app.height <= 0 {
		return
	}
	if core.app.mem_dc == nil {
		resize_backbuffer()
	}
	if core.app.mem_dc == nil {
		return
	}

	ui.paint(core.app.mem_dc)
	_ = win.BitBlt(hdc, 0, 0, core.app.width, core.app.height, core.app.mem_dc, 0, 0, win.SRCCOPY)
}

resize_backbuffer :: proc() {
	core.destroy_backbuffer()
	if core.app.width <= 0 || core.app.height <= 0 {
		return
	}

	screen := win.GetDC(core.app.hwnd)
	if screen == nil {
		return
	}
	dc := win.CreateCompatibleDC(screen)
	bmp := win.CreateCompatibleBitmap(screen, core.app.width, core.app.height)
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
