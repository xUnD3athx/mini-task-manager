package main

import win "core:sys/windows"

// 绘制基础：双缓冲入口、文字、圆角矩形、卡片。

paint :: proc(dc: win.HDC) {
	if app.width <= 0 || app.height <= 0 {
		return
	}
	_ = win.SetBkMode(dc, win.BKMODE.TRANSPARENT)

	full := win.RECT{0, 0, app.width, app.height}
	_ = win.FillRect(dc, &full, app.brushes.bg)

	if app.view != .none && app.height > app.bar_h {
		draw_drawer(dc)
	}

	// The bar is drawn in its own local space and shifted to the bottom edge
	// when the window is pinned there.
	if settings.dock == .bottom {
		previous: win.POINT
		_ = SetViewportOrgEx(dc, 0, bar_top(), &previous)
		draw_bar(dc)
		_ = SetViewportOrgEx(dc, previous.x, previous.y, nil)
	} else {
		draw_bar(dc)
	}
}

draw_text :: proc(
	dc: win.HDC,
	text: string,
	x, y, w, h: i32,
	font: win.HFONT,
	color: Color,
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
	color: Color,
	flags: u32,
) {
	if text == nil {
		return
	}
	rect := win.RECT{x, y, x + w, y + h}
	_ = win.SelectObject(dc, win.HGDIOBJ(font))
	_ = win.SetTextColor(dc, colorref(color))
	_ = DrawTextW(dc, text, -1, &rect, flags)
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

fill_color_rect :: proc(dc: win.HDC, rect: win.RECT, color: Color, radius: i32) {
	brush := win.CreateSolidBrush(colorref(color))
	fill_round(dc, rect, brush, app.pens.null, radius)
	_ = win.DeleteObject(win.HGDIOBJ(brush))
}

draw_card :: proc(dc: win.HDC, rect: win.RECT) {
	fill_round(dc, rect, app.brushes.card, app.pens.border, dip(10))
}
