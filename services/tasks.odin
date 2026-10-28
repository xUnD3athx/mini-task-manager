package services

import "base:runtime"
import win "core:sys/windows"
import "../core"
import "../platform"

// 进程枚举、排序、分组和选中项指标。

lower_wide :: proc(c: u16) -> u16 {
	if c >= 'A' && c <= 'Z' {
		return c + 32
	}
	return c
}

task_name_is :: proc(name: [core.MAX_NAME_U16]u16, candidate: string) -> bool {
	if len(candidate) >= core.MAX_NAME_U16 {
		return false
	}
	for i in 0..<len(candidate) {
		c := name[i]
		if c == 0 {
			return false
		}
		cc := u16(candidate[i])
		if cc >= 'A' && cc <= 'Z' {
			cc += 32
		}
		if lower_wide(c) != cc {
			return false
		}
	}
	return name[len(candidate)] == 0
}

task_name_in :: proc(name: [core.MAX_NAME_U16]u16, candidates: []string) -> bool {
	for candidate in candidates {
		if task_name_is(name, candidate) {
			return true
		}
	}
	return false
}

same_task_name :: proc(a, b: [core.MAX_NAME_U16]u16) -> bool {
	for i in 0..<core.MAX_NAME_U16 {
		if a[i] != b[i] {
			return false
		}
		if a[i] == 0 {
			return true
		}
	}
	return true
}

