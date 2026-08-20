// AccountPurchaseHistoryView.swift
// OSGKeyboard · Main App
//
// Displays verified StoreKit credit purchases for the active OSG account.

import Foundation
import OSGKeyboardShared
import SwiftUI

struct AccountPurchaseHistoryView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject var manager: AccountCreditPurchaseManager

    let accountID: UUID

    var body: some View {
        Group {
            switch manager.historyPhase {
            case .idle, .loading:
                ProgressView("account.purchaseHistory.loading")
                    .tint(palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let records):
                if records.isEmpty {
                    ContentUnavailableView(
                        "account.purchaseHistory.empty",
                        systemImage: "clock.arrow.circlepath"
                    )
                } else {
                    purchaseList(records)
                }
            case .failed(let messageKey):
                VStack(spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(palette.warning)
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(messageKey))
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                    Button("account.retry") {
                        Task {
                            await manager.loadPurchaseHistory(
                                accountID: accountID,
                                force: true
                            )
                        }
                    }
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("account.purchaseHistory.title")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenPushed()
        .task {
            await manager.loadPurchaseHistory(accountID: accountID)
        }
    }

    private func purchaseList(
        _ records: [AccountCreditPurchaseRecord]
    ) -> some View {
        List {
            ForEach(records) { record in
                purchaseRow(record)
                    .listRowBackground(palette.surface)
                    .listRowSeparatorTint(palette.divider)
                    .task {
                        guard record.id == records.last?.id else { return }
                        await manager.loadNextPurchaseHistoryPage(accountID: accountID)
                    }
            }

            if manager.isLoadingMoreHistory {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(palette.accent)
                    Spacer()
                }
                .listRowBackground(palette.surface)
            } else if let errorKey = manager.historyLoadMoreErrorKey {
                Button {
                    Task {
                        await manager.loadNextPurchaseHistoryPage(accountID: accountID)
                    }
                } label: {
                    Text(LocalizedStringKey(errorKey))
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .accessibilityIdentifier("account.purchaseHistory.list")
        .refreshable {
            await manager.loadPurchaseHistory(accountID: accountID, force: true)
        }
    }

    private func purchaseRow(
        _ record: AccountCreditPurchaseRecord
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text("+")
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.success)
                    Text(record.creditsGranted, format: .number.grouping(.automatic))
                        .font(TypeStyle.bodyEmph.monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text("account.storekit.credits")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Text(purchaseDateText(record.purchasedAt))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(balanceAfterText(record.balanceAfter))
                    .font(TypeStyle.caption.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                Text("account.purchaseHistory.status.credited")
                    .font(TypeStyle.caption.weight(.semibold))
                    .foregroundStyle(palette.success)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func purchaseDateText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
                .locale(config.uiLanguage.swiftUILocale)
        )
    }

    private func balanceAfterText(_ balance: Int64) -> String {
        AppL10n.format(
            "account.purchaseHistory.balanceAfter",
            language: config.uiLanguage,
            balance.formatted(.number.grouping(.automatic))
        )
    }
}
