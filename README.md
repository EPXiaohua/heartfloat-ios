# HeartFloat 心率悬浮窗

<p align="center">
  <img src="HeartFloat/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="100" alt="HeartFloat Icon"/>
</p>

把实时心率悬浮在屏幕上的 iOS 应用 —— 通过画中画实现常亮悬浮显示。看得见，别不当回事。

> 主要在小米手环 9 Pro 上测试。其他设备如遇连接或数据问题，欢迎到 [Issues](https://github.com/EPXiaohua/heartfloat-ios/issues) 反馈。

## 功能特性

- 🔵 **BLE 蓝牙连接** —— 连接小米手环等标准心率设备（180D / 2A37），直连优先、连接验证、断连检测、15 秒数据看门狗
- 📺 **画中画悬浮窗** —— iOS 原生画中画常亮显示心率，数字大小 / 颜色 / 位置 / 背景亮度可自定义
- 📝 **心率记录** —— 手动 / Auto 双模式（连接即记录、断开自动保存）、异常退出快照恢复、JSON / CSV 导入导出、删除二次确认
- 📈 **图表分析** —— 实时曲线与记录图表支持单击查询、拖动平移、双指缩放、全屏横屏分析
- 🌐 **推送服务** —— 内置 HTTP + WebSocket 服务器，实时推送心率数据，直播页可作 OBS 浏览器源
- 🔄 **自动检查更新** —— 启动静默检查 GitHub Releases，发现新版本才提示，可开关
- 💾 **存储管理** —— 应用占用 / 手机剩余 / 总容量对比，一键清理临时缓存

## 下载安装

前往 [Releases](https://github.com/EPXiaohua/heartfloat-ios/releases) 下载最新版本 IPA。

IPA 为未签名包，需自行签名安装，可选 AltStore / Sideloadly / TrollStore 等工具。

## 系统要求

- iOS 15.0+
- iPhone 设备
- 支持 Bluetooth LE 的心率设备（已在小米手环 9 Pro 上测试）

## 使用方法

1. 首次打开授予蓝牙权限，应用会自动搜索并连接心率设备（若未连接，可在手环上关闭再开启心率广播）
2. 连接成功后点击「显示悬浮窗」开启画中画显示
3. 长按记录按钮选择手动 / Auto 模式，开始记录心率
4. 在设置中可配置悬浮窗样式、推送服务、蓝牙设备、存储管理、自动检查更新等

## 推送服务

在「设置 → 推送服务」开启（支持启动自启），同一 WiFi / 热点下的设备可直接访问。

HTTP 接口：

- `GET /heartbeat` —— 返回纯文本心率值
- `GET /heartbeat.json` —— 返回 JSON 格式数据
- `GET /live` —— 直播悬浮页（透明背景，可作 OBS 浏览器源），优先 WebSocket 实时推送

WebSocket 实时推送（默认端口 8081）：

- 连接 `ws://<设备IP>:8081`，服务端每次心率采样主动广播一条 JSON：

```json
{"bpm": 72, "isContact": true, "lastUpdate": 1696570000000}
```

> 蜂窝网络下设备拿到的是运营商内网地址，外部设备无法直接连入，建议使用 WiFi 或个人热点。

## 从源码构建

```bash
git clone https://github.com/EPXiaohua/heartfloat-ios.git
cd heartfloat-ios
```

用 Xcode 15+ 打开 `HeartFloat.xcodeproj`（无第三方依赖），选择真机运行即可。仓库同时提供 XcodeGen 配置（`project.yml`），可用 `xcodegen` 重新生成工程。

## CI 构建

- 推送到 main 分支：GitHub Actions 自动构建未签名 IPA，可在 Actions 页面下载
- 推送版本 tag（如 `2.0`）：自动构建并把 IPA 发布到 GitHub Releases

## 技术栈

- Swift 5 / SwiftUI（iOS 15+）
- CoreBluetooth
- AVKit Picture in Picture
- Network.framework（HTTP / WebSocket 服务器）

## 许可证

MIT License

## 作者

小花
