package ui

import win "core:sys/windows"
import "../core"
import "../platform"

// 绘制基础：双缓冲入口、文字、圆角矩形、卡片。

// Only the dirty rect is re-rendered, so scrolling and hover cost the pixels
// they actually touch instead of the whole window. The backbuffer keeps the
// rest of the last full frame.
paint :: proc(dc: win.HDC, dirty: win.RECT) {
	if core.app.width <= 0 || core.app.layout_h <= 0 {
		return
	}
	clip := win.RECT{
		max(dirty.left, 0),
		max(dirty.top, 0),
		min(dirty.right, core.app.width),
		min(dirty.bottom, core.app.layout_h),
	}
	if clip.right <= clip.left || clip.bottom <= clip.top {
		return
	}
	paint_dirty = clip

	saved := win.SaveDC(dc)
	_ = platform.IntersectClipRect(dc, clip.left, clip.top, clip.right, clip.bottom)

	_ = win.SetBkMode(dc, win.BKMODE.TRANSPARENT)

	full := win.RECT{0, 0, core.app.width, core.app.layout_h}
	_ = win.FillRect(dc, &full, core.app.brushes.bg)

	// Buttons claim this during the pass; whatever is left over is the control
	// under the pointer this frame.
	core.app.hover_rect = {}
	core.app.hover_rect_count = 0

	if core.app.view != .none && core.app.layout_h > core.app.bar_h {
		gdiplus_begin(dc)
		draw_drawer(dc)
		gdiplus_end()
	}

	gdiplus_begin(dc)
	draw_bar(dc)
	gdiplus_end()

	_ = win.RestoreDC(dc, saved)
	finish_hover_pass()
}

// The clip shared by every GDI+ pass of the current paint.
paint_dirty: win.RECT

// Repaints exactly these pixels of the backbuffer and the window.
invalidate_rect :: proc(rect: win.RECT) {
	if core.app.hwnd == nil || rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	// One pixel of slack keeps antialiased edges inside the redrawn area.
	r := win.RECT{rect.left - 1, rect.top - 1, rect.right + 1, rect.bottom + 1}
	_ = win.InvalidateRect(core.app.hwnd, &r, win.FALSE)
}

// Pointer movement only repaints when the control under the cursor changed,
// and then only the old and new control rects.
invalidate_hover_transition :: proc(pos: win.POINT) {
	next: win.RECT
	for i in 0..<core.app.hover_rect_count {
		if core.point_in_rect(pos.x, pos.y, core.app.hover_rects[i]) {
			next = core.app.hover_rects[i]
		}
	}
	if next == core.app.hover_last {
		return
	}
	invalidate_rect(core.app.hover_last)
	invalidate_rect(next)
}

invalidate_tasks_scroll :: proc() {
	geo := tasks_geometry()
	invalidate_rect(win.RECT{geo.panel.left, geo.list_top, geo.panel.right, geo.list_bottom})
}

invalidate_settings_scroll :: proc() {
	layout := settings_layout()
	invalidate_rect(win.RECT{layout.body.left, layout.body.top, layout.outer.right, layout.body.bottom})
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
	if paint_dirty.right > paint_dirty.left && paint_dirty.bottom > paint_dirty.top {
		_ = platform.GdipSetClipRect(graphics, f32(paint_dirty.left), f32(paint_dirty.top),
			f32(paint_dirty.right - paint_dirty.left), f32(paint_dirty.bottom - paint_dirty.top),
			platform.GDIP_COMBINE_REPLACE)
	}
	gfx = graphics
}

gdiplus_end :: proc() {
	if gfx != nil {
		_ = platform.GdipDeleteGraphics(gfx)
		gfx = nil
	}
}

// Panels narrow the clip while they draw and call this afterwards: it restores
// the paint's dirty rect rather than clearing the clip, so later shapes in the
// same pass stay inside it.
gdiplus_reset_clip :: proc() {
	if gfx == nil {
		return
	}
	if paint_dirty.right > paint_dirty.left && paint_dirty.bottom > paint_dirty.top {
		_ = platform.GdipSetClipRect(gfx, f32(paint_dirty.left), f32(paint_dirty.top),
			f32(paint_dirty.right - paint_dirty.left), f32(paint_dirty.bottom - paint_dirty.top),
			platform.GDIP_COMBINE_REPLACE)
	} else {
		_ = platform.GdipResetClip(gfx)
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

// Hover is a single control at a time, identified by its rect: the button under
// the pointer claims it for this pass and reads the shared fade value.
hover_alpha :: proc(rect: win.RECT) -> f32 {
	if !core.app.mouse_inside {
		return 0
	}
	if !core.point_in_rect(core.app.mouse_pos.x, core.app.mouse_pos.y, rect) {
		return 0
	}
	core.app.hover_rect = rect
	if !core.settings.animations {
		return 1
	}
	return core.app.hover_amount
}

// Runs once per paint pass. A different control under the pointer restarts the
// fade, and a pressed/held control keeps the timer alive.
finish_hover_pass :: proc() {
	if core.app.hover_rect == core.app.hover_last {
		return
	}
	core.app.hover_last = core.app.hover_rect
	core.app.hover_active = core.app.hover_rect.right > core.app.hover_rect.left
	if core.settings.animations {
		core.start_ui_anim()
	}
}

// Every live button rect is remembered for the pointer-move hit test, so a move
// does not have to repaint the window to discover what it landed on.
register_hover_rect :: proc(rect: win.RECT) {
	if rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	if core.app.hover_rect_count < len(core.app.hover_rects) {
		core.app.hover_rects[core.app.hover_rect_count] = rect
		core.app.hover_rect_count += 1
	}
}

// Lightens a hovered button and darkens one that is being held, drawn over the
// button's fill and under its label.
button_feedback :: proc(dc: win.HDC, rect: win.RECT, radius: i32, enabled: bool = true) {
	if !enabled {
		return
	}
	register_hover_rect(rect)
	hover := hover_alpha(rect)
	if hover > 0.02 {
		tint_round(dc, rect, radius, {255, 255, 255}, u8(26*hover))
	}
	pressed := core.app.mouse_down && core.app.press_valid &&
		core.point_in_rect(core.app.press_pos.x, core.app.press_pos.y, rect) &&
		core.point_in_rect(core.app.mouse_pos.x, core.app.mouse_pos.y, rect)
	if pressed {
		tint_round(dc, rect, radius, {0, 0, 0}, 60)
	}
}

tint_round :: proc(dc: win.HDC, rect: win.RECT, radius: i32, color: core.Color, alpha: u8) {
	if alpha == 0 || gfx == nil || rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	path := create_round_path(rect, radius)
	if path == nil {
		return
	}
	defer _ = platform.GdipDeletePath(path)

	brush: rawptr
	if platform.GdipCreateSolidFill(argb_alpha(color, alpha), &brush) == 0 {
		_ = platform.GdipFillPath(gfx, brush, path)
		_ = platform.GdipDeleteBrush(brush)
	}
}

argb_alpha :: proc(c: core.Color, alpha: u8) -> u32 {
	return u32(alpha) << 24 | u32(c[0]) << 16 | u32(c[1]) << 8 | u32(c[2])
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
