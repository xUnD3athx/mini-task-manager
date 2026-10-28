package main

import "core:fmt"
import win "core:sys/windows"

// 顶栏：模块布局、数值、迷你曲线。

draw_bar :: proc(dc: win.HDC) {
	bar := win.RECT{0, 0, app.width, app.bar_h}
	_ = win.FillRect(dc, &bar, app.brushes.sidebar)

	draw_tasks_button(dc)

	gap := dip(BAR_SECTION_GAP_DIP)
	x := dip(BAR_PADDING_DIP) + dip(TASKS_BUTTON_W_DIP)
	right_limit := app.width - dip(BAR_PADDING_DIP) - dip(BAR_RIGHT_RESERVE_DIP)

	cpu_w := dip(180)
	cores_w := dip(140)
	mem_w := dip(220)
	gpu_w := dip(160)
	disk_w := dip(160)
	net_w := dip(180)
	uptime_w := dip(104)

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
	divider := win.RECT{x, dip(15), x + 1, app.bar_h - dip(15)}
	_ = win.FillRect(dc, &divider, app.brushes.line)
}

draw_tasks_button :: proc(dc: win.HDC) {
	rect := tasks_button_rect()
	background := app.brushes.badge
	if app.view == .tasks {
		background = app.brushes.selected
	}

	inner := win.RECT{rect.left + dip(3), dip(7), rect.right - dip(3), app.bar_h - dip(7)}
	fill_round(dc, inner, background, app.pens.null, dip(10))

	icon_size := dip(28)
	icon_x := rect.left + dip(11)
	icon_y := (app.bar_h - icon_size) / 2
	icon_rect := win.RECT{icon_x, icon_y, icon_x + icon_size, icon_y + icon_size}
	fill_round(dc, icon_rect, app.brushes.accent, app.pens.null, dip(8))

	line_w := dip(12)
	line_h := max(dip(2), 1)
	line_x := icon_x + (icon_size - line_w) / 2
	for i in 0..<3 {
		line_y := icon_y + icon_size/2 + i32(i-1)*dip(5) - line_h/2
		r := win.RECT{line_x, line_y, line_x + line_w, line_y + line_h}
		_ = win.FillRect(dc, &r, app.brushes.dark)
	}

	text_x := rect.left + dip(52)
	text_w := rect.right - dip(36) - text_x
	draw_text(dc, "TASKS", text_x, dip(16), text_w, dip(11),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	count_buf: [32]u8
	count_text := fmt.bprintf(count_buf[:], "%d", app.process_count)
	draw_text(dc, count_text, text_x, dip(28), text_w, dip(20),
		app.fonts.stat, COL_TEXT, DT_LEFT | DT_SINGLELINE)

	chevron := "▾"
	if app.view == .tasks {
		chevron = "▴"
	}
	draw_text(dc, chevron, rect.right - dip(26), 0, dip(18), app.bar_h,
		app.fonts.small, COL_MUTED, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
}

draw_settings_button :: proc(dc: win.HDC, rect: win.RECT) {
	if app.view == .settings {
		fill_round(dc, rect, app.brushes.selected, app.pens.null, dip(7))
	}

	center_x := (rect.left + rect.right) / 2
	center_y := (rect.top + rect.bottom) / 2
	line_w := dip(15)
	line_h := max(dip(2), 1)

	for i in 0..<3 {
		y := center_y + i32(i-1)*dip(5)
		line := win.RECT{center_x - line_w/2, y - line_h/2, center_x + line_w/2, y + line_h/2}
		_ = win.FillRect(dc, &line, app.brushes.muted)

		knob_x_ratio: i32 = 3
		if i == 1 {
			knob_x_ratio = 8
		} else if i == 2 {
			knob_x_ratio = 5
		}
		knob_x := center_x - line_w/2 + line_w*knob_x_ratio/10 - dip(2)
		knob := win.RECT{knob_x, y - dip(3), knob_x + dip(4), y + dip(3)}
		_ = win.FillRect(dc, &knob, app.brushes.accent)
	}
}

draw_bar_cpu :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "CPU", x, w)

	buf: [32]u8
	value := fmt.bprintf(buf[:], "%d%%", i32(app.cpu + 0.5))
	sub_buf: [32]u8
	sub := fmt.bprintf(sub_buf[:], "%d cores", app.cores)
	draw_bar_value(dc, x, w - dip(76), value, sub)

	spark := win.RECT{x + w - dip(70), dip(18), x + w, dip(48)}
	draw_sparkline(dc, spark, app.cpu_samples[:], app.pens.cpu, app.brushes.cpu_fill)
}

draw_bar_memory :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "MEMORY", x, w)

	buf: [32]u8
	value := fmt.bprintf(buf[:], "%d%%", i32(app.mem_percent + 0.5))
	sub_buf: [48]u8
	sub := fmt.bprintf(sub_buf[:], "%.1f/%.1f GB", app.mem_used, app.mem_total)
	draw_bar_value(dc, x, w - dip(76), value, sub)

	spark := win.RECT{x + w - dip(70), dip(18), x + w, dip(48)}
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
	draw_bar_value(dc, x, w - dip(76), value, sub)

	if app.gpu_ok {
		spark := win.RECT{x + w - dip(70), dip(18), x + w, dip(48)}
		draw_sparkline(dc, spark, app.gpu_samples[:], app.pens.gpu, app.brushes.gpu_fill)
	}
}

draw_bar_cores :: proc(dc: win.HDC, x, w: i32) {
	draw_bar_label(dc, "PER-CORE", x, w)
	if app.cores <= 0 {
		return
	}

	top := dip(23)
	bottom := dip(53)
	height := bottom - top
	if height <= 0 {
		return
	}

	gap := max(dip(1), 1)
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
	draw_text(dc, label, x, dip(7), w, dip(11),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
}

draw_bar_value :: proc(dc: win.HDC, x, w: i32, value: string, sub: string) {
	draw_text(dc, value, x, dip(18), w, dip(24),
		app.fonts.stat, COL_TEXT, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
	draw_text(dc, sub, x, dip(43), w, dip(12),
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
	if width < dip(8) || height < dip(8) {
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
