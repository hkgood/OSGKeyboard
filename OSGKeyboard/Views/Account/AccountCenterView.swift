// AccountCenterView.swift
// OSGKeyboard · Main App
//
// Optional account center. Signing in unlocks managed credits and referrals;
// local transcription and user-owned provider keys remain independent.

import OSGKeyboardShared
import SwiftUI
import UIKit

struct AccountCenterView: View {
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var coordinator: AccountSessionCoordinator
    @ObservedObject private var config = ProviderConfig.shared

    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteReauthentication = false
    @State private var showProfileEditor = false
    @State private var displayNameDraft = ""

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            sessionContent
        }
        .navigationTitle("account.title")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenPushed()
        .task(id: coordinator.accountID) {
            guard let accountID = coordinator.accountID else {
                coordinator.creditPurchases.reset()
                return
            }
            async let accountRefresh: Void = coordinator.refreshAccountData()
            async let purchasePreparation: Void =
                coordinator.creditPurchases.prepare(accountID: accountID)
            _ = await (accountRefresh, purchasePreparation)
            if case let .signedIn(session) = coordinator.sessionPhase {
                displayNameDraft = session.displayName ?? ""
            }
        }
        .onDisappear {
            coordinator.creditPurchases.dismissSuccessMessage()
        }
        .alert(
            "account.error.title",
            isPresented: operationErrorBinding
        ) {
            Button("common.done") {
                coordinator.dismissOperationError()
            }
        } message: {
            if let key = coordinator.operationErrorKey {
                Text(LocalizedStringKey(key))
            }
        }
        .alert(
            "account.profile.editTitle",
            isPresented: $showProfileEditor
        ) {
            TextField("account.profile.nickname", text: $displayNameDraft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("common.cancel", role: .cancel) {}
            Button("account.profile.save") {
                if case let .signedIn(session) = coordinator.sessionPhase {
                    saveDisplayName(session: session)
                }
            }
            .disabled(!canSaveCurrentDisplayName)
        } message: {
            Text("account.profile.editMessage")
        }
        .sheet(isPresented: $showDeleteReauthentication) {
            deleteReauthenticationSheet
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch coordinator.sessionPhase {
        case .restoring:
            AccountStateCard(
                systemImage: "person.crop.circle",
                titleKey: "account.loading.session",
                showsProgress: true
            )
        case .signedOut:
            signedOutContent
        case let .signedIn(session):
            signedInContent(session: session)
        }
    }

    private var signedOutContent: some View {
        ScrollView {
            CardPageContent {
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)

                    VStack(spacing: Spacing.xs) {
                        Text("account.signedOut.title")
                            .font(.title2.bold())
                            .foregroundStyle(palette.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("account.signedOut.body")
                            .font(.body)
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    AccountAppleAuthorizationButton(purpose: .signIn)
                        .disabled(coordinator.operation != nil)

                    if coordinator.operation == .signingIn {
                        ProgressView("account.signIn.loading")
                            .tint(palette.accent)
                    }

                    if coordinator.pendingReferralCode != nil {
                        Label("account.referral.pendingAfterSignIn", systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("account.signedOut.localUnaffected")
                        .font(.footnote)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity)
                .surfaceCard()
            }
        }
    }

    private func signedInContent(session: AccountSession) -> some View {
        ScrollView {
            CardPageContent {
                accountSummarySection(session: session)
                accountRewardsContent(session: session)
                securitySection
            }
            .padding(.bottom, Spacing.lg)
        }
        .refreshable {
            async let accountRefresh: Void = coordinator.refreshAccountData(force: true)
            async let catalogRefresh: Void =
                coordinator.creditPurchases.refreshCatalog(accountID: session.accountID)
            _ = await (accountRefresh, catalogRefresh)
        }
        .accessibilityIdentifier("account.center.signedIn")
    }

    @ViewBuilder
    private func accountRewardsContent(session: AccountSession) -> some View {
        switch coordinator.snapshotPhase {
        case .idle, .loading:
            AccountStateCard(
                systemImage: "arrow.triangle.2.circlepath",
                titleKey: "account.loading.center",
                showsProgress: true
            )
        case let .failed(messageKey):
            AccountStateCard(
                systemImage: "exclamationmark.triangle",
                titleKey: messageKey,
                actionKey: "account.retry"
            ) {
                Task { await coordinator.refreshAccountData(force: true) }
            }
        case .loaded:
            EmptyView()
        }

        CardSection("account.storekit.section") {
            VStack(spacing: Spacing.sm) {
                AccountCreditPurchaseSection(
                    manager: coordinator.creditPurchases,
                    accountID: session.accountID,
                    onGranted: {
                        Task { await coordinator.refreshAccountData(force: true) }
                    }
                )
                purchaseHistoryLink(accountID: session.accountID)
            }
        }
    }

    private func purchaseHistoryLink(accountID: UUID) -> some View {
        NavigationLink {
            AccountPurchaseHistoryView(
                manager: coordinator.creditPurchases,
                accountID: accountID
            )
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text("account.purchaseHistory.title")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .settingsListRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .surfaceCard()
        .accessibilityIdentifier("account.purchaseHistory.link")
    }

    private func accountSummarySection(session: AccountSession) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)

        return HStack(spacing: Spacing.md) {
            AccountAvatarView(
                accountID: session.accountID,
                displayName: session.displayName,
                size: 52
            )

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(
                    session.displayName
                        ?? AppL10n.string(
                            "account.profile.fallbackName",
                            language: config.uiLanguage
                        )
                )
                    .font(TypeStyle.headline)
                    .foregroundStyle(palette.textPrimary)
                Text(verbatim: "ID · \(session.accountID.uuidString.suffix(8))")
                    .font(TypeStyle.caption2.monospaced())
                    .foregroundStyle(palette.textTertiary)
            }

            Spacer(minLength: Spacing.xs)

            Button {
                displayNameDraft = session.displayName ?? ""
                showProfileEditor = true
            } label: {
                Group {
                    if coordinator.operation == .updatingProfile {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(palette.accent)
                .frame(width: 40, height: 40)
                .background(palette.surfaceElevated, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(coordinator.operation != nil)
            .accessibilityLabel("account.profile.editTitle")
        }
        .padding(Spacing.lg)
        .background(palette.surface, in: shape)
        .overlay(shape.stroke(palette.divider, lineWidth: 0.5))
        .accessibilityIdentifier("account.summary")
    }

    private var canSaveCurrentDisplayName: Bool {
        guard case let .signedIn(session) = coordinator.sessionPhase else { return false }
        return canSaveDisplayName(session: session)
    }

    private func canSaveDisplayName(session: AccountSession) -> Bool {
        let value = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty
            && value.count <= 64
            && value != session.displayName
            && coordinator.operation == nil
    }

    private func saveDisplayName(session: AccountSession) {
        guard canSaveDisplayName(session: session) else { return }
        let value = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await coordinator.updateDisplayName(value) {
                displayNameDraft = value
            }
        }
    }

    private var securitySection: some View {
        VStack(spacing: 0) {
            Button {
                showSignOutConfirmation = true
            } label: {
                AccountActionRow(
                    titleKey: "account.signOut.action",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    color: palette.textPrimary,
                    showsProgress: coordinator.operation == .signingOut
                )
            }
            .buttonStyle(.plain)
            .disabled(coordinator.operation != nil)
            .confirmationDialog(
                "account.signOut.confirmTitle",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("account.signOut.action", role: .destructive) {
                    Task {
                        await coordinator.signOut()
                        if !coordinator.isSignedIn {
                            config.credentialSource = .byok
                        }
                    }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("account.signOut.confirmMessage")
            }

            Divider().background(palette.divider)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                AccountActionRow(
                    titleKey: "account.delete.action",
                    systemImage: "trash",
                    color: palette.danger,
                    showsProgress: coordinator.operation == .deletingAccount
                )
            }
            .buttonStyle(.plain)
            .disabled(coordinator.operation != nil)
            .confirmationDialog(
                "account.delete.confirmTitle",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("account.delete.continue", role: .destructive) {
                    showDeleteReauthentication = true
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("account.delete.confirmMessage")
            }
        }
        .surfaceCard()
    }

    private var deleteReauthenticationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(palette.danger)
                    .accessibilityHidden(true)

                Text("account.delete.reauthenticateBody")
                    .font(.body)
                    .foregroundStyle(palette.textSecondary)

                AccountAppleAuthorizationButton(
                    purpose: .deleteAccount,
                    onDeleted: {
                        showDeleteReauthentication = false
                        config.credentialSource = .byok
                    }
                )
                .disabled(coordinator.operation != nil)

                if coordinator.operation == .deletingAccount {
                    ProgressView("account.delete.loading")
                        .tint(palette.accent)
                        .frame(maxWidth: .infinity)
                }

                Spacer()
            }
            .padding(Spacing.lg)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("account.delete.reauthenticateTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        showDeleteReauthentication = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { coordinator.operationErrorKey != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator.dismissOperationError()
                }
            }
        )
    }
}

