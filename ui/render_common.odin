package ui

import win "core:sys/windows"
import "../core"
import "../platform"

// 绘制基础：双缓冲入口、文字、圆角矩形、卡片。

paint :: proc(dc: win.HDC) {
	if core.app.width <= 0 || core.app.height <= 0 {
		return
	}
	_ = win.SetBkMode(dc, win.BKMODE.TRANSPARENT)

	full := win.RECT{0, 0, core.app.width, core.app.height}
	_ = win.FillRect(dc, &full, core.app.brushes.bg)

	if core.app.view != .none && core.app.height > core.app.bar_h {
		draw_drawer(dc)
	}

	// The bar is drawn in its own local space and shifted to the bottom edge
	// when the window is pinned there.
	if core.settings.dock == .bottom {
		previous: win.POINT
		_ = platform.SetViewportOrgEx(dc, 0, bar_top(), &previous)
		draw_bar(dc)
		_ = platform.SetViewportOrgEx(dc, previous.x, previous.y, nil)
	} else {
		draw_bar(dc)
	}
}

draw_text :: proc(
	dc: win.HDC,
	text: string,
	x, y, w, h: i32,
	font: win.HFONT,
	color: core.Color,
	flags: u32,
) {
	if len(text) == 0 {
		return
	}
	buf: [512]u16
	ws := win.utf8_to_wstring_buf(buf[:], text)
	if ws == nil {
		return
	}
	draw_text_w(dc, ws, x, y, w, h, font, color, flags)
}

draw_text_w :: proc(
	dc: win.HDC,
	text: win.LPCWSTR,
	x, y, w, h: i32,
	font: win.HFONT,
	color: core.Color,
	flags: u32,
) {
	if text == nil {
		return
	}
	rect := win.RECT{x, y, x + w, y + h}
	_ = win.SelectObject(dc, win.HGDIOBJ(font))
	_ = win.SetTextColor(dc, core.colorref(color))
	_ = platform.DrawTextW(dc, text, -1, &rect, flags)
}

fill_round :: proc(dc: win.HDC, rect: win.RECT, brush: win.HBRUSH, pen: win.HPEN, radius: i32) {
	old_brush := win.SelectObject(dc, win.HGDIOBJ(brush))
	old_pen := win.SelectObject(dc, win.HGDIOBJ(pen))
	if radius > 0 {
		_ = win.RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, radius*2, radius*2)
	} else {
		_ = win.Rectangle(dc, rect.left, rect.top, rect.right, rect.bottom)
	}
	_ = win.SelectObject(dc, old_pen)
	_ = win.SelectObject(dc, old_brush)
}

fill_color_rect :: proc(dc: win.HDC, rect: win.RECT, color: core.Color, radius: i32) {
	brush := win.CreateSolidBrush(core.colorref(color))
	fill_round(dc, rect, brush, core.app.pens.null, radius)
	_ = win.DeleteObject(win.HGDIOBJ(brush))
}

draw_card :: proc(dc: win.HDC, rect: win.RECT) {
	fill_round(dc, rect, core.app.brushes.card, core.app.pens.border, core.dip(10))
}
