import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Darwin
import CryptoKit

@available(macOS 13.0, *)
@main
struct ContextWatcherMain {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 2 else { fputs("usage: context-watcher /absolute/output-root\n", stderr); exit(2) }
        let watcher = ContextWatcher(root: URL(fileURLWithPath: CommandLine.arguments[1]))
        await watcher.run()
    }
}

@available(macOS 13.0, *)
@MainActor
final class ContextWatcher {
    let root: URL; let timeline: URL; let screenshots: URL
    var previous = ""; var previousName = "unknown"; var previousBundle = "unknown"; var previousTitle = "unknown"; var sessionStarted = Date(); var lastShot = Date.distantPast; var lastHash = ""; var memoryWarningUntil = Date.distantPast; var lastMode = ""; var lastCPU = 0.0; var resourceOverSeconds = 0; var stopRequested = false
    init(root: URL) { self.root = root; timeline = root.appendingPathComponent("context-timeline.jsonl"); screenshots = root.appendingPathComponent("context-screenshots") }
    func run() async {
        do { try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true) } catch { fputs("CONTEXT_FAILED \(error)\n", stderr); return }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        pressure.setEventHandler { [weak self] in Task { @MainActor in self?.memoryWarningUntil = Date().addingTimeInterval(60) } }; pressure.resume()
        signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        term.setEventHandler { [weak self] in self?.stopRequested = true }
        interrupt.setEventHandler { [weak self] in self?.stopRequested = true }
        term.resume(); interrupt.resume()
        defer { pressure.cancel(); term.cancel(); interrupt.cancel() }
        while !Task.isCancelled && !stopRequested {
            await sample()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        if !previous.isEmpty {
            append("{\"at\":\"\(iso())\",\"event\":\"session_end\",\"duration_seconds\":\(Int(Date().timeIntervalSince(sessionStarted))),\"application\":\"\(escape(previousName))\",\"bundle_id\":\"\(escape(previousBundle))\",\"window_title\":\"\(escape(previousTitle))\",\"ended_reason\":\"stopped\"}")
        }
    }
    func sample() async {
        let stats = resourceStats()
        let cpu = lastCPU == 0 ? 0 : max(0, (stats.cpuSeconds - lastCPU) / 5 * 100); lastCPU = stats.cpuSeconds
        let resourceOver = stats.rssBytes > 80 * 1024 * 1024 || cpu > 2
        resourceOverSeconds = resourceOver ? resourceOverSeconds + 5 : 0
        let app = NSWorkspace.shared.frontmostApplication
        let name = app?.localizedName ?? "unknown", bundle = app?.bundleIdentifier ?? "unknown", pid = app?.processIdentifier ?? 0
        let title = focusedTitle(pid: pid) ?? "unknown"
        let idle = ProcessInfo.processInfo.environment["WORK_MATERIAL_TEST_ACTIVE"] == "1" ? 0 : idleSeconds()
        let key = "\(bundle)|\(title)", changed = key != previous
        let memoryWarning = Date() < memoryWarningUntil
        let mode = resourceOver ? "resource_limited" : (idle >= 120 ? "idle" : (memoryWarning ? "memory_pressure" : (isSensitive(name, bundle) ? "sensitive" : "active")))
        if mode != lastMode { append("{\"at\":\"\(iso())\",\"event\":\"state\",\"state\":\"\(mode)\",\"rss_bytes\":\(stats.rssBytes),\"cpu_percent\":\(String(format: "%.3f", cpu)),\"resource_over_seconds\":\(resourceOverSeconds),\"application\":\"\(escape(name))\",\"bundle_id\":\"\(escape(bundle))\",\"window_title\":\"\(escape(title))\",\"idle_seconds\":\(Int(idle))}"); lastMode = mode }
        if changed && !previous.isEmpty { append("{\"at\":\"\(iso())\",\"event\":\"session_end\",\"duration_seconds\":\(Int(Date().timeIntervalSince(sessionStarted))),\"application\":\"\(escape(previousName))\",\"bundle_id\":\"\(escape(previousBundle))\",\"window_title\":\"\(escape(previousTitle))\"}") }
        if changed { previous = key; previousName = name; previousBundle = bundle; previousTitle = title; sessionStarted = Date(); append("{\"at\":\"\(iso())\",\"event\":\"session_start\",\"application\":\"\(escape(name))\",\"bundle_id\":\"\(escape(bundle))\",\"window_title\":\"\(escape(title))\",\"privacy\":\"unreviewed\",\"public_eligible\":false}") }
        var shot: String? = nil
        let canShot = mode == "active"
        if canShot && ((changed && Date().timeIntervalSince(lastShot) >= 30) || Date().timeIntervalSince(lastShot) >= 120) {
            shot = await capture()
            if let shot { append("{\"at\":\"\(iso())\",\"event\":\"screenshot\",\"reason\":\"\(changed ? "changed" : "heartbeat")\",\"application\":\"\(escape(name))\",\"bundle_id\":\"\(escape(bundle))\",\"window_title\":\"\(escape(title))\",\"screenshot\":\"\(escape(shot))\",\"privacy\":\"unreviewed\",\"public_eligible\":false}") }
            else { append("{\"at\":\"\(iso())\",\"event\":\"screenshot_failed\",\"reason\":\"\(changed ? "changed" : "heartbeat")\",\"application\":\"\(escape(name))\",\"bundle_id\":\"\(escape(bundle))\",\"window_title\":\"\(escape(title))\"}") }
        }
        if resourceOverSeconds >= 60 { append("{\"at\":\"\(iso())\",\"event\":\"resource_exit\",\"rss_bytes\":\(stats.rssBytes),\"cpu_percent\":\(String(format: "%.3f", cpu))}"); stopRequested = true }
    }
    func focusedTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid); var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success, let w = window else { return nil }
        var title: CFTypeRef?; guard AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }
    func capture() async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            let cfg = SCStreamConfiguration(); cfg.width = 1280; cfg.height = 720; cfg.showsCursor = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { return nil }
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined(); guard hash != lastHash else { return nil }; lastHash = hash
            let file = screenshots.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).jpg")
            try data.write(to: file, options: .atomic); lastShot = Date(); return file.path
        } catch { return nil }
    }
    func isSensitive(_ name: String, _ bundle: String) -> Bool {
        let file = URL(fileURLWithPath: "/Users/macmini/Developer/work-material-capture/config/sensitive-apps.txt")
        let entries = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        return entries.contains { !$0.hasPrefix("#") && ($0 == name || $0 == bundle) }
    }
    func append(_ line: String) { if let d = (line + "\n").data(using: .utf8), let h = try? FileHandle(forWritingTo: timeline) { _ = try? h.seekToEnd(); try? h.write(contentsOf: d); try? h.close() } else { FileManager.default.createFile(atPath: timeline.path, contents: (line + "\n").data(using: .utf8)) } }
    func escape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") }
    func iso() -> String { ISO8601DateFormatter().string(from: Date()) }
    func idleSeconds() -> Double {
        let events: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return events.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }
    func resourceStats() -> (rssBytes: UInt64, cpuSeconds: Double) {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return (result == KERN_SUCCESS ? UInt64(info.resident_size) : 0, cpu)
    }
}
