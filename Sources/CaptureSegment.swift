import AppKit
import AVFoundation
import Dispatch
import Foundation
import ScreenCaptureKit
import Darwin

@available(macOS 13.0, *)
final class DisplayRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let outputURL: URL
    private let width: Int
    private let height: Int
    private let fps: Int
    private var writer: AVAssetWriter!
    private var input: AVAssetWriterInput!
    private var stream: SCStream?
    private var started = false
    private var captureError: Error?
    private var frameCount = 0

    init(outputURL: URL, width: Int, height: Int, fps: Int) {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.fps = fps
    }

    func start(displayIndex: Int) async throws {
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CaptureError.outputAlreadyExists(outputURL.path)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard content.displays.indices.contains(displayIndex) else {
            throw CaptureError.displayNotFound(displayIndex, content.displays.count)
        }
        let display = content.displays[displayIndex]
        let filter = SCContentFilter(display: display, excludingWindows: [])

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_200_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureError.writerSetup("cannot add H.264 input") }
        writer.add(input)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 5
        config.capturesAudio = false
        config.showsCursor = true
        config.showMouseClicks = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "work-material-capture.frames"))
        self.stream = stream
        try await stream.startCapture()
        print("CAPTURE_STARTED display=\(displayIndex) size=\(width)x\(height) fps=\(fps) audio=false output=\(outputURL.path)")
        fflush(stdout)
    }

    func stop() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
        input.markAsFinished()
        await writer.finishWriting()
        if let captureError { throw captureError }
        guard writer.status == .completed else {
            throw writer.error ?? CaptureError.writerSetup("writer ended with \(writer.status.rawValue)")
        }
        guard frameCount > 0 else { throw CaptureError.writerSetup("no video frames received") }
        print("CAPTURE_FINISHED frames=\(frameCount) output=\(outputURL.path)")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sampleBuffer), captureError == nil else { return }
        if !started {
            guard writer.startWriting() else {
                captureError = writer.error ?? CaptureError.writerSetup("startWriting failed")
                return
            }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            started = true
        }
        guard input.isReadyForMoreMediaData else { return }
        if !input.append(sampleBuffer) {
            captureError = writer.error ?? CaptureError.writerSetup("append failed")
            return
        }
        frameCount += 1
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        captureError = error
    }
}

final class TerminationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    func set() { lock.lock(); requested = true; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return requested }
}

enum CaptureError: LocalizedError {
    case outputAlreadyExists(String)
    case displayNotFound(Int, Int)
    case writerSetup(String)

    var errorDescription: String? {
        switch self {
        case .outputAlreadyExists(let path): return "output already exists: \(path)"
        case .displayNotFound(let requested, let count): return "display \(requested) not available; visible displays: \(count)"
        case .writerSetup(let message): return message
        }
    }
}

struct Options {
    var output: String = ""
    var seconds: Double = 60
    var fps: Int = 12
    var displayIndex: Int = 0
    var maxHeight: Int = 720
}

func parseOptions() throws -> Options {
    var options = Options()
    var index = 1
    let arguments = CommandLine.arguments
    while index < arguments.count {
        let argument = arguments[index]
        guard index + 1 < arguments.count else { throw CaptureError.writerSetup("missing value for \(argument)") }
        let value = arguments[index + 1]
        switch argument {
        case "--output": options.output = value
        case "--seconds": options.seconds = Double(value) ?? 0
        case "--fps": options.fps = Int(value) ?? 0
        case "--display-index": options.displayIndex = Int(value) ?? -1
        case "--max-height": options.maxHeight = Int(value) ?? 0
        default: throw CaptureError.writerSetup("unknown option: \(argument)")
        }
        index += 2
    }
    guard !options.output.isEmpty, options.seconds > 0, options.fps >= 1, options.fps <= 30, options.displayIndex >= 0, options.maxHeight >= 240 else {
        throw CaptureError.writerSetup("usage: capture-segment --output /absolute/file.mp4 --seconds 60 --fps 12 --display-index 0 --max-height 720")
    }
    return options
}

@main
struct CaptureSegmentMain {
    @MainActor static func main() async {
        do {
            _ = NSApplication.shared
            NSApplication.shared.setActivationPolicy(.prohibited)
            let options = try parseOptions()
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard content.displays.indices.contains(options.displayIndex) else {
                throw CaptureError.displayNotFound(options.displayIndex, content.displays.count)
            }
            let display = content.displays[options.displayIndex]
            let ratio = Double(display.width) / Double(display.height)
            let height = max(240, options.maxHeight - options.maxHeight % 2)
            let width = max(320, Int((Double(height) * ratio).rounded()) / 2 * 2)
            let recorder = DisplayRecorder(outputURL: URL(fileURLWithPath: options.output), width: width, height: height, fps: options.fps)
            // TERM is intentionally converted into an orderly writer finalization. This is used by
            // stop.sh and the resource guard; a forced exit would leave an MP4 without its moov atom.
            Darwin.signal(SIGTERM, SIG_IGN)
            let terminator = DispatchSource.makeSignalSource(signal: SIGTERM, queue: DispatchQueue.global())
            let terminationFlag = TerminationFlag()
            terminator.setEventHandler { terminationFlag.set() }
            terminator.resume()
            try await recorder.start(displayIndex: options.displayIndex)
            let deadline = Date().addingTimeInterval(options.seconds)
            var terminated = false
            while Date() < deadline {
                if terminationFlag.get() {
                    terminated = true
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try await recorder.stop()
            terminator.cancel()
            if terminated {
                print("CAPTURE_TERMINATED_GRACEFULLY output=\(options.output)")
            }
        } catch {
            fputs("CAPTURE_FAILED \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
