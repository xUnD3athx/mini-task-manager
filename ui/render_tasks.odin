package ui

import "core:fmt"
import win "core:sys/windows"
import "../core"
import "../platform"
import "../services"

// 任务抽屉：列表、分组行、进程行、滚动条。

risk_brush :: proc(tier: core.Risk_Tier) -> win.HBRUSH {
	switch tier {
	case .blocked: return core.app.brushes.risk_blocked
	case .risky:   return core.app.brushes.risk_risky
	case .safe:    return core.app.brushes.risk_safe
	case .unknown: return core.app.brushes.risk_unknown
	}
	return core.app.brushes.risk_unknown
}

// Draws the tier dot before a row's text and returns the horizontal space it
// consumed, so name and subtitle stay aligned.
draw_risk_dot :: proc(dc: win.HDC, tier: core.Risk_Tier, x, y: i32) -> i32 {
	size := core.dip(7)
	fill_round(dc, win.RECT{x, y, x + size, y + size}, risk_brush(tier), core.app.pens.null, size/2)
	return size + core.dip(7)
}

draw_drawer :: proc(dc: win.HDC) {
	switch core.app.view {
	case .tasks:
		draw_tasks_view(dc)
	case .settings:
		services.hide_preview_thumbnail()
		draw_settings_view(dc)
	case .none:
		services.hide_preview_thumbnail()
	}

	bottom := win.RECT{0, core.app.layout_h - 1, core.app.width, core.app.layout_h}
	_ = win.FillRect(dc, &bottom, core.app.brushes.line)
}

draw_tasks_view :: proc(dc: win.HDC) {
	draw_core_band(dc)

	geo := tasks_geometry()
	if geo.panel.right <= geo.panel.left {
		return
	}
	draw_tasks_panel(dc, geo)

	right_x := geo.panel.right + core.dip(18)
	right := core.app.width - core.dip(18)
	if right - right_x <= core.dip(220) {
		services.hide_preview_thumbnail()
		return
	}

	// Selecting a task turns the right side into that task's detail page.
	if core.app.has_selection {
		draw_task_view(dc)
		return
	}
	services.hide_preview_thumbnail()
	draw_select_hint(dc, win.RECT{right_x, geo.panel.top, right, geo.panel.bottom})
}

