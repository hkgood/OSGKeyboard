// InviteShareSheet.swift
// OSGKeyboard · Main App
//
// Opened by the Invite button. Shows the invitation poster, which opens a
// full-screen code for face-to-face scanning when tapped, plus the three ways an
// invitation usually leaves the phone: saving the image to send in a chat app,
// the system share sheet, or the plain link.

import OSGKeyboardShared
import Photos
import SwiftUI
import UIKit

struct InviteShareSheet: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AccountSessionCoordinator
    @ObservedObject private var config = ProviderConfig.shared

    let invitationURL: URL
    /// Display form (`XXXX-XXXX`), printed on the poster when available.
    var shortCode: String?
    @ObservedObject var referralProfile: ReferralProfileViewModel

    @State private var poster: UIImage?
    @State private var qrImage: CGImage?
    @State private var isShowingFullScreenCode = false
    @State private var isSharingPoster = false
    @State private var isSaving = false
    @State private var status: Status?

    private enum Status: Equatable {
        case success(messageKey: String)
        case failure(messageKey: String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    posterPreview
                    actions
                    statusMessage
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(AppL10n.string("account.referral.poster.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.string("common.done")) { dismiss() }
                        .tint(palette.textPrimary)
                }
            }
        }
        .task(id: posterRenderID) {
            qrImage = InviteQRCode.makeImage(for: invitationURL)
            poster = InvitePosterRenderer
                .render(
                    inviteURL: invitationURL,
                    shortCode: resolvedShortCode,
                    inviterName: inviterName,
                    language: config.uiLanguage,
                    colorScheme: colorScheme
                )
                .map { UIImage(cgImage: $0) }
        }
        .task {
            // A cached pre-short-code profile may be visible for the first
            // frame. Refresh when the sheet opens and rerender once the server
            // supplies the account's assigned alias.
            guard shortCode == nil else { return }
            await referralProfile.refresh()
        }
        .fullScreenCover(isPresented: $isShowingFullScreenCode) {
            if let qrImage {
                InviteQRFullScreenView(qrImage: qrImage, language: config.uiLanguage)
            }
        }
        .sheet(isPresented: $isSharingPoster) {
            if let poster {
                InvitePosterActivityView(poster: poster)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .accessibilityIdentifier("account.referral.poster")
    }

    /// Tapping the poster opens the full-screen code for face-to-face scanning.
    private var posterPreview: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return Button {
            isShowingFullScreenCode = true
        } label: {
            Group {
                if let poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        colorScheme == .dark
                            ? OSGColor.fixedDarkContent
                            : OSGColor.fixedLightContent
                        ProgressView()
                            .tint(
                                colorScheme == .dark
                                    ? OSGColor.fixedLightContent
                                    : OSGColor.fixedDarkContent
                            )
                    }
                }
            }
            .aspectRatio(
                InvitePosterView.size.width / InvitePosterView.size.height,
                contentMode: .fit
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(posterPrimaryContent)
                    .frame(width: 32, height: 32)
                    .background(posterPrimaryContent.opacity(0.16), in: Circle())
                    .padding(Spacing.sm)
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(qrImage == nil)
        .frame(maxWidth: 320)
        .cardElevation()
        .accessibilityLabel(AppL10n.string("account.referral.poster.accessibility"))
        .accessibilityHint(AppL10n.string("account.referral.poster.enlargeHint"))
        .accessibilityIdentifier("account.referral.poster.preview")
    }

    private var inviterName: String? {
        guard case let .signedIn(session) = coordinator.sessionPhase else { return nil }
        return session.displayName
    }

    private var resolvedShortCode: String? {
        if let shortCode { return shortCode }
        guard case let .loaded(profile) = referralProfile.state else { return nil }
        return profile.code.displayShortCode
    }

    private var posterRenderID: String {
        "\(colorScheme)-\(resolvedShortCode ?? "")-\(inviterName ?? "")"
    }

    private var posterPrimaryContent: Color {
        colorScheme == .dark
            ? OSGColor.fixedLightContent
            : OSGColor.fixedDarkContent
    }

    private var actions: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                Task { await savePoster() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(palette.textOnAccent)
                    } else {
                        Label(
                            AppL10n.string("account.referral.poster.save"),
                            systemImage: "square.and.arrow.down"
                        )
                    }
                }
                .primaryButton()
            }
            .buttonStyle(.plain)
            .disabled(poster == nil || isSaving)
            .accessibilityIdentifier("account.referral.poster.save")

            HStack(spacing: Spacing.sm) {
                Button {
                    isSharingPoster = true
                } label: {
                    Label(
                        AppL10n.string("account.referral.poster.share"),
                        systemImage: "square.and.arrow.up"
                    )
                    .secondaryButton()
                }
                .buttonStyle(.plain)
                .disabled(poster == nil)
                .accessibilityIdentifier("account.referral.poster.share")

                Button(action: copyLink) {
                    Label(
                        AppL10n.string("account.referral.poster.copyLink"),
                        systemImage: "link"
                    )
                    .secondaryButton()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.referral.poster.copyLink")
            }
        }
        .frame(maxWidth: 360)
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch status {
        case .success(let messageKey):
            Label(AppL10n.string(messageKey), systemImage: "checkmark.circle.fill")
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.success)
        case .failure(let messageKey):
            Label(AppL10n.string(messageKey), systemImage: "exclamationmark.triangle.fill")
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.danger)
                .multilineTextAlignment(.center)
        case nil:
            Text(AppL10n.string("account.referral.poster.footnote"))
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func savePoster() async {
        guard let poster, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        // PhotoKit terminates the process instead of throwing when this usage
        // description is missing from the built app. Keep this preflight so a
        // future project-generation regression becomes a visible error.
        guard let usageDescription = Bundle.main.object(
            forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription"
        ) as? String, !usageDescription.isEmpty else {
            status = .failure(messageKey: "account.referral.poster.saveFailed")
            return
        }

        // Add-only access: the app never needs to read the user's library.
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            status = .failure(messageKey: "account.referral.poster.saveDenied")
            return
        }
        guard let pngData = poster.pngData() else {
            status = .failure(messageKey: "account.referral.poster.saveFailed")
            return
        }
        do {
            try await Self.addToPhotos(pngData: pngData)
            status = .success(messageKey: "account.referral.poster.saved")
            AnalyticsHostService.shared.client.recordReferralShared()
        } catch {
            status = .failure(messageKey: "account.referral.poster.saveFailed")
        }
    }

    /// Photos runs the change block on its own transaction queue. It must be
    /// built outside the view's main-actor isolation: Swift 6 traps when a
    /// main-actor closure runs off the main thread.
    private nonisolated static func addToPhotos(pngData: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: pngData, options: nil)
        }
    }

    private func copyLink() {
        UIPasteboard.general.string = invitationURL.absoluteString
        status = .success(messageKey: "account.referral.poster.linkCopied")
        AnalyticsHostService.shared.client.recordReferralShared()
    }
}

/// Shares the poster image only. Chat apps' share extensions often refuse a
/// mixed image + URL payload, and the link is one tap away via Copy Link.
private struct InvitePosterActivityView: UIViewControllerRepresentable {
    let poster: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [poster],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { @MainActor in
                AnalyticsHostService.shared.client.recordReferralShared()
            }
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
