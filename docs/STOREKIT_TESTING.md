# StoreKit — managed credit packs

OSGKeyboard ships **three Consumable** in-app purchases and no subscriptions.
All three add credits to the optional OSG managed account. The authoritative
local catalog is [`OSGKeyboard.storekit`](../OSGKeyboard.storekit); App Store
Connect must match it exactly.

| Product ID | Type | Reference name | Display name (en) | Price (CN) | Grants |
|---|---|---|---|---|---|
| `500tks` | Consumable | 500 OSG 积分 | 500 OSG Credits | ¥8 | 500 account credits |
| `1500tks` | Consumable | 1,500 OSG 积分 | 1,500 OSG Credits | ¥18 | 1,500 account credits |
| `3000tks` | Consumable | 3,000 OSG 积分 | 3,000 OSG Credits | ¥28 | 3,000 account credits |

Rules that apply to all three:

- Consumables **cannot be restored** (Apple policy). The UI states this.
- Nothing here gates a feature. Local dictation, BYOK providers, typing,
  clipboard skills, and iCloud sync stay free with or without a purchase.
- Credits only add balance to the optional OSG account. They are useless
  without Sign in with Apple, and the app never requires an account.
- Credit packs are **iOS / iPadOS only**. The macOS build ships via Developer
  ID outside the Mac App Store, so it loads no StoreKit products at all.

## Where the packs appear

iOS Home → credit card → Account Center, and Settings → Account Center. Both
require Sign in with Apple.

## Purchase flow (server-verified)

Credit packs are not client-trusted. `AccountCreditPurchaseManager`:

1. Buys with StoreKit 2, binding `appAccountToken` to the signed-in account ID.
2. Rejects any transaction whose `appAccountToken` or product ID does not match
   the configured set.
3. Submits the signed transaction to the account service
   (`submitCreditTransaction`) and checks the returned transaction and product
   IDs against the local ones.
4. Calls `transaction.finish()` **only after** the server confirms and the
   ledger is updated.

A purchase that fails server verification stays unfinished and is retried from
the transaction-updates stream, so a crashed or backgrounded app does not lose
credits.

---

## App Store Connect setup

1. Open **App Store Connect → OSGKeyboard → In-App Purchases**.
2. Create each of the three products as **Consumable** with the exact Product
   IDs above. Do not rename an existing ID — Apple treats it as a new product.
3. Add en + zh-Hans localizations. Copy comes from
   [`OSGKeyboard.storekit`](../OSGKeyboard.storekit) (`localizations`) and
   [`docs/APPSTORE_METADATA.md`](APPSTORE_METADATA.md).
4. Set pricing to the nearest App Store tier for China (¥8 / ¥18 / ¥28) and let
   Apple map the equivalent tiers elsewhere.
5. Submit the IAPs for review **together with** the app version that exposes
   them. A first IAP submitted without a build is rejected as incomplete.

### Review screenshot (required — otherwise「元数据丢失」)

Each product needs a screenshot under **审核信息 → 截屏**: run the app signed
in, open **Home → credit card → Account Center**, and capture the pack list
showing localized prices.

Optional **审核备注**:

```
Consumable credits for the optional OSG managed speech/AI service.
Requires Sign in with Apple. Local dictation and user-supplied API keys
remain free and never require credits. Consumable — cannot restore.
```

Save — status should become **准备提交**.

---

## Local testing (StoreKit Test — no Connect, no sandbox account)

The **OSGKeyboard** scheme already references `OSGKeyboard.storekit` in
`project.yml` (`storeKitConfiguration`).

1. `./Scripts/generate-xcodeproj.sh && open OSGKeyboard.xcodeproj`
2. **Product → Scheme → Edit Scheme → Run → Options** — confirm
   **StoreKit Configuration** = `OSGKeyboard.storekit`
3. Run **OSGKeyboard** on a simulator (e.g. iPhone 17) or a device.
4. Sign in with Apple, then open **Home → credit card → Account Center**.
5. Buy `500tks` → balance increases by 500 after the account service confirms;
   the purchase-history row appears.
6. Cancel a purchase → returns to idle with no error spam.
7. Repeat a purchase → allowed (Consumable).

**Debug menu:** Xcode → **Debug → StoreKit → Manage Transactions** to inspect
or delete test purchases.

Automated coverage: `AccountCreditPurchaseManagerTests` (in the hermetic
manifest — see [TESTING.md](TESTING.md)) and `AccountCenterUITests`, which runs
separately via `xcodebuild -scheme OSGKeyboardUITests` against the `IAPReview`
stub harness — see
[ACCOUNT_MANAGED_GATEWAY_TESTING.md](ACCOUNT_MANAGED_GATEWAY_TESTING.md).

---

## Sandbox testing (after Connect IAPs reach 准备提交)

1. App Store Connect → **用户和访问 → 沙盒** → create a **Sandbox Tester**.
2. On device: **设置 → App Store → 沙盒账户** → sign in (not your real Apple ID).
3. Install via **TestFlight**, or Debug-run with **StoreKit Configuration =
   None** so the app hits Connect products.
4. Buy each pack once and confirm the server-side ledger, not just the UI.
5. Sandbox charges are free; the receipt path is the real one.

The full server-side matrix (replayed transactions, interrupted network,
wrong-account rejection) lives in
[ACCOUNT_MANAGED_GATEWAY_TESTING.md](ACCOUNT_MANAGED_GATEWAY_TESTING.md).

---

## Release checklist

- [ ] All three products load and show localized prices
- [ ] Each pack adds the correct balance after server verification
- [ ] Purchase history lists the new transaction without duplicates
- [ ] A failed/interrupted verification is retried and not lost
- [ ] User cancel returns to idle (no error spam)
- [ ] Repeat purchase works (Consumable allows multiple)
- [ ] No Restore button for any of these products
- [ ] Local dictation, BYOK, typing, and clipboard skills unchanged after purchase

---

## Files

| File | Role |
|---|---|
| `OSGKeyboard/Views/Account/AccountCreditPurchaseManager.swift` | Purchase + server verification |
| `OSGKeyboard/Views/Account/AccountCreditStore.swift` | StoreKit 2 product/purchase abstraction |
| `OSGKeyboard/Views/Account/AccountCenterView.swift` | Credit pack UI, purchase history |
| `OSGKeyboard.storekit` | Local StoreKit Test catalog |