struct AccountAvatarView: View {
    let accountID: UUID
    let displayName: String?
    let size: CGFloat

    private static let gradients: [[Color]] = [
        [.indigo, .blue],
        [.purple, .pink],
        [.teal, .cyan],
        [.orange, .red],
        [.mint, .green]
    ]

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: Self.gradients[gradientIndex],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = (displayName ?? "")
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined().uppercased()
        return value.isEmpty ? "O" : value
    }

    private var gradientIndex: Int {
        let hash = accountID.uuidString.unicodeScalars.reduce(UInt32(2_166_136_261)) {
            ($0 ^ $1.value) &* 16_777_619
        }
        return Int(hash % UInt32(Self.gradients.count))
    }
}

private struct AccountCreditsSection: View {
    @Environment(\.themePalette) private var palette
    let snapshot: AccountCenterSnapshot

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(
                        snapshot.credits.balance,
                        format: .number.grouping(.automatic)
                    )
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    Text("account.credits.balance")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: Spacing.md)

                HStack(spacing: Spacing.xxs) {
                    Text("account.credits.used")
                    Text(
                        snapshot.credits.usedCredits,
                        format: .number.grouping(.automatic)
                    )
                    .monospacedDigit()
                }
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
            }

            AccountCreditProgress(
                remaining: snapshot.credits.balance,
                used: snapshot.credits.usedCredits,
                showsLabels: false
            )
        }
        .padding(Spacing.md)
        .surfaceCard()
    }
}

