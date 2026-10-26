package main

import "core:fmt"
import win "core:sys/windows"

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
	draw_bar(dc)
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
	fill_round(dc, rect, app.brushes.card, app.pens.border, S(10))
}

draw_bar :: proc(dc: win.HDC) {
	bar := win.RECT{0, 0, app.width, app.bar_h}
	_ = win.FillRect(dc, &bar, app.brushes.sidebar)

	draw_tasks_button(dc)

	gap := S(BAR_SECTION_GAP_DIP)
	x := S(BAR_PADDING_DIP) + S(TASKS_BUTTON_W_DIP)
	right_limit := app.width - S(BAR_PADDING_DIP) - S(BAR_RIGHT_RESERVE_DIP)

	cpu_w := S(180)
	cores_w := S(140)
	mem_w := S(220)
	gpu_w := S(160)
	disk_w := S(160)
	net_w := S(180)
	uptime_w := S(104)

	show_cpu := module_enabled(.cpu)
	show_cores := show_cpu && module_enabled(.cores)
	show_mem := module_enabled(.memory)
	show_gpu := module_enabled(.gpu)
	show_disk := module_enabled(.disk)
	show_net := module_enabled(.network)
	show_uptime := module_enabled(.uptime)

	total: i32 = 0
	if show_cpu {
		total += cpu_w + gap
	}
	if show_cores {
		total += cores_w + gap
	}
	if show_mem {
		total += mem_w + gap
	}
	if show_gpu {
		total += gpu_w + gap
	}
	if show_disk {
		total += disk_w + gap
	}
	if show_net {
		total += net_w + gap
	}
	if show_uptime {
		total += uptime_w + gap
	}

	available := right_limit - (x + gap)
	if total > available && show_uptime {
		show_uptime = false
		total -= uptime_w + gap
	}
	if total > available && show_disk {
		show_disk = false
		total -= disk_w + gap
	}
	if total > available && show_cores {
		show_cores = false
		total -= cores_w + gap
	}
	if total > available && show_net {
		show_net = false
		total -= net_w + gap
	}
	if total > available && show_gpu {
		show_gpu = false
		total -= gpu_w + gap
	}
	if total > available && show_mem {
		show_mem = false
		total -= mem_w + gap
	}

	x += gap
	if show_cpu {
		draw_bar_divider(dc, x - gap/2)
		draw_bar_cpu(dc, x, cpu_w)
		x += cpu_w + gap
	}
	if show_cores {
		draw_bar_divider(dc, x - gap/2)
		draw_bar_cores(dc, x, cores_w)
		x += cores_w + gap
	}
	if show_mem {
		draw_bar_divider(dc, x - gap/2)
		draw_bar_memory(dc, x, mem_w)
		x += mem_w + gap
	}
	if show_gpu {
		draw_bar_divider(dc, x - gap/2)
		draw_bar_gpu(dc, x, gpu_w)
		x += gpu_w + gap
	}
	if show_disk {
		draw_bar_divider(dc, x - gap/2)
		draw_bar_disk(dc, x, disk_w)
		x += disk_w + gap
	}
	if show_net {
		draw_bar_divider(dc, x - gap/2)
		draw_bar_network(dc, x, net_w)
		x += net_w + gap
	}
	if show_uptime {
		draw_bar_divider(dc, x - gap/2)
		draw_bar_uptime(dc, x, uptime_w)
	}

	exit := exit_button_rect()
	settings := settings_button_rect()

	draw_settings_button(dc, settings)

	draw_text(dc, "×", exit.left, exit.top, exit.right - exit.left, exit.bottom - exit.top,
		app.fonts.med, COL_MUTED, DT_CENTER | DT_VCENTER | DT_SINGLELINE)

	border := win.RECT{0, app.bar_h - 1, app.width, app.bar_h}
	_ = win.FillRect(dc, &border, app.brushes.line)
}

draw_bar_divider :: proc(dc: win.HDC, x: i32) {
	divider := win.RECT{x, S(15), x + 1, app.bar_h - S(15)}
	_ = win.FillRect(dc, &divider, app.brushes.line)
}

draw_tasks_button :: proc(dc: win.HDC) {
	rect := tasks_button_rect()
	background := app.brushes.badge
	if app.view == .tasks {
		background = app.brushes.selected
	}

	inner := win.RECT{rect.left + S(3), S(7), rect.right - S(3), app.bar_h - S(7)}
	fill_round(dc, inner, background, app.pens.null, S(10))

	icon_size := S(28)
	icon_x := rect.left + S(11)
	icon_y := (app.bar_h - icon_size) / 2
	icon_rect := win.RECT{icon_x, icon_y, icon_x + icon_size, icon_y + icon_size}
	fill_round(dc, icon_rect, app.brushes.accent, app.pens.null, S(8))

	line_w := S(12)
	line_h := max(S(2), 1)
	line_x := icon_x + (icon_size - line_w) / 2
	for i in 0..<3 {
		line_y := icon_y + icon_size/2 + i32(i-1)*S(5) - line_h/2
		r := win.RECT{line_x, line_y, line_x + line_w, line_y + line_h}
		_ = win.FillRect(dc, &r, app.brushes.dark)
	}

	text_x := rect.left + S(52)
	text_w := rect.right - S(36) - text_x
	draw_text(dc, "TASKS", text_x, S(16), text_w, S(11),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	count_buf: [32]u8
	count_text := fmt.bprintf(count_buf[:], "%d", app.process_count)
	draw_text(dc, count_text, text_x, S(28), text_w, S(20),
		app.fonts.stat, COL_TEXT, DT_LEFT | DT_SINGLELINE)

	chevron := "▾"
	if app.view == .tasks {
		chevron = "▴"
	}
	draw_text(dc, chevron, rect.right - S(26), 0, S(18), app.bar_h,
		app.fonts.small, COL_MUTED, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
}

draw_settings_button :: proc(dc: win.HDC, rect: win.RECT) {
	if app.view == .settings {
		fill_round(dc, rect, app.brushes.selected, app.pens.null, S(7))
	}

	center_x := (rect.left + rect.right) / 2
	center_y := (rect.top + rect.bottom) / 2
	line_w := S(15)
	line_h := max(S(2), 1)

	for i in 0..<3 {
		y := center_y + i32(i-1)*S(5)
		line := win.RECT{center_x - line_w/2, y - line_h/2, center_x + line_w/2, y + line_h/2}
		_ = win.FillRect(dc, &line, app.brushes.muted)

		knob_x_ratio: i32 = 3
		if i == 1 {
			knob_x_ratio = 8
		} else if i == 2 {
			knob_x_ratio = 5
		}
		knob_x := center_x - line_w/2 + line_w*knob_x_ratio/10 - S(2)
		knob := win.RECT{knob_x, y - S(3), knob_x + S(4), y + S(3)}
		_ = win.FillRect(dc, &knob, app.brushes.accent)
	}
}

draw_bar_cpu :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "CPU", x, w)

	buf: [32]u8
	value := fmt.bprintf(buf[:], "%d%%", i32(app.cpu + 0.5))
	sub_buf: [32]u8
	sub := fmt.bprintf(sub_buf[:], "%d cores", app.cores)
	draw_bar_value(dc, x, w - S(76), value, sub)

	spark := win.RECT{x + w - S(70), S(18), x + w, S(48)}
	draw_sparkline(dc, spark, app.cpu_samples[:], app.pens.cpu, app.brushes.cpu_fill)
}