// Nothing selected: the monitoring column stays empty so the user knows the
// right side belongs to the selected task.
draw_select_hint :: proc(dc: win.HDC, rect: win.RECT) {
	if rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	draw_card(dc, rect)

	width := rect.right - rect.left
	mid := rect.top + (rect.bottom - rect.top)/2

	draw_text(dc, "Select a task", rect.left, mid - core.dip(46), width, core.dip(34),
		core.app.fonts.heading, core.COL_TEXT, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
	draw_text(dc, "Choose a process on the left to preview its window and monitoring.",
		rect.left + core.dip(24), mid - core.dip(4), width - core.dip(48), core.dip(22),
		core.app.fonts.small, core.COL_MUTED, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)
}

draw_tasks_panel :: proc(dc: win.HDC, geo: Tasks_Geometry) {
	draw_card(dc, geo.panel)

	draw_text(dc, "Tasks", geo.panel.left + core.dip(20), geo.panel.top + core.dip(12),
		geo.panel.right - geo.panel.left - core.dip(110), core.dip(30),
		core.app.fonts.title, core.COL_TEXT, platform.DT_LEFT | platform.DT_VCENTER | platform.DT_SINGLELINE)

	count_buf: [32]u8
	count_text := fmt.bprintf(count_buf[:], "%d", core.app.process_count)
	visible_count := services.visible_process_count()
	if core.risk_filter_active() && visible_count < core.app.process_count {
		count_text = fmt.bprintf(count_buf[:], "%d of %d", visible_count, core.app.process_count)
	}
	draw_text(dc, count_text, geo.panel.right - core.dip(20) - core.dip(104), geo.panel.top + core.dip(16),
		core.dip(104), core.dip(20), core.app.fonts.small, core.COL_MUTED, platform.DT_RIGHT | platform.DT_VCENTER | platform.DT_SINGLELINE)

	labels := core.SORT_FIELD_LABELS
	for i in 0..<len(labels) {
		chip := task_sort_chip_rect(geo.panel, i)
		active := core.settings.sort_field == core.Sort_Field(i)
		brush := core.app.brushes.badge
		color := core.COL_MUTED
		label := labels[i]
		if active {
			arrow := "↓"
			if !core.settings.sort_desc {
				arrow = "↑"
			}
			label_buf: [24]u8
			label = fmt.bprintf(label_buf[:], "%s %s", labels[i], arrow)
			brush = core.app.brushes.accent
			color = core.COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, core.app.pens.border, core.dip(6))
		draw_text(dc, label, chip.left, chip.top, chip.right - chip.left, chip.bottom - chip.top,
			core.app.fonts.tiny, color, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
	}

	divider := win.RECT{geo.panel.left + core.dip(18), geo.panel.top + core.dip(96),
		geo.panel.right - core.dip(18), geo.panel.top + core.dip(97)}
	_ = win.FillRect(dc, &divider, core.app.brushes.line)

	risk_y := geo.panel.top + core.dip(core.TASK_RISK_ROW_DIP)
	draw_text(dc, "RISK", geo.panel.left + core.dip(20), risk_y,
		core.dip(34), core.dip(core.TASK_RISK_CHIP_H_DIP), core.app.fonts.tiny, core.COL_MUTED,
		platform.DT_LEFT | platform.DT_VCENTER | platform.DT_SINGLELINE)
	for i in 0..<len(core.RISK_TIERS) {
		chip := task_risk_chip_rect(geo.panel, i)
		tier := core.RISK_TIERS[i]
		visible := core.risk_tier_visible(tier)

		brush := core.app.brushes.badge
		text_color := core.COL_MUTED
		if visible {
			brush = risk_brush(tier)
			text_color = core.COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, core.app.pens.border, core.dip(6))
		draw_text(dc, core.risk_label(tier), chip.left, chip.top,
			chip.right - chip.left, chip.bottom - chip.top, core.app.fonts.tiny, text_color,
			platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)
	}

	if core.app.process_count == 0 {
		draw_text(dc, "No processes", geo.panel.left, geo.list_top,
			geo.panel.right - geo.panel.left, core.dip(40),
			core.app.fonts.small, core.COL_MUTED, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
		return
	}
	if core.app.task_row_count == 0 {
		draw_text(dc, "No tasks match the risk filter", geo.panel.left + core.dip(20), geo.list_top + core.dip(16),
			geo.panel.right - geo.panel.left - core.dip(40), core.dip(20),
			core.app.fonts.small, core.COL_TEXT, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
		draw_text(dc, "Change the risk filter above.", geo.panel.left + core.dip(20), geo.list_top + core.dip(38),
			geo.panel.right - geo.panel.left - core.dip(40), core.dip(20),
			core.app.fonts.tiny, core.COL_MUTED, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
		return
	}

	row_h := core.dip(core.TASK_ROW_HEIGHT_DIP)
	scroll := core.app.scroll
	first := int(scroll / f32(row_h))
	offset := i32(scroll - f32(first)*f32(row_h))

	// A smooth scroll leaves the first and last rows half outside the list, so
	// the rows are clipped to it in both GDI and GDI+.
	saved := win.SaveDC(dc)
	_ = platform.IntersectClipRect(dc, geo.panel.left + core.dip(1), geo.list_top,
		geo.panel.right - core.dip(1), geo.list_bottom)
	if gfx != nil {
		_ = platform.GdipSetClipRect(gfx, f32(geo.panel.left + core.dip(1)), f32(geo.list_top),
			f32(geo.panel.right - geo.panel.left - core.dip(2)), f32(geo.list_bottom - geo.list_top),
			platform.GDIP_COMBINE_REPLACE)
	}
	rows_to_draw := geo.visible
	if offset > 0 {
		// The row below the last full one is partly visible mid-scroll. At rest
		// the list keeps its blank sliver, exactly as before.
		rows_to_draw += 1
	}
	for row in 0..<rows_to_draw {
		index := first + row
		if index >= core.app.task_row_count {
			break
		}
		y := geo.list_top - offset + i32(row)*row_h
		item := core.app.task_rows[index]
		switch item.kind {
		case .group:
			draw_group_row(dc, &core.app.groups[item.index], geo.panel.left, geo.panel.right, y, row_h)
		case .process:
			draw_process_row(dc, &core.app.processes[item.index], geo.panel.left + core.dip(24),
				geo.panel.right, y, row_h)
		}
	}
	if gfx != nil {
		_ = platform.GdipResetClip(gfx)
	}
	_ = win.RestoreDC(dc, saved)

	draw_list_scrollbar(dc, geo.panel.right, geo.list_top, geo.list_bottom, geo.visible)
}

draw_process_row :: proc(dc: win.HDC, p: ^core.Process, left, right, y, row_h: i32) {
	selected := core.app.has_selection && p.pid == core.app.selected_pid
	margin := core.dip(12)

	if selected {
		row_rect := win.RECT{left + margin, y + 1, right - margin, y + row_h - core.dip(2)}
		fill_round(dc, row_rect, core.app.brushes.selected, core.app.pens.null, core.dip(9))

		stripe := win.RECT{left + margin + core.dip(2), y + core.dip(13), left + margin + core.dip(5), y + row_h - core.dip(13)}
		_ = win.FillRect(dc, &stripe, core.app.brushes.accent)
	}

	badge_size := core.dip(28)
	bx := left + margin + core.dip(13)
	by := y + (row_h - badge_size) / 2
	draw_task_icon(dc, p.name, win.RECT{bx, by, bx + badge_size, by + badge_size}, selected)

	tx := bx + badge_size + core.dip(11)
	tw := right - margin - core.dip(16) - tx
	if tw < core.dip(20) {
		return
	}

	indent := draw_risk_dot(dc, p.risk, tx, y + core.dip(13))
	tx += indent
	tw -= indent

	name := win.wstring(raw_data(p.name[:]))
	name_w := tw
	extra_buf: [32]u8
	extra := sort_extra_text(extra_buf[:], p.gpu_percent, p.io_bps)
	if len(extra) > 0 {
		extra_w := core.dip(110)
		if extra_w < tw/2 {
			name_w = tw - extra_w - core.dip(8)
			draw_text(dc, extra, tx + tw - extra_w, y + core.dip(5), extra_w, core.dip(16),
				core.app.fonts.tiny, core.COL_MUTED, platform.DT_RIGHT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)
		}
	}
	draw_text_w(dc, name, tx, y + core.dip(6), name_w, core.dip(21), core.app.fonts.body, core.COL_TEXT,
		platform.DT_LEFT | platform.DT_VCENTER | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS | platform.DT_NOPREFIX)

	sub_buf: [64]u8
	sub := fmt.bprintf(sub_buf[:], "PID %d  ·  %d threads", p.pid, p.threads)
	metric_w := core.dip(100)
	left_w := tw - metric_w
	if left_w < core.dip(40) {
		left_w = tw
	}
	draw_text(dc, sub, tx, y + core.dip(27), left_w, core.dip(16), core.app.fonts.tiny, core.COL_MUTED,
		platform.DT_LEFT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)

	mem_buf: [32]u8
	cpu_buf: [16]u8
	right_buf: [64]u8
	mem_text := services.format_memory(mem_buf[:], p.working_set)
	cpu_text := fmt.bprintf(cpu_buf[:], "%d%%", i32(p.cpu_percent + 0.5))
	metrics := fmt.bprintf(right_buf[:], "%s · %s", mem_text, cpu_text)
	draw_text(dc, metrics, tx + tw - metric_w, y + core.dip(27), metric_w, core.dip(16),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_RIGHT | platform.DT_SINGLELINE)
}

sort_extra_text :: proc(buf: []u8, gpu: f32, io_bps: f64) -> string {
	switch core.settings.sort_field {
	case .gpu:
		return fmt.bprintf(buf, "GPU %d%%", i32(gpu + 0.5))
	case .disk:
		factor, suffix := services.rate_scale(io_bps)
		return fmt.bprintf(buf, "I/O %.1f %s", io_bps/factor, suffix)
	case .cpu, .memory:
	}
	return ""
}

// Prefer the executable's shell icon; the letter badge remains the fallback
// for processes whose icon cannot be read.
draw_task_icon :: proc(dc: win.HDC, name: [core.MAX_NAME_U16]u16, rect: win.RECT, highlighted: bool) {
	icon := services.icon_for_task_name(name)
	if icon == nil {
		draw_letter_badge(dc, name, rect, highlighted)
		return
	}

	width := rect.right - rect.left
	height := rect.bottom - rect.top
	size := min(width, height)
	x := rect.left + (width - size) / 2
	y := rect.top + (height - size) / 2
	_ = platform.DrawIconEx(dc, x, y, icon, size, size, 0, nil, platform.DI_NORMAL)
}

draw_letter_badge :: proc(dc: win.HDC, name: [core.MAX_NAME_U16]u16, rect: win.RECT, highlighted: bool) {
	brush := core.app.brushes.badge
	letter_color := core.COL_TEXT
	if highlighted {
		brush = core.app.brushes.accent
		letter_color = core.COL_BADGE_TEXT
	}
	fill_round(dc, rect, brush, core.app.pens.null, core.dip(8))

	initial: u16 = 0
	for i in 0..<core.MAX_NAME_U16 {
		c := name[i]
		if c == 0 {
			break
		}
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			initial = c
			break
		}
	}
	if initial == 0 {
		initial = name[0]
	}
	if initial >= 'a' && initial <= 'z' {
		initial -= 32
	}
	if initial != 0 {
		letter: [2]u16
		letter[0] = initial
		letter[1] = 0
		draw_text_w(dc, win.wstring(raw_data(letter[:])), rect.left, rect.top,
			rect.right - rect.left, rect.bottom - rect.top, core.app.fonts.badge, letter_color,
			platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
	}
}

draw_group_row :: proc(dc: win.HDC, g: ^core.Task_Group, left, right, y, row_h: i32) {
	margin := core.dip(12)
	expanded := services.group_is_expanded(g.name)
	selected := core.app.has_selection && core.app.group_selected && services.same_task_name(g.name, core.app.selected_group)

	if selected {
		row_rect := win.RECT{left + margin, y + 1, right - margin, y + row_h - core.dip(2)}
		fill_round(dc, row_rect, core.app.brushes.selected, core.app.pens.null, core.dip(9))
	}

	chevron := "▸"
	if expanded {
		chevron = "▾"
	}
	draw_text(dc, chevron, left + core.dip(14), y, core.dip(16), row_h,
		core.app.fonts.small, core.COL_MUTED, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)

	badge_size := core.dip(28)
	bx := left + core.dip(36)
	by := y + (row_h - badge_size) / 2
	draw_task_icon(dc, g.name, win.RECT{bx, by, bx + badge_size, by + badge_size}, selected)

	tx := bx + badge_size + core.dip(11)
	tw := right - margin - core.dip(16) - tx
	if tw < core.dip(20) {
		return
	}

	indent := draw_risk_dot(dc, g.visible_risk, tx, y + core.dip(13))
	tx += indent
	tw -= indent

	extra_buf: [32]u8
	extra := sort_extra_text(extra_buf[:], g.gpu_percent, g.io_bps)
	name_w := tw
	if len(extra) > 0 {
		extra_w := core.dip(110)
		if extra_w < tw/2 {
			name_w = tw - extra_w - core.dip(8)
			draw_text(dc, extra, tx + tw - extra_w, y + core.dip(5), extra_w, core.dip(16),
				core.app.fonts.tiny, core.COL_MUTED, platform.DT_RIGHT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)
		}
	}

	draw_text_w(dc, win.wstring(raw_data(g.name[:])), tx, y + core.dip(6), name_w, core.dip(21),
		core.app.fonts.stat, core.COL_TEXT,
		platform.DT_LEFT | platform.DT_VCENTER | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS | platform.DT_NOPREFIX)

	sub_buf: [48]u8
	sub := ""
	if g.visible_count > 0 && g.visible_count < g.count {
		sub = fmt.bprintf(sub_buf[:], "%d of %d processes", g.visible_count, g.count)
	} else if g.count == 1 {
		sub = "1 process"
	} else {
		sub = fmt.bprintf(sub_buf[:], "%d processes", g.count)
	}
	metric_w := core.dip(100)
	left_w := tw - metric_w
	if left_w < core.dip(40) {
		left_w = tw
	}
	draw_text(dc, sub, tx, y + core.dip(27), left_w, core.dip(16), core.app.fonts.tiny, core.COL_MUTED,
		platform.DT_LEFT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)

	mem_buf: [32]u8
	cpu_buf: [16]u8
	right_buf: [64]u8
	mem_text := services.format_memory(mem_buf[:], g.working_set)
	cpu_text := fmt.bprintf(cpu_buf[:], "%d%%", i32(g.cpu_percent + 0.5))
	metrics := fmt.bprintf(right_buf[:], "%s · %s", mem_text, cpu_text)
	draw_text(dc, metrics, tx + tw - metric_w, y + core.dip(27), metric_w, core.dip(16),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_RIGHT | platform.DT_SINGLELINE)
}

draw_list_scrollbar :: proc(dc: win.HDC, panel_right, list_top, list_bottom: i32, visible: int) {
	if visible <= 0 || core.app.task_row_count <= visible {
		return
	}
	track_x := panel_right - core.dip(10)
	top := list_top
	bottom := list_bottom
	if bottom <= top {
		return
	}

	track_rect := win.RECT{track_x, top, track_x + core.dip(3), bottom}
	_ = win.FillRect(dc, &track_rect, core.app.brushes.track)

	track_h := bottom - top
	thumb_h := max(core.dip(26), track_h * i32(visible) / i32(core.app.task_row_count))
	max_scroll := f32(max(core.app.task_row_count - visible, 1)) * f32(core.dip(core.TASK_ROW_HEIGHT_DIP))
	progress := core.app.scroll / max_scroll
	if progress < 0 {
		progress = 0
	}
	if progress > 1 {
		progress = 1
	}
	travel := track_h - thumb_h
	if travel < 0 {
		travel = 0
	}
	thumb_y := top + i32(f32(travel)*progress)

	thumb_rect := win.RECT{track_x, thumb_y, track_x + core.dip(3), thumb_y + thumb_h}
	_ = win.FillRect(dc, &thumb_rect, core.app.brushes.thumb)
}
