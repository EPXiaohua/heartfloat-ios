import Foundation
import UIKit
import SwiftUI
import AVFoundation

/// PiP 帧渲染器：把心率 UI 直接绘制进 CMSampleBuffer（官方视频通话画中画方案，无载体视频）。
/// 样式 0：数字卡片（数字 + BPM 标签，沿用悬浮窗设置的位置/颜色/字号/圆体）
/// 样式 1：心率曲线（60 秒滚动曲线 + 渐变填充 + 节拍光斑，BPM 数字按位置设置叠加）
final class HeartRatePipFrameRenderer {

    /// 渲染分辨率（3:2，与画中画窗口比例匹配）
    static let size = CGSize(width: 240, height: 160)
    static let frameRate: Int32 = 30

    /// 全局设置（每帧读取，修改即时生效）
    var settings: SettingsManager?
    /// 曲线数据源（与主页实时图表同源的 60 秒窗口采样）
    var samples: [(Date, Double)] = []
    /// 当前心率（数字显示值）
    var heartRate: Int = 0
    /// 是否已连接（未连接时显示占位）
    var isConnected: Bool = false

    private var pixelPool: CVPixelBufferPool?

    // MARK: - 帧生成

    /// 渲染一帧并包装为 CMSampleBuffer：
    /// @2x 位图绘制 UI → blit 进 CVPixelBufferPool 的 buffer → 包 sample 并设 DisplayImmediately。
    /// DisplayImmediately 是关键：sample buffer layer 没有 timebase，缺了它帧永远不会被展示（黑屏）。
    func makeSampleBuffer(at hostTime: CMTime) -> CMSampleBuffer? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: Self.size, format: format)
        let image = renderer.image { ctx in
            // 渲染器上下文已是 UIKit 左上原点坐标系，直接画即可
            self.draw(into: ctx.cgContext, bounds: CGRect(origin: .zero, size: Self.size))
        }
        guard let cgImage = image.cgImage else { return nil }

        let pixels = CGSize(width: cgImage.width, height: cgImage.height)
        guard let pool = pixelBufferPool(size: pixels) else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        let blit = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        blit?.draw(cgImage, in: CGRect(origin: .zero, size: pixels))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard blit != nil else { return nil }

        var formatDescription: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: buffer,
                formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return nil }

        // PTS 取 hostTime 当前时刻 + DisplayImmediately：每帧到达即显示
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: hostTime,
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: buffer,
                formatDescription: formatDescription,
                sampleTiming: &timing,
                sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let entry = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                entry,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    private func pixelBufferPool(size: CGSize) -> CVPixelBufferPool? {
        if let pixelPool, CVPixelBufferPoolGetPixelWidth(pixelPool) == Int(size.width) {
            return pixelPool
        }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var created: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(
                kCFAllocatorDefault, nil, attributes as CFDictionary,
                &created) == kCVReturnSuccess,
              let created else { return nil }
        pixelPool = created
        return created
    }

    // MARK: - 绘制

    private func draw(into ctx: CGContext, bounds: CGRect) {
        // 背景：亮度设置 0 = 纯黑，100 = 纯白（不透明视频帧用实色）
        let brightness = max(0, min(100, settings?.backgroundBrightness ?? 0)) / 100.0
        ctx.setFillColor(UIColor(white: CGFloat(brightness), alpha: 1).cgColor)
        ctx.fill(bounds)

        let s = settings
        if s?.pipStyle == 1 {
            // 曲线样式：曲线占窗口底部 42%，数字叠加在上部 55% 区域（避免与曲线重叠）
            drawCurve(in: ctx, bounds: bounds, settings: s)
            var textBounds = bounds
            textBounds.size.height = bounds.height * 0.55
            drawNumberAndLabel(in: ctx, bounds: textBounds, settings: s, withPlate: true)
        } else {
            drawNumberAndLabel(in: ctx, bounds: bounds, settings: s, withPlate: false)
        }
    }

    // MARK: - 心率曲线（样式 1）

    private func drawCurve(in ctx: CGContext, bounds: CGRect, settings s: SettingsManager?) {
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }

        let color = UIColor(Color(hex: s?.bpmNumberColorHex ?? "FF6B6B"))
        // 曲线绘图区：窗口底部 42%，左右留 10pt 边距
        let curveHeight = bounds.height * 0.42
        let plot = CGRect(
            x: 10, y: bounds.maxY - curveHeight - 8,
            width: bounds.width - 20, height: curveHeight)
        let valid = samples.filter { $0.1 > 0.05 }

        guard valid.count >= 2, let newest = valid.last else {
            // 占位提示
            let hint = isConnected ? "正在采集心率数据..." : "连接手环后显示心率曲线"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(white: 0.5, alpha: 1)
            ]
            let size = hint.size(withAttributes: attrs)
            hint.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: plot.midY - size.height / 2), withAttributes: attrs)
            return
        }

        // 网格线（按背景亮度选深浅墨色）
        let brightness = max(0, min(100, s?.backgroundBrightness ?? 0)) / 100.0
        let gridColor = brightness > 0.5
            ? UIColor(white: 0, alpha: 0.06).cgColor
            : UIColor(white: 1, alpha: 0.09).cgColor
        ctx.setStrokeColor(gridColor)
        ctx.setLineWidth(1)
        for ratio in [0.25, 0.5, 0.75] {
            let y = plot.minY + plot.height * CGFloat(ratio)
            ctx.move(to: CGPoint(x: plot.minX, y: y))
            ctx.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        ctx.strokePath()

        // 值域自适应：贴数据范围，span 下限 20 保证安静心率也有起伏
        let values = valid.map { $0.1 }
        let vmin = values.min() ?? 60
        let vmax = values.max() ?? 100
        let mid = (vmin + vmax) / 2
        let span = max(vmax - vmin, 20) * 1.15
        let lo = mid - span / 2
        let hi = mid + span / 2

        // 时间轴：视口右缘跟随最新采样点，两次采样间画面静止
        let base = newest.0
        let oldest = valid[0].0
        let viewport = min(60.0, max(base.timeIntervalSince(oldest), 5.0))

        let yFor: (Double) -> CGFloat = { v in
            let ratio = min(max((v - lo) / max(hi - lo, 1), -0.2), 1.2)
            return plot.maxY - CGFloat(ratio) * plot.height
        }
        let xFor: (Date) -> CGFloat = { t in
            plot.maxX - CGFloat(base.timeIntervalSince(t) / viewport) * plot.width
        }

        // 剪裁绘图区后绘制填充与折线
        ctx.saveGState()
        UIBezierPath(rect: plot).addClip()

        var line = UIBezierPath()
        var started = false
        for (t, v) in valid {
            let p = CGPoint(x: xFor(t), y: yFor(v))
            if started {
                line.addLine(to: p)
            } else {
                line.move(to: p)
                started = true
            }
        }

        // 渐变填充
        let fill = line.copy() as! UIBezierPath
        fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        fill.close()
        let colors = [
            color.withAlphaComponent(0.30).cgColor,
            color.withAlphaComponent(0.02).cgColor
        ]
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray, locations: [0, 1]) {
            ctx.saveGState()
            fill.addClip()
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: plot.minY),
                end: CGPoint(x: 0, y: plot.maxY),
                options: [])
            ctx.restoreGState()
        }

        // 折线描边
        color.setStroke()
        line.lineWidth = 2.5
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.stroke()
        ctx.restoreGState()

        // 当前心率圆点贴右缘，按心率节拍向外扩散
        let head = CGPoint(x: plot.maxX, y: yFor(newest.1))
        let bpm = max(heartRate, 40)
        let beatInterval = 60.0 / Double(bpm)
        let phase = CACurrentMediaTime().truncatingRemainder(dividingBy: beatInterval) / beatInterval
        let expand = 1 - phase

        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8)).fill()
        color.withAlphaComponent(0.5 * expand).setStroke()
        let ring = UIBezierPath(
            ovalIn: CGRect(x: head.x - 5 - 7 * expand, y: head.y - 5 - 7 * expand,
                           width: 10 + 14 * expand, height: 10 + 14 * expand))
        ring.lineWidth = 1.5
        ring.stroke()
    }

    // MARK: - 数字 + BPM 标签（两种样式共用布局）

    /// withPlate：曲线样式下文字后面画半透明底板保证可读性；数字样式背景纯色无需底板
    private func drawNumberAndLabel(in ctx: CGContext, bounds: CGRect, settings s: SettingsManager?, withPlate: Bool) {
        guard let s = s else { return }
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }

        let scale = min(bounds.width / 240.0, bounds.height / 160.0)
        let numberText = isConnected && heartRate > 0 ? "\(heartRate)" : "--"
        let numberColor = UIColor(Color(hex: s.bpmNumberColorHex))
        let labelColor = UIColor(Color(hex: s.bpmLabelColorHex))

        let baseNumberFont = roundedFont(ofSize: CGFloat(s.bpmNumberSize) * 2.5 * scale, weight: .bold)
        let labelFont = UIFont.systemFont(ofSize: CGFloat(s.bpmLabelSize) * 2.0 * scale, weight: .medium)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: labelColor]

        let maxTextWidth = bounds.width - 16
        // 数字超宽时按比例缩小字号（等效 adjustsFontSizeToFitWidth）
        var numberFont = baseNumberFont
        var numberAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: numberColor]
        var numberSize = numberText.size(withAttributes: numberAttrs)
        if numberSize.width > maxTextWidth {
            numberFont = roundedFont(ofSize: numberFont.pointSize * maxTextWidth / numberSize.width, weight: .bold)
            numberAttrs = [.font: numberFont, .foregroundColor: numberColor]
            numberSize = numberText.size(withAttributes: numberAttrs)
        }
        let labelSize = "BPM".size(withAttributes: labelAttrs)

        let spacing = 8 * scale
        // 高度钳制：纵向排列时数字+标签+间距超出绘制区则缩小数字字号（曲线样式上部区域较小）
        if numberSize.height + labelSize.height + spacing > bounds.height {
            let ratio = (bounds.height - labelSize.height - spacing) / numberSize.height
            numberFont = roundedFont(ofSize: numberFont.pointSize * max(ratio, 0.3), weight: .bold)
            numberAttrs = [.font: numberFont, .foregroundColor: numberColor]
            numberSize = numberText.size(withAttributes: numberAttrs)
        }
        let numberW = min(numberSize.width + 4, maxTextWidth)
        let labelW = min(labelSize.width + 4, maxTextWidth)
        let cx = bounds.midX
        let cy = bounds.midY

        let numberRect: CGRect
        let labelRect: CGRect
        switch s.bpmPosition {
        case 0: // BPM 在数字上方
            numberRect = CGRect(x: cx - numberW / 2, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
            labelRect = CGRect(x: cx - labelW / 2, y: numberRect.minY - labelSize.height - spacing, width: labelW, height: labelSize.height)
        case 1: // BPM 在数字下方
            numberRect = CGRect(x: cx - numberW / 2, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
            labelRect = CGRect(x: cx - labelW / 2, y: numberRect.maxY + spacing, width: labelW, height: labelSize.height)
        case 2: // BPM 在数字左侧
            let totalW = numberW + spacing + labelW
            labelRect = CGRect(x: cx - totalW / 2, y: cy - labelSize.height / 2, width: labelW, height: labelSize.height)
            numberRect = CGRect(x: labelRect.maxX + spacing, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
        default: // BPM 在数字右侧
            let totalW = numberW + spacing + labelW
            numberRect = CGRect(x: cx - totalW / 2, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
            labelRect = CGRect(x: numberRect.maxX + spacing, y: cy - labelSize.height / 2, width: labelW, height: labelSize.height)
        }

        // 曲线样式下的可读性底板（覆盖数字与标签的外包区域）
        if withPlate {
            let brightness = max(0, min(100, s.backgroundBrightness)) / 100.0
            let plateColor = UIColor(white: CGFloat(brightness), alpha: 0.8)
            let union = numberRect.union(labelRect).insetBy(dx: -6 * scale, dy: -4 * scale)
            plateColor.setFill()
            UIBezierPath(roundedRect: union, cornerRadius: 8 * scale).fill()
        }

        // 文字绘制（draw(at:) 定位到外包矩形内居中）
        numberText.draw(
            at: CGPoint(x: numberRect.midX - numberSize.width / 2, y: numberRect.midY - numberSize.height / 2),
            withAttributes: numberAttrs)
        "BPM".draw(
            at: CGPoint(x: labelRect.midX - labelSize.width / 2, y: labelRect.midY - labelSize.height / 2),
            withAttributes: labelAttrs)
    }

    private func roundedFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }
}