draw_bar_memory :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "MEMORY", x, w)

	buf: [32]u8
	value := fmt.bprintf(buf[:], "%d%%", i32(app.mem_percent + 0.5))
	sub_buf: [48]u8
	sub := fmt.bprintf(sub_buf[:], "%.1f/%.1f GB", app.mem_used, app.mem_total)
	draw_bar_value(dc, x, w - S(76), value, sub)

	spark := win.RECT{x + w - S(70), S(18), x + w, S(48)}
	draw_sparkline(dc, spark, app.mem_samples[:], app.pens.mem, app.brushes.mem_fill)
}

draw_bar_gpu :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "GPU", x, w)

	value := "—"
	sub := "unavailable"
	value_buf: [32]u8
	sub_buf: [48]u8
	if app.gpu_ok {
		value = fmt.bprintf(value_buf[:], "%d%%", i32(app.gpu + 0.5))
		if app.gpu_mem_ok {
			sub = fmt.bprintf(sub_buf[:], "VRAM %.1f GB", app.gpu_vram)
		} else {
			sub = "engine load"
		}
	}
	draw_bar_value(dc, x, w - S(76), value, sub)

	if app.gpu_ok {
		spark := win.RECT{x + w - S(70), S(18), x + w, S(48)}
		draw_sparkline(dc, spark, app.gpu_samples[:], app.pens.gpu, app.brushes.gpu_fill)
	}
}

draw_bar_cores :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "PER-CORE", x, w)
	if app.cores <= 0 {
		return
	}

	top := S(23)
	bottom := S(53)
	height := bottom - top
	if height <= 0 {
		return
	}

	gap := max(S(1), 1)
	bar_w := (w - gap*i32(app.cores-1)) / i32(app.cores)
	if bar_w < 1 {
		return
	}

	for i in 0..<app.cores {
		bx := x + i32(i)*(bar_w + gap)
		track := win.RECT{bx, top, bx + bar_w, bottom}
		_ = win.FillRect(dc, &track, app.brushes.track)

		v := app.core_usage[i]
		if v < 0 {
			v = 0
		}
		if v > 100 {
			v = 100
		}
		fill_h := i32(f32(height) * v / 100.0)
		if fill_h > 0 {
			fill := win.RECT{bx, bottom - fill_h, bx + bar_w, bottom}
			_ = win.FillRect(dc, &fill, app.brushes.accent)
		}
	}
}

draw_bar_disk :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "DISK", x, w)

	value := "—"
	sub := "unavailable"
	value_buf: [32]u8
	sub_buf: [48]u8
	if app.pdh_ok {
		total := app.disk_read_bps + app.disk_write_bps
		factor, suffix := rate_scale(total)
		value = fmt.bprintf(value_buf[:], "%.1f %s", total/factor, suffix)
		sub = fmt.bprintf(sub_buf[:], "R %.1f · W %.1f", app.disk_read_bps/factor, app.disk_write_bps/factor)
	}
	draw_bar_value(dc, x, w, value, sub)
}

draw_bar_network :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "NETWORK", x, w)

	value := "—"
	sub := "unavailable"
	value_buf: [32]u8
	sub_buf: [48]u8
	if app.net_ok {
		if !app.net_online {
			sub = "offline"
		} else {
			total := app.net_in_bps + app.net_out_bps
			factor, suffix := rate_scale(total)
			value = fmt.bprintf(value_buf[:], "%.1f %s", total/factor, suffix)
			sub = fmt.bprintf(sub_buf[:], "↓ %.1f · ↑ %.1f", app.net_in_bps/factor, app.net_out_bps/factor)
		}
	}
	draw_bar_value(dc, x, w, value, sub)
}

draw_bar_uptime :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "UPTIME", x, w)
	buf: [48]u8
	value := format_uptime(buf[:])
	draw_bar_value(dc, x, w, value, "system")
}

