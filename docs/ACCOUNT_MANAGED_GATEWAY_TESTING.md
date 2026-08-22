# Account and managed gateway verification

This checklist validates the optional OSG account path without changing the
existing local or BYOK defaults. Never record tokens, Apple identifiers, audio,
prompts, transcripts, or model output while running these checks.

## Automated gate

```bash
./Scripts/run-tests.sh validate
./Scripts/run-tests.sh pr
swiftlint lint --quiet --strict
xcodebuild \
  -project OSGKeyboard.xcodeproj \
  -scheme OSGKeyboardUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OSGKeyboardUITests/AccountCenterUITests \
  test
xcodebuild \
  -project OSGKeyboard.xcodeproj \
  -scheme OSGKeyboard \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Release \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The account and managed gateway tests must remain hermetic. They use injected
Apple integrity adapters, URL loading stubs, and WebSocket fakes rather than
production credentials.

## Physical-device prerequisites

- A development build signed for `com.osgkeyboard.ios`.
- Sign in with Apple, App Attest, DeviceCheck, Associated Domains, and both
  Keychain groups enabled in the provisioning profile.
- `https://osglab.com/.well-known/apple-app-site-association` returns HTTP 200
  without a redirect and includes `X329MZU23S.com.osgkeyboard.ios` for `/i/*`.
- The production account service is ready at `https://account.osglab.com`.
- The production service temporarily enables `ALLOW_DEVELOPMENT_APP_ATTEST=true`
  for the test window; disable it again after physical-device testing.
- OSGKeyboard is installed and enabled with Full Access for managed requests.
- The test account has enough non-production credits for the requested checks.

## Identity and account

1. Sign in with Apple and verify that nickname, balance, and referral state load
   after a cold launch.
2. Confirm the raw nonce is never persisted and an App Attest assertion is
   accepted. Repeat after an access-token expiry to exercise one refresh.
3. Open `https://osglab.com/i/{test-code}` while signed out. Sign in, then
   verify the pending code is redeemed exactly once.
4. Force-quit and reopen the app. Verify session recovery without another Apple
   prompt and confirm the keyboard extension cannot read the account session.
5. Sign out and verify account tokens plus shared gateway grants are removed.
6. Sign in again, choose Delete Account, complete Apple reauthentication, and
   verify local and BYOK features still work afterward.

For destructive verification, use a disposable Apple sandbox identity:

1. Set a nickname, generate an invitation code, and select **Use Credits**.
2. Delete the account after both confirmations and fresh Apple authorization.
3. Confirm the app returns to signed-out/BYOK state and no account, grant,
   profile, or purchase state remains visible.
4. Confirm old access and refresh tokens receive `401`; an Apple revoke outage
   must not restore the locally deleted account.
5. Sign in again and confirm a new local App Attest key state is registered.

Only pseudonymous immutable ledger, StoreKit audit, and time-limited anti-abuse
records remain where required for replay and abuse prevention.

## Managed DeepSeek

1. Select **Use Credits** for the first time. Verify the managed-cloud data
   disclosure appears, Cancel leaves BYOK selected, and Agree enables credits.
   Switch away and back again to confirm the disclosure is not repeated.
2. Verify the runtime uses managed Volcengine ASR and managed polishing together.
3. Run one polish request and one AI request. Verify actionable behavior for
   insufficient balance, expired grant, timeout, and cancellation.
4. In the server ledger, verify one reservation and one settlement per request.
   Retrying the same transport request must not create a second charge.

## Managed Volcengine ASR

1. Record approximately ten seconds of Mandarin PCM16LE at 16 kHz.
2. Verify partial and final results, then run translate-and-polish.
3. Cancel one recording mid-stream and verify the WebSocket closes without a
   stuck reservation.
4. Verify session-open fallback, idle timeout, empty result, insufficient
   balance, and concurrency-limit behavior.
5. Confirm the ledger settles successful sessions and releases failed or
   cancelled reservations.

Managed ASR currently does not send hotwords. Treat this as an explicit product
difference until the server request schema supports them.

## Regression gate

- Signed-out use remains valid.
- Local ASR never requires an account.
- Existing BYOK LLM and ASR credentials still use their direct providers.
- iCloud settings sync never contains account or gateway tokens.
- Flow, keyboard typing, and keyboard-extension memory-budget tests pass.

## StoreKit credits

The existing `ByRockyACoffee` product remains a voluntary consumable and never
grants credits. Configure `500tks` for 500 credits at USD 0.99, `1500tks` for
1,500 credits at USD 1.99 / CNY 18, and `3000tks` for 3,000 credits at
USD 2.99 / CNY 28.

1. Use a Sandbox Apple account and sign in to the same OSG account before
   purchasing.
2. Confirm the purchase supplies the OSG account UUID as `appAccountToken`.
3. Buy each product and verify the server grants exactly 500, 1,500, or 3,000
   credits and appends one `STOREKIT_PURCHASE` ledger entry before the app
   finishes the transaction.
4. Submit the same signed transaction again and verify the response is marked
   as replayed without changing the balance.
5. Interrupt the network after App Store success but before server
   acknowledgement. Relaunch and verify the unfinished transaction reconciles
   once.
6. Sign in to another OSG account and verify the first account's transaction is
   rejected.
7. Confirm there is no Restore Purchases action for credit packs and that the
   voluntary tip still changes only the local support count.
