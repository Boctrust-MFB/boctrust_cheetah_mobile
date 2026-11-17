# Core Mobile Endpoint Coverage (2026-10-24)

This compares the Swagger UI's `Mobile` customer groups (https://core-dev-api.centurysoftware.dev/api/v1/docs/) with the Core paths in `lib/app/core_api_endpoints.dart`, `lib/app/feature_capability.dart`, and the Core services. "Not consumed" means the app sends no matching Core request; a similarly named local or User Service flow does not count.

## Covered by 2026-10-24 plans

- Account statement: [core account statement](../plans/2026-10-24-core-account-statement.md).
- Savings catalogue, quote, create `amount`, and delete: [savings plan integration](../plans/2026-10-24-savings-plan-delete.md).
- Transfer liveness completion routes and service method: [transfer liveness](../plans/2026-10-24-core-transfer-liveness.md). The attempt state machine and UI are deferred until a bank-approved liveness provider exists.

## Not consumed and unplanned

### Customer Accounts (Mobile)

- `POST /api/v1/me/bank-accounts` — open the customer's BocFlex account.
- `GET /api/v1/me/customer-biodata/tier` — read the customer's tier.
- `PATCH /api/v1/me/customer-biodata/tier` — update/refresh the customer's tier.

### Customer Savings Plans (Mobile)

- `GET /api/v1/me/savings-plans/flat` — skipped deliberately: the screens are product-specific and use the grouped `/me/savings-plans` response. Revisit only if a cross-product plan list is added.

### Snap To Pay and Scan To Pay (Mobile)

- `POST /api/v1/me/snap-to-pay` and `POST /api/v1/me/scan-to-pay` — extract a number from a photo. The app runs OCR on-device and uses Core name enquiry afterwards.
