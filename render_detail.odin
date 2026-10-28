package main

import "core:fmt"
import win "core:sys/windows"

// 选中任务详情：窗口预览、监控卡片、每核曲线带。

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

	t := &app.task
	p, found := find_process(app.selected_pid)

	// Header: process or application name, PID/count and total CPU time.
	time_buf: [32]u8
	time_value := format_cpu_time(time_buf[:], t.cpu_time)
	meta_buf: [96]u8
	meta := ""
	if app.group_selected {
		count_word := "processes"
		if t.count == 1 {
			count_word = "process"
		}
		meta = fmt.bprintf(meta_buf[:], "%d %s · CPU time %s", t.count, count_word, time_value)
	} else {
		meta = fmt.bprintf(meta_buf[:], "PID %d · CPU time %s", app.selected_pid, time_value)
	}

	meta_w := min(dip(260), (layout.title.right - layout.title.left) / 2)
	name_w := layout.title.right - layout.title.left - meta_w - dip(12)
	if name_w < dip(60) {
		name_w = dip(60)
	}
	if app.group_selected {
		draw_text_w(dc, win.wstring(raw_data(app.selected_group[:])), layout.title.left, layout.title.top,
			name_w, layout.title.bottom - layout.title.top, app.fonts.title, COL_TEXT,
			DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)
	} else if found {
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

	cpu_value := fmt.bprintf(cpu_buf[:], "%d%%", i32(t.cpu + 0.5))
	mem_value := format_memory(mem_buf[:], t.mem_bytes)
	threads_value := fmt.bprintf(threads_buf[:], "%d", t.threads)

	handles_value := "—"
	if t.handles > 0 {
		handles_value = fmt.bprintf(handles_buf[:], "%d", t.handles)
	}

	gpu_value := "—"
	if app.gpu_ok {
		gpu_value = fmt.bprintf(gpu_buf[:], "%d%%", i32(t.gpu + 0.5))
	}

	read_factor, read_suffix := rate_scale(t.read_bps)
	read_value := fmt.bprintf(read_buf[:], "%.1f %s", t.read_bps/read_factor, read_suffix)
	write_factor, write_suffix := rate_scale(t.write_bps)
	write_value := fmt.bprintf(write_buf[:], "%.1f %s", t.write_bps/write_factor, write_suffix)

	cpu_max: f32 = 100
	if app.group_selected {
		cpu_max = scaled_peak(t.cpu_samples[:], 100)
	}

	draw_metric_card(dc, layout.cpu, "CPU", cpu_value, t.cpu_samples[:], cpu_max,
		app.pens.cpu, app.brushes.cpu_fill)
	draw_metric_card(dc, layout.memory, "MEMORY", mem_value, t.mem_samples[:],
		scaled_peak(t.mem_samples[:], 1), app.pens.mem, app.brushes.mem_fill)
	draw_metric_card(dc, layout.gpu, "GPU", gpu_value, t.gpu_samples[:], 100,
		app.pens.gpu, app.brushes.gpu_fill)
	draw_metric_card(dc, layout.io_read, "I/O READ", read_value, t.read_samples[:],
		scaled_peak(t.read_samples[:], 1024), app.pens.mem, app.brushes.mem_fill)
	draw_metric_card(dc, layout.io_write, "I/O WRITE", write_value, t.write_samples[:],
		scaled_peak(t.write_samples[:], 1024), app.pens.gpu, app.brushes.gpu_fill)
	draw_metric_card(dc, layout.threads, "THREADS", threads_value, t.threads_samples[:],
		scaled_peak(t.threads_samples[:], 1), app.pens.cpu, app.brushes.cpu_fill)
	draw_metric_card(dc, layout.handles, "HANDLES", handles_value, t.handles_samples[:],
		scaled_peak(t.handles_samples[:], 1), app.pens.cpu, app.brushes.cpu_fill)
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

	pad := dip(14)
	inner_x := rect.left + pad
	inner_w := rect.right - pad - inner_x
	if inner_w < dip(40) {
		return
	}

	value_w := min(dip(150), inner_w / 2)
	draw_text(dc, label, inner_x, rect.top + dip(8), inner_w - value_w - dip(8), dip(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)
	draw_text(dc, value, rect.right - pad - value_w, rect.top + dip(6), value_w, dip(16),
		app.fonts.small, COL_TEXT, DT_RIGHT | DT_SINGLELINE | DT_END_ELLIPSIS)

	graph := win.RECT{inner_x, rect.top + dip(26), rect.right - pad, rect.bottom - dip(10)}
	if graph.bottom - graph.top >= dip(12) {
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
	if label_w > dip(220) {
		label_w = dip(220)
	}
	draw_text(dc, "CPU CORES · SYSTEM", layout.header.left, layout.header.top, label_w, dip(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	mode_buf: [64]u8
	mode := "all cores"
	if !is_core_page_max() {
		mode = fmt.bprintf(mode_buf[:], "%d per page", per)
	}
	mode_w := dip(140)
	draw_text(dc, mode, layout.header.left + label_w + dip(12), layout.header.top, mode_w, dip(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	info_right := layout.prev.left - dip(10)
	info_w := dip(120)
	info_buf: [48]u8
	info := "—"
	if app.cores > 0 && last > first {
		info = fmt.bprintf(info_buf[:], "%d-%d / %d", first, last - 1, app.cores)
	}
	draw_text(dc, info, info_right - info_w, layout.header.top, info_w, dip(14),
		app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)

	draw_page_button(dc, layout.prev, "<", app.core_page > 0)
	draw_page_button(dc, layout.next, ">", app.core_page + 1 < pages)

	count := last - first
	charts_top := layout.charts.top
	charts_bottom := layout.charts.bottom
	inner_w := layout.charts.right - layout.charts.left
	if count <= 0 || inner_w <= 0 || charts_bottom - charts_top < dip(24) {
		return
	}

	gap := dip(8)
	chart_w := (inner_w - gap*i32(count-1)) / i32(count)
	if chart_w < dip(8) {
		return
	}

	for i in 0..<count {
		index := first + i
		x := layout.charts.left + i32(i)*(chart_w + gap)

		label_buf: [16]u8
		draw_text(dc, fmt.bprintf(label_buf[:], "%d", index), x, charts_top, chart_w, dip(12),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

		graph := win.RECT{x, charts_top + dip(13), x + chart_w, charts_bottom}
		draw_sparkline(dc, graph, app.core_samples[index][:], app.pens.cpu, app.brushes.cpu_fill, 100)
	}
}

draw_page_button :: proc(dc: win.HDC, rect: win.RECT, label: string, enabled: bool) {
	if rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	fill_round(dc, rect, app.brushes.badge, app.pens.border, dip(6))
	color := COL_MUTED
	if enabled {
		color = COL_TEXT
	}
	draw_text(dc, label, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
		app.fonts.small, color, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
}

draw_window_preview :: proc(dc: win.HDC, rect: win.RECT) {
	draw_card(dc, rect)

	pad := dip(16)
	inner_x := rect.left + pad
	inner_w := rect.right - rect.left - pad*2
	if inner_w < dip(80) {
		return
	}

	draw_text(dc, "WINDOW", inner_x, rect.top + dip(14), inner_w, dip(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	if len(app.preview.title) > 0 && app.preview.title[0] != 0 {
		draw_text_w(dc, win.wstring(raw_data(app.preview.title[:])), inner_x, rect.top + dip(30),
			inner_w, dip(20), app.fonts.small, COL_TEXT,
			DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)
	}

	content := win.RECT{inner_x, rect.top + dip(58), rect.right - pad, rect.bottom - pad}
	if content.bottom <= content.top || content.right <= content.left {
		return
	}
	fill_round(dc, content, app.brushes.dark, app.pens.border, dip(8))
	draw_preview_thumbnail(content)
}
