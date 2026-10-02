import Foundation
import UIKit
import AVFoundation

/// 生成画中画载体视频（纯黑，无内容）。
/// 参考 CaiWanFeng/PiP 方案：视频仅作为画中画的"载体"，
/// 真正的心率 UI 由 HeartRatePipView 叠加渲染到画中画窗口上，
/// 因此视频本身不需要包含任何文字/颜色内容，也就不存在颜色空间问题。
final class HeartRateVideoRenderer {

    static let shared = HeartRateVideoRenderer()

    private let videoSize = CGSize(width: 240, height: 160)
    private let frameRate: Int32 = 15
    private var cachedURL: URL?

    /// 生成（或复用缓存的）纯黑循环视频
    func generateBlackVideo() -> URL? {
        if let url = cachedURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pip_carrier_black.mp4")

        // 已存在旧文件则先删除
        try? FileManager.default.removeItem(at: url)

        let settingsDict: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 100000,
                AVVideoMaxKeyFrameIntervalKey: frameRate
            ]
        ]

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            return nil
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settingsDict)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height)
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = frameRate * 2 // 2 秒循环视频
        for frameIndex in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let buffer = createBlackPixelBuffer() else { continue }
            let time = CMTime(value: Int64(frameIndex), timescale: frameRate)
            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()

        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()

        if writer.status == .completed {
            cachedURL = url
            return url
        }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    private func createBlackPixelBuffer() -> CVPixelBuffer? {
        let width = Int(videoSize.width)
        let height = Int(videoSize.height)

        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 纯黑填充 —— 黑色在任何颜色空间下都是黑色，杜绝色偏
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}
