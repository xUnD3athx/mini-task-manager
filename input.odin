package main

import "core:fmt"
import win "core:sys/windows"
import "core"
import "platform"
import "services"
import "ui"

// 鼠标/键盘输入：只修改状态，不绘制。

handle_click :: proc(lparam: win.LPARAM) {
	x := i32(lparam & 0xffff)
	y := i32((lparam >> 16) & 0xffff)

	if y >= 0 && y < core.app.bar_h {
		if core.point_in_rect(x, y, ui.tasks_button_rect()) {
			toggle_view(.tasks)
			return
		}
		if core.point_in_rect(x, y, ui.settings_button_rect()) {
			toggle_view(.settings)
			return
		}
		if core.point_in_rect(x, y, ui.exit_button_rect()) {
			_ = win.PostMessageW(core.app.hwnd, win.WM_CLOSE, 0, 0)
			return
		}
		// The empty part of a standalone bar drags the whole window; an
		// appbar stays where it is.
		if core.settings.dock == .standalone && !core.app.anim.active {
			drag_window()
		}
		return
	}

	// Drawer content is only reliable once the slide has settled.
	if core.app.anim.active {
		return
	}

	switch core.app.view {
	case .tasks:
		handle_tasks_click(x, y)
	case .settings:
		handle_settings_click(x, y)
	case .none:
	}
}

// Hands the bar over to the system move loop. Only standalone windows can be
// dragged; an appbar is pinned by Explorer.
drag_window :: proc() {
	_ = win.ReleaseCapture()
	_ = win.SendMessageW(core.app.hwnd, win.WM_NCLBUTTONDOWN, win.WPARAM(win.HTCAPTION), 0)
}

handle_tasks_click :: proc(x, y: i32) {
	band := ui.core_band_layout()
	if core.point_in_rect(x, y, band.prev) {
		core.app.core_page -= 1
		ui.clamp_core_page()
		_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
		return
	}
	if core.point_in_rect(x, y, band.next) {
		core.app.core_page += 1
		ui.clamp_core_page()
		_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
		return
	}

	// The end-task button spans the bottom of the monitoring column.
	if core.app.has_selection {
		view := ui.task_view_layout()
		slot := ui.end_task_button_rect(view.detail)
		if slot.right > slot.left && core.point_in_rect(x, y, slot) {
			handle_end_task_click(x, y, slot)
			return
		}
	}

	geo := ui.tasks_geometry()
	if geo.panel.right <= geo.panel.left {
		return
	}

	for i in 0..<len(core.RISK_TIERS) {
		if core.point_in_rect(x, y, ui.task_risk_chip_rect(geo.panel, i)) {
			core.settings_toggle_risk_tier(core.RISK_TIERS[i])
			services.rebuild_task_rows()
			services.clear_hidden_selection()
			ui.clamp_scroll()
			_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
			return
		}
	}

	if geo.visible <= 0 {
		return
	}

	for i in 0..<len(core.SORT_FIELD_LABELS) {
		if core.point_in_rect(x, y, ui.task_sort_chip_rect(geo.panel, i)) {
			settings_set_sort(core.Sort_Field(i))
			return
		}
	}

	if x < geo.panel.left || x >= geo.panel.right || y < geo.list_top || y >= geo.list_bottom {
		return
	}

	row := int((y - geo.list_top) / core.dip(core.TASK_ROW_HEIGHT_DIP))
	index := core.app.scroll + row
	if row < geo.visible && index >= 0 && index < core.app.task_row_count {
		item := core.app.task_rows[index]
		switch item.kind {
		case .group:
			g := &core.app.groups[item.index]
			// Only the triangle toggles the subtree; the rest of the row selects
			// the whole application.
			if x < geo.panel.left + core.dip(34) {
				services.group_set_expanded(g.name, !services.group_is_expanded(g.name))
				services.rebuild_task_rows()
				ui.clamp_scroll()
				_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
				return
			}

			if !core.app.group_selected || !services.same_task_name(core.app.selected_group, g.name) {
				core.app.task = core.Task_Metrics{group_mode = true, group = g.name}
			}
			core.kill_arm_clear()
			core.app.selected_group = g.name
			core.app.group_selected = true
			core.app.has_selection = true
			services.refresh_window_preview()
			_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
		case .process:
			p := &core.app.processes[item.index]
			if core.app.group_selected || p.pid != core.app.selected_pid {
				core.app.task = core.Task_Metrics{pid = p.pid}
			}
			core.kill_arm_clear()
			core.app.selected_pid = p.pid
			core.app.group_selected = false
			core.app.has_selection = true
			services.refresh_window_preview()
			_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
		}
	}
}

