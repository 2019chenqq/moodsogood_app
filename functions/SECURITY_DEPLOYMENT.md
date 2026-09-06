# Security deployment checklist

## Required secret

AI callable functions now verify the authenticated Firebase UID against the
RevenueCat `premium` entitlement using RevenueCat's server API. Set a
RevenueCat secret API key before deploying:

```sh
firebase functions:secrets:set REVENUECAT_SECRET_API_KEY
```

Do not use the public `goog_` or `appl_` SDK key for this secret and never put
the server key in Flutter code, `--dart-define`, `.env` files shipped with the
app, or source control.

The RevenueCat App User ID must continue to be the signed-in Firebase UID. A
fresh server result is cached for 15 minutes. A previously verified active
entitlement has a maximum six-hour grace window only when RevenueCat is
temporarily unavailable; an expired entitlement is never accepted.

## AI request ceilings

- Per Firebase UID: 12/minute, 120/hour, 300/day.
- Whole project: 120/minute, 5,000/day.

Counters are server-only in `ai_rate_limits` and `ai_global_rate_limits`.
Tune these values from observed production usage before increasing them.

## Deploy and verify

1. Set the RevenueCat secret above.
2. Deploy Firestore rules before distributing another APK.
3. Deploy Functions.
4. Verify an active `premium` subscriber can call every AI flow.
5. Verify a signed-in non-Pro account receives `permission-denied`.
6. Verify a missing/invalid server key fails closed and does not call OpenAI.
7. Remove or rotate the legacy Make webhook in the Make dashboard; deleting it
   from current source does not invalidate URLs already present in Git history
   or older APKs.
