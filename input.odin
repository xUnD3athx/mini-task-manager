package main

import win "core:sys/windows"

// 鼠标/键盘输入：只修改状态，不绘制。

handle_click :: proc(lparam: win.LPARAM) {
	x := i32(lparam & 0xffff)
	y := i32((lparam >> 16) & 0xffff)

	if bar_y := y - bar_top(); bar_y >= 0 && bar_y < app.bar_h {
		if point_in_rect(x, bar_y, tasks_button_rect()) {
			toggle_view(.tasks)
			return
		}
		if point_in_rect(x, bar_y, settings_button_rect()) {
			toggle_view(.settings)
			return
		}
		if point_in_rect(x, bar_y, exit_button_rect()) {
			_ = win.PostMessageW(app.hwnd, win.WM_CLOSE, 0, 0)
			return
		}
		return
	}

	switch app.view {
	case .tasks:
		handle_tasks_click(x, y)
	case .settings:
		handle_settings_click(x, y)
	case .none:
	}
}

handle_tasks_click :: proc(x, y: i32) {
	band := core_band_layout()
	if point_in_rect(x, y, band.prev) {
		app.core_page -= 1
		clamp_core_page()
		_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
		return
	}
	if point_in_rect(x, y, band.next) {
		app.core_page += 1
		clamp_core_page()
		_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
		return
	}

	geo := tasks_geometry()
	if geo.visible <= 0 || geo.panel.right <= geo.panel.left {
		return
	}

	for i in 0..<len(SORT_FIELD_LABELS) {
		if point_in_rect(x, y, task_sort_chip_rect(geo.panel, i)) {
			settings_set_sort(Sort_Field(i))
			return
		}
	}

	if x < geo.panel.left || x >= geo.panel.right || y < geo.list_top || y >= geo.list_bottom {
		return
	}

	row := int((y - geo.list_top) / dip(TASK_ROW_HEIGHT_DIP))
	index := app.scroll + row
	if row < geo.visible && index >= 0 && index < app.task_row_count {
		item := app.task_rows[index]
		switch item.kind {
		case .group:
			g := &app.groups[item.index]
			// Only the triangle toggles the subtree; the rest of the row selects
			// the whole application.
			if x < geo.panel.left + dip(34) {
				group_set_expanded(g.name, !group_is_expanded(g.name))
				rebuild_task_rows()
				clamp_scroll()
				_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
				return
			}

			if !app.group_selected || !same_task_name(app.selected_group, g.name) {
				app.task = Task_Metrics{group_mode = true, group = g.name}
			}
			app.selected_group = g.name
			app.group_selected = true
			app.has_selection = true
			refresh_window_preview()
			_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
		case .process:
			p := &app.processes[item.index]
			if app.group_selected || p.pid != app.selected_pid {
				app.task = Task_Metrics{pid = p.pid}
			}
			app.selected_pid = p.pid
			app.group_selected = false
			app.has_selection = true
			refresh_window_preview()
			_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
		}
	}
}

handle_settings_click :: proc(x, y: i32) {
	layout := settings_layout()

	// Clicking anywhere else finishes an in-progress interval edit.
	if app.refresh_edit {
		commit_refresh_edit()
	}

	if point_in_rect(x, y, layout.reset) {
		reset_settings()
		return
	}

	for i in 0..<7 {
		if point_in_rect(x, y, settings_module_row(layout, i)) {
			id := Module_Id(i)
			if id == .cores && !settings.modules.cpu {
				return
			}
			settings_toggle_module(id)
			return
		}
	}

	options := CORE_PAGE_OPTIONS
	for i in 0..<len(options) {
		if point_in_rect(x, y, settings_cores_page_rect(layout, i)) {
			if options[i] < 0 {
				settings_use_custom_cores()
			} else {
				settings_set_cores_per_page(options[i])
			}
			return
		}
	}

	if is_core_page_custom() {
		if point_in_rect(x, y, settings_custom_minus_rect(layout)) {
			settings_adjust_custom_cores(-1)
			return
		}
		if point_in_rect(x, y, settings_custom_plus_rect(layout)) {
			settings_adjust_custom_cores(1)
			return
		}
	}

	for role in 0..<3 {
		palette := palette_for_role(role)
		for i in 0..<len(palette) {
			if point_in_rect(x, y, settings_swatch_rect(layout, role, i)) {
				settings_set_color(role, palette[i])
				return
			}
		}
		if point_in_rect(x, y, settings_custom_rect(layout, role)) {
			open_color_picker(role)
			return
		}
	}

	for i in 0..<len(THEMES) {
		if point_in_rect(x, y, settings_theme_rect(layout, i)) {
			settings_set_theme(i)
			return
		}
	}

	refresh_options := REFRESH_OPTIONS
	for i in 0..<len(refresh_options) {
		if point_in_rect(x, y, settings_refresh_chip_rect(layout, i)) {
			if refresh_options[i] < 0 {
				settings_use_custom_refresh()
			} else {
				settings_set_refresh_ms(refresh_options[i])
			}
			return
		}
	}

	if is_refresh_custom() {
		if point_in_rect(x, y, settings_refresh_minus_rect(layout)) {
			settings_adjust_custom_refresh(-REFRESH_STEP_MS)
			return
		}
		if point_in_rect(x, y, settings_refresh_plus_rect(layout)) {
			settings_adjust_custom_refresh(REFRESH_STEP_MS)
			return
		}
		if point_in_rect(x, y, settings_refresh_value_rect(layout)) {
			begin_refresh_edit()
			return
		}
	}

	dock_modes := [2]Dock_Mode{.top, .bottom}
	for i in 0..<len(dock_modes) {
		if point_in_rect(x, y, settings_dock_chip_rect(layout, i)) {
			settings_set_dock(dock_modes[i])
			return
		}
	}
}

handle_refresh_edit_char :: proc(ch: int) {
	switch ch {
	case '0'..='9':
		if app.refresh_edit_len < len(app.refresh_edit_buf) {
			// The field opens with the current value selected; the first digit
			// types over it instead of appending.
			if app.refresh_edit_replace {
				app.refresh_edit_len = 0
				app.refresh_edit_replace = false
			}
			app.refresh_edit_buf[app.refresh_edit_len] = u8(ch)
			app.refresh_edit_len += 1
			_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
		}
	case 8: // backspace
		app.refresh_edit_replace = false
		if app.refresh_edit_len > 0 {
			app.refresh_edit_len -= 1
			_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
		}
	case 13: // enter
		commit_refresh_edit()
	case 27: // escape
		cancel_refresh_edit()
	}
}

handle_wheel :: proc(wparam: win.WPARAM) {
	if app.view != .tasks {
		return
	}

	pts: win.POINT
	_ = win.GetCursorPos(&pts)
	_ = win.ScreenToClient(app.hwnd, &pts)
	geo := tasks_geometry()
	if pts.x < geo.panel.left || pts.x >= geo.panel.right ||
	   pts.y < geo.list_top || pts.y >= geo.list_bottom {
		return
	}

	bits := u16((u64(wparam) >> 16) & 0xffff)
	delta := i32(i16(bits))
	steps := delta / 120
	if steps == 0 && delta != 0 {
		steps = 1
		if delta < 0 {
			steps = -1
		}
	}

	app.scroll -= int(steps) * 3
	clamp_scroll()
	_ = win.InvalidateRect(app.hwnd, nil, win.FALSE)
}