private struct AccountCreditPurchaseSection: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var manager: AccountCreditPurchaseManager
    @State private var didRecordPurchaseView = false

    let accountID: UUID
    let onGranted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !manager.options.isEmpty {
                VStack(spacing: 0) {
                    ForEach(manager.options) { option in
                        purchaseOption(option)
                        if option.id != manager.options.last?.id {
                            Divider().background(palette.divider)
                        }
                    }
                }
                .surfaceCard()
            } else if manager.catalogPhase == .loading {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accent)
                    Text("account.storekit.loading")
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .settingsListRow()
                .surfaceCard()
            }

            catalogStateMessage
            stateMessage
        }
        .onChange(of: manager.lastGrantedBalance) { previous, current in
            guard current != nil, current != previous else { return }
            onGranted()
        }
        .onAppear {
            guard !didRecordPurchaseView else { return }
            didRecordPurchaseView = true
            manager.recordPurchaseViewed()
        }
    }

    private func purchaseOption(_ option: AccountCreditPurchaseOption) -> some View {
        Button {
            Task {
                _ = await manager.purchase(
                    productID: option.productID,
                    accountID: accountID
                )
            }
        } label: {
            HStack(spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text(option.credits, format: .number.grouping(.automatic))
                        .font(TypeStyle.title3.monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text("account.storekit.credits")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: Spacing.xs)

                Text(option.displayPrice)
                    .font(TypeStyle.bodyEmph.monospacedDigit())
                    .foregroundStyle(palette.textPrimary)

                Group {
                    if purchasingProductID == option.productID {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("account.storekit.purchase")
                            .font(TypeStyle.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.sm)
                .frame(minWidth: 54, minHeight: 34)
                .background(
                    palette.accent,
                    in: RoundedRectangle(
                        cornerRadius: Radius.medium,
                        style: .continuous
                    )
                )
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(purchasingProductID != nil)
        .accessibilityIdentifier("account.purchase.\(option.productID)")
        .accessibilityLabel(
            Text(
                "\(Text(option.credits, format: .number)) \(Text("account.storekit.credits")) \(Text(option.displayPrice))"
            )
        )
    }

    private var purchasingProductID: String? {
        guard case .purchasing(let productID) = manager.state else { return nil }
        return productID
    }

    @ViewBuilder
    private var catalogStateMessage: some View {
        switch manager.catalogPhase {
        case .idle:
            catalogRetryMessage(messageKey: "account.storekit.error.productUnavailable")
        case .loading, .loaded:
            if let messageKey = manager.catalogRefreshErrorKey {
                catalogRetryMessage(messageKey: messageKey)
            }
        case .failed(let messageKey):
            catalogRetryMessage(messageKey: messageKey)
        }
    }

    private func catalogRetryMessage(messageKey: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Label(
                LocalizedStringKey(messageKey),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(TypeStyle.footnote)
            .foregroundStyle(palette.danger)
            Spacer(minLength: Spacing.xs)
            Button("account.retry") {
                Task { await manager.refreshCatalog(accountID: accountID) }
            }
            .font(TypeStyle.bodyEmph)
            .foregroundStyle(palette.accent)
        }
    }

    @ViewBuilder
    private var stateMessage: some View {
        Group {
            switch manager.state {
            case .pending:
                Label("account.storekit.pending", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
            case .succeeded(let credits):
                Label {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "account.storekit.succeeded",
                                comment: ""
                            ),
                            credits
                        )
                    )
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.success)
            case .failed(let messageKey):
                HStack(spacing: Spacing.sm) {
                    Label(
                        LocalizedStringKey(messageKey),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.danger)
                    Spacer(minLength: Spacing.xs)
                }
            default:
                EmptyView()
            }
        }
        .accessibilityIdentifier("account.purchase.status")
    }
}

struct AccountCreditProgress: View {
    @Environment(\.themePalette) private var palette

    let remaining: Int64
    let used: Int64
    let showsLabels: Bool

    init(remaining: Int64, used: Int64, showsLabels: Bool = true) {
        self.remaining = remaining
        self.used = used
        self.showsLabels = showsLabels
    }

    private var usedFraction: Double {
        fraction(for: used)
    }

    private var remainingFraction: Double {
        fraction(for: remaining)
    }

    private func fraction(for value: Int64) -> Double {
        let available = Double(max(remaining, 0))
        let consumed = Double(max(used, 0))
        let total = available + consumed
        return total > 0 ? Double(max(value, 0)) / total : 0
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.surfaceElevated)
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(palette.success)
                            .frame(width: proxy.size.width * remainingFraction)
                        Rectangle()
                            .fill(palette.textTertiary.opacity(0.55))
                            .frame(width: proxy.size.width * usedFraction)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 8)

            if showsLabels {
                HStack(spacing: Spacing.sm) {
                    percentageLabel(
                        "account.credits.remaining",
                        fraction: remainingFraction,
                        color: palette.success
                    )
                    Spacer(minLength: Spacing.xs)
                    percentageLabel(
                        "account.credits.used",
                        fraction: usedFraction,
                        color: palette.textTertiary
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func percentageLabel(
        _ titleKey: LocalizedStringKey,
        fraction: Double,
        color: Color
    ) -> some View {
        let percentageText = fraction.formatted(
            .percent.precision(.fractionLength(0))
        )
        return HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(titleKey)
            Text(verbatim: percentageText)
                .monospacedDigit()
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textSecondary)
    }
}

struct AccountInvitationButton: View {
    @Environment(\.themePalette) private var palette
    @State private var showsShareDrawer = false

    let invitationURL: URL?

    var body: some View {
        Button {
            guard invitationURL != nil else { return }
            showsShareDrawer = true
        } label: {
            Label("account.referral.inviteTitle", systemImage: "person.badge.plus")
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: 38)
                .background(
                    palette.success,
                    in: RoundedRectangle(
                        cornerRadius: Radius.medium,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(invitationURL == nil)
        .accessibilityIdentifier("account.referral.share")
        .sheet(isPresented: $showsShareDrawer) {
            if let invitationURL {
                AccountInvitationActivityView(invitationURL: invitationURL)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct AccountInvitationActivityView: UIViewControllerRepresentable {
    let invitationURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [invitationURL],
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

#if DEBUG
@MainActor
struct IAPReviewScreenshotHarness: View {
    @StateObject private var purchaseManager: AccountCreditPurchaseManager

    private let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000100")!

    init() {
        _purchaseManager = StateObject(
            wrappedValue: AccountCreditPurchaseManager(
                service: IAPReviewAccountService(),
                store: IAPReviewCreditStore()
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPageContent {
                    CardSection("account.credits.section") {
                        VStack(spacing: Spacing.sm) {
                            AccountCreditsSection(snapshot: Self.snapshot)
                            AccountCreditPurchaseSection(
                                manager: purchaseManager,
                                accountID: accountID,
                                onGranted: {}
                            )
                        }
                    }
                }
                .padding(.bottom, Spacing.lg)
            }
            .navigationTitle("account.rewards.title")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await purchaseManager.prepare(accountID: accountID)
        }
    }

    private static let snapshot = AccountCenterSnapshot(
        account: AccountSession(
            accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
            createdAtEpochSeconds: 0,
            displayName: "OSG User"
        ),
        credits: AccountCreditSummary(balance: 1_000, usedCredits: 0),
        referrals: []
    )
}

private struct IAPReviewAccountService: AccountCenterServicing {
    func loadAccountCenter() async throws -> AccountCenterSnapshot {
        throw AccountIntegrationError.unavailable
    }

    func redeemReferral(code: String) async throws {}

    func loadCreditProducts() async throws -> [AccountCreditProduct] {
        [
            AccountCreditProduct(productID: "500tks", credits: 500),
            AccountCreditProduct(productID: "1500tks", credits: 1_500),
            AccountCreditProduct(productID: "3000tks", credits: 3_000)
        ]
    }
}

@MainActor
private final class IAPReviewCreditStore: AccountCreditStore {
    func product(for productID: String) async throws -> AccountStoreProduct? {
        let price: String
        switch productID {
        case "500tks":
            price = "¥8.00"
        case "1500tks":
            price = "¥18.00"
        case "3000tks":
            price = "¥28.00"
        default:
            return nil
        }
        return AccountStoreProduct(id: productID, displayPrice: price)
    }

    func purchase(
        productID: String,
        accountID: UUID
    ) async throws -> AccountStorePurchaseOutcome {
        .userCancelled
    }

    func unfinishedTransactions() -> AsyncStream<AccountStoreVerification> {
        AsyncStream { $0.finish() }
    }

    func transactionUpdates() -> AsyncStream<AccountStoreVerification> {
        AsyncStream { $0.finish() }
    }

    func allTransactions() -> AsyncStream<AccountStoreVerification> {
        AsyncStream { $0.finish() }
    }
}
#endif

private struct AccountActionRow: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let color: Color
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Label(titleKey, systemImage: systemImage)
                .font(.body)
            Spacer(minLength: Spacing.xs)
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .foregroundStyle(color)
        .settingsListRow()
        .contentShape(Rectangle())
    }
}

private struct AccountStateCard: View {
    @Environment(\.themePalette) private var palette

    let systemImage: String
    let titleKey: String
    var actionKey: LocalizedStringKey?
    var showsProgress = false
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: Spacing.md) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
                    .tint(palette.accent)
            } else {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
            }

            Text(LocalizedStringKey(titleKey))
                .font(.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)

            if let actionKey {
                Button(actionKey, action: action)
                    .font(.headline)
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .surfaceCard()
    }
}
