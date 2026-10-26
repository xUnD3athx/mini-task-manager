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
	max_value: f32 = 100.0,
) {
	width := rect.right - rect.left
	height := rect.bottom - rect.top
	if width < S(8) || height < S(8) {
		return
	}

	scale := max_value
	if scale <= 0 {
		scale = 1
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
		if v > scale {
			v = scale
		}
		px := rect.left + i32(i)*(width - 1)/i32(count - 1)
		py := rect.bottom - i32(v*f32(height)/scale)
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
	draw_core_band(dc)

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

	draw_text(dc, "Select a task", rect.left, mid - S(46), width, S(34),
		app.fonts.heading, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	draw_text(dc, "Choose a process on the left to preview its window and monitoring.",
		rect.left + S(24), mid - S(4), width - S(48), S(22),
		app.fonts.small, COL_MUTED, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS)
}

// Detail page for the selected task: its window on the left, a monitoring
// dashboard of curves on the right.
draw_task_view :: proc(dc: win.HDC) {
	view := task_view_layout()
	if view.show_preview {
		draw_window_preview(dc, view.preview)
	} else {
		hide_preview_thumbnail()
	}
	draw_task_detail(dc, view.detail)
}

draw_task_detail :: proc(dc: win.HDC, rect: win.RECT) {
	layout := task_detail_layout(rect)
	if layout.cpu.right <= layout.cpu.left {
		return
	}

	p, found := find_process(app.selected_pid)

	// Header: process name, PID and total CPU time.
	meta_buf: [96]u8
	meta := fmt.bprintf(meta_buf[:], "PID %d", app.selected_pid)
	if found {
		time_buf: [32]u8
		time_value := format_cpu_time(time_buf[:], p.cpu_time)
		meta = fmt.bprintf(meta_buf[:], "PID %d · CPU time %s", app.selected_pid, time_value)
	}

	meta_w := min(S(260), (layout.title.right - layout.title.left) / 2)
	name_w := layout.title.right - layout.title.left - meta_w - S(12)
	if name_w < S(60) {
		name_w = S(60)
	}
	if found {
		draw_text_w(dc, win.wstring(raw_data(p.name[:])), layout.title.left, layout.title.top,
			name_w, layout.title.bottom - layout.title.top, app.fonts.title, COL_TEXT,
			DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)
	} else {
		draw_text(dc, "—", layout.title.left, layout.title.top, name_w, layout.title.bottom - layout.title.top,
			app.fonts.title, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	}
	draw_text(dc, meta, layout.title.right - meta_w, layout.title.top,
		meta_w, layout.title.bottom - layout.title.top, app.fonts.tiny, COL_MUTED,
		DT_RIGHT | DT_SINGLELINE | DT_END_ELLIPSIS)

	cpu_buf: [16]u8
	mem_buf: [32]u8
	threads_buf: [16]u8
	handles_buf: [16]u8
	read_buf: [32]u8
	write_buf: [32]u8
	gpu_buf: [16]u8

	cpu_value := "—"
	mem_value := "—"
	threads_value := "—"
	if found {
		cpu_value = fmt.bprintf(cpu_buf[:], "%d%%", i32(p.cpu_percent + 0.5))
		mem_value = format_memory(mem_buf[:], p.working_set)
		threads_value = fmt.bprintf(threads_buf[:], "%d", p.threads)
	}

	handles_value := "—"
	if app.task.handles > 0 {
		handles_value = fmt.bprintf(handles_buf[:], "%d", app.task.handles)
	}

	gpu_value := "—"
	if app.gpu_ok {
		gpu_value = fmt.bprintf(gpu_buf[:], "%d%%", i32(app.task.gpu + 0.5))
	}

	read_factor, read_suffix := rate_scale(app.task.read_bps)
	read_value := fmt.bprintf(read_buf[:], "%.1f %s", app.task.read_bps/read_factor, read_suffix)
	write_factor, write_suffix := rate_scale(app.task.write_bps)
	write_value := fmt.bprintf(write_buf[:], "%.1f %s", app.task.write_bps/write_factor, write_suffix)

	draw_metric_card(dc, layout.cpu, "CPU", cpu_value, app.task.cpu_samples[:], 100,
		app.pens.cpu, app.brushes.cpu_fill)
	draw_metric_card(dc, layout.memory, "MEMORY", mem_value, app.task.mem_samples[:],
		scaled_peak(app.task.mem_samples[:], 1), app.pens.mem, app.brushes.mem_fill)
	draw_metric_card(dc, layout.gpu, "GPU", gpu_value, app.task.gpu_samples[:], 100,
		app.pens.gpu, app.brushes.gpu_fill)
	draw_metric_card(dc, layout.io_read, "I/O READ", read_value, app.task.read_samples[:],
		scaled_peak(app.task.read_samples[:], 1024), app.pens.mem, app.brushes.mem_fill)
	draw_metric_card(dc, layout.io_write, "I/O WRITE", write_value, app.task.write_samples[:],
		scaled_peak(app.task.write_samples[:], 1024), app.pens.gpu, app.brushes.gpu_fill)
	draw_metric_card(dc, layout.threads, "THREADS", threads_value, app.task.threads_samples[:],
		scaled_peak(app.task.threads_samples[:], 1), app.pens.cpu, app.brushes.cpu_fill)
	draw_metric_card(dc, layout.handles, "HANDLES", handles_value, app.task.handles_samples[:],
		scaled_peak(app.task.handles_samples[:], 1), app.pens.cpu, app.brushes.cpu_fill)
}

// Cards with values in bytes/thread counts need a peak-relative scale instead of
// the fixed 0–100 used by percentages.
scaled_peak :: proc(samples: []f32, floor_value: f32) -> f32 {
	peak: f32 = 0
	for v in samples {
		if v > peak {
			peak = v
		}
	}
	peak *= 1.15
	if peak < floor_value {
		peak = floor_value
	}
	return peak
}

draw_metric_card :: proc(
	dc: win.HDC,
	rect: win.RECT,
	label, value: string,
	samples: []f32,
	max_value: f32,
	pen: win.HPEN,
	brush: win.HBRUSH,
) {
	if rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	draw_card(dc, rect)

	pad := S(14)
	inner_x := rect.left + pad
	inner_w := rect.right - pad - inner_x
	if inner_w < S(40) {
		return
	}

	value_w := min(S(150), inner_w / 2)
	draw_text(dc, label, inner_x, rect.top + S(8), inner_w - value_w - S(8), S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
	draw_text(dc, value, rect.right - pad - value_w, rect.top + S(6), value_w, S(16),
		app.fonts.small, COL_TEXT, DT_RIGHT | DT_SINGLELINE | DT_END_ELLIPSIS)

	graph := win.RECT{inner_x, rect.top + S(26), rect.right - pad, rect.bottom - S(10)}
	if graph.bottom - graph.top >= S(12) {
		draw_sparkline(dc, graph, samples, pen, brush, max_value)
	}
}

draw_core_band :: proc(dc: win.HDC) {
	layout := core_band_layout()
	if layout.rect.right <= layout.rect.left {
		return
	}
	draw_card(dc, layout.rect)

	clamp_core_page()
	per := core_page_per_core()
	pages := core_page_count()
	first := app.core_page * per
	last := min(first + per, app.cores)
	if last < first {
		last = first
	}

	header_w := layout.header.right - layout.header.left
	label_w := header_w
	if label_w > S(220) {
		label_w = S(220)
	}
	draw_text(dc, "CPU CORES · SYSTEM", layout.header.left, layout.header.top, label_w, S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	mode_buf: [64]u8
	mode := "all cores"
	if !is_core_page_max() {
		mode = fmt.bprintf(mode_buf[:], "%d per page", per)
	}
	mode_w := S(140)
	draw_text(dc, mode, layout.header.left + label_w + S(12), layout.header.top, mode_w, S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	info_right := layout.prev.left - S(10)
	info_w := S(120)
	info_buf: [48]u8
	info := "—"
	if app.cores > 0 && last > first {
		info = fmt.bprintf(info_buf[:], "%d-%d / %d", first, last - 1, app.cores)
	}
	draw_text(dc, info, info_right - info_w, layout.header.top, info_w, S(14),
		app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)

	draw_page_button(dc, layout.prev, "<", app.core_page > 0)
	draw_page_button(dc, layout.next, ">", app.core_page + 1 < pages)

	count := last - first
	charts_top := layout.charts.top
	charts_bottom := layout.charts.bottom
	inner_w := layout.charts.right - layout.charts.left
	if count <= 0 || inner_w <= 0 || charts_bottom - charts_top < S(24) {
		return
	}

	gap := S(8)
	chart_w := (inner_w - gap*i32(count-1)) / i32(count)
	if chart_w < S(8) {
		return
	}

	for i in 0..<count {
		index := first + i
		x := layout.charts.left + i32(i)*(chart_w + gap)

		label_buf: [16]u8
		draw_text(dc, fmt.bprintf(label_buf[:], "%d", index), x, charts_top, chart_w, S(12),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

		graph := win.RECT{x, charts_top + S(13), x + chart_w, charts_bottom}
		draw_sparkline(dc, graph, app.core_samples[index][:], app.pens.cpu, app.brushes.cpu_fill, 100)
	}
}

draw_page_button :: proc(dc: win.HDC, rect: win.RECT, label: string, enabled: bool) {
	if rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	fill_round(dc, rect, app.brushes.badge, app.pens.border, S(6))
	color := COL_MUTED
	if enabled {
		color = COL_TEXT
	}
	draw_text(dc, label, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
		app.fonts.small, color, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
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
		fill_round(dc, chip, brush, app.pens.border, S(6))
		draw_text(dc, label, chip.left, chip.top, chip.right - chip.left, chip.bottom - chip.top,
			app.fonts.tiny, color, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	}

	divider := win.RECT{geo.panel.left + S(18), geo.panel.top + S(72),
		geo.panel.right - S(18), geo.panel.top + S(73)}
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
	name_w := tw
	extra_buf: [32]u8
	extra := ""
	switch settings.sort_field {
	case .gpu:
		extra = fmt.bprintf(extra_buf[:], "GPU %d%%", i32(p.gpu_percent + 0.5))
	case .disk:
		factor, suffix := rate_scale(p.io_bps)
		extra = fmt.bprintf(extra_buf[:], "I/O %.1f %s", p.io_bps/factor, suffix)
	case .cpu, .memory:
	}
	if len(extra) > 0 {
		extra_w := S(110)
		if extra_w < tw/2 {
			name_w = tw - extra_w - S(8)
			draw_text(dc, extra, tx + tw - extra_w, y + S(5), extra_w, S(16),
				app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE | DT_END_ELLIPSIS)
		}
	}
	draw_text_w(dc, name, tx, y + S(6), name_w, S(21), app.fonts.body, COL_TEXT,
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

	cores_label_y := settings_cores_label_y(layout)
	draw_text(dc, "CORES PER PAGE", layout.modules.left, cores_label_y,
		layout.modules.right - layout.modules.left, S(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	options := CORE_PAGE_OPTIONS
	for i in 0..<len(options) {
		chip := settings_cores_page_rect(layout, i)
		option := options[i]
		selected := false
		label := ""
		label_buf: [16]u8
		if option < 0 {
			selected = is_core_page_custom()
			label = "CUSTOM"
		} else if option == 0 {
			selected = is_core_page_max()
			label = "MAX"
		} else {
			selected = settings.cores_per_page == option && !settings.cores_custom_mode
			label = fmt.bprintf(label_buf[:], "%d", option)
		}

		brush := app.brushes.badge
		text_color := COL_TEXT
		if selected {
			brush = app.brushes.accent
			text_color = COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, app.pens.border, S(7))

		draw_text(dc, label, chip.left, chip.top,
			chip.right - chip.left, chip.bottom - chip.top, app.fonts.tiny, text_color,
			DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS)
	}

	if is_core_page_custom() {
		row_y := settings_custom_row_y(layout)
		draw_text(dc, "CUSTOM", layout.modules.left, row_y + S(5), S(76), S(14),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

		current := core_page_per_core()
		minus := settings_custom_minus_rect(layout)
		plus := settings_custom_plus_rect(layout)
		draw_page_button(dc, minus, "-", current > 1)
		draw_page_button(dc, plus, "+", current < max(app.cores, 1))

		value_buf: [16]u8
		draw_text(dc, fmt.bprintf(value_buf[:], "%d", current),
			minus.right, minus.top, plus.left - minus.right, plus.bottom - minus.top,
			app.fonts.small, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
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
