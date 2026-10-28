package main

import win "core:sys/windows"

// 进程枚举、排序、分组和选中项指标。

lower_wide :: proc(c: u16) -> u16 {
	if c >= 'A' && c <= 'Z' {
		return c + 32
	}
	return c
}

same_task_name :: proc(a, b: [MAX_NAME_U16]u16) -> bool {
	for i in 0..<MAX_NAME_U16 {
		if a[i] != b[i] {
			return false
		}
		if a[i] == 0 {
			return true
		}
	}
	return true
}

task_name_less :: proc(a, b: [MAX_NAME_U16]u16) -> bool {
	for i in 0..<MAX_NAME_U16 {
		ca := a[i]
		cb := b[i]
		if ca == 0 {
			return cb != 0
		}
		if cb == 0 {
			return false
		}
		la := lower_wide(ca)
		lb := lower_wide(cb)
		if la != lb {
			return la < lb
		}
	}
	return false
}

process_name_less :: proc(a, b: ^Process) -> bool {
	return task_name_less(a.name, b.name)
}

process_order_less :: proc(a, b: ^Process) -> bool {
	switch settings.sort_field {
	case .cpu:
		if a.cpu_percent != b.cpu_percent {
			if settings.sort_desc {
				return a.cpu_percent > b.cpu_percent
			}
			return a.cpu_percent < b.cpu_percent
		}
	case .memory:
		if a.working_set != b.working_set {
			if settings.sort_desc {
				return a.working_set > b.working_set
			}
			return a.working_set < b.working_set
		}
	case .gpu:
		if a.gpu_percent != b.gpu_percent {
			if settings.sort_desc {
				return a.gpu_percent > b.gpu_percent
			}
			return a.gpu_percent < b.gpu_percent
		}
	case .disk:
		if a.io_bps != b.io_bps {
			if settings.sort_desc {
				return a.io_bps > b.io_bps
			}
			return a.io_bps < b.io_bps
		}
	}
	// Ties keep an alphabetical order so the list doesn't shuffle per sample.
	return process_name_less(a, b)
}

sort_processes :: proc(list: []Process) {
	for i in 1..<len(list) {
		p := list[i]
		j := i - 1
		for j >= 0 && process_order_less(&p, &list[j]) {
			list[j+1] = list[j]
			j -= 1
		}
		list[j+1] = p
	}
}

group_order_less :: proc(a, b: ^Task_Group) -> bool {
	switch settings.sort_field {
	case .cpu:
		if a.cpu_percent != b.cpu_percent {
			if settings.sort_desc {
				return a.cpu_percent > b.cpu_percent
			}
			return a.cpu_percent < b.cpu_percent
		}
	case .memory:
		if a.working_set != b.working_set {
			if settings.sort_desc {
				return a.working_set > b.working_set
			}
			return a.working_set < b.working_set
		}
	case .gpu:
		if a.gpu_percent != b.gpu_percent {
			if settings.sort_desc {
				return a.gpu_percent > b.gpu_percent
			}
			return a.gpu_percent < b.gpu_percent
		}
	case .disk:
		if a.io_bps != b.io_bps {
			if settings.sort_desc {
				return a.io_bps > b.io_bps
			}
			return a.io_bps < b.io_bps
		}
	}
	return task_name_less(a.name, b.name)
}

group_is_expanded :: proc(name: [MAX_NAME_U16]u16) -> bool {
	for i in 0..<app.expand_count {
		if same_task_name(app.expand_state[i].name, name) {
			return app.expand_state[i].expanded
		}
	}
	return false
}

group_set_expanded :: proc(name: [MAX_NAME_U16]u16, expanded: bool) {
	for i in 0..<app.expand_count {
		if same_task_name(app.expand_state[i].name, name) {
			app.expand_state[i].expanded = expanded
			return
		}
	}
	if app.expand_count < MAX_GROUPS {
		app.expand_state[app.expand_count] = Expand_State{name = name, expanded = expanded}
		app.expand_count += 1
	}
}

append_task_row :: proc(kind: List_Row_Kind, index: int) {
	if app.task_row_count < MAX_TASK_ROWS {
		app.task_rows[app.task_row_count] = List_Row{kind = kind, index = index}
		app.task_row_count += 1
	}
}

