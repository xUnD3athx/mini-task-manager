package main

import "core:fmt"
import win "core:sys/windows"

// 任务抽屉：列表、分组行、进程行、滚动条。

draw_drawer :: proc(dc: win.HDC) {
	switch app.view {
	case .tasks:
		draw_tasks_view(dc)
	case .settings:
		hide_preview_thumbnail()
		draw_settings_view(dc)
	case .none:
		hide_preview_thumbnail()
	}

	bottom := win.RECT{0, app.height - 1, app.width, app.height}
	_ = win.FillRect(dc, &bottom, app.brushes.line)
}

draw_tasks_view :: proc(dc: win.HDC) {
	draw_core_band(dc)

	geo := tasks_geometry()
	if geo.panel.right <= geo.panel.left {
		return
	}
	draw_tasks_panel(dc, geo)

	right_x := geo.panel.right + dip(18)
	right := app.width - dip(18)
	if right - right_x <= dip(220) {
		hide_preview_thumbnail()
		return
	}

	// Selecting a task turns the right side into that task's detail page.
	if app.has_selection {
		draw_task_view(dc)
		return
	}
	hide_preview_thumbnail()
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

	draw_text(dc, "Select a task", rect.left, mid - dip(46), width, dip(34),
		app.fonts.heading, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	draw_text(dc, "Choose a process on the left to preview its window and monitoring.",
		rect.left + dip(24), mid - dip(4), width - dip(48), dip(22),
		app.fonts.small, COL_MUTED, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS)
}

draw_tasks_panel :: proc(dc: win.HDC, geo: Tasks_Geometry) {
	draw_card(dc, geo.panel)

	draw_text(dc, "Tasks", geo.panel.left + dip(20), geo.panel.top + dip(12),
		geo.panel.right - geo.panel.left - dip(110), dip(30),
		app.fonts.title, COL_TEXT, DT_LEFT | DT_VCENTER | DT_SINGLELINE)

	count_buf: [32]u8
	count_text := fmt.bprintf(count_buf[:], "%d", app.process_count)
	draw_text(dc, count_text, geo.panel.right - dip(20) - dip(70), geo.panel.top + dip(16),
		dip(70), dip(20), app.fonts.small, COL_MUTED, DT_RIGHT | DT_VCENTER | DT_SINGLELINE)

	labels := SORT_FIELD_LABELS
	for i in 0..<len(labels) {
		chip := task_sort_chip_rect(geo.panel, i)
		active := settings.sort_field == Sort_Field(i)
		brush := app.brushes.badge
		color := COL_MUTED
		label := labels[i]
		if active {
			arrow := "↓"
			if !settings.sort_desc {
				arrow = "↑"
			}
			label_buf: [24]u8
			label = fmt.bprintf(label_buf[:], "%s %s", labels[i], arrow)
			brush = app.brushes.accent
			color = COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, app.pens.border, dip(6))
		draw_text(dc, label, chip.left, chip.top, chip.right - chip.left, chip.bottom - chip.top,
			app.fonts.tiny, color, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	}

	divider := win.RECT{geo.panel.left + dip(18), geo.panel.top + dip(72),
		geo.panel.right - dip(18), geo.panel.top + dip(73)}
	_ = win.FillRect(dc, &divider, app.brushes.line)

	if app.process_count == 0 {
		draw_text(dc, "No processes", geo.panel.left, geo.list_top,
			geo.panel.right - geo.panel.left, dip(40),
			app.fonts.small, COL_MUTED, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
		return
	}

	row_h := dip(TASK_ROW_HEIGHT_DIP)
	for row in 0..<geo.visible {
		index := app.scroll + row
		if index < 0 || index >= app.task_row_count {
			break
		}
		y := geo.list_top + i32(row)*row_h
		item := app.task_rows[index]
		switch item.kind {
		case .group:
			draw_group_row(dc, &app.groups[item.index], geo.panel.left, geo.panel.right, y, row_h)
		case .process:
			draw_process_row(dc, &app.processes[item.index], geo.panel.left + dip(24),
				geo.panel.right, y, row_h)
		}
	}

	draw_list_scrollbar(dc, geo.panel.right, geo.list_top, geo.list_bottom, geo.visible)
}

draw_process_row :: proc(dc: win.HDC, p: ^Process, left, right, y, row_h: i32) {
	selected := app.has_selection && p.pid == app.selected_pid
	margin := dip(12)

	if selected {
		row_rect := win.RECT{left + margin, y + 1, right - margin, y + row_h - dip(2)}
		fill_round(dc, row_rect, app.brushes.selected, app.pens.null, dip(9))

		stripe := win.RECT{left + margin + dip(2), y + dip(13), left + margin + dip(5), y + row_h - dip(13)}
		_ = win.FillRect(dc, &stripe, app.brushes.accent)
	}

	badge_size := dip(28)
	bx := left + margin + dip(13)
	by := y + (row_h - badge_size) / 2
	draw_task_icon(dc, p.name, win.RECT{bx, by, bx + badge_size, by + badge_size}, selected)

	tx := bx + badge_size + dip(11)
	tw := right - margin - dip(16) - tx
	if tw < dip(20) {
		return
	}

	name := win.wstring(raw_data(p.name[:]))
	name_w := tw
	extra_buf: [32]u8
	extra := sort_extra_text(extra_buf[:], p.gpu_percent, p.io_bps)
	if len(extra) > 0 {
		extra_w := dip(110)
		if extra_w < tw/2 {
			name_w = tw - extra_w - dip(8)
			draw_text(dc, extra, tx + tw - extra_w, y + dip(5), extra_w, dip(16),
				app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE | DT_END_ELLIPSIS)
		}
	}
	draw_text_w(dc, name, tx, y + dip(6), name_w, dip(21), app.fonts.body, COL_TEXT,
		DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)

	sub_buf: [64]u8
	sub := fmt.bprintf(sub_buf[:], "PID %d  ·  %d threads", p.pid, p.threads)
	metric_w := dip(100)
	left_w := tw - metric_w
	if left_w < dip(40) {
		left_w = tw
	}
	draw_text(dc, sub, tx, y + dip(27), left_w, dip(16), app.fonts.tiny, COL_MUTED,
		DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	mem_buf: [32]u8
	cpu_buf: [16]u8
	right_buf: [64]u8
	mem_text := format_memory(mem_buf[:], p.working_set)
	cpu_text := fmt.bprintf(cpu_buf[:], "%d%%", i32(p.cpu_percent + 0.5))
	metrics := fmt.bprintf(right_buf[:], "%s · %s", mem_text, cpu_text)
	draw_text(dc, metrics, tx + tw - metric_w, y + dip(27), metric_w, dip(16),
		app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)
}

sort_extra_text :: proc(buf: []u8, gpu: f32, io_bps: f64) -> string {
	switch settings.sort_field {
	case .gpu:
		return fmt.bprintf(buf, "GPU %d%%", i32(gpu + 0.5))
	case .disk:
		factor, suffix := rate_scale(io_bps)
		return fmt.bprintf(buf, "I/O %.1f %s", io_bps/factor, suffix)
	case .cpu, .memory:
	}
	return ""
}

// Prefer the executable's shell icon; the letter badge remains the fallback
// for processes whose icon cannot be read.
draw_task_icon :: proc(dc: win.HDC, name: [MAX_NAME_U16]u16, rect: win.RECT, highlighted: bool) {
	icon := icon_for_task_name(name)
	if icon == nil {
		draw_letter_badge(dc, name, rect, highlighted)
		return
	}

	width := rect.right - rect.left
	height := rect.bottom - rect.top
	size := min(width, height)
	x := rect.left + (width - size) / 2
	y := rect.top + (height - size) / 2
	_ = DrawIconEx(dc, x, y, icon, size, size, 0, nil, DI_NORMAL)
}

draw_letter_badge :: proc(dc: win.HDC, name: [MAX_NAME_U16]u16, rect: win.RECT, highlighted: bool) {
	brush := app.brushes.badge
	letter_color := COL_TEXT
	if highlighted {
		brush = app.brushes.accent
		letter_color = COL_BADGE_TEXT
	}
	fill_round(dc, rect, brush, app.pens.null, dip(8))

	initial: u16 = 0
	for i in 0..<MAX_NAME_U16 {
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
			rect.right - rect.left, rect.bottom - rect.top, app.fonts.badge, letter_color,
			DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	}
}

draw_group_row :: proc(dc: win.HDC, g: ^Task_Group, left, right, y, row_h: i32) {
	margin := dip(12)
	expanded := group_is_expanded(g.name)
	selected := app.has_selection && app.group_selected && same_task_name(g.name, app.selected_group)

	if selected {
		row_rect := win.RECT{left + margin, y + 1, right - margin, y + row_h - dip(2)}
		fill_round(dc, row_rect, app.brushes.selected, app.pens.null, dip(9))
	}

	chevron := "▸"
	if expanded {
		chevron = "▾"
	}
	draw_text(dc, chevron, left + dip(14), y, dip(16), row_h,
		app.fonts.small, COL_MUTED, DT_CENTER | DT_VCENTER | DT_SINGLELINE)

	badge_size := dip(28)
	bx := left + dip(36)
	by := y + (row_h - badge_size) / 2
	draw_task_icon(dc, g.name, win.RECT{bx, by, bx + badge_size, by + badge_size}, selected)

	tx := bx + badge_size + dip(11)
	tw := right - margin - dip(16) - tx
	if tw < dip(20) {
		return
	}

	extra_buf: [32]u8
	extra := sort_extra_text(extra_buf[:], g.gpu_percent, g.io_bps)
	name_w := tw
	if len(extra) > 0 {
		extra_w := dip(110)
		if extra_w < tw/2 {
			name_w = tw - extra_w - dip(8)
			draw_text(dc, extra, tx + tw - extra_w, y + dip(5), extra_w, dip(16),
				app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE | DT_END_ELLIPSIS)
		}
	}

	draw_text_w(dc, win.wstring(raw_data(g.name[:])), tx, y + dip(6), name_w, dip(21),
		app.fonts.stat, COL_TEXT,
		DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)

	sub_buf: [32]u8
	sub := fmt.bprintf(sub_buf[:], "%d processes", g.count)
	if g.count == 1 {
		sub = "1 process"
	}
	metric_w := dip(100)
	left_w := tw - metric_w
	if left_w < dip(40) {
		left_w = tw
	}
	draw_text(dc, sub, tx, y + dip(27), left_w, dip(16), app.fonts.tiny, COL_MUTED,
		DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	mem_buf: [32]u8
	cpu_buf: [16]u8
	right_buf: [64]u8
	mem_text := format_memory(mem_buf[:], g.working_set)
	cpu_text := fmt.bprintf(cpu_buf[:], "%d%%", i32(g.cpu_percent + 0.5))
	metrics := fmt.bprintf(right_buf[:], "%s · %s", mem_text, cpu_text)
	draw_text(dc, metrics, tx + tw - metric_w, y + dip(27), metric_w, dip(16),
		app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)
}

draw_list_scrollbar :: proc(dc: win.HDC, panel_right, list_top, list_bottom: i32, visible: int) {
	if visible <= 0 || app.task_row_count <= visible {
		return
	}
	track_x := panel_right - dip(10)
	top := list_top
	bottom := list_bottom
	if bottom <= top {
		return
	}

	track_rect := win.RECT{track_x, top, track_x + dip(3), bottom}
	_ = win.FillRect(dc, &track_rect, app.brushes.track)

	track_h := bottom - top
	thumb_h := max(dip(26), track_h * i32(visible) / i32(app.task_row_count))
	max_scroll := max(app.task_row_count - visible, 1)
	travel := track_h - thumb_h
	if travel < 0 {
		travel = 0
	}
	thumb_y := top + travel * i32(app.scroll) / i32(max_scroll)

	thumb_rect := win.RECT{track_x, thumb_y, track_x + dip(3), thumb_y + thumb_h}
	_ = win.FillRect(dc, &thumb_rect, app.brushes.thumb)
}
