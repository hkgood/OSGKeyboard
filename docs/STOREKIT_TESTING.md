# StoreKit — Voluntary Support Tip

OSGKeyboard offers a single **Consumable** in-app purchase:

| Field | Value |
|---|---|
| **Type** | Consumable |
| **Product ID** | `ByRockyACoffee` |
| **Reference name (Connect)** | 给老刘买杯咖啡 |
| **Display name (en)** | Buy me a cup of coffee |
| **Display name (zh-Hans)** | 给老刘买杯冰美式 |
| **Price (China)** | ¥28 (nearest available App Store tier) |
| **Price (US, suggested)** | $3.99 equivalent tier |

**Important:** this tip does **not** unlock translation, dictionary limits,
long Flow sessions, or any other capability. The app remains fully free.

Consumable purchases **cannot be restored** (Apple policy). Settings copy
explains this to users.

---

## App Store Connect setup

1. Open **App Store Connect → OSGKeyboard → In-App Purchases**.
2. Create **Consumable** with Product ID `ByRockyACoffee`.
3. Add localizations (en + zh-Hans) using the strings in
   `OSGKeyboardShared/*/Shared.strings` (`tip.*` keys) and
   `docs/APPSTORE_METADATA.md`.
4. Set pricing: **China ¥28** (App Store only offers fixed tiers — ¥28 is
   the nearest to ¥30); pick equivalent tiers for other territories.
5. Submit the IAP for review **with** the app version that includes the
   Settings → Support the Developer entry.

### Review screenshot (required — fixes「元数据丢失」)

App Store Connect → IAP **ByRockyACoffee** → **审核信息** → **截屏**:

1. Run the app (Simulator or device) with Settings open at the top
   **支持开发者** card showing the green **打赏 ¥28.00** button.
2. Capture that screen (⌘S in Simulator, or device screenshot).
3. Upload to **截屏 → 选取文件**.
4. Optional **审核备注**:

```
Optional voluntary tip only (Consumable IAP ByRockyACoffee).
All features free before and after purchase. Settings tab → top of page.
Consumable — cannot restore (stated in UI).
```

Save — status should become **准备提交**.

---

## Local testing (StoreKit Test — no Connect / sandbox account)

Uses [`OSGKeyboard.storekit`](../OSGKeyboard.storekit). The **OSGKeyboard**
scheme already references it in `project.yml` (`storeKitConfiguration`).

1. `xcodegen generate && open OSGKeyboard.xcodeproj`
2. **Product → Scheme → Edit Scheme → Run → Options**
   - Confirm **StoreKit Configuration** = `OSGKeyboard.storekit`
3. Run **OSGKeyboard** on Simulator (e.g. iPhone 17) or a plugged-in device
4. Open **Settings** tab → top card **支持开发者**
5. Tap **打赏 ¥28.00** → StoreKit Test purchase sheet appears
6. **Buy** → thank-you alert; **Cancel** → no error
7. Repeat buy once (Consumable allows multiple)

**Debug menu (optional):** Xcode → **Debug → StoreKit → Manage Transactions**
to view / delete test purchases.

---

## Sandbox testing (real App Store sandbox — after Connect IAP is 准备提交)

1. App Store Connect → **用户和访问** → **沙盒** → create a **Sandbox Tester**
2. On device: **设置 → App Store → 沙盒账户** → sign in (not your real Apple ID)
3. Install via **TestFlight** or **Debug run without** `.storekit`:
   - To hit Connect products: Edit Scheme → Run → Options → set StoreKit
     Configuration to **None**, then run on device
4. Settings → **支持开发者** → purchase with sandbox account
5. Sandbox charges are free; receipt is real sandbox flow

---

## Submit to App Review (after local + sandbox pass)

Yes — **wait until testing looks good**, then:

1. IAP **ByRockyACoffee** status = **准备提交** (pricing + screenshot + localizations)
2. Bump app version in `project.yml` / `CHANGELOG.md` if needed
3. **Archive** → upload build to App Store Connect
4. Open the new **App Store version** page → **App 内购买项目** → **+** → select **ByRockyACoffee**
5. Fill metadata, attach build, submit **version + IAP together** (first IAP rule)

### Sandbox checklist

- [ ] Product loads and shows localized price
- [ ] Successful purchase shows thank-you alert
- [ ] User cancel returns to idle (no error spam)
- [ ] Repeat purchase works (Consumable allows multiple)
- [ ] No Restore button for this product (Consumable)
- [ ] Translation, Flow, dictionary, BYOK unchanged after tipping

### macOS note

The menu-bar Mac build (`com.osgkeyboard.mac`) ships via Developer ID outside
the Mac App Store today. StoreKit products load only for App Store builds.
The Mac Settings UI is present for parity; tip IAP requires an App Store
distribution if Mac tipping is enabled later.

---

## Files

| File | Role |
|---|---|
| `OSGKeyboardShared/Services/Tip/TipProduct.swift` | Product ID constants |
| `OSGKeyboardShared/Services/Tip/TipPurchaseManager.swift` | StoreKit 2 purchase flow |
| `OSGKeyboardShared/DesignSystem/SupportDeveloperSection.swift` | iOS Settings UI |
| `OSGKeyboardMac/MacSupportDeveloperTipRows.swift` | macOS Settings UI |
| `OSGKeyboard.storekit` | Local StoreKit Test catalog |
