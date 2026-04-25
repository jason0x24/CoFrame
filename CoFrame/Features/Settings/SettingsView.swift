import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage(AppPreferences.Key.muteSystemSounds)
    private var muteSystemSounds: Bool = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("录制时静音系统提示音", isOn: $muteSystemSounds)
                } footer: {
                    Text("画质和基准线会按你在录制界面的最近一次选择自动记住，无需在这里设置。")
                }

                Section("关于") {
                    LabeledContent("版本", value: versionString)
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                    Link(destination: feedbackURL) {
                        Label("发送反馈邮件", systemImage: "envelope")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var feedbackURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "daffimalfa@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "CoFrame 反馈"),
            URLQueryItem(name: "body", value: "App 版本：\(versionString)\n\n")
        ]
        return components.url ?? URL(string: "mailto:daffimalfa@gmail.com")!
    }
}

// MARK: - Privacy

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CoFrame 不收集、不上传你的任何数据。所有录制文件仅保存在本机沙盒（草稿箱）中，是否导出到相册完全由你主动选择。")

                Divider()

                Text("访问的系统权限").font(.headline)

                privacyRow(icon: "camera",
                           title: "相机",
                           desc: "用于横屏 + 竖屏视频录制")
                privacyRow(icon: "mic",
                           title: "麦克风",
                           desc: "用于采集音频")
                privacyRow(icon: "photo",
                           title: "相册（仅添加）",
                           desc: "仅在你点击「导出到相册」时使用，不读取已有照片")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 28, height: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(desc).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
