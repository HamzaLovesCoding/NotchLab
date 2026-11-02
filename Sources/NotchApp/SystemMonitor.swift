import AppKit
import Darwin
import IOKit
import Observation
import SwiftUI

enum StatKind: CaseIterable, Identifiable {
    case cpu, memory, gpu

    var id: Self { self }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        }
    }
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "display"
        }
    }
    var color: Color {
        switch self {
        case .cpu: Color(red: 0.25, green: 0.55, blue: 1)
        case .memory: Color(red: 0.35, green: 0.85, blue: 0.4)
        case .gpu: Color(red: 0.8, green: 0.35, blue: 0.95)
        }
    }
}

struct CPUStats: Sendable {
    var usage = 0.0, user = 0.0, system = 0.0
}

struct MemoryStats: Sendable {
    var total = ProcessInfo.processInfo.physicalMemory
    var app: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, cached: UInt64 = 0, swapUsed: UInt64 = 0

    // Same definition as Activity Monitor's "Memory Used".
    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used ? total - used : 0 }
    var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
}

struct GPUStats: Sendable {
    var usage = 0.0, renderer = 0.0, tiler = 0.0
    var memoryInUse: UInt64 = 0
}

struct ProcessSample: Sendable {
    let pid: pid_t
    let value: Double
    let path: String
    let fallbackName: String
}

struct ProcessUsage: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage
    let value: Double
}

struct StatsSnapshot: Sendable {
    var cpu = CPUStats()
    var memory = MemoryStats()
    var gpu = GPUStats()
    var processes: [ProcessSample]?
}

/// Samples only while the Dev page is visible; nothing runs while the notch is closed.
@Observable
@MainActor
final class SystemMonitor {

    private(set) var cpu = CPUStats()
    private(set) var memory = MemoryStats()
    private(set) var gpu = GPUStats()
    private(set) var processes: [ProcessUsage] = []
    private(set) var detailKind: StatKind?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let sampler = StatsSampler()
    @ObservationIgnored private let queue = DispatchQueue(label: "notch.stats", qos: .utility)
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        detailKind = nil
        processes = []
    }

    func showDetail(_ kind: StatKind?) {
        detailKind = kind
        processes = []
        guard kind != nil else { return }
        tick()
        // Per-process rates need two samples; take the second quickly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.tick() }
    }

    private func tick() {
        let kind = detailKind
        let sampler = sampler
        queue.async { [weak self] in
            let snapshot = sampler.sample(processesFor: kind)
            DispatchQueue.main.async { self?.apply(snapshot, kind: kind) }
        }
    }

    private func apply(_ snapshot: StatsSnapshot, kind: StatKind?) {
        cpu = snapshot.cpu
        memory = snapshot.memory
        gpu = snapshot.gpu
        if let samples = snapshot.processes, kind != nil, kind == detailKind {
            processes = samples.map { sample in
                let (name, icon) = identity(of: sample)
                return ProcessUsage(id: sample.pid, name: name, icon: icon, value: sample.value)
            }
        }
    }

    private func identity(of sample: ProcessSample) -> (String, NSImage) {
        if let app = NSRunningApplication(processIdentifier: sample.pid), let name = app.localizedName {
            return (name, app.icon ?? genericIcon)
        }
        let name = sample.path.isEmpty ? sample.fallbackName : (sample.path as NSString).lastPathComponent
        // Helpers live inside their app's bundle; show the outermost app's icon.
        guard let range = sample.path.range(of: ".app/") else { return (name, genericIcon) }
        let bundle = String(sample.path[..<range.lowerBound]) + ".app"
        if let cached = iconCache[bundle] { return (name, cached) }
        let icon = NSWorkspace.shared.icon(forFile: bundle)
        iconCache[bundle] = icon
        return (name, icon)
    }

    private var genericIcon: NSImage {
        if let cached = iconCache[""] { return cached }
        let icon = NSWorkspace.shared.icon(for: .unixExecutable)
        iconCache[""] = icon
        return icon
    }
}