rebuild_task_rows :: proc() {
	app.task_row_count = 0
	for gi in 0..<app.group_count {
		g := &app.groups[gi]
		append_task_row(.group, gi)
		if !group_is_expanded(g.name) {
			continue
		}
		for pi in 0..<app.process_count {
			if same_task_name(app.processes[pi].name, g.name) {
				append_task_row(.process, pi)
			}
		}
	}
}

build_task_groups :: proc() {
	app.group_count = 0
	for pi in 0..<app.process_count {
		p := &app.processes[pi]
		gi := -1
		for j in 0..<app.group_count {
			if same_task_name(app.groups[j].name, p.name) {
				gi = j
				break
			}
		}
		if gi < 0 {
			if app.group_count >= MAX_GROUPS {
				continue
			}
			gi = app.group_count
			app.groups[gi] = Task_Group{name = p.name}
			app.group_count += 1
		}

		g := &app.groups[gi]
		g.count += 1
		g.cpu_percent += p.cpu_percent
		g.working_set += p.working_set
		g.gpu_percent += p.gpu_percent
		g.io_bps += p.io_bps
	}

	for i in 1..<app.group_count {
		g := app.groups[i]
		j := i - 1
		for j >= 0 && group_order_less(&g, &app.groups[j]) {
			app.groups[j+1] = app.groups[j]
			j -= 1
		}
		app.groups[j+1] = g
	}

	rebuild_task_rows()
}

find_old_process :: proc(pid: u32) -> (p: ^Process, found: bool) {
	for i in 0..<app.process_count {
		if app.processes[i].pid == pid {
			return &app.processes[i], true
		}
	}
	return nil, false
}

gpu_usage_add :: proc(pid: u32, usage: f32) {
	if pid == 0 || usage <= 0 {
		return
	}
	for i in 0..<app.gpu_pid_count {
		if app.gpu_pid_usage[i].pid == pid {
			app.gpu_pid_usage[i].usage += usage
			return
		}
	}
	if app.gpu_pid_count < GPU_PID_CAPACITY {
		app.gpu_pid_usage[app.gpu_pid_count] = Gpu_Pid_Usage{pid = pid, usage = usage}
		app.gpu_pid_count += 1
	}
}

gpu_usage_for_pid :: proc(pid: u32) -> f32 {
	if pid == 0 {
		return 0
	}
	for i in 0..<app.gpu_pid_count {
		if app.gpu_pid_usage[i].pid == pid {
			v := app.gpu_pid_usage[i].usage
			if v > 100 {
				return 100
			}
			return v
		}
	}
	return 0
}

find_process :: proc(pid: u32) -> (p: ^Process, found: bool) {
	for i in 0..<app.process_count {
		if app.processes[i].pid == pid {
			return &app.processes[i], true
		}
	}
	return nil, false
}