// Ends the selected task directly when it is safe, and asks otherwise by
// turning the button into confirm/cancel.
handle_end_task_click :: proc(x, y: i32, slot: win.RECT) {
	if core.kill_arm_active() {
		if core.point_in_rect(x, y, ui.end_task_confirm_rect(slot)) {
			execute_end_task()
		} else if core.point_in_rect(x, y, ui.end_task_cancel_rect(slot)) {
			core.kill_arm_clear()
			_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
		}
		return
	}

	if ui.end_task_disabled() {
		return
	}

	if ui.selected_kill_risk() == .safe {
		execute_end_task()
		return
	}

	core.kill_arm_set()
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

execute_end_task :: proc() {
	killed, total, err := services.terminate_selected_task()
	core.kill_arm_clear()

	// The two-second process timer is too slow here: the ended task is usually
	// the selected one, and its detail page must not survive it.
	services.refresh_processes()
	services.update_task_metrics()
	services.refresh_window_preview()
	ui.clamp_scroll()

	if err != 0 {
		show_end_task_error(killed, total, err)
	}
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

show_end_task_error :: proc(killed, total: int, err: win.DWORD) {
	message_buf: [768]u8
	message: string
	if killed > 0 {
		message = fmt.bprintf(message_buf[:],
			"Ended %d of %d processes.\r\n\r\nThe last one failed with error %d. " +
			"Processes owned by another user or running elevated need administrator rights.",
			killed, total, err)
	} else {
		message = fmt.bprintf(message_buf[:],
			"Could not end the task (error %d).\r\n\r\n" +
			"Processes owned by another user or running elevated need administrator rights.",
			err)
	}

	text_buf: [800]u16
	title_buf: [64]u16
	text := win.utf8_to_wstring_buf(text_buf[:], message)
	caption := win.utf8_to_wstring_buf(title_buf[:], "MiniTaskManager")
	if text == nil || caption == nil {
		return
	}

	core.app.modal_open = true
	_ = win.MessageBoxW(core.app.hwnd, text, caption, win.MB_OK | win.MB_ICONERROR)
	core.app.modal_open = false
}

handle_settings_click :: proc(x, y: i32) {
	layout := ui.settings_layout()

	// Clicking anywhere else finishes an in-progress interval edit.
	if core.app.refresh_edit {
		core.commit_refresh_edit()
	}

	if core.point_in_rect(x, y, layout.reset) {
		core.reset_settings()
		services.sort_processes(core.app.processes[:core.app.process_count])
		services.build_task_groups()
		ui.clamp_scroll()
		return
	}

	// The page scrolls under the header; only the body holds controls.
	if x < layout.body.left || x >= layout.body.right ||
	   y < layout.body.top || y >= layout.body.bottom {
		return
	}

	for i in 0..<7 {
		if core.point_in_rect(x, y, ui.settings_module_row(layout, i)) {
			id := core.Module_Id(i)
			if id == .cores && !core.settings.modules.cpu {
				return
			}
			core.settings_toggle_module(id)
			return
		}
	}

	options := core.CORE_PAGE_OPTIONS
	for i in 0..<len(options) {
		if core.point_in_rect(x, y, ui.settings_cores_page_rect(layout, i)) {
			if options[i] < 0 {
				settings_use_custom_cores()
			} else {
				settings_set_cores_per_page(options[i])
			}
			return
		}
	}

	if ui.is_core_page_custom() {
		if core.point_in_rect(x, y, ui.settings_custom_minus_rect(layout)) {
			settings_adjust_custom_cores(-1)
			return
		}
		if core.point_in_rect(x, y, ui.settings_custom_plus_rect(layout)) {
			settings_adjust_custom_cores(1)
			return
		}
	}

	for role in 0..<3 {
		palette := core.palette_for_role(role)
		for i in 0..<len(palette) {
			if core.point_in_rect(x, y, ui.settings_swatch_rect(layout, role, i)) {
				core.settings_set_color(role, palette[i])
				return
			}
		}
		if core.point_in_rect(x, y, ui.settings_custom_rect(layout, role)) {
			core.open_color_picker(role)
			return
		}
	}

	for i in 0..<len(core.THEMES) {
		if core.point_in_rect(x, y, ui.settings_theme_rect(layout, i)) {
			core.settings_set_theme(i)
			return
		}
	}

	refresh_options := core.REFRESH_OPTIONS
	for i in 0..<len(refresh_options) {
		if core.point_in_rect(x, y, ui.settings_refresh_chip_rect(layout, i)) {
			if refresh_options[i] < 0 {
				core.settings_use_custom_refresh()
			} else {
				core.settings_set_refresh_ms(refresh_options[i])
			}
			return
		}
	}

	if core.is_refresh_custom() {
		if core.point_in_rect(x, y, ui.settings_refresh_minus_rect(layout)) {
			core.settings_adjust_custom_refresh(-core.REFRESH_STEP_MS)
			return
		}
		if core.point_in_rect(x, y, ui.settings_refresh_plus_rect(layout)) {
			core.settings_adjust_custom_refresh(core.REFRESH_STEP_MS)
			return
		}
		if core.point_in_rect(x, y, ui.settings_refresh_value_rect(layout)) {
			core.begin_refresh_edit()
			return
		}
	}

	dock_modes := [2]core.Dock_Mode{.top, .standalone}
	for i in 0..<len(dock_modes) {
		if core.point_in_rect(x, y, ui.settings_dock_chip_rect(layout, i)) {
			settings_set_dock(dock_modes[i])
			return
		}
	}

	if core.point_in_rect(x, y, ui.settings_unsafe_row_rect(layout)) {
		core.settings_toggle_unsafe_kill()
		return
	}
}

handle_refresh_edit_char :: proc(ch: int) {
	switch ch {
	case '0'..='9':
		if core.app.refresh_edit_len < len(core.app.refresh_edit_buf) {
			// The field opens with the current value selected; the first digit
			// types over it instead of appending.
			if core.app.refresh_edit_replace {
				core.app.refresh_edit_len = 0
				core.app.refresh_edit_replace = false
			}
			core.app.refresh_edit_buf[core.app.refresh_edit_len] = u8(ch)
			core.app.refresh_edit_len += 1
			_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
		}
	case 8: // backspace
		core.app.refresh_edit_replace = false
		if core.app.refresh_edit_len > 0 {
			core.app.refresh_edit_len -= 1
			_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
		}
	case 13: // enter
		core.commit_refresh_edit()
	case 27: // escape
		core.cancel_refresh_edit()
	}
}

handle_wheel :: proc(wparam: win.WPARAM) {
	if core.app.anim.active || core.app.view == .none {
		return
	}

	pts: win.POINT
	_ = win.GetCursorPos(&pts)
	_ = win.ScreenToClient(core.app.hwnd, &pts)

	steps := wheel_steps(wparam)
	if steps == 0 {
		return
	}

	switch core.app.view {
	case .tasks:
		geo := ui.tasks_geometry()
		if pts.x < geo.panel.left || pts.x >= geo.panel.right ||
		   pts.y < geo.list_top || pts.y >= geo.list_bottom {
			return
		}
		core.app.scroll -= int(steps) * 3
		ui.clamp_scroll()
	case .settings:
		layout := ui.settings_layout()
		if layout.scroll_max <= 0 ||
		   pts.x < layout.body.left || pts.x >= layout.body.right ||
		   pts.y < layout.body.top || pts.y >= layout.body.bottom {
			return
		}
		core.app.settings_scroll -= steps * core.dip(core.SETTINGS_SCROLL_STEP_DIP)
		ui.clamp_settings_scroll()
	case .none:
		return
	}
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

wheel_steps :: proc(wparam: win.WPARAM) -> i32 {
	bits := u16((u64(wparam) >> 16) & 0xffff)
	delta := i32(i16(bits))
	steps := delta / 120
	if steps == 0 && delta != 0 {
		steps = 1
		if delta < 0 {
			steps = -1
		}
	}
	return steps
}

settings_set_dock :: proc(mode: core.Dock_Mode) {
	if core.settings.dock == mode {
		return
	}
	core.settings.dock = mode
	core.app.deactivate_guard_until = platform.GetTickCount64() + 600
	core.save_settings()
	cancel_drawer_anim()

	if mode == .top {
		// The appbar drawer has its own height; the standalone one left the
		// shared value sized to the floating window.
		update_screen_metrics()
		if !core.app.appbar_registered {
			register_appbar(core.app.hwnd)
		}
		position_appbar(core.app.hwnd)
	} else {
		enter_standalone(core.app.hwnd)
	}
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

settings_set_cores_per_page :: proc(per: int) {
	if per < 0 || per > core.MAX_CORES {
		return
	}
	core.settings.cores_per_page = per
	if per <= 0 {
		core.settings.cores_custom_mode = false
	} else if per == 4 || per == 6 || per == 8 || per == 16 {
		core.settings.cores_custom_mode = false
	} else {
		core.settings.cores_custom_mode = true
		core.settings.cores_custom = per
	}
	core.app.core_page = 0
	ui.clamp_core_page()
	core.save_settings()
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

settings_use_custom_cores :: proc() {
	max_per := max(core.app.cores, 1)
	core.settings.cores_custom_mode = true
	core.settings.cores_custom = clamp(core.settings.cores_custom, 1, max_per)
	core.settings.cores_per_page = core.settings.cores_custom
	core.app.core_page = 0
	ui.clamp_core_page()
	core.save_settings()
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

settings_adjust_custom_cores :: proc(delta: int) {
	max_per := max(core.app.cores, 1)
	base := clamp(core.settings.cores_per_page, 1, max_per)
	per := clamp(base + delta, 1, max_per)
	core.settings.cores_custom = per
	core.settings.cores_per_page = per
	core.settings.cores_custom_mode = true
	core.app.core_page = 0
	ui.clamp_core_page()
	core.save_settings()
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}

settings_set_sort :: proc(field: core.Sort_Field) {
	if core.settings.sort_field == field {
		core.settings.sort_desc = !core.settings.sort_desc
	} else {
		core.settings.sort_field = field
		core.settings.sort_desc = true
	}
	services.sort_processes(core.app.processes[:core.app.process_count])
	services.build_task_groups()
	core.save_settings()
	_ = win.InvalidateRect(core.app.hwnd, nil, win.FALSE)
}