draw_bar_label :: proc(dc: win.HDC, label: string, x, w: i32) {
	draw_text(dc, label, x, S(7), w, S(11),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
}

draw_bar_value :: proc(dc: win.HDC, x, w: i32, value: string, sub: string) {
	draw_text(dc, value, x, S(18), w, S(24),
		app.fonts.stat, COL_TEXT, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
	draw_text(dc, sub, x, S(43), w, S(12),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
}

draw_sparkline :: proc(
	dc: win.HDC,
	rect: win.RECT,
	samples: []f32,
	line_pen: win.HPEN,
	fill_brush: win.HBRUSH,
) {
	width := rect.right - rect.left
	height := rect.bottom - rect.top
	if width < S(8) || height < S(8) {
		return
	}

	count := min(len(samples), SAMPLE_COUNT)
	if count < 2 {
		return
	}

	points: [SAMPLE_COUNT + 2]win.POINT
	points[0] = win.POINT{rect.left, rect.bottom}

	for i in 0..<count {
		v := samples[i]
		if v < 0 {
			v = 0
		}
		if v > 100 {
			v = 100
		}
		px := rect.left + i32(i)*(width - 1)/i32(count - 1)
		py := rect.bottom - i32(v*f32(height)/100.0)
		points[i + 1] = win.POINT{px, py}
	}
	points[count + 1] = win.POINT{rect.right, rect.bottom}

	_ = win.SelectObject(dc, win.HGDIOBJ(fill_brush))
	_ = win.SelectObject(dc, win.HGDIOBJ(app.pens.null))
	_ = win.Polygon(dc, raw_data(points[:]), i32(count + 2))

	_ = win.SelectObject(dc, win.HGDIOBJ(line_pen))
	_ = Polyline(dc, raw_data(points[1:]), i32(count))
}

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
	geo := tasks_geometry()
	if geo.panel.right <= geo.panel.left {
		return
	}
	draw_tasks_panel(dc, geo)

	right_x := geo.panel.right + S(18)
	right := app.width - S(18)
	if right - right_x <= S(220) {
		hide_preview_thumbnail()
		return
	}

	// Selecting a task turns the right side into that task's detail page.
	if app.has_selection {
		draw_task_view(dc, right_x, right, geo.panel.top, geo.panel.bottom)
		return
	}
	hide_preview_thumbnail()

	gap := S(18)
	panel_h := geo.panel.bottom - geo.panel.top

	stats_h := S(90)
	cards_h := panel_h - stats_h - gap
	if cards_h < S(170) {
		cards_h = panel_h
		stats_h = 0
	}

	card_kinds: [3]int
	card_count := 0
	if settings.modules.cpu {
		card_kinds[card_count] = 0
		card_count += 1
	}
	if settings.modules.memory {
		card_kinds[card_count] = 1
		card_count += 1
	}
	if settings.modules.gpu {
		card_kinds[card_count] = 2
		card_count += 1
	}

	if card_count > 0 {
		card_w := (right - right_x - gap*i32(card_count-1)) / i32(card_count)
		for i in 0..<card_count {
			left := right_x + i32(i)*(card_w + gap)
			rect := win.RECT{left, geo.panel.top, left + card_w, geo.panel.top + cards_h}
			switch card_kinds[i] {
			case 0:
				draw_cpu_card(dc, rect)
			case 1:
				draw_memory_card(dc, rect)
			case 2:
				draw_gpu_card(dc, rect)
			}
		}
	} else {
		placeholder := win.RECT{right_x, geo.panel.top, right, geo.panel.top + cards_h}
		draw_card(dc, placeholder)
		draw_text(dc, "No performance modules enabled", placeholder.left + S(18), placeholder.top + S(22),
			placeholder.right - placeholder.left - S(36), S(24),
			app.fonts.small, COL_TEXT, DT_LEFT | DT_SINGLELINE)
		draw_text(dc, "Open Settings from the top bar to enable CPU, memory or GPU.", placeholder.left + S(18),
			placeholder.top + S(48), placeholder.right - placeholder.left - S(36), S(18),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
	}

	if stats_h > 0 {
		stats_rect := win.RECT{right_x, geo.panel.top + cards_h + gap, right, geo.panel.top + cards_h + gap + stats_h}
		draw_stats_row(dc, stats_rect)
	}
}

// Detail page for the selected task: its window on the left, its own metrics on
// the right.
draw_task_view :: proc(dc: win.HDC, left, right, top, bottom: i32) {
	gap := S(18)
	detail_rect := win.RECT{left, top, right, bottom}
	show_preview := false

	if preview_is_alive() {
		width := right - left
		preview_w := clamp(width * 46 / 100, S(320), S(900))
		if width - preview_w - gap >= S(420) {
			preview_rect := win.RECT{left, top, left + preview_w, bottom}
			detail_rect = win.RECT{left + preview_w + gap, top, right, bottom}
			draw_window_preview(dc, preview_rect)
			show_preview = true
		}
	}
	if !show_preview {
		hide_preview_thumbnail()
	}

	draw_task_detail(dc, detail_rect)
}

draw_task_detail :: proc(dc: win.HDC, rect: win.RECT) {
	draw_card(dc, rect)

	pad := S(20)
	inner_x := rect.left + pad
	inner_w := rect.right - pad - inner_x
	if inner_w < S(80) || rect.bottom - rect.top < S(200) {
		return
	}

	p, found := find_process(app.selected_pid)

	// Header: process name and PID.
	pid_buf: [32]u8
	pid_text := fmt.bprintf(pid_buf[:], "PID %d", app.selected_pid)
	pid_w := S(120)
	if found {
		draw_text_w(dc, win.wstring(raw_data(p.name[:])), inner_x, rect.top + S(14),
			inner_w - pid_w - S(10), S(28), app.fonts.title, COL_TEXT,
			DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)
	} else {
		draw_text(dc, "—", inner_x, rect.top + S(14), inner_w - pid_w - S(10), S(28),
			app.fonts.title, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	}
	draw_text(dc, pid_text, rect.right - pad - pid_w, rect.top + S(20), pid_w, S(18),
		app.fonts.small, COL_MUTED, DT_RIGHT | DT_SINGLELINE)

	divider_y := rect.top + S(54)
	divider := win.RECT{inner_x, divider_y, rect.right - pad, divider_y + 1}
	_ = win.FillRect(dc, &divider, app.brushes.line)

	// CPU headline and total CPU time.
	draw_text(dc, "TASK CPU", inner_x, rect.top + S(70), inner_w, S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	cpu_buf: [16]u8
	cpu_value := "—"
	if found {
		cpu_value = fmt.bprintf(cpu_buf[:], "%d%%", i32(p.cpu_percent + 0.5))
	}
	draw_text(dc, cpu_value, inner_x, rect.top + S(86), inner_w, S(46),
		app.fonts.huge, COL_TEXT, DT_LEFT | DT_SINGLELINE)

	if found {
		time_buf: [32]u8
		time_label_buf: [64]u8
		time_value := format_cpu_time(time_buf[:], p.cpu_time)
		time_label := fmt.bprintf(time_label_buf[:], "CPU time %s", time_value)
		draw_text(dc, time_label, inner_x, rect.top + S(132), inner_w, S(16),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	}

	// Metric tiles are anchored to the bottom so the sparkline can grow.
	tile_gap := S(18)
	tile_w := (inner_w - tile_gap*2) / 3
	row2_y := rect.bottom - pad - S(42)
	row1_y := row2_y - S(56)

	spark_top := rect.top + S(156)
	spark_bottom := row1_y - S(20)
	if spark_bottom - spark_top >= S(58) {
		draw_text(dc, "CPU HISTORY", inner_x, spark_top, inner_w, S(14),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)
		spark := win.RECT{inner_x, spark_top + S(18), rect.right - pad, spark_bottom}
		draw_sparkline(dc, spark, app.task.cpu_samples[:], app.pens.cpu, app.brushes.cpu_fill)
	}

	mem_buf: [32]u8
	threads_buf: [16]u8
	handles_buf: [16]u8
	read_buf: [32]u8
	write_buf: [32]u8
	gpu_buf: [16]u8

	mem_text := "—"
	threads_text := "—"
	if found {
		mem_text = format_memory(mem_buf[:], p.working_set)
		threads_text = fmt.bprintf(threads_buf[:], "%d", p.threads)
	}

	handles_text := "—"
	if app.task.handles > 0 {
		handles_text = fmt.bprintf(handles_buf[:], "%d", app.task.handles)
	}

	read_factor, read_suffix := rate_scale(app.task.read_bps)
	read_text := fmt.bprintf(read_buf[:], "%.1f %s", app.task.read_bps/read_factor, read_suffix)
	write_factor, write_suffix := rate_scale(app.task.write_bps)
	write_text := fmt.bprintf(write_buf[:], "%.1f %s", app.task.write_bps/write_factor, write_suffix)

	gpu_text := "—"
	if app.gpu_ok {
		gpu_text = fmt.bprintf(gpu_buf[:], "%d%%", i32(app.task.gpu + 0.5))
	}

	if row1_y - S(20) > rect.top + S(170) {
		draw_metric_tile(dc, inner_x, row1_y, tile_w, mem_text, "MEMORY")
		draw_metric_tile(dc, inner_x + tile_w + tile_gap, row1_y, tile_w, threads_text, "THREADS")
		draw_metric_tile(dc, inner_x + (tile_w + tile_gap)*2, row1_y, tile_w, handles_text, "HANDLES")

		draw_metric_tile(dc, inner_x, row2_y, tile_w, read_text, "I/O READ")
		draw_metric_tile(dc, inner_x + tile_w + tile_gap, row2_y, tile_w, write_text, "I/O WRITE")
		draw_metric_tile(dc, inner_x + (tile_w + tile_gap)*2, row2_y, tile_w, gpu_text, "GPU")
	}
}

draw_metric_tile :: proc(dc: win.HDC, x, y, w: i32, value, label: string) {
	draw_text(dc, value, x, y, w, S(28), app.fonts.med, COL_TEXT,
		DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
	draw_text(dc, label, x, y + S(26), w, S(14), app.fonts.tiny, COL_MUTED,
		DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
}

draw_window_preview :: proc(dc: win.HDC, rect: win.RECT) {
	draw_card(dc, rect)

	pad := S(16)
	inner_x := rect.left + pad
	inner_w := rect.right - rect.left - pad*2
	if inner_w < S(80) {
		return
	}

	draw_text(dc, "WINDOW", inner_x, rect.top + S(14), inner_w, S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	if len(app.preview.title) > 0 && app.preview.title[0] != 0 {
		draw_text_w(dc, win.wstring(raw_data(app.preview.title[:])), inner_x, rect.top + S(30),
			inner_w, S(20), app.fonts.small, COL_TEXT,
			DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)
	}

	content := win.RECT{inner_x, rect.top + S(58), rect.right - pad, rect.bottom - pad}
	if content.bottom <= content.top || content.right <= content.left {
		return
	}
	fill_round(dc, content, app.brushes.dark, app.pens.border, S(8))
	draw_preview_thumbnail(content)
}

draw_tasks_panel :: proc(dc: win.HDC, geo: Tasks_Geometry) {
	draw_card(dc, geo.panel)

	draw_text(dc, "Tasks", geo.panel.left + S(20), geo.panel.top + S(12),
		geo.panel.right - geo.panel.left - S(110), S(30),
		app.fonts.title, COL_TEXT, DT_LEFT | DT_VCENTER | DT_SINGLELINE)

	count_buf: [32]u8
	count_text := fmt.bprintf(count_buf[:], "%d", app.process_count)
	draw_text(dc, count_text, geo.panel.right - S(20) - S(70), geo.panel.top + S(16),
		S(70), S(20), app.fonts.small, COL_MUTED, DT_RIGHT | DT_VCENTER | DT_SINGLELINE)

	divider := win.RECT{geo.panel.left + S(18), geo.panel.top + S(58),
		geo.panel.right - S(18), geo.panel.top + S(59)}
	_ = win.FillRect(dc, &divider, app.brushes.line)

	if app.process_count == 0 {
		draw_text(dc, "No processes", geo.panel.left, geo.list_top,
			geo.panel.right - geo.panel.left, S(40),
			app.fonts.small, COL_MUTED, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
		return
	}

	row_h := S(TASK_ROW_HEIGHT_DIP)
	for row in 0..<geo.visible {
		index := app.scroll + row
		if index < 0 || index >= app.process_count {
			break
		}
		y := geo.list_top + i32(row)*row_h
		draw_process_row(dc, &app.processes[index], geo.panel.left, geo.panel.right, y, row_h)
	}

	draw_list_scrollbar(dc, geo.panel.right, geo.list_top, geo.list_bottom, geo.visible)
}

draw_process_row :: proc(dc: win.HDC, p: ^Process, left, right, y, row_h: i32) {
	selected := app.has_selection && p.pid == app.selected_pid
	margin := S(12)

	if selected {
		row_rect := win.RECT{left + margin, y + 1, right - margin, y + row_h - S(2)}
		fill_round(dc, row_rect, app.brushes.selected, app.pens.null, S(9))

		stripe := win.RECT{left + margin + S(2), y + S(13), left + margin + S(5), y + row_h - S(13)}
		_ = win.FillRect(dc, &stripe, app.brushes.accent)
	}

	badge_size := S(28)
	bx := left + margin + S(13)
	by := y + (row_h - badge_size) / 2
	badge_rect := win.RECT{bx, by, bx + badge_size, by + badge_size}

	badge_brush := app.brushes.badge
	if selected {
		badge_brush = app.brushes.accent
	}
	fill_round(dc, badge_rect, badge_brush, app.pens.null, S(8))

	initial: u16 = 0
	for i in 0..<MAX_NAME_U16 {
		c := p.name[i]
		if c == 0 {
			break
		}
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			initial = c
			break
		}
	}
	if initial == 0 {
		initial = u16(p.name[0])
	}
	if initial >= 'a' && initial <= 'z' {
		initial -= 32
	}
	if initial != 0 {
		letter: [2]u16
		letter[0] = initial
		letter[1] = 0
		letter_color := COL_TEXT
		if selected {
			letter_color = COL_BADGE_TEXT
		}
		draw_text_w(dc, win.wstring(raw_data(letter[:])), badge_rect.left, badge_rect.top,
			badge_size, badge_size, app.fonts.badge, letter_color,
			DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	}

	tx := bx + badge_size + S(11)
	tw := right - margin - S(16) - tx
	if tw < S(20) {
		return
	}

	name := win.wstring(raw_data(p.name[:]))
	draw_text_w(dc, name, tx, y + S(6), tw, S(21), app.fonts.body, COL_TEXT,
		DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)

	sub_buf: [64]u8
	sub := fmt.bprintf(sub_buf[:], "PID %d  ·  %d threads", p.pid, p.threads)
	metric_w := S(100)
	left_w := tw - metric_w
	if left_w < S(40) {
		left_w = tw
	}
	draw_text(dc, sub, tx, y + S(27), left_w, S(16), app.fonts.tiny, COL_MUTED,
		DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	mem_buf: [32]u8
	cpu_buf: [16]u8
	right_buf: [64]u8
	mem_text := format_memory(mem_buf[:], p.working_set)
	cpu_text := fmt.bprintf(cpu_buf[:], "%d%%", i32(p.cpu_percent + 0.5))
	metrics := fmt.bprintf(right_buf[:], "%s · %s", mem_text, cpu_text)
	draw_text(dc, metrics, tx + tw - metric_w, y + S(27), metric_w, S(16),
		app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)
}

draw_list_scrollbar :: proc(dc: win.HDC, panel_right, list_top, list_bottom: i32, visible: int) {
	if visible <= 0 || app.process_count <= visible {
		return
	}
	track_x := panel_right - S(10)
	top := list_top
	bottom := list_bottom
	if bottom <= top {
		return
	}

	track_rect := win.RECT{track_x, top, track_x + S(3), bottom}
	_ = win.FillRect(dc, &track_rect, app.brushes.track)

	track_h := bottom - top
	thumb_h := max(S(26), track_h * i32(visible) / i32(app.process_count))
	max_scroll := max(app.process_count - visible, 1)
	travel := track_h - thumb_h
	if travel < 0 {
		travel = 0
	}
	thumb_y := top + travel * i32(app.scroll) / i32(max_scroll)

	thumb_rect := win.RECT{track_x, thumb_y, track_x + S(3), thumb_y + thumb_h}
	_ = win.FillRect(dc, &thumb_rect, app.brushes.thumb)
}

draw_cpu_card :: proc(dc: win.HDC, rect: win.RECT) {
	draw_card(dc, rect)

	pad := S(20)
	inner_x := rect.left + pad
	inner_w := (rect.right - pad) - inner_x
	if inner_w < S(40) {
		return
	}

	draw_text(dc, "CPU", inner_x, rect.top + S(15), inner_w, S(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	buf: [32]u8
	value := fmt.bprintf(buf[:], "%d%%", i32(app.cpu + 0.5))
	draw_text(dc, value, inner_x, rect.top + S(30), inner_w, S(46),
		app.fonts.huge, COL_TEXT, DT_LEFT | DT_SINGLELINE)

	sub_buf: [64]u8
	sub := fmt.bprintf(sub_buf[:], "%d logical processors", app.cores)
	draw_text(dc, sub, inner_x, rect.top + S(78), inner_w, S(16),
		app.fonts.small, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	card_h := rect.bottom - rect.top
	show_cores := card_h >= S(215) && app.cores > 0 && settings.modules.cores
	core_h := S(50)

	graph_top := rect.top + S(100)
	graph_bottom := rect.bottom - S(18)
	if show_cores {
		graph_bottom -= core_h + S(10)
	}

	if graph_bottom - graph_top > S(16) {
		graph_rect := win.RECT{inner_x, graph_top, rect.right - pad, graph_bottom}
		draw_graph(dc, graph_rect, app.cpu_samples[:], app.pens.cpu, app.brushes.cpu_fill)
	}

	if show_cores {
		core_top := rect.bottom - S(18) - core_h
		draw_core_strip(dc, inner_x, core_top, inner_w, core_h)
	}
}

draw_core_strip :: proc(dc: win.HDC, x, y, w, h: i32) {
	if app.cores <= 0 || w <= 0 {
		return
	}

	peak: f32 = 0
	for i in 0..<app.cores {
		if app.core_usage[i] > peak {
			peak = app.core_usage[i]
		}
	}

	draw_text(dc, "PER-CORE", x, y, w/2, S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	peak_buf: [32]u8
	peak_text := fmt.bprintf(peak_buf[:], "PEAK %d%%", i32(peak + 0.5))
	draw_text(dc, peak_text, x + w/2, y, w/2, S(14),
		app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)

	bars_top := y + S(16)
	bars_bottom := y + h
	bars_h := bars_bottom - bars_top
	if bars_h < S(4) {
		return
	}

	gap := max(S(2), 1)
	bar_w := (w - gap*i32(app.cores-1)) / i32(app.cores)
	if bar_w < 1 {
		return
	}

	for i in 0..<app.cores {
		bx := x + i32(i)*(bar_w + gap)
		track := win.RECT{bx, bars_top, bx + bar_w, bars_bottom}
		_ = win.FillRect(dc, &track, app.brushes.track)

		v := app.core_usage[i]
		if v < 0 {
			v = 0
		}
		if v > 100 {
			v = 100
		}
		fill_h := i32(f32(bars_h) * v / 100.0)
		if fill_h > 0 {
			fill := win.RECT{bx, bars_bottom - fill_h, bx + bar_w, bars_bottom}
			_ = win.FillRect(dc, &fill, app.brushes.accent)
		}
	}
}

draw_memory_card :: proc(dc: win.HDC, rect: win.RECT) {
	draw_card(dc, rect)

	pad := S(20)
	inner_x := rect.left + pad
	inner_w := (rect.right - pad) - inner_x
	if inner_w < S(40) {
		return
	}

	draw_text(dc, "MEMORY", inner_x, rect.top + S(15), inner_w, S(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	buf: [32]u8
	value := fmt.bprintf(buf[:], "%d%%", i32(app.mem_percent + 0.5))
	draw_text(dc, value, inner_x, rect.top + S(30), inner_w, S(46),
		app.fonts.huge, COL_TEXT, DT_LEFT | DT_SINGLELINE)

	sub_buf: [64]u8
	sub := fmt.bprintf(sub_buf[:], "%.1f GB of %.1f GB", app.mem_used, app.mem_total)
	draw_text(dc, sub, inner_x, rect.top + S(78), inner_w, S(16),
		app.fonts.small, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	card_h := rect.bottom - rect.top
	show_details := app.mem_details_ok && card_h >= S(215)
	details_h := S(50)

	graph_top := rect.top + S(100)
	graph_bottom := rect.bottom - S(18)
	if show_details {
		graph_bottom -= details_h + S(10)
	}

	if graph_bottom - graph_top > S(16) {
		graph_rect := win.RECT{inner_x, graph_top, rect.right - pad, graph_bottom}
		draw_graph(dc, graph_rect, app.mem_samples[:], app.pens.mem, app.brushes.mem_fill)
	}

	if show_details {
		details_top := rect.bottom - S(18) - details_h
		col_w := inner_w / 4

		avail_buf: [32]u8
		commit_buf: [48]u8
		cache_buf: [32]u8
		handle_buf: [32]u8

		draw_memory_detail(dc, inner_x, details_top, col_w, "AVAILABLE",
			fmt.bprintf(avail_buf[:], "%.1f GB", app.mem_available))
		draw_memory_detail(dc, inner_x + col_w, details_top, col_w, "COMMITTED",
			fmt.bprintf(commit_buf[:], "%.1f / %.1f GB", app.mem_committed, app.mem_commit_limit))
		draw_memory_detail(dc, inner_x + col_w*2, details_top, col_w, "CACHED",
			fmt.bprintf(cache_buf[:], "%.1f GB", app.mem_cached))
		draw_memory_detail(dc, inner_x + col_w*3, details_top, col_w, "HANDLES",
			fmt.bprintf(handle_buf[:], "%d", app.handle_count))
	}
}

draw_memory_detail :: proc(dc: win.HDC, x, y, w: i32, label: string, value: string) {
	draw_text(dc, label, x, y, w, S(14), app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	draw_text(dc, value, x, y + S(18), w, S(20), app.fonts.small, COL_TEXT,
		DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
}

draw_gpu_card :: proc(dc: win.HDC, rect: win.RECT) {
	draw_card(dc, rect)

	pad := S(20)
	inner_x := rect.left + pad
	inner_w := (rect.right - pad) - inner_x
	if inner_w < S(40) {
		return
	}

	draw_text(dc, "GPU", inner_x, rect.top + S(15), inner_w, S(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	if app.gpu_ok {
		buf: [32]u8
		value := fmt.bprintf(buf[:], "%d%%", i32(app.gpu + 0.5))
		draw_text(dc, value, inner_x, rect.top + S(30), inner_w, S(46),
			app.fonts.huge, COL_TEXT, DT_LEFT | DT_SINGLELINE)
	} else {
		draw_text(dc, "—", inner_x, rect.top + S(30), inner_w, S(46),
			app.fonts.huge, COL_TEXT, DT_LEFT | DT_SINGLELINE)
	}

	sub_buf: [64]u8
	sub := "GPU counters unavailable"
	if app.gpu_ok {
		if app.gpu_mem_ok {
			sub = fmt.bprintf(sub_buf[:], "Dedicated %.1f GB", app.gpu_vram)
		} else {
			sub = "engine utilization"
		}
	}
	draw_text(dc, sub, inner_x, rect.top + S(78), inner_w, S(16),
		app.fonts.small, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	if !app.gpu_ok {
		return
	}

	card_h := rect.bottom - rect.top
	show_engines := card_h >= S(215)
	engines_h := S(50)

	graph_top := rect.top + S(100)
	graph_bottom := rect.bottom - S(18)
	if show_engines {
		graph_bottom -= engines_h + S(10)
	}

	if graph_bottom - graph_top > S(16) {
		graph_rect := win.RECT{inner_x, graph_top, rect.right - pad, graph_bottom}
		draw_graph(dc, graph_rect, app.gpu_samples[:], app.pens.gpu, app.brushes.gpu_fill)
	}

	if show_engines {
		details_top := rect.bottom - S(18) - engines_h
		col_w := inner_w / GPU_ENGINE_COUNT
		for i in 0..<GPU_ENGINE_COUNT {
			x := inner_x + i32(i)*col_w
			draw_text(dc, GPU_ENGINE_NAMES[i], x, details_top, col_w - S(4), S(13),
				app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

			value_buf: [24]u8
			value := fmt.bprintf(value_buf[:], "%d%%", i32(app.gpu_engine_usage[i] + 0.5))
			draw_text(dc, value, x, details_top + S(16), col_w - S(4), S(18),
				app.fonts.small, COL_TEXT, DT_LEFT | DT_SINGLELINE)

			track := win.RECT{x, details_top + S(42), x + col_w - S(10), details_top + S(45)}
			_ = win.FillRect(dc, &track, app.brushes.track)

			bar_w := i32(f32(col_w - S(10)) * clamp(app.gpu_engine_usage[i], 0, 100) / 100.0)
			if bar_w > 0 {
				fill := win.RECT{x, details_top + S(42), x + bar_w, details_top + S(45)}
				_ = win.FillRect(dc, &fill, app.brushes.gpu)
			}
		}
	}
}

draw_stats_row :: proc(dc: win.HDC, rect: win.RECT) {
	Stat_Spec :: struct {
		label: string,
		value: string,
		sub:   string,
	}

	specs: [4]Stat_Spec
	count := 0

	proc_buf: [32]u8
	threads_buf: [48]u8
	processes := fmt.bprintf(proc_buf[:], "%d", app.process_count)
	threads := fmt.bprintf(threads_buf[:], "%d threads", app.thread_count)
	specs[count] = Stat_Spec{"PROCESSES", processes, threads}
	count += 1

	disk_value_buf: [32]u8
	disk_sub_buf: [64]u8
	if settings.modules.disk {
		disk_value := "—"
		disk_sub := "unavailable"
		if app.pdh_ok {
			disk_total := app.disk_read_bps + app.disk_write_bps
			factor, suffix := rate_scale(disk_total)
			disk_value = fmt.bprintf(disk_value_buf[:], "%.1f %s", disk_total/factor, suffix)
			disk_sub = fmt.bprintf(disk_sub_buf[:], "R %.1f · W %.1f", app.disk_read_bps/factor, app.disk_write_bps/factor)
		}
		specs[count] = Stat_Spec{"DISK", disk_value, disk_sub}
		count += 1
	}

	net_value_buf: [32]u8
	net_sub_buf: [64]u8
	if settings.modules.network {
		net_value := "—"
		net_sub := "unavailable"
		if app.net_ok {
			if !app.net_online {
				net_sub = "offline"
			} else {
				net_total := app.net_in_bps + app.net_out_bps
				factor, suffix := rate_scale(net_total)
				net_value = fmt.bprintf(net_value_buf[:], "%.1f %s", net_total/factor, suffix)
				net_sub = fmt.bprintf(net_sub_buf[:], "↓ %.1f · ↑ %.1f", app.net_in_bps/factor, app.net_out_bps/factor)
			}
		}
		specs[count] = Stat_Spec{"NETWORK", net_value, net_sub}
		count += 1
	}

	uptime_buf: [64]u8
	if settings.modules.uptime {
		uptime := format_uptime(uptime_buf[:])
		specs[count] = Stat_Spec{"UPTIME", uptime, "system uptime"}
		count += 1
	}

	gap := S(18)
	total_w := rect.right - rect.left
	card_w := (total_w - gap*i32(count-1)) / i32(count)
	if card_w <= 0 {
		return
	}
	height := rect.bottom - rect.top

	for i in 0..<count {
		x := rect.left + i32(i)*(card_w + gap)
		spec := specs[i]
		draw_stat_card(dc, x, rect.top, card_w, height, spec.label, spec.value, spec.sub)
	}
}

draw_stat_card :: proc(
	dc: win.HDC,
	x, y, w, h: i32,
	label: string,
	value: string,
	sub: string,
) {
	rect := win.RECT{x, y, x + w, y + h}
	draw_card(dc, rect)

	draw_text(dc, label, x + S(16), y + S(12), w - S(32), S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	draw_text(dc, value, x + S(16), y + S(31), w - S(32), S(26),
		app.fonts.stat, COL_TEXT, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
	draw_text(dc, sub, x + S(16), y + S(61), w - S(32), S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
}

draw_graph :: proc(
	dc: win.HDC,
	rect: win.RECT,
	samples: []f32,
	line_pen: win.HPEN,
	fill_brush: win.HBRUSH,
) {
	width := rect.right - rect.left
	height := rect.bottom - rect.top
	if width < S(20) || height < S(10) {
		return
	}

	for level in 1..=3 {
		y := rect.bottom - height*i32(level)/4
		line := win.RECT{rect.left, y, rect.right, y + 1}
		_ = win.FillRect(dc, &line, app.brushes.grid)
	}

	count := min(len(samples), SAMPLE_COUNT)
	if count < 2 {
		return
	}

	points: [SAMPLE_COUNT + 2]win.POINT
	points[0] = win.POINT{rect.left, rect.bottom}

	for i in 0..<count {
		v := samples[i]
		if v < 0 {
			v = 0
		}
		if v > 100 {
			v = 100
		}
		px := rect.left + i32(i)*(width - 1)/i32(count - 1)
		py := rect.bottom - i32(v*f32(height)/100.0)
		points[i + 1] = win.POINT{px, py}
	}
	points[count + 1] = win.POINT{rect.right, rect.bottom}

	_ = win.SelectObject(dc, win.HGDIOBJ(fill_brush))
	_ = win.SelectObject(dc, win.HGDIOBJ(app.pens.null))
	_ = win.Polygon(dc, raw_data(points[:]), i32(count + 2))

	_ = win.SelectObject(dc, win.HGDIOBJ(line_pen))
	_ = Polyline(dc, raw_data(points[1:]), i32(count))
}

draw_settings_view :: proc(dc: win.HDC) {
	layout := settings_layout()
	draw_card(dc, layout.outer)

	draw_text(dc, "Settings", layout.outer.left + S(24), layout.outer.top + S(16),
		S(240), S(30), app.fonts.title, COL_TEXT, DT_LEFT | DT_VCENTER | DT_SINGLELINE)
	draw_text(dc, "Modules, colors and bar theme", layout.outer.left + S(24), layout.outer.top + S(44),
		S(420), S(16), app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	fill_round(dc, layout.reset, app.brushes.badge, app.pens.border, S(8))
	draw_text(dc, "Reset defaults", layout.reset.left, layout.reset.top,
		layout.reset.right - layout.reset.left, layout.reset.bottom - layout.reset.top,
		app.fonts.small, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)

	divider := win.RECT{layout.outer.left + S(24), layout.outer.top + S(70),
		layout.outer.right - S(24), layout.outer.top + S(71)}
	_ = win.FillRect(dc, &divider, app.brushes.line)

	draw_text(dc, "MODULES", layout.modules.left, layout.modules.top, layout.modules.right - layout.modules.left, S(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	draw_text(dc, "COLORS", layout.colors.left, layout.colors.top, layout.colors.right - layout.colors.left, S(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	draw_text(dc, "APPEARANCE", layout.appearance.left, layout.appearance.top, layout.appearance.right - layout.appearance.left, S(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	sep1 := win.RECT{layout.modules.right + S(12), layout.body_top, layout.modules.right + S(13), layout.body_bottom}
	sep2 := win.RECT{layout.colors.right + S(12), layout.body_top, layout.colors.right + S(13), layout.body_bottom}
	_ = win.FillRect(dc, &sep1, app.brushes.line)
	_ = win.FillRect(dc, &sep2, app.brushes.line)

	for i in 0..<7 {
		id := Module_Id(i)
		row := settings_module_row(layout, i)
		disabled := id == .cores && !settings.modules.cpu
		label_color := COL_TEXT
		if disabled {
			label_color = COL_MUTED
		}
		draw_text(dc, module_label(id), row.left, row.top, row.right - row.left - S(70), row.bottom - row.top,
			app.fonts.small, label_color, DT_LEFT | DT_VCENTER | DT_SINGLELINE)

		switch_rect := win.RECT{row.right - S(56), row.top + (row.bottom - row.top - S(20))/2,
			row.right - S(16), row.top + (row.bottom - row.top - S(20))/2 + S(20)}
		draw_switch(dc, switch_rect, module_enabled(id) && !disabled, !disabled)
	}

	roles := [3]string{"ACCENT", "MEMORY", "GPU"}
	for role in 0..<3 {
		label_y := settings_color_label_y(layout, role)
		draw_text(dc, roles[role], layout.colors.left, label_y - S(17),
			layout.colors.right - layout.colors.left, S(14),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

		current := color_for_role(role)

		chip := win.RECT{layout.colors.left + S(72), label_y - S(18),
			layout.colors.left + S(88), label_y - S(2)}
		fill_color_rect(dc, chip, current, S(3))

		palette := palette_for_role(role)
		for i in 0..<len(palette) {
			swatch := settings_swatch_rect(layout, role, i)
			fill_color_rect(dc, swatch, palette[i], S(6))
			if palette[i] == current {
				draw_text(dc, "✓", swatch.left, swatch.top, swatch.right - swatch.left, swatch.bottom - swatch.top,
					app.fonts.badge, COL_BADGE_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
			}
		}

		custom := settings_custom_rect(layout, role)
		fill_round(dc, custom, app.brushes.badge, app.pens.border, S(8))
		draw_text(dc, "Custom…", custom.left, custom.top, custom.right - custom.left, custom.bottom - custom.top,
			app.fonts.tiny, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	}

	for i in 0..<len(THEMES) {
		preview := settings_theme_rect(layout, i)
		theme := THEMES[i]

		fill_color_rect(dc, preview, theme.bg, S(8))
		top_strip := win.RECT{preview.left + S(2), preview.top + S(2), preview.right - S(2), preview.top + S(26)}
		fill_color_rect(dc, top_strip, theme.sidebar, S(6))

		card_rect := win.RECT{preview.left + S(16), preview.top + S(38), preview.right - S(16), preview.bottom - S(16)}
		fill_color_rect(dc, card_rect, theme.card, S(5))

		dot := win.RECT{preview.left + S(14), preview.top + S(10), preview.left + S(22), preview.top + S(18)}
		fill_color_rect(dc, dot, settings.accent, S(4))

		draw_text(dc, theme.name, preview.left + S(28), preview.bottom - S(40),
			preview.right - preview.left - S(80), S(20),
			app.fonts.small, COL_TEXT, DT_LEFT | DT_VCENTER | DT_SINGLELINE)

		if settings.theme == i {
			stripe := win.RECT{preview.left, preview.top + S(10), preview.left + S(3), preview.bottom - S(10)}
			_ = win.FillRect(dc, &stripe, app.brushes.accent)
			draw_text(dc, "✓", preview.right - S(40), preview.bottom - S(40), S(20), S(20),
				app.fonts.small, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
		}
	}

	draw_text(dc, "Changes are saved automatically", layout.outer.right - S(244), layout.outer.bottom - S(30),
		S(220), S(14), app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)
}

draw_switch :: proc(dc: win.HDC, rect: win.RECT, on: bool, enabled: bool) {
	track := app.brushes.track
	if on && enabled {
		track = app.brushes.accent
	}
	fill_round(dc, rect, track, app.pens.null, (rect.bottom - rect.top)/2)

	knob_size := S(14)
	knob_y := rect.top + (rect.bottom - rect.top - knob_size)/2
	knob_x := rect.left + S(3)
	if on {
		knob_x = rect.right - knob_size - S(3)
	}
	knob_color := app.brushes.muted
	if on && enabled {
		knob_color = app.brushes.light
	}
	knob := win.RECT{knob_x, knob_y, knob_x + knob_size, knob_y + knob_size}
	fill_round(dc, knob, knob_color, app.pens.null, knob_size/2)
}
