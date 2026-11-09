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
    private var poolSize: CGSize = .zero

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
        if let pixelPool, poolSize == size { return pixelPool }
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
        poolSize = size
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
            // 曲线样式：监护仪风格，整窗由 drawCurve 独立绘制（状态条/波形/底栏）
            drawCurve(in: ctx, bounds: bounds, settings: s)
        } else {
            drawNumberAndLabel(in: ctx, bounds: bounds, settings: s)
        }
    }

    // MARK: - 心率曲线（样式 1）

    private func drawCurve(in ctx: CGContext, bounds: CGRect, settings s: SettingsManager?) {
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }

        let color = UIColor(Color(hex: s?.bpmNumberColorHex ?? "FF6B6B"))
        let brightness = max(0, min(100, s?.backgroundBrightness ?? 0)) / 100.0
        let inkColor = brightness > 0.5
            ? UIColor(white: 0, alpha: 0.45)
            : UIColor(white: 1, alpha: 0.45)
        let now = Date()

        // 三段布局：顶部状态条 / 中间监护曲线 / 底部 心脏图标 + 心率数字
        let statusHeight = bounds.height * 0.14
        let bottomHeight = bounds.height * 0.20
        let plot = CGRect(
            x: 12, y: statusHeight + 6,
            width: bounds.width - 24,
            height: bounds.height - statusHeight - bottomHeight - 12)
        let valid = samples.filter { $0.1 > 0.05 }

        // 顶部状态条：左 延迟(ms)，右 频率(Hz)
        let statusFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let statusAttrs: [NSAttributedString.Key: Any] = [.font: statusFont, .foregroundColor: inkColor]
        if isConnected, let newest = valid.last {
            let latencyMs = max(0, Int(now.timeIntervalSince(newest.0) * 1000))
            let latencyText = latencyMs > 9999 ? "延迟 --ms" : "延迟 \(latencyMs)ms"
            var hzText = "1.0 Hz"
            if valid.count >= 3 {
                let tail = valid.suffix(9)
                let intervals = zip(tail.dropFirst(), tail.dropLast())
                    .map { $0.0.timeIntervalSince($1.0) }
                    .filter { $0 > 0.2 && $0 < 5 }
                if !intervals.isEmpty {
                    let avg = intervals.reduce(0, +) / Double(intervals.count)
                    if avg > 0 { hzText = String(format: "%.1f Hz", 1.0 / avg) }
                }
            }
            latencyText.draw(at: CGPoint(x: plot.minX, y: 5), withAttributes: statusAttrs)
            let hzSize = hzText.size(withAttributes: statusAttrs)
            hzText.draw(at: CGPoint(x: plot.maxX - hzSize.width, y: 5), withAttributes: statusAttrs)
        } else {
            "未连接".draw(at: CGPoint(x: plot.minX, y: 5), withAttributes: statusAttrs)
        }

        guard valid.count >= 2, let newest = valid.last else {
            let hint = isConnected ? "正在采集心率数据..." : "连接手环后显示心率曲线"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(white: 0.5, alpha: 1)
            ]
            let size = hint.size(withAttributes: attrs)
            hint.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: plot.midY - size.height / 2), withAttributes: attrs)
            drawBottomBar(in: ctx, bounds: bounds, bottomHeight: bottomHeight, color: color)
            return
        }

        // 网格线（按背景亮度选深浅墨色）
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

        // 医用监护风格折线：纯净圆角细线，无填充
        ctx.saveGState()
        UIBezierPath(rect: plot).addClip()
        let line = UIBezierPath()
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
        color.setStroke()
        line.lineWidth = 2
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.stroke()
        ctx.restoreGState()

        // 两端淡入淡出：用背景色横向渐变盖住曲线两端（监护仪滚入滚出的观感）
        let bg = UIColor(white: CGFloat(brightness), alpha: 1)
        let fadeWidth = plot.width * 0.16
        let fadeRects = [
            CGRect(x: plot.minX, y: plot.minY - 2, width: fadeWidth, height: plot.height + 4),
            CGRect(x: plot.maxX - fadeWidth, y: plot.minY - 2, width: fadeWidth, height: plot.height + 4)
        ]
        let fadeEnds = [plot.minX + fadeWidth, plot.maxX - fadeWidth]
        for (rect, end) in zip(fadeRects, fadeEnds) {
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [bg.cgColor, bg.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]) {
                ctx.saveGState()
                UIBezierPath(rect: rect).addClip()
                ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: end, y: 0), options: [])
                ctx.restoreGState()
            }
        }

        drawBottomBar(in: ctx, bounds: bounds, bottomHeight: bottomHeight, color: color)
    }

    /// 底栏：左 心脏图标随 BPM 轮动，右 心率数字
    private func drawBottomBar(in ctx: CGContext, bounds: CGRect, bottomHeight: CGFloat, color: UIColor) {
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }
        let bar = CGRect(x: 12, y: bounds.maxY - bottomHeight - 4, width: bounds.width - 24, height: bottomHeight)

        // 心脏图标：随 BPM 节拍收缩+明暗（未连接/无数据时静态灰）
        let heartSize: CGFloat = 11
        let heartCenter = CGPoint(x: bar.minX + heartSize + 2, y: bar.midY)
        var heartColor = UIColor(white: 0.6, alpha: 1)
        var pulse: CGFloat = 0
        if isConnected && heartRate > 0 {
            let bpm = max(heartRate, 40)
            let beatInterval = 60.0 / Double(bpm)
            let phase = CACurrentMediaTime().truncatingRemainder(dividingBy: beatInterval) / beatInterval
            pulse = 1 - phase
            heartColor = color
        }
        let grow = 1 + 0.25 * pulse
        ctx.saveGState()
        ctx.translateBy(x: heartCenter.x, y: heartCenter.y)
        ctx.scaleBy(x: grow, y: grow)
        ctx.translateBy(x: -heartCenter.x, y: -heartCenter.y)
        heartColor.withAlphaComponent(0.55 + 0.45 * pulse).setFill()
        heartPath(center: heartCenter, size: heartSize).fill()
        ctx.restoreGState()

        // 心率数字：右对齐，圆体加粗
        let numberText = isConnected && heartRate > 0 ? "\(heartRate)" : "--"
        let font = roundedFont(ofSize: bar.height * 0.72, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = numberText.size(withAttributes: attrs)
        numberText.draw(
            at: CGPoint(x: bar.maxX - size.width, y: bar.midY - size.height / 2),
            withAttributes: attrs)
    }

    /// 实心心形路径
    private func heartPath(center: CGPoint, size: CGFloat) -> UIBezierPath {
        let s = size
        let p = UIBezierPath()
        p.move(to: CGPoint(x: center.x, y: center.y + s))
        p.addCurve(
            to: CGPoint(x: center.x, y: center.y - s * 0.55),
            controlPoint1: CGPoint(x: center.x + s * 1.15, y: center.y + s * 0.30),
            controlPoint2: CGPoint(x: center.x + s * 0.95, y: center.y - s * 0.55))
        p.addCurve(
            to: CGPoint(x: center.x, y: center.y + s),
            controlPoint1: CGPoint(x: center.x - s * 0.95, y: center.y - s * 0.55),
            controlPoint2: CGPoint(x: center.x - s * 1.15, y: center.y + s * 0.30))
        p.close()
        return p
    }

    // MARK: - 数字 + BPM 标签（数字样式）

    private func drawNumberAndLabel(in ctx: CGContext, bounds: CGRect, settings s: SettingsManager?) {
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
        let numberW = min(numberSize.width + 4, maxTextWidth)
        let cx = bounds.midX
        let cy = bounds.midY

        // BPM 文本开关：关闭后仅居中显示心率数字
        guard s.pipShowBpmLabel else {
            numberText.draw(
                at: CGPoint(x: cx - numberSize.width / 2, y: cy - numberSize.height / 2),
                withAttributes: numberAttrs)
            return
        }

        let labelSize = "BPM".size(withAttributes: labelAttrs)
        let spacing = 8 * scale
        // 高度钳制：纵向排列时数字+标签+间距超出绘制区则缩小数字字号
        if numberSize.height + labelSize.height + spacing > bounds.height {
            let ratio = (bounds.height - labelSize.height - spacing) / numberSize.height
            numberFont = roundedFont(ofSize: numberFont.pointSize * max(ratio, 0.3), weight: .bold)
            numberAttrs = [.font: numberFont, .foregroundColor: numberColor]
            numberSize = numberText.size(withAttributes: numberAttrs)
        }
        let labelW = min(labelSize.width + 4, maxTextWidth)

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