refresh_processes :: proc() {
	now := GetTickCount64()
	elapsed_ms := now - app.last_process_ms
	app.last_process_ms = now

	snap := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0)
	if snap == win.INVALID_HANDLE_VALUE {
		return
	}
	defer win.CloseHandle(snap)

	entry: win.PROCESSENTRY32W
	entry.dwSize = u32(size_of(win.PROCESSENTRY32W))

	count := 0

	for status := win.Process32FirstW(snap, &entry); status; status = win.Process32NextW(snap, &entry) {
		if count >= MAX_PROCESSES {
			break
		}

		p := &next_processes[count]
		p^ = Process{}
		p.pid = entry.th32ProcessID
		p.threads = entry.cntThreads

		n := 0
		for n < MAX_NAME_U16-1 {
			c := entry.szExeFile[n]
			if c == 0 {
				break
			}
			p.name[n] = u16(c)
			n += 1
		}
		p.name[n] = 0

		old, has_old := find_old_process(p.pid)

		handle := win.OpenProcess(
			PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
			win.FALSE,
			p.pid,
		)
		if handle != nil {
			counters: Process_Memory_Counters
			counters.cb = u32(size_of(Process_Memory_Counters))
			if GetProcessMemoryInfo(handle, &counters, counters.cb) {
				p.working_set = u64(counters.working_set_size)
			}

			creation, exit_time, kernel_time, user_time: win.FILETIME
			if win.GetProcessTimes(handle, &creation, &exit_time, &kernel_time, &user_time) {
				p.cpu_time = filetime_value(kernel_time) + filetime_value(user_time)
			}

			io: Io_Counters
			if GetProcessIoCounters(handle, &io) {
				p.io_read_total = io.read_bytes
				p.io_write_total = io.write_bytes
			}

			handles: u32
			if GetProcessHandleCount(handle, &handles) {
				p.handles = handles
			}
			_ = win.CloseHandle(handle)
		}

		if has_old && elapsed_ms > 0 {
			if p.cpu_time > old.cpu_time && app.cores > 0 {
				delta := p.cpu_time - old.cpu_time
				units := f64(elapsed_ms) * 10000.0 * f64(app.cores)
				pct := f32(f64(delta) / units * 100.0)
				if pct < 0 {
					pct = 0
				}
				if pct > 100 {
					pct = 100
				}
				p.cpu_percent = pct
			}
			if p.io_read_total >= old.io_read_total {
				p.io_read_bps = f64(p.io_read_total - old.io_read_total) * 1000.0 / f64(elapsed_ms)
			}
			if p.io_write_total >= old.io_write_total {
				p.io_write_bps = f64(p.io_write_total - old.io_write_total) * 1000.0 / f64(elapsed_ms)
			}
			p.io_bps = p.io_read_bps + p.io_write_bps
		}

		p.gpu_percent = gpu_usage_for_pid(p.pid)

		count += 1
	}

	sort_processes(next_processes[:count])

	for i in 0..<count {
		app.processes[i] = next_processes[i]
	}
	app.process_count = count

	if app.has_selection {
		alive := false
		for i in 0..<count {
			if app.group_selected {
				if same_task_name(app.processes[i].name, app.selected_group) {
					alive = true
					break
				}
			} else if app.processes[i].pid == app.selected_pid {
				alive = true
				break
			}
		}
		if !alive {
			app.has_selection = false
			app.group_selected = false
			app.task = {}
			refresh_window_preview()
		}
	}

	build_task_groups()
	clamp_scroll()
}

push_sample :: proc(samples: []f32, v: f32) {
	if len(samples) == 0 {
		return
	}
	for i in 1..<len(samples) {
		samples[i-1] = samples[i]
	}
	samples[len(samples)-1] = v
}

update_task_metrics :: proc() {
	if !app.has_selection {
		if app.task.pid != 0 || app.task.group_mode {
			app.task = {}
		}
		return
	}

	// Start a fresh history when the selection changes.
	if app.group_selected {
		if !app.task.group_mode || !same_task_name(app.task.group, app.selected_group) {
			app.task = Task_Metrics{group_mode = true, group = app.selected_group}
		}
	} else if app.task.group_mode || app.task.pid != app.selected_pid {
		app.task = Task_Metrics{pid = app.selected_pid}
	}

	t := &app.task
	t.cpu = 0
	t.mem_bytes = 0
	t.gpu = 0
	t.read_bps = 0
	t.write_bps = 0
	t.threads = 0
	t.handles = 0
	t.cpu_time = 0
	t.count = 0

	if t.group_mode {
		for i in 0..<app.process_count {
			p := &app.processes[i]
			if !same_task_name(p.name, t.group) {
				continue
			}
			t.count += 1
			t.cpu += p.cpu_percent
			t.mem_bytes += p.working_set
			t.gpu += p.gpu_percent
			t.read_bps += p.io_read_bps
			t.write_bps += p.io_write_bps
			t.threads += p.threads
			t.handles += p.handles
			t.cpu_time += p.cpu_time
		}
	} else if p, found := find_process(t.pid); found {
		t.count = 1
		t.cpu = p.cpu_percent
		t.mem_bytes = p.working_set
		t.gpu = gpu_usage_for_pid(p.pid)
		t.read_bps = p.io_read_bps
		t.write_bps = p.io_write_bps
		t.threads = p.threads
		t.handles = p.handles
		t.cpu_time = p.cpu_time
	}
	if t.gpu > 100 {
		t.gpu = 100
	}

	push_sample(t.cpu_samples[:], t.cpu)
	push_sample(t.mem_samples[:], f32(f64(t.mem_bytes) / (1024.0*1024.0)))
	push_sample(t.threads_samples[:], f32(t.threads))
	push_sample(t.handles_samples[:], f32(t.handles))
	push_sample(t.gpu_samples[:], t.gpu)
	push_sample(t.read_samples[:], f32(t.read_bps))
	push_sample(t.write_samples[:], f32(t.write_bps))
}
