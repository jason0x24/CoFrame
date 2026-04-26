# CoFrame

> 一次拍摄，同时产出横屏 16:9 与竖屏 9:16 两个独立视频文件——为知识博主而生的 iOS 录制工具。

## 解决什么问题

知识类博主（口播 / 教学 / 测评 / 访谈）通常需要把同一段内容同时分发到：

- **横屏渠道**：YouTube、B 站主站、视频号横版
- **竖屏渠道**：抖音、小红书、Instagram Reels、视频号竖版

CoFrame 让博主在拍摄时**同时看到横屏和竖屏的取景框**，单次录制即得两个版本，免去重录或后期 AI 重构图。

## 核心特性

### 录制
- 🎥 **单次拍摄、双路输出**：单镜头 4K 横屏采集 + 双 `AVAssetWriter` 同步写出原始横屏和 9:16 竖屏（Metal 加速裁切）
- 📐 **主预览 + 可拖拽缩放 PiP**：横屏 16:9 主预览 + 9:16 竖屏 PiP（默认左下，单指拖动到任何位置，双指捏合 0.6×–1.5× 缩放）
- ✋ **可水平拖动的 9:16 裁切框**：用户决定竖屏录什么区域，实时同步到 PiP 与录制管线
- 🔍 **多镜头变焦**：UW (0.5×) / Wide (1×) / Telephoto (2×, 5×)，点击切换 + 双指捏合连续变焦，自动用最佳虚拟摄像头（`builtInTripleCamera` / `builtInDualWideCamera`）
- 🎯 **对焦 / 曝光 / 手电筒**：单击对焦、长按 AE/AF 锁定、对焦框旁竖向 EV ±2 滑条、手电筒 chip
- 📏 **构图辅助**：九宫格 / 中心十字 / 水平仪（CoreMotion）/ 全部，一键切换；横屏与 PiP 都显示
- 🎚 **三档画质**：1080p30 / 4K30 / 4K60（H.264）；最近一次选择自动持久化
- 🔄 **前/后摄像头切换**：用 `AVCaptureDevice.RotationCoordinator` 自动处理朝向 × 镜头位置；PiP 视图自动镜像匹配前置预览

### 草稿箱与导出
- 📦 **沙盒草稿箱**：录制不直接落相册，先存 `Documents/Recordings/<UUID>/`
- 🖼 **草稿列表**：缩略图（首帧 JPEG）+ 时间 / 画质 / 时长 / 体积 / 横竖徽章
- 📊 **存储用量**：顶部进度条显示草稿用量与设备剩余
- ▶️ **横竖切换播放**：详情页 segmented control，`AVPlayer` 回看
- 💾 **导出到相册**：`PHPhotoLibrary` `addOnly` 权限，可选仅横/仅竖/两个都导
- 📤 **系统分享**：`ShareLink` 调系统 Share Sheet
- 🗑 **删除**：滑动删除 + 二次确认

### 稳定性
- 🌡 **温度监控**：`ProcessInfo.thermalState` 监听，serious 时顶部黄色警告，critical 时自动停录保住文件
- ☎️ **中断处理**：来电、其他 app 占用相机、进入后台、系统资源紧张、分屏——分别给出对应的 transient banner 并停录
- 🚀 **启动动画**：双框 + 红色录制点的入场动画掩盖相机初始化等待

### 体验
- 🪞 **iPhone Camera 风格 UI**：悬浮 chip 控件、ultraThinMaterial 背景、横屏锁定、Dynamic Island 自适应
- 🌍 **中英文双语**：跟随系统或在设置中手动切换
- 🎨 **App 图标 + 启动屏**：双框 + 红点视觉语言，深蓝渐变；light / dark / tinted 三套适配
- 🛡 **隐私清晰**：不收集任何数据、不接入第三方 SDK；`PrivacyInfo.xcprivacy` 完整声明所有 required reason API

## 技术栈

- Swift 5 + SwiftUI（iOS 26.4+，iPhone 12+）
- AVFoundation：`AVCaptureSession` / `AVCaptureVideoDataOutput` / `AVAssetWriter` / `AVSampleBufferDisplayLayer` / `AVCaptureDevice.RotationCoordinator`
- Core Image + Metal：实时 9:16 裁切
- CoreMotion：水平仪
- Photos：相册导出（`addOnly`）
- ProcessInfo / NotificationCenter：温度与会话中断监听

## 工程结构

