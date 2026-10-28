package ui

import "core:fmt"
import win "core:sys/windows"
import "../core"
import "../platform"
import "../services"

// 选中任务详情：窗口预览、监控卡片、每核曲线带。

// Risk of the currently selected task, including the aggregated tier of an
// application group.
selected_risk :: proc() -> (tier: core.Risk_Tier, reason: core.Risk_Reason) {
	if core.app.group_selected {
		for i in 0..<core.app.group_count {
			g := &core.app.groups[i]
			if services.same_task_name(g.name, core.app.selected_group) {
				if g.visible_count > 0 {
					return g.visible_risk, g.visible_risk_reason
				}
				return g.risk, g.risk_reason
			}
		}
		return .unknown, .no_signal
	}
	if p, found := services.find_process(core.app.selected_pid); found {
		return p.risk, p.risk_reason
	}
	return .unknown, .no_signal
}

// Detail page for the selected task: its window on the left, a monitoring
// dashboard of curves on the right.
draw_task_view :: proc(dc: win.HDC) {
	view := task_view_layout()
	if view.show_preview {
		draw_window_preview(dc, view.preview)
	} else {
		services.hide_preview_thumbnail()
	}
	draw_task_detail(dc, view.detail)
}

draw_task_detail :: proc(dc: win.HDC, rect: win.RECT) {
	layout := task_detail_layout(rect)
	if layout.cpu.right <= layout.cpu.left {
		return
	}

	t := &core.app.task
	p, found := services.find_process(core.app.selected_pid)
	risk, risk_reason := selected_risk()

	// Header: process or application name, PID/count and total CPU time.
	time_buf: [32]u8
	time_value := services.format_cpu_time(time_buf[:], t.cpu_time)
	meta_buf: [96]u8
	meta := ""
	if core.app.group_selected {
		count_word := "processes"
		if t.count == 1 {
			count_word = "process"
		}
		meta = fmt.bprintf(meta_buf[:], "%d %s · CPU time %s", t.count, count_word, time_value)
	} else {
		meta = fmt.bprintf(meta_buf[:], "PID %d · CPU time %s", core.app.selected_pid, time_value)
	}

	title_w := layout.title.right - layout.title.left
	pill_w := min(core.dip(150), title_w / 3)
	pill_h := core.dip(20)
	gap := core.dip(10)
	meta_w := min(core.dip(230), title_w / 3)
	name_max_w := title_w - meta_w - pill_w - gap*2
	if name_max_w < core.dip(60) {
		name_max_w = core.dip(60)
	}

	dash := [2]u16{0x2014, 0}
	name_text: win.LPCWSTR = win.wstring(raw_data(dash[:]))
	name_color := core.COL_MUTED
	if core.app.group_selected {
		name_text = win.wstring(raw_data(core.app.selected_group[:]))
		name_color = core.COL_TEXT
	} else if found {
		name_text = win.wstring(raw_data(p.name[:]))
		name_color = core.COL_TEXT
	}

	_ = win.SelectObject(dc, win.HGDIOBJ(core.app.fonts.title))
	measured := win.RECT{0, 0, name_max_w, layout.title.bottom - layout.title.top}
	_ = platform.DrawTextW(dc, name_text, -1, &measured, platform.DT_CALCRECT | platform.DT_SINGLELINE | platform.DT_NOPREFIX)
	name_w := min(measured.right - measured.left, name_max_w)
	draw_text_w(dc, name_text, layout.title.left, layout.title.top,
		name_w, layout.title.bottom - layout.title.top, core.app.fonts.title, name_color,
		platform.DT_LEFT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS | platform.DT_NOPREFIX)

	pill_x := layout.title.left + name_w + gap
	// A squeezed name can shrink the reserved space below the minimum width, so
	// push the meta left instead of letting it run under the pill.
	meta_x := max(layout.title.right - meta_w, pill_x + pill_w + gap)
	draw_text(dc, meta, meta_x, layout.title.top,
		layout.title.right - meta_x, layout.title.bottom - layout.title.top, core.app.fonts.tiny, core.COL_MUTED,
		platform.DT_RIGHT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)

	// The tier badge follows the task name instead of floating at the row's
	// right edge, so the header reads name -> badge -> meta.
	pill_y := layout.title.top + (layout.title.bottom - layout.title.top - pill_h)/2
	pill := win.RECT{pill_x, pill_y, pill_x + pill_w, pill_y + pill_h}
	fill_round(dc, pill, risk_brush(risk), core.app.pens.null, core.dip(7))

	risk_buf: [32]u8
	risk_text := core.risk_label(risk)
	if label := core.risk_reason_label(risk_reason); len(label) > 0 {
		risk_text = fmt.bprintf(risk_buf[:], "%s · %s", risk_text, label)
	}
	draw_text(dc, risk_text, pill.left, pill.top, pill.right - pill.left, pill.bottom - pill.top,
		core.app.fonts.tiny, core.COL_BADGE_TEXT,
		platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)

	cpu_buf: [16]u8
	mem_buf: [32]u8
	threads_buf: [16]u8
	handles_buf: [16]u8
	read_buf: [32]u8
	write_buf: [32]u8
	gpu_buf: [16]u8

	cpu_value := fmt.bprintf(cpu_buf[:], "%d%%", i32(t.cpu + 0.5))
	mem_value := services.format_memory(mem_buf[:], t.mem_bytes)
	threads_value := fmt.bprintf(threads_buf[:], "%d", t.threads)

	handles_value := "—"
	if t.handles > 0 {
		handles_value = fmt.bprintf(handles_buf[:], "%d", t.handles)
	}

	gpu_value := "—"
	if core.app.gpu_ok {
		gpu_value = fmt.bprintf(gpu_buf[:], "%d%%", i32(t.gpu + 0.5))
	}

	read_factor, read_suffix := services.rate_scale(t.read_bps)
	read_value := fmt.bprintf(read_buf[:], "%.1f %s", t.read_bps/read_factor, read_suffix)
	write_factor, write_suffix := services.rate_scale(t.write_bps)
	write_value := fmt.bprintf(write_buf[:], "%.1f %s", t.write_bps/write_factor, write_suffix)

	cpu_max: f32 = 100
	if core.app.group_selected {
		cpu_max = scaled_peak(t.cpu_samples[:], 100)
	}

	draw_metric_card(dc, layout.cpu, "CPU", cpu_value, t.cpu_samples[:], cpu_max,
		core.app.pens.cpu, core.app.brushes.cpu_fill)
	draw_metric_card(dc, layout.memory, "MEMORY", mem_value, t.mem_samples[:],
		scaled_peak(t.mem_samples[:], 1), core.app.pens.mem, core.app.brushes.mem_fill)
	draw_metric_card(dc, layout.gpu, "GPU", gpu_value, t.gpu_samples[:], 100,
		core.app.pens.gpu, core.app.brushes.gpu_fill)
	draw_metric_card(dc, layout.io_read, "I/O READ", read_value, t.read_samples[:],
		scaled_peak(t.read_samples[:], 1024), core.app.pens.mem, core.app.brushes.mem_fill)
	draw_metric_card(dc, layout.io_write, "I/O WRITE", write_value, t.write_samples[:],
		scaled_peak(t.write_samples[:], 1024), core.app.pens.gpu, core.app.brushes.gpu_fill)
	draw_metric_card(dc, layout.threads, "THREADS", threads_value, t.threads_samples[:],
		scaled_peak(t.threads_samples[:], 1), core.app.pens.cpu, core.app.brushes.cpu_fill)
	draw_metric_card(dc, layout.handles, "HANDLES", handles_value, t.handles_samples[:],
		scaled_peak(t.handles_samples[:], 1), core.app.pens.cpu, core.app.brushes.cpu_fill)
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

	pad := core.dip(14)
	inner_x := rect.left + pad
	inner_w := rect.right - pad - inner_x
	if inner_w < core.dip(40) {
		return
	}

	value_w := min(core.dip(150), inner_w / 2)
	draw_text(dc, label, inner_x, rect.top + core.dip(8), inner_w - value_w - core.dip(8), core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)
	draw_text(dc, value, rect.right - pad - value_w, rect.top + core.dip(6), value_w, core.dip(16),
		core.app.fonts.small, core.COL_TEXT, platform.DT_RIGHT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)

	graph := win.RECT{inner_x, rect.top + core.dip(26), rect.right - pad, rect.bottom - core.dip(10)}
	if graph.bottom - graph.top >= core.dip(12) {
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
	first := core.app.core_page * per
	last := min(first + per, core.app.cores)
	if last < first {
		last = first
	}

	header_w := layout.header.right - layout.header.left
	label_w := header_w
	if label_w > core.dip(220) {
		label_w = core.dip(220)
	}
	draw_text(dc, "CPU CORES · SYSTEM", layout.header.left, layout.header.top, label_w, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)

	mode_buf: [64]u8
	mode := "all cores"
	if !is_core_page_max() {
		mode = fmt.bprintf(mode_buf[:], "%d per page", per)
	}
	mode_w := core.dip(140)
	draw_text(dc, mode, layout.header.left + label_w + core.dip(12), layout.header.top, mode_w, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)

	info_right := layout.prev.left - core.dip(10)
	info_w := core.dip(120)
	info_buf: [48]u8
	info := "—"
	if core.app.cores > 0 && last > first {
		info = fmt.bprintf(info_buf[:], "%d-%d / %d", first, last - 1, core.app.cores)
	}
	draw_text(dc, info, info_right - info_w, layout.header.top, info_w, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_RIGHT | platform.DT_SINGLELINE)

	draw_page_button(dc, layout.prev, "<", core.app.core_page > 0)
	draw_page_button(dc, layout.next, ">", core.app.core_page + 1 < pages)

	count := last - first
	charts_top := layout.charts.top
	charts_bottom := layout.charts.bottom
	inner_w := layout.charts.right - layout.charts.left
	if count <= 0 || inner_w <= 0 || charts_bottom - charts_top < core.dip(24) {
		return
	}

	gap := core.dip(8)
	chart_w := (inner_w - gap*i32(count-1)) / i32(count)
	if chart_w < core.dip(8) {
		return
	}

	for i in 0..<count {
		index := first + i
		x := layout.charts.left + i32(i)*(chart_w + gap)

		label_buf: [16]u8
		draw_text(dc, fmt.bprintf(label_buf[:], "%d", index), x, charts_top, chart_w, core.dip(12),
			core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

		graph := win.RECT{x, charts_top + core.dip(13), x + chart_w, charts_bottom}
		draw_sparkline(dc, graph, core.app.core_samples[index][:], core.app.pens.cpu, core.app.brushes.cpu_fill, 100)
	}
}

draw_page_button :: proc(dc: win.HDC, rect: win.RECT, label: string, enabled: bool) {
	if rect.right <= rect.left || rect.bottom <= rect.top {
		return
	}
	fill_round(dc, rect, core.app.brushes.badge, core.app.pens.border, core.dip(6))
	color := core.COL_MUTED
	if enabled {
		color = core.COL_TEXT
	}
	draw_text(dc, label, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
		core.app.fonts.small, color, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
}

draw_window_preview :: proc(dc: win.HDC, rect: win.RECT) {
	draw_card(dc, rect)

	pad := core.dip(16)
	inner_x := rect.left + pad
	inner_w := rect.right - rect.left - pad*2
	if inner_w < core.dip(80) {
		return
	}

	draw_text(dc, "WINDOW", inner_x, rect.top + core.dip(14), inner_w, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

	if len(core.app.preview.title) > 0 && core.app.preview.title[0] != 0 {
		draw_text_w(dc, win.wstring(raw_data(core.app.preview.title[:])), inner_x, rect.top + core.dip(30),
			inner_w, core.dip(20), core.app.fonts.small, core.COL_TEXT,
			platform.DT_LEFT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS | platform.DT_NOPREFIX)
	}

	content := win.RECT{inner_x, rect.top + core.dip(58), rect.right - pad, rect.bottom - pad}
	if content.bottom <= content.top || content.right <= content.left {
		return
	}
	fill_round(dc, content, core.app.brushes.dark, core.app.pens.border, core.dip(8))
	services.draw_preview_thumbnail(content)
}