task_name_less :: proc(a, b: [core.MAX_NAME_U16]u16) -> bool {
	for i in 0..<core.MAX_NAME_U16 {
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

process_name_less :: proc(a, b: ^core.Process) -> bool {
	return task_name_less(a.name, b.name)
}

process_order_less :: proc(a, b: ^core.Process) -> bool {
	switch core.settings.sort_field {
	case .cpu:
		if a.cpu_percent != b.cpu_percent {
			if core.settings.sort_desc {
				return a.cpu_percent > b.cpu_percent
			}
			return a.cpu_percent < b.cpu_percent
		}
	case .memory:
		if a.working_set != b.working_set {
			if core.settings.sort_desc {
				return a.working_set > b.working_set
			}
			return a.working_set < b.working_set
		}
	case .gpu:
		if a.gpu_percent != b.gpu_percent {
			if core.settings.sort_desc {
				return a.gpu_percent > b.gpu_percent
			}
			return a.gpu_percent < b.gpu_percent
		}
	case .disk:
		if a.io_bps != b.io_bps {
			if core.settings.sort_desc {
				return a.io_bps > b.io_bps
			}
			return a.io_bps < b.io_bps
		}
	}
	// Ties keep an alphabetical order so the list doesn't shuffle per sample.
	return process_name_less(a, b)
}

sort_processes :: proc(list: []core.Process) {
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

group_order_less :: proc(a, b: ^core.Task_Group) -> bool {
	switch core.settings.sort_field {
	case .cpu:
		if a.cpu_percent != b.cpu_percent {
			if core.settings.sort_desc {
				return a.cpu_percent > b.cpu_percent
			}
			return a.cpu_percent < b.cpu_percent
		}
	case .memory:
		if a.working_set != b.working_set {
			if core.settings.sort_desc {
				return a.working_set > b.working_set
			}
			return a.working_set < b.working_set
		}
	case .gpu:
		if a.gpu_percent != b.gpu_percent {
			if core.settings.sort_desc {
				return a.gpu_percent > b.gpu_percent
			}
			return a.gpu_percent < b.gpu_percent
		}
	case .disk:
		if a.io_bps != b.io_bps {
			if core.settings.sort_desc {
				return a.io_bps > b.io_bps
			}
			return a.io_bps < b.io_bps
		}
	}
	return task_name_less(a.name, b.name)
}

group_is_expanded :: proc(name: [core.MAX_NAME_U16]u16) -> bool {
	for i in 0..<core.app.expand_count {
		if same_task_name(core.app.expand_state[i].name, name) {
			return core.app.expand_state[i].expanded
		}
	}
	return false
}

group_set_expanded :: proc(name: [core.MAX_NAME_U16]u16, expanded: bool) {
	for i in 0..<core.app.expand_count {
		if same_task_name(core.app.expand_state[i].name, name) {
			core.app.expand_state[i].expanded = expanded
			return
		}
	}
	if core.app.expand_count < core.MAX_GROUPS {
		core.app.expand_state[core.app.expand_count] = core.Expand_State{name = name, expanded = expanded}
		core.app.expand_count += 1
	}
}

append_task_row :: proc(kind: core.List_Row_Kind, index: int) {
	if core.app.task_row_count < core.MAX_TASK_ROWS {
		core.app.task_rows[core.app.task_row_count] = core.List_Row{kind = kind, index = index}
		core.app.task_row_count += 1
	}
}

rebuild_task_rows :: proc() {
	core.app.task_row_count = 0
	for gi in 0..<core.app.group_count {
		g := &core.app.groups[gi]
		append_task_row(.group, gi)
		if !group_is_expanded(g.name) {
			continue
		}
		for pi in 0..<core.app.process_count {
			if same_task_name(core.app.processes[pi].name, g.name) {
				append_task_row(.process, pi)
			}
		}
	}
}

build_task_groups :: proc() {
	core.app.group_count = 0
	for pi in 0..<core.app.process_count {
		p := &core.app.processes[pi]
		gi := -1
		for j in 0..<core.app.group_count {
			if same_task_name(core.app.groups[j].name, p.name) {
				gi = j
				break
			}
		}
		if gi < 0 {
			if core.app.group_count >= core.MAX_GROUPS {
				continue
			}
			gi = core.app.group_count
			core.app.groups[gi] = core.Task_Group{name = p.name}
			core.app.group_count += 1
		}

		g := &core.app.groups[gi]
		g.count += 1
		g.cpu_percent += p.cpu_percent
		g.working_set += p.working_set
		g.gpu_percent += p.gpu_percent
		g.io_bps += p.io_bps
		if p.risk > g.risk {
			g.risk = p.risk
			g.risk_reason = p.risk_reason
		}
	}

	for i in 1..<core.app.group_count {
		g := core.app.groups[i]
		j := i - 1
		for j >= 0 && group_order_less(&g, &core.app.groups[j]) {
			core.app.groups[j+1] = core.app.groups[j]
			j -= 1
		}
		core.app.groups[j+1] = g
	}

	rebuild_task_rows()
}

find_old_process :: proc(pid: u32) -> (p: ^core.Process, found: bool) {
	for i in 0..<core.app.process_count {
		if core.app.processes[i].pid == pid {
			return &core.app.processes[i], true
		}
	}
	return nil, false
}

gpu_usage_add :: proc(pid: u32, usage: f32) {
	if pid == 0 || usage <= 0 {
		return
	}
	for i in 0..<core.app.gpu_pid_count {
		if core.app.gpu_pid_usage[i].pid == pid {
			core.app.gpu_pid_usage[i].usage += usage
			return
		}
	}
	if core.app.gpu_pid_count < core.GPU_PID_CAPACITY {
		core.app.gpu_pid_usage[core.app.gpu_pid_count] = core.Gpu_Pid_Usage{pid = pid, usage = usage}
		core.app.gpu_pid_count += 1
	}
}

gpu_usage_for_pid :: proc(pid: u32) -> f32 {
	if pid == 0 {
		return 0
	}
	for i in 0..<core.app.gpu_pid_count {
		if core.app.gpu_pid_usage[i].pid == pid {
			v := core.app.gpu_pid_usage[i].usage
			if v > 100 {
				return 100
			}
			return v
		}
	}
	return 0
}

find_process :: proc(pid: u32) -> (p: ^core.Process, found: bool) {
	for i in 0..<core.app.process_count {
		if core.app.processes[i].pid == pid {
			return &core.app.processes[i], true
		}
	}
	return nil, false
}

// Fallbacks for when the process cannot be queried: the critical flag wins
// when it is readable, and these names cover the cases where it is not.
CRITICAL_TASK_NAMES := [?]string{
	"[system process]",
	"system",
	"registry",
	"memory compression",
	"secure system",
	"system idle process",
	"smss.exe",
	"csrss.exe",
	"wininit.exe",
	"winlogon.exe",
	"services.exe",
	"lsass.exe",
}

// Session infrastructure restarts itself, but ending it visibly disrupts the
// desktop, so it sits one tier below the critical set.
SHELL_TASK_NAMES := [?]string{
	"explorer.exe",
	"dwm.exe",
	"fontdrvhost.exe",
	"sihost.exe",
}

visible_window_callback :: proc "system" (hwnd: win.HWND, lparam: win.LPARAM) -> win.BOOL {
	context = runtime.default_context()

	if win.IsWindowVisible(hwnd) == win.FALSE {
		return win.TRUE
	}
	pid: win.DWORD
	_ = win.GetWindowThreadProcessId(hwnd, &pid)

	count := int(lparam)
	for i in 0..<count {
		if core.next_processes[i].pid == pid {
			core.next_processes[i].has_window = true
			break
		}
	}
	return win.TRUE
}

// One EnumWindows pass per refresh answers "does this process own a visible
// window", which is the strongest signal that it is a user application.
mark_window_processes :: proc(count: int) {
	if count <= 0 {
		return
	}
	_ = win.EnumWindows(visible_window_callback, win.LPARAM(count))
}

classify_task_risk :: proc(p: ^core.Process, self_session: win.DWORD) {
	p.risk = .blocked
	p.risk_reason = .inspect_denied

	handle := win.OpenProcess(platform.PROCESS_QUERY_LIMITED_INFORMATION, win.FALSE, p.pid)
	defer _ = win.CloseHandle(handle)

	if handle != nil {
		critical: win.BOOL
		if platform.IsProcessCritical(handle, &critical) && critical != win.FALSE {
			p.risk_reason = .critical_process
			return
		}

		protection: platform.Process_Protection_Level_Information
		if platform.GetProcessInformation(
			handle,
			platform.PROCESS_INFORMATION_CLASS_PROTECTION_LEVEL,
			rawptr(&protection),
			u32(size_of(protection)),
		) && protection.protection_level != platform.PROTECTION_LEVEL_NONE {
			p.risk_reason = .protected_process
			return
		}
	}

	if task_name_in(p.name, CRITICAL_TASK_NAMES[:]) {
		p.risk_reason = .critical_process
		return
	}
	if task_name_in(p.name, SHELL_TASK_NAMES[:]) {
		p.risk = .risky
		p.risk_reason = .shell_component
		return
	}

	// Services run in session 0 and stay classifiable even when the handle is
	// denied, which is common for SYSTEM processes without elevation.
	session: win.DWORD
	if platform.ProcessIdToSessionId(p.pid, &session) && session != self_session {
		p.risk = .risky
		p.risk_reason = .system_session
		return
	}

	if handle == nil {
		// Same session yet unopenable: elevated or protected, so leave it blocked.
		return
	}

	if p.has_window {
		p.risk = .safe
		p.risk_reason = .app_window
		return
	}

	p.risk = .unknown
	p.risk_reason = .no_signal
}

refresh_processes :: proc() {
	now := platform.GetTickCount64()
	elapsed_ms := now - core.app.last_process_ms
	core.app.last_process_ms = now

	snap := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0)
	if snap == win.INVALID_HANDLE_VALUE {
		return
	}
	defer win.CloseHandle(snap)

	entry: win.PROCESSENTRY32W
	entry.dwSize = u32(size_of(win.PROCESSENTRY32W))

	count := 0

	self_session: win.DWORD
	_ = platform.ProcessIdToSessionId(win.GetCurrentProcessId(), &self_session)

	for status := win.Process32FirstW(snap, &entry); status; status = win.Process32NextW(snap, &entry) {
		if count >= core.MAX_PROCESSES {
			break
		}

		p := &core.next_processes[count]
		p^ = core.Process{}
		p.pid = entry.th32ProcessID
		p.threads = entry.cntThreads

		n := 0
		for n < core.MAX_NAME_U16-1 {
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
			platform.PROCESS_QUERY_LIMITED_INFORMATION | platform.PROCESS_VM_READ,
			win.FALSE,
			p.pid,
		)
		if handle != nil {
			counters: platform.Process_Memory_Counters
			counters.cb = u32(size_of(platform.Process_Memory_Counters))
			if platform.GetProcessMemoryInfo(handle, &counters, counters.cb) {
				p.working_set = u64(counters.working_set_size)
			}

			creation, exit_time, kernel_time, user_time: win.FILETIME
			if win.GetProcessTimes(handle, &creation, &exit_time, &kernel_time, &user_time) {
				p.cpu_time = core.filetime_value(kernel_time) + core.filetime_value(user_time)
			}

			io: platform.Io_Counters
			if platform.GetProcessIoCounters(handle, &io) {
				p.io_read_total = io.read_bytes
				p.io_write_total = io.write_bytes
			}

			handles: u32
			if platform.GetProcessHandleCount(handle, &handles) {
				p.handles = handles
			}
			_ = win.CloseHandle(handle)
		}

		if has_old && elapsed_ms > 0 {
			if p.cpu_time > old.cpu_time && core.app.cores > 0 {
				delta := p.cpu_time - old.cpu_time
				units := f64(elapsed_ms) * 10000.0 * f64(core.app.cores)
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

	mark_window_processes(count)
	for i in 0..<count {
		classify_task_risk(&core.next_processes[i], self_session)
	}

	sort_processes(core.next_processes[:count])

	for i in 0..<count {
		core.app.processes[i] = core.next_processes[i]
	}
	core.app.process_count = count

	if core.app.has_selection {
		alive := false
		for i in 0..<count {
			if core.app.group_selected {
				if same_task_name(core.app.processes[i].name, core.app.selected_group) {
					alive = true
					break
				}
			} else if core.app.processes[i].pid == core.app.selected_pid {
				alive = true
				break
			}
		}
		if !alive {
			core.app.has_selection = false
			core.app.group_selected = false
			core.app.task = {}
			refresh_window_preview()
		}
	}

	build_task_groups()
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
	if !core.app.has_selection {
		if core.app.task.pid != 0 || core.app.task.group_mode {
			core.app.task = {}
		}
		return
	}

	// Start a fresh history when the selection changes.
	if core.app.group_selected {
		if !core.app.task.group_mode || !same_task_name(core.app.task.group, core.app.selected_group) {
			core.app.task = core.Task_Metrics{group_mode = true, group = core.app.selected_group}
		}
	} else if core.app.task.group_mode || core.app.task.pid != core.app.selected_pid {
		core.app.task = core.Task_Metrics{pid = core.app.selected_pid}
	}

	t := &core.app.task
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
		for i in 0..<core.app.process_count {
			p := &core.app.processes[i]
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
