// HostBundleProbeCard.swift
// OSGKeyboard · Main App
//
// 临时调试卡片（仅 DEBUG）：展示键盘扩展识别到的宿主 bundle ID，
// 用于真机验证 iOS 26.4+ 宿主识别。验证结束后删除。

#if DEBUG
import OSGKeyboardShared
import SwiftUI

struct HostBundleProbeCard: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @State private var entries: [HostBundleProbeLog.Entry] = []
    @State private var draft = ""

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("宿主识别测试（临时）")
                    .font(TypeStyle.footnote.weight(.semibold))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Spacing.xs)
                Button("清空") {
                    HostBundleProbeLog.clear()
                    reload()
                }
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.accent)
            }

            // 在 OSG 自己里唤起键盘时，预期识别结果是主 App 的 bundle ID。
            TextField("点这里唤起 OSG 键盘", text: $draft)
                .textFieldStyle(.roundedBorder)

            if entries.isEmpty {
                Text("暂无记录：去其他 App 唤起 OSG 键盘后回到这里查看")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
                .textSelection(.enabled)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        // 卡片可见期间每秒刷新，在本 App 内唤起键盘时也能实时看到结果。
        .task {
            while !Task.isCancelled {
                reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func entryRow(_ entry: HostBundleProbeLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Spacing.xs) {
                Text(Self.timeFormatter.string(from: entry.date))
                    .foregroundStyle(palette.textTertiary)
                Text(entry.event)
                    .foregroundStyle(entry.event == "appear" ? palette.textSecondary : palette.accent)
                if let detail = entry.detail {
                    Text(detail)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 11, design: .monospaced))

            if entry.event != "appear" {
                Text(entry.bundleId ?? "nil")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(entry.bundleId == nil ? palette.warning : palette.textPrimary)
            }
        }
    }

    private func reload() {
        let latest = HostBundleProbeLog.entries()
        if latest != entries { entries = latest }
    }
}
#endif
