# CoFrame

> One shot, two formats — an iOS recorder that captures landscape (16:9) and portrait (9:16) video simultaneously, built for content creators.
>
> 一次拍摄，同时产出横屏 16:9 与竖屏 9:16 两个独立视频文件——为知识博主而生的 iOS 录制工具。

[English](#english) · [中文](#中文)

---

## English

### What problem it solves

Knowledge creators (talking-heads, tutorials, reviews, interviews) typically distribute the same content to:

- **Landscape platforms**: YouTube, Bilibili, WeChat Channels (horizontal)
- **Portrait platforms**: TikTok, Instagram Reels, YouTube Shorts, RED, WeChat Channels (vertical)

CoFrame lets creators **see both viewfinders while recording**, producing both versions from a single take — no re-takes, no AI re-cropping in post.

### Core Features

#### Recording
- 🎥 **One shot, dual output** — Single-camera 4K landscape capture + dual `AVAssetWriter` writing the original landscape and a 9:16 portrait crop in parallel (Metal-accelerated)
- 📐 **Main preview + draggable, resizable PiP** — 16:9 main view with a 9:16 portrait PiP (default bottom-left, drag anywhere, pinch 0.6×–1.5× to resize)
- ✋ **Pannable 9:16 crop indicator** — User picks which slice of the landscape becomes the portrait; PiP and recorder pipeline track in real time
- 🔍 **Multi-lens zoom** — UW (0.5×) / Wide (1×) / Telephoto (2×, 5×) tap-to-switch + pinch for continuous zoom; auto-uses best virtual device (`builtInTripleCamera` / `builtInDualWideCamera`)
- 🎯 **Focus / exposure / torch** — Tap to focus, long-press for AE/AF lock, vertical ±2 EV slider, torch chip
- 📏 **Composition guides** — Rule of thirds / crosshair / level (CoreMotion) / all; toggleable on both main and PiP
- 🎚 **Three quality tiers** — 1080p30 / 4K30 / 4K60 (H.264); last selection auto-persisted
- 🔄 **Front/back camera switch** — Uses `AVCaptureDevice.RotationCoordinator` to handle orientation × lens position automatically; PiP mirrors to match front-facing preview

#### Drafts & Export
- 📦 **Sandbox drafts** — Recordings don't auto-write to Photos; stored in `Documents/Recordings/<UUID>/`
- 🖼 **Draft list** — Thumbnail (first-frame JPEG) + time / quality / duration / size / orientation badges
- 📊 **Storage usage** — Top progress bar shows draft usage and device free space
- ▶️ **Landscape ↔ portrait playback** — Detail page segmented control + `AVPlayer`
- 💾 **Save to Photos** — `PHPhotoLibrary` `addOnly` permission; choose landscape only / portrait only / both
- 🗑 **Delete** — Swipe to delete with confirmation

#### Stability
- 🌡 **Thermal monitoring** — Watches `ProcessInfo.thermalState`; orange warning at `serious`, auto-stops recording at `critical` to preserve the file
- ☎️ **Interruption handling** — Phone calls, other-app camera use, backgrounding, system pressure, Split View — each shows a transient banner and stops recording
- 🚀 **Launch animation** — Frame-blooming + record-dot intro masks camera initialization wait

#### Polish
- 🪞 **iPhone Camera-style UI** — Floating chip controls, ultraThinMaterial backgrounds, landscape-locked, Dynamic Island-aware
- 🌍 **Bilingual** — Follows system language, or set Chinese/English manually in Settings
- 🎨 **App icon + launch screen** — Dual-frame + record-dot visual language with deep blue gradient; light / dark / tinted variants
- 🛡 **Privacy-first** — No data collected, no third-party SDKs; complete `PrivacyInfo.xcprivacy` declaring all required-reason APIs

### Tech Stack

- Swift 5 + SwiftUI (iOS 26.4+, iPhone 12+)
- AVFoundation: `AVCaptureSession` / `AVCaptureVideoDataOutput` / `AVAssetWriter` / `AVSampleBufferDisplayLayer` / `AVCaptureDevice.RotationCoordinator`
- Core Image + Metal: real-time 9:16 cropping
- CoreMotion: digital level
- Photos: `addOnly` library export
- ProcessInfo / NotificationCenter: thermal & session interruption observation

### Project Structure

```
CoFrame/
  CoFrameApp.swift            # SwiftUI entry + locale environment injection
  PrivacyInfo.xcprivacy       # App Store privacy manifest
  InfoPlist.xcstrings         # Permission strings (zh / en)
  Localizable.xcstrings       # UI strings (zh / en)
  Assets.xcassets/            # AppIcon (light/dark/tinted) + LaunchBackground

  Features/
    Capture/                  # Recording UI
      CaptureView.swift           - Main view + SystemBannerOverlay + ZoomSelector
      CaptureViewModel.swift      - State machine + focus/zoom/thermal/interruption
      CameraPreviewView.swift     - AVCaptureVideoPreviewLayer + gestures
      PortraitPiPView.swift       - PiP container (layer.frame offset for 9:16 crop)
      PortraitFrameSource.swift   - Feeds AVSampleBufferDisplayLayer
      DraggablePiP.swift          - Drag + pinch-to-resize
      GuideOverlay.swift          - Thirds / crosshair / level
      RecordButton.swift
      LaunchSplash.swift          - Launch animation
      SampleCoordinator.swift     - Fan-out single sink to recorder + PiP
    Drafts/                   # Drafts inbox
      DraftsView.swift            - List + storage bar
      DraftDetailView.swift       - Landscape/portrait playback + export / delete
    Settings/                 # Settings (about + language)
      SettingsView.swift

  Core/
    Camera/
      CameraSession.swift         - AVCaptureSession + multi-lens + focus/exposure/torch/zoom + interruption
      CameraPermission.swift      - Camera/microphone permission
    Recording/
      DualRecorder.swift          - Dual AVAssetWriter pipeline + Metal crop
      VideoQuality.swift          - 1080p30 / 4K30 / 4K60 tiers
    Storage/
      RecordingStore.swift        - Sandbox file mgmt + thumbnail (with timeout)
      RecordingSession.swift      - Persisted model
    Export/
      PhotoExporter.swift         - PHPhotoLibrary addOnly wrapper
    Motion/
      LevelMonitor.swift          - CoreMotion level
    System/
      ThermalMonitor.swift        - ProcessInfo.thermalState observer
    Settings/
      AppPreferences.swift        - UserDefaults + LanguageOption

scripts/
  generate_icon.swift             - Programmatic 1024×1024 icon generator
```

Detailed requirements & decisions: [PRD.md](PRD.md). App Store metadata: [app-store-metadata.md](app-store-metadata.md).

### Key Technical Decisions

- **No `AVCaptureMultiCamSession`** — Single camera + dual cropping: consistent image, low power, supported on all iPhone 12+. Multi-lens switching uses the `builtInTripleCamera` virtual device, letting the system seamlessly transition between UW / Wide / Tele
- **PiP uses `AVSampleBufferDisplayLayer` instead of a second `AVCaptureVideoPreviewLayer`** — Avoids connection contention from two preview layers on a single-camera session
- **PiP 9:16 crop uses `layer.frame.x` offset + `clipsToBounds`** — `AVSampleBufferDisplayLayer` doesn't honor `contentsRect`; sublayer offset is the only reliable path
- **Recording connection forces no mirroring** — Matches iOS Camera: recording not mirrored, only front-camera preview is (PiP UIView gets a transform)
- **Front-camera `cropPosition` inversion** — Preview auto-mirrors but the un-mirrored buffer doesn't; aligned via `effectiveCropPosition = 1 - portraitCropPosition`
- **`AVCaptureDevice.RotationCoordinator` drives rotation** — Auto-adapts to device orientation × camera position (front sensor orientation differs; hardcoding 0° would invert)
- **PiP sample buffer enqueue on a dedicated userInteractive queue** — 30/60fps frames don't hammer the main thread, keeping gestures/SwiftUI ticks responsive
- **Auto-stop recording at thermal critical** — Preserves the in-progress file before iOS may suspend the session

### Status

**v1.0 complete.** All five PRD milestones (M0–M4) delivered. TestFlight-ready.

### Roadmap

In rough priority order:

1. **TestFlight & App Store** — Archive → App Store Connect → metadata + screenshots
2. **Teleprompter** — Translucent scrolling script overlay; a must for solo creators
3. **Snapshot during recording** — Double-tap to grab the current frame as JPEG cover art
4. **Pause / resume recording** — Combine multiple takes into one file
5. **Smart subject-tracking crop** — Vision-based face detection; portrait window auto-pans with the subject

### License

[MIT License](LICENSE) — Use, modify, and redistribute freely; just preserve the copyright notice.

---

## 中文

### 解决什么问题

知识类博主（口播 / 教学 / 测评 / 访谈）通常需要把同一段内容同时分发到：

- **横屏渠道**：YouTube、B 站主站、视频号横版
- **竖屏渠道**：抖音、小红书、Instagram Reels、视频号竖版

CoFrame 让博主在拍摄时**同时看到横屏和竖屏的取景框**，单次录制即得两个版本，免去重录或后期 AI 重构图。

### 核心特性

#### 录制
- 🎥 **单次拍摄、双路输出**：单镜头 4K 横屏采集 + 双 `AVAssetWriter` 同步写出原始横屏和 9:16 竖屏（Metal 加速裁切）
- 📐 **主预览 + 可拖拽缩放 PiP**：横屏 16:9 主预览 + 9:16 竖屏 PiP（默认左下，单指拖动到任何位置，双指捏合 0.6×–1.5× 缩放）
- ✋ **可水平拖动的 9:16 裁切框**：用户决定竖屏录什么区域，实时同步到 PiP 与录制管线
- 🔍 **多镜头变焦**：UW (0.5×) / Wide (1×) / Telephoto (2×, 5×)，点击切换 + 双指捏合连续变焦，自动用最佳虚拟摄像头（`builtInTripleCamera` / `builtInDualWideCamera`）
- 🎯 **对焦 / 曝光 / 手电筒**：单击对焦、长按 AE/AF 锁定、对焦框旁竖向 EV ±2 滑条、手电筒 chip
- 📏 **构图辅助**：九宫格 / 中心十字 / 水平仪（CoreMotion）/ 全部，一键切换；横屏与 PiP 都显示
- 🎚 **三档画质**：1080p30 / 4K30 / 4K60（H.264）；最近一次选择自动持久化
- 🔄 **前/后摄像头切换**：用 `AVCaptureDevice.RotationCoordinator` 自动处理朝向 × 镜头位置；PiP 视图自动镜像匹配前置预览

#### 草稿箱与导出
- 📦 **沙盒草稿箱**：录制不直接落相册，先存 `Documents/Recordings/<UUID>/`
- 🖼 **草稿列表**：缩略图（首帧 JPEG）+ 时间 / 画质 / 时长 / 体积 / 横竖徽章
- 📊 **存储用量**：顶部进度条显示草稿用量与设备剩余
- ▶️ **横竖切换播放**：详情页 segmented control，`AVPlayer` 回看
- 💾 **导出到相册**：`PHPhotoLibrary` `addOnly` 权限，可选仅横/仅竖/两个都导
- 🗑 **删除**：滑动删除 + 二次确认

#### 稳定性
- 🌡 **温度监控**：`ProcessInfo.thermalState` 监听，serious 时顶部黄色警告，critical 时自动停录保住文件
- ☎️ **中断处理**：来电、其他 app 占用相机、进入后台、系统资源紧张、分屏——分别给出对应的 transient banner 并停录
- 🚀 **启动动画**：双框 + 红色录制点的入场动画掩盖相机初始化等待

#### 体验
- 🪞 **iPhone Camera 风格 UI**：悬浮 chip 控件、ultraThinMaterial 背景、横屏锁定、Dynamic Island 自适应
- 🌍 **中英文双语**：跟随系统或在设置中手动切换
- 🎨 **App 图标 + 启动屏**：双框 + 红点视觉语言，深蓝渐变；light / dark / tinted 三套适配
- 🛡 **隐私清晰**：不收集任何数据、不接入第三方 SDK；`PrivacyInfo.xcprivacy` 完整声明所有 required reason API

### 技术栈

- Swift 5 + SwiftUI（iOS 26.4+，iPhone 12+）
- AVFoundation：`AVCaptureSession` / `AVCaptureVideoDataOutput` / `AVAssetWriter` / `AVSampleBufferDisplayLayer` / `AVCaptureDevice.RotationCoordinator`
- Core Image + Metal：实时 9:16 裁切
- CoreMotion：水平仪
- Photos：相册导出（`addOnly`）
- ProcessInfo / NotificationCenter：温度与会话中断监听

### 工程结构

工程目录与英文版相同，参考上方 [Project Structure](#project-structure)。

详细需求与决策记录见 [PRD.md](PRD.md)。App Store 上架元数据见 [app-store-metadata.md](app-store-metadata.md)。

### 关键技术决策

- **不使用 `AVCaptureMultiCamSession`** —— 单镜头 + 双路裁切，画面一致、功耗低、所有 iPhone 12+ 都支持。多镜头切换走 `builtInTripleCamera` 虚拟设备，由系统在 UW/Wide/Tele 间无缝切换
- **PiP 用 `AVSampleBufferDisplayLayer` 而非第二个 `AVCaptureVideoPreviewLayer`** —— 避免单镜头 session 下两个 preview layer 抢占 connection
- **PiP 9:16 裁切用 `layer.frame.x` 偏移 + `clipsToBounds`** —— `AVSampleBufferDisplayLayer` 不响应 `contentsRect`，只能用 sublayer 偏移这条可靠路径
- **录制连接强制不镜像** —— 与系统 Camera 一致：录像不镜像，仅前摄预览镜像（PiP UIView 加 transform）
- **前置摄像头的 cropPosition 翻转** —— preview 自动镜像 vs un-mirrored buffer 之间用 `effectiveCropPosition = 1 - portraitCropPosition` 对齐
- **`AVCaptureDevice.RotationCoordinator` 驱动旋转** —— 自动适配设备朝向 × 前后镜头（前摄 sensor 朝向不同，硬编码 0° 会上下颠倒）
- **PiP sample buffer enqueue 在专用 userInteractive 队列** —— 30/60fps 帧不霸占主线程，手势/SwiftUI tick 更顺
- **温度 critical 时自动停录** —— 保住已写文件，避免长时间录制时被系统强杀

### 状态

**v1.0 实现完成**，PRD §9 五个里程碑（M0–M4）全部交付，准备 TestFlight 内测。

### 下一步候选

按价值排序：

1. **TestFlight 上架**：Archive → App Store Connect → 元数据 + 截图
2. **提词器**：录制时半透明文字滚动覆盖，知识博主刚需
3. **录制中拍照**：双击截当前帧为 JPEG 做封面
4. **暂停/继续录制**：把多个 take 录到同一文件
5. **智能裁切跟人脸**（Vision face detection）：9:16 区域自动跟随人物

### License

[MIT License](LICENSE) —— 自由使用、修改、再分发，保留版权声明即可。