/// Raw sampling. Only used from SystemMonitor's serial queue.
final class StatsSampler: @unchecked Sendable {
    private let host = mach_host_self()
    private let timebase: (numer: UInt64, denom: UInt64)
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousProcessTimes: [pid_t: UInt64] = [:]
    private var previousProcessSampleTime: UInt64 = 0
    private var previousKind: StatKind?

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = (UInt64(info.numer), UInt64(info.denom))
    }

    func sample(processesFor kind: StatKind?) -> StatsSnapshot {
        var snapshot = StatsSnapshot(cpu: cpuStats(), memory: memoryStats())
        let (gpu, gpuTimes) = gpuStats(perProcess: kind == .gpu)
        snapshot.gpu = gpu

        if kind != previousKind {
            previousKind = kind
            previousProcessTimes = [:]
        }
        switch kind {
        case .cpu: snapshot.processes = rates(from: cpuTimes().mapValues { ($0, "") })
        case .gpu: snapshot.processes = rates(from: gpuTimes)
        case .memory: snapshot.processes = topFootprints()
        case nil: break
        }
        return snapshot
    }

    // MARK: Totals

    private func cpuStats() -> CPUStats {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return CPUStats() }
        let ticks = (user: load.cpu_ticks.0, system: load.cpu_ticks.1, idle: load.cpu_ticks.2, nice: load.cpu_ticks.3)
        // First sample: average since boot. Counters are 32-bit, so subtract with wraparound.
        let base = previousTicks ?? (0, 0, 0, 0)
        previousTicks = ticks
        let user = Double((ticks.user &- base.user) &+ (ticks.nice &- base.nice))
        let system = Double(ticks.system &- base.system)
        let idle = Double(ticks.idle &- base.idle)
        let total = user + system + idle
        guard total > 0 else { return CPUStats() }
        return CPUStats(usage: (user + system) / total * 100, user: user / total * 100, system: system / total * 100)
    }

    private func memoryStats() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var memory = MemoryStats()
        guard result == KERN_SUCCESS else { return memory }
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let page = UInt64(pageSize)
        let internalPages = UInt64(stats.internal_page_count), purgeable = UInt64(stats.purgeable_count)
        memory.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        memory.wired = UInt64(stats.wire_count) * page
        memory.compressed = UInt64(stats.compressor_page_count) * page
        memory.cached = (UInt64(stats.external_page_count) + purgeable) * page
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { memory.swapUsed = swap.xsu_used }
        return memory
    }

    /// Overall utilization from the accelerator, plus cumulative GPU time per process from
    /// its user clients (each Metal client reports `accumulatedGPUTime` in nanoseconds).
    private func gpuStats(perProcess: Bool) -> (GPUStats, [pid_t: (UInt64, String)]) {
        var stats = GPUStats()
        var perPid: [pid_t: (UInt64, String)] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return (stats, perPid)
        }
        defer { IOObjectRelease(iterator) }
        var accelerator = IOIteratorNext(iterator)
        while accelerator != 0 {
            if let perf = property(accelerator, "PerformanceStatistics") as? [String: Any] {
                stats.usage = max(stats.usage, double(perf["Device Utilization %"]))
                stats.renderer = max(stats.renderer, double(perf["Renderer Utilization %"]))
                stats.tiler = max(stats.tiler, double(perf["Tiler Utilization %"]))
                stats.memoryInUse += UInt64(double(perf["In use system memory"]))
            }
            if perProcess {
                var children: io_iterator_t = 0
                if IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS {
                    var child = IOIteratorNext(children)
                    while child != 0 {
                        if let creator = property(child, "IOUserClientCreator") as? String,
                           let usage = property(child, "AppUsage") as? [[String: Any]] {
                            let (pid, name) = Self.parseCreator(creator)
                            let time = usage.reduce(UInt64(0)) { $0 + ((($1["accumulatedGPUTime"]) as? NSNumber)?.uint64Value ?? 0) }
                            if pid > 0 { perPid[pid] = ((perPid[pid]?.0 ?? 0) + time, name) }
                        }
                        IOObjectRelease(child)
                        child = IOIteratorNext(children)
                    }
                    IOObjectRelease(children)
                }
            }
            IOObjectRelease(accelerator)
            accelerator = IOIteratorNext(iterator)
        }
        return (stats, perPid)
    }

    /// "pid 392, WindowServer" -> (392, "WindowServer")
    private static func parseCreator(_ creator: String) -> (pid_t, String) {
        let parts = creator.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let pid = parts.first.flatMap { pid_t($0.replacingOccurrences(of: "pid ", with: "")) } ?? 0
        return (pid, parts.count > 1 ? parts[1] : "")
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func double(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }

    // MARK: Processes

    private func allPids() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(filled, 0))).filter { $0 > 0 }
    }

    /// CPU time in nanoseconds for every process we're allowed to inspect (root-owned
    /// processes need privileges and are skipped).
    private func cpuTimes() -> [pid_t: UInt64] {
        var times: [pid_t: UInt64] = [:]
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        for pid in allPids() {
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            times[pid] = (info.pti_total_user + info.pti_total_system) * timebase.numer / timebase.denom
        }
        return times
    }

    /// Converts cumulative nanosecond counters into percent of one core since the last call.
    private func rates(from times: [pid_t: (UInt64, String)]) -> [ProcessSample] {
        let now = DispatchTime.now().uptimeNanoseconds
        defer {
            previousProcessTimes = times.mapValues(\.0)
            previousProcessSampleTime = now
        }
        guard !previousProcessTimes.isEmpty, now > previousProcessSampleTime else { return [] }
        let interval = Double(now - previousProcessSampleTime)
        let rates: [(pid_t, Double, String)] = times.compactMap { pid, entry in
            guard let previous = previousProcessTimes[pid], entry.0 > previous else { return nil }
            return (pid, Double(entry.0 - previous) / interval * 100, entry.1)
        }
        return rates.sorted { $0.1 > $1.1 }.prefix(10).filter { $0.1 >= 0.1 }.map {
            ProcessSample(pid: $0.0, value: $0.1, path: Self.path(of: $0.0), fallbackName: $0.2)
        }
    }

    private func topFootprints() -> [ProcessSample] {
        var footprints: [(pid_t, UInt64)] = []
        for pid in allPids() {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            if status == 0 { footprints.append((pid, info.ri_phys_footprint)) }
        }
        return footprints.sorted { $0.1 > $1.1 }.prefix(10).map {
            ProcessSample(pid: $0.0, value: Double($0.1), path: Self.path(of: $0.0), fallbackName: "")
        }
    }

    private static func path(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : ""
    }
}
