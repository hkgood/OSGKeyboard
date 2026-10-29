// DebugAccountHandoffSection.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Settings → Diagnostics controls for `DebugAccountSessionHandoff`: a device
// hands its session off to the Simulator; the Simulator parks and resumes it
// to switch between signed-out and signed-in without a server logout.
// Debug tooling, so the copy is not localized.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

#if !targetEnvironment(simulator)
struct DebugAccountHandoffSection: View {
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var accountSession: AccountSessionCoordinator

    @State private var showsConfirmation = false
    @State private var exportURL: URL?
    @State private var errorText: String?

    var body: some View {
        CardSection(title: "模拟器账号交接 · DEBUG") {
            VStack(spacing: 0) {
                DebugAccountStatusRow(text: statusText, isError: errorText != nil)

                Divider().background(palette.divider)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        DebugAccountActionRow(title: "AirDrop 到 Mac", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        showsConfirmation = true
                    } label: {
                        DebugAccountActionRow(
                            title: "把账号会话交给模拟器",
                            systemImage: "iphone.and.arrow.forward"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!accountSession.isSignedIn || accountSession.operation != nil)
                }
            }
            .surfaceCard()
        }
        .confirmationDialog(
            "把账号会话交给模拟器？",
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button("交出会话", role: .destructive) { handOff() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "本机会退出登录，但不通知服务器，会话随文件转给模拟器。"
                    + "本机之后要用，重新登录即可。文件里是有效的登录凭证，不要转给别人。"
            )
        }
        .onDisappear { deleteExportFile() }
    }

    private var statusText: String {
        if let errorText { return errorText }
        if exportURL != nil {
            return "会话已从本机移除。AirDrop 到 Mac 后运行："
                + "Scripts/sim-import-account-session.sh <文件> [模拟器 UDID]"
        }
        return accountSession.isSignedIn
            ? "模拟器无法生成设备证据，不能自己登录。把本机会话交过去，模拟器就能使用真实账号与托管云服务。"
            : "本机未登录。先登录，再交出会话。"
    }

    private func handOff() {
        errorText = nil
        Task {
            do {
                exportURL = try await accountSession.debugRelinquishSession(
                    writingTo: FileManager.default.temporaryDirectory
                )
            } catch {
                errorText = "交接失败（\(AccountDiagnostic.code(for: error))），请稍后重试。"
            }
        }
    }

    private func deleteExportFile() {
        guard let exportURL else { return }
        try? FileManager.default.removeItem(at: exportURL)
        self.exportURL = nil
    }
}
#else
struct DebugAccountParkingSection: View {
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var accountSession: AccountSessionCoordinator

    @State private var hasParkedSession = DebugAccountSessionHandoff.hasPendingImport()
    @State private var errorText: String?

    var body: some View {
        CardSection(title: "模拟器登录状态 · DEBUG") {
            VStack(spacing: 0) {
                DebugAccountStatusRow(text: statusText, isError: errorText != nil)

                Divider().background(palette.divider)

                if accountSession.isSignedIn {
                    Button(action: park) {
                        DebugAccountActionRow(
                            title: "暂时退出（保留会话）",
                            systemImage: "pause.circle"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(accountSession.operation != nil)
                } else {
                    Button(action: resume) {
                        DebugAccountActionRow(title: "恢复登录", systemImage: "play.circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasParkedSession || accountSession.operation != nil)
                }
            }
            .surfaceCard()
        }
        .onAppear { hasParkedSession = DebugAccountSessionHandoff.hasPendingImport() }
    }

    private var statusText: String {
        if let errorText { return errorText }
        if accountSession.isSignedIn {
            return "暂时退出只清掉本地登录状态，不通知服务器；之后点「恢复登录」或重启 App 即可回来。"
                + "不要用「退出登录」，那会让服务器作废这个会话。"
        }
        return hasParkedSession
            ? "会话已暂存在模拟器里，App 现在是未登录状态。"
            : "没有暂存的会话。用 Scripts/sim-import-account-session.sh 从真机交接一个。"
    }

    private func park() {
        errorText = nil
        Task {
            do {
                _ = try await accountSession.debugRelinquishSession(
                    writingTo: DebugAccountSessionHandoff.defaultImportDirectory
                )
            } catch {
                errorText = "暂存失败（\(AccountDiagnostic.code(for: error))），请稍后重试。"
            }
            hasParkedSession = DebugAccountSessionHandoff.hasPendingImport()
        }
    }

    private func resume() {
        errorText = nil
        Task {
            await accountSession.debugResumeParkedSession()
            hasParkedSession = DebugAccountSessionHandoff.hasPendingImport()
            if !accountSession.isSignedIn {
                errorText = "恢复失败，会话可能已在服务器端失效，需要从真机重新交接。"
            }
        }
    }
}
#endif

private struct DebugAccountStatusRow: View {
    @Environment(\.themePalette) private var palette
    let text: String
    let isError: Bool

    var body: some View {
        Text(verbatim: text)
            .font(TypeStyle.caption2)
            .foregroundStyle(isError ? palette.warning : palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsListRow()
    }
}

private struct DebugAccountActionRow: View {
    @Environment(\.themePalette) private var palette
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
            Text(verbatim: title)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Spacing.sm)
        }
        .settingsListRow()
        .contentShape(Rectangle())
    }
}
#endif
