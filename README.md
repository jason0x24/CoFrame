# CoFrame

> 一次拍摄，同时产出横屏 16:9 与竖屏 9:16 两个独立视频文件——为知识博主而生的 iOS 录制工具。

## 解决什么问题

知识类博主（口播 / 教学 / 测评 / 访谈）通常需要把同一段内容同时分发到：

- **横屏渠道**：YouTube、B 站主站、视频号横版
- **竖屏渠道**：抖音、小红书、Instagram Reels、视频号竖版

CoFrame 让博主在拍摄时**同时看到横屏和竖屏的取景框**，单次录制即得两个版本，免去重录或后期 AI 重构图。

## 核心特性

- 🎥 **单次拍摄、双路输出**：单镜头 4K 横屏采集 + 双 `AVAssetWriter` 同步写出原始横屏和中心 9:16 竖屏（Metal 加速裁切）
- 📐 **横屏即时预览 + 竖屏 PiP**：主预览看横屏 16:9，右上角悬浮小窗实时反映 9:16 竖屏裁切区域
- 📏 **构图辅助**：九宫格 / 中心十字 / 水平仪 / 全部，一键切换
- 🎚 **三档画质**：1080p30 / 4K30 / 4K60（H.264）
- 🔄 **前后摄像头切换**：自动用 `AVCaptureDevice.RotationCoordinator` 处理朝向 × 镜头位置的旋转
- 📦 **沙盒草稿箱**：录制不直接落相册，先存 `Documents/Recordings/<UUID>/`，用户回看后选择导出
- 🪞 **iPhone Camera 风格 UI**：悬浮 chip 控件、ultraThinMaterial 背景、横屏锁定

## 技术栈

- Swift 5 + SwiftUI（iOS 26.4+，iPhone 12+）
- AVFoundation：`AVCaptureSession` / `AVCaptureVideoDataOutput` / `AVAssetWriter` / `AVSampleBufferDisplayLayer`
- Core Image + Metal：实时 9:16 中心裁切
- CoreMotion：水平仪
- 沙盒文件 + `PHPhotoLibrary` (`addOnly`) 导出

## 工程结构

```
CoFrame/
  App/                  # SwiftUI 入口
  Features/
    Capture/            # 录制主界面、ViewModel、相机预览、PiP、悬浮控件
    Drafts/             # 草稿箱
  Core/
    Camera/             # AVCaptureSession 管理 + RotationCoordinator
    Recording/          # 双路 AssetWriter 管线 + 画质档位
    Storage/            # 沙盒文件管理
    Motion/             # CoreMotion 水平仪
```

详见 [PRD.md](PRD.md)。

## 关键技术决策

- **不使用 `AVCaptureMultiCamSession`** —— 单镜头 + 双路裁切，画面一致、功耗低、所有 iPhone 12+ 都支持
- **PiP 用 `AVSampleBufferDisplayLayer` 而非第二个 `AVCaptureVideoPreviewLayer`** —— 避免单镜头会话下两个 preview layer 抢占 connection
- **录制连接强制不镜像** —— 与系统 Camera 一致：录像不镜像，仅前摄预览镜像
- **`AVCaptureDevice.RotationCoordinator` 驱动旋转** —— 自动适配设备朝向 × 前后镜头

## 状态

v0.1 · M1 进行中 · 录制管线和主界面已可用，草稿箱回看 / 导出（M2）尚未完成。

## License

私有项目（暂无）。