```
CoFrame/
  CoFrameApp.swift            # SwiftUI 入口 + 语言环境注入
  PrivacyInfo.xcprivacy       # App Store 隐私清单
  InfoPlist.xcstrings         # 权限说明中英翻译
  Localizable.xcstrings       # UI 文案中英翻译
  Assets.xcassets/            # AppIcon (light/dark/tinted) + LaunchBackground

  Features/
    Capture/                  # 录制主界面
      CaptureView.swift           - 主视图 + SystemBannerOverlay + ZoomSelector
      CaptureViewModel.swift      - 状态机 + 焦点/变焦/温度/中断协调
      CameraPreviewView.swift     - AVCaptureVideoPreviewLayer + 手势
      PortraitPiPView.swift       - PiP 容器（layer.frame 偏移做 9:16 裁切）
      PortraitFrameSource.swift   - 喂帧给 AVSampleBufferDisplayLayer
      DraggablePiP.swift          - 拖拽 + 捏合缩放
      GuideOverlay.swift          - 九宫格 / 十字 / 水平仪
      RecordButton.swift
      LaunchSplash.swift          - 启动动画
      SampleCoordinator.swift     - 把单一 sink fan-out 给 recorder + PiP
    Drafts/                   # 草稿箱
      DraftsView.swift            - 列表 + 存储进度条
      DraftDetailView.swift       - 横竖播放 + 导出 / 分享 / 删除
    Settings/                 # 设置（关于 + 语言切换）
      SettingsView.swift

  Core/
    Camera/
      CameraSession.swift         - AVCaptureSession + 多镜头 + 焦点/曝光/torch/zoom + 中断通知
      CameraPermission.swift      - 相机/麦克风权限请求
    Recording/
      DualRecorder.swift          - 双 AVAssetWriter 管线 + Metal 裁切
      VideoQuality.swift          - 1080p30 / 4K30 / 4K60 档位
    Storage/
      RecordingStore.swift        - 沙盒文件管理 + 缩略图（带超时）
      RecordingSession.swift      - 持久化模型
    Export/
      PhotoExporter.swift         - PHPhotoLibrary addOnly 封装
    Motion/
      LevelMonitor.swift          - CoreMotion 水平仪
    System/
      ThermalMonitor.swift        - ProcessInfo.thermalState 监听
    Settings/
      AppPreferences.swift        - UserDefaults + LanguageOption

scripts/
  generate_icon.swift             - Core Graphics 程序化生成 1024×1024 图标
```

详细需求与决策记录见 [PRD.md](PRD.md)。

## 关键技术决策

- **不使用 `AVCaptureMultiCamSession`** —— 单镜头 + 双路裁切，画面一致、功耗低、所有 iPhone 12+ 都支持。多镜头切换走 `builtInTripleCamera` 虚拟设备，由系统在 UW/Wide/Tele 间无缝切换
- **PiP 用 `AVSampleBufferDisplayLayer` 而非第二个 `AVCaptureVideoPreviewLayer`** —— 避免单镜头 session 下两个 preview layer 抢占 connection
- **PiP 9:16 裁切用 `layer.frame.x` 偏移 + `clipsToBounds`** —— `AVSampleBufferDisplayLayer` 不响应 `contentsRect`，只能用 sublayer 偏移这条可靠路径
- **录制连接强制不镜像** —— 与系统 Camera 一致：录像不镜像，仅前摄预览镜像（PiP UIView 加 transform）
- **前置摄像头的 cropPosition 翻转** —— preview 自动镜像 vs un-mirrored buffer 之间用 `effectiveCropPosition = 1 - portraitCropPosition` 对齐
- **`AVCaptureDevice.RotationCoordinator` 驱动旋转** —— 自动适配设备朝向 × 前后镜头（前摄 sensor 朝向不同，硬编码 0° 会上下颠倒）
- **PiP sample buffer enqueue 在专用 userInteractive 队列** —— 30/60fps 帧不霸占主线程，手势/SwiftUI tick 更顺
- **温度 critical 时自动停录** —— 保住已写文件，避免长时间录制时被系统强杀

## 状态

**v1.0 实现完成**，PRD §9 五个里程碑（M0–M4）全部交付，准备 TestFlight 内测。

## 下一步候选

按价值排序：

1. **TestFlight 上架**：Archive → App Store Connect → 元数据 + 截图
2. **提词器**：录制时半透明文字滚动覆盖，知识博主刚需
3. **录制中拍照**：双击截当前帧为 JPEG 做封面
4. **暂停/继续录制**：把多个 take 录到同一文件
5. **智能裁切跟人脸**（Vision face detection）：9:16 区域自动跟随人物

## License

私有项目（暂无开源协议）。
