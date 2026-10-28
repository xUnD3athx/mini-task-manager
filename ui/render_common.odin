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
		gdiplus_begin(dc)
		draw_drawer(dc)
		gdiplus_end()
	}

	// The bar is drawn in its own local space and shifted to the bottom edge
	// when the window is pinned there. GDI+ is started after the viewport shift
	// so anti-aliased shapes and GDI text/icons share the same origin.
	if core.settings.dock == .bottom {
		previous: win.POINT
		_ = platform.SetViewportOrgEx(dc, 0, bar_top(), &previous)
		gdiplus_begin(dc)
		draw_bar(dc)
		gdiplus_end()
		_ = platform.SetViewportOrgEx(dc, previous.x, previous.y, nil)
	} else {
		gdiplus_begin(dc)
		draw_bar(dc)
		gdiplus_end()
	}
}

// Anti-aliased shapes go through one GDI+ Graphics per painting pass; text and
// icons stay on GDI, whose ClearType output is already smooth.
gfx: rawptr

gdiplus_begin :: proc(dc: win.HDC) {
	graphics: rawptr
	if platform.GdipCreateFromHDC(dc, &graphics) != 0 || graphics == nil {
		gfx = nil
		return
	}
	_ = platform.GdipSetSmoothingMode(graphics, platform.SMOOTHING_MODE_ANTIALIAS)
	_ = platform.GdipSetPixelOffsetMode(graphics, platform.PIXEL_OFFSET_MODE_HALF)
	gfx = graphics
}

gdiplus_end :: proc() {
	if gfx != nil {
		_ = platform.GdipDeleteGraphics(gfx)
		gfx = nil
	}
}

argb :: proc(c: core.Color) -> u32 {
	return 0xFF000000 | u32(c[0]) << 16 | u32(c[1]) << 8 | u32(c[2])
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
	fill, has_fill := core.brush_color_of(brush)
	stroke, has_stroke, stroke_width := core.pen_style_of(pen)
	fill_shape(dc, rect, radius, fill, has_fill, stroke, has_stroke, stroke_width)
}

fill_color_rect :: proc(dc: win.HDC, rect: win.RECT, color: core.Color, radius: i32) {
	fill_shape(dc, rect, radius, color, true, {}, false, 0)
}

fill_shape :: proc(
	dc: win.HDC,
	rect: win.RECT,
	radius: i32,
	fill: core.Color,
	has_fill: bool,
	stroke: core.Color,
	has_stroke: bool,
	stroke_width: i32,
) {
	if gfx == nil || rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	if !has_fill && !has_stroke {
		return
	}

	path := create_round_path(rect, radius)
	if path == nil {
		return
	}
	defer _ = platform.GdipDeletePath(path)

	if has_fill {
		brush: rawptr
		if platform.GdipCreateSolidFill(argb(fill), &brush) == 0 {
			_ = platform.GdipFillPath(gfx, brush, path)
			_ = platform.GdipDeleteBrush(brush)
		}
	}
	if has_stroke {
		pen: rawptr
		width := f32(max(stroke_width, 1))
		if platform.GdipCreatePen1(argb(stroke), width, platform.GDIP_UNIT_PIXEL, &pen) == 0 {
			_ = platform.GdipDrawPath(gfx, pen, path)
			_ = platform.GdipDeletePen(pen)
		}
	}
}

create_round_path :: proc(rect: win.RECT, radius: i32) -> rawptr {
	width := rect.right - rect.left
	height := rect.bottom - rect.top
	if width <= 0 || height <= 0 {
		return nil
	}

	path: rawptr
	if platform.GdipCreatePath(platform.GDIP_FILL_MODE_WINDING, &path) != 0 || path == nil {
		return nil
	}

	r := clamp(radius, 0, min(width, height)/2)
	if r <= 0 {
		_ = platform.GdipAddPathRectangle(path, f32(rect.left), f32(rect.top), f32(width), f32(height))
		return path
	}

	d := f32(r * 2)
	left := f32(rect.left)
	top := f32(rect.top)
	right := f32(rect.right)
	bottom := f32(rect.bottom)
	_ = platform.GdipAddPathArc(path, left, top, d, d, 180, 90)
	_ = platform.GdipAddPathArc(path, right - d, top, d, d, 270, 90)
	_ = platform.GdipAddPathArc(path, right - d, bottom - d, d, d, 0, 90)
	_ = platform.GdipAddPathArc(path, left, bottom - d, d, d, 90, 90)
	_ = platform.GdipClosePathFigure(path)
	return path
}

draw_card :: proc(dc: win.HDC, rect: win.RECT) {
	fill_round(dc, rect, core.app.brushes.card, core.app.pens.border, core.dip(10))
}
