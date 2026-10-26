# Application-token authentication proposal (not implemented)

> **Status:** Unimplemented design proposal. The running server accepts only the
> settings in the [README](README.md#configuration). `TAIGA__USEAPPLICATIONTOKEN`,
> `TAIGA__APPLICATIONID`, and `TAIGA__APPLICATIONKEY` have no implemented effect.
> Endpoint/crypto details below are design assumptions requiring upstream
> verification before implementation. This is not a setup guide.

## Goals & Use Case
- Motivation: explore an alternative to username/password bootstrap. The original hypothesis about Codex caching Taiga bearer tokens was not established. In this stdio server, AuthClient owns Taiga tokens and refreshes after a received 401; Codex does not supply the upstream bearer token.
- Goal: Use Taiga “Application tokens” for MCP→Taiga calls. These are long-lived, tied to an application+user, and sent via `Authorization: Application {token}`.
- Outcome: Reliable, long-lived auth for the MCP server with no behavior change unless opted in.

## Approach Overview
- Add an alternative auth mode (“Application Token mode”) alongside the current bearer mode.
- Bootstrap with short-lived bearer (using username/password) only to perform the one-time exchange to obtain the application token.
- Persist the application token in memory for the MCP process lifetime; do not write to disk.
- For all subsequent Taiga API calls, send `Authorization: Application {token}`.
- On 401 responses, re-run the exchange flow and retry once.

## Configuration
- Options (env vars map to `Taiga` section via `TAIGA__*`):
  - `UseApplicationToken` (bool) → `TAIGA__USEAPPLICATIONTOKEN`
  - `ApplicationId` (UUID string) → `TAIGA__APPLICATIONID`
  - `ApplicationKey` (shared secret string) → `TAIGA__APPLICATIONKEY`
- Existing values remain required for bootstrap: `Username`, `Password`, optional `BaseUrl`.
- Defaults: feature disabled unless `UseApplicationToken=true` and both `ApplicationId` and `ApplicationKey` are provided.

## HTTP Flow (Taiga endpoints)
1) Check existing app token
- GET `applications/{applicationId}/token`
- Headers: `Authorization: Bearer {auth_token}` (short-lived bearer)
- If response contains non-null `id` and `auth_code`, skip to Validate (step 3). If both are null, continue to Authorize.

2) Authorize app token
- POST `application-tokens/authorize`
- Headers: `Authorization: Bearer {auth_token}`
- Body: `{ "application": "{applicationId}", "state": "{unguessable-state}" }`
- Response: `{ "auth_code": "...", "state": "...", ... }`
- Verify `state` matches.

3) Validate authorization code
- POST `application-tokens/validate`
- Headers: `Authorization: Bearer {auth_token}`
- Body: `{ "application": "{applicationId}", "auth_code": "{auth_code}", "state": "{state}" }`
- Response: `{ "cyphered_token": "<JWE>" }`

4) Decrypt the JWE
- JWE algorithms: `alg=A128KW`, `enc=A256GCM`.
- Use `ApplicationKey` as the symmetric key to unwrap/decrypt.
- Decrypted JSON: `{ "token": "<application-token>" }`.
- Store token in-memory and switch to `Authorization: Application {token}` for subsequent calls.

## Header Strategy
- Application mode enabled: always send `Authorization: Application {token}` for API calls.
- Bearer is used only internally during bootstrap/renewal to call the application-token endpoints.

## Error & Expiry Handling
- 401 on an API call using Application header:
  - Attempt re-acquisition: perform steps 1–4 again using a fresh short-lived bearer (log in with username/password).
  - Retry the original request once with the new Application token.
- 401 during authorize/validate: treat as invalid bearer; re-login once, then retry.
- `state` mismatch or JWE decrypt failure: abort, log safely, and surface an actionable error.

## Caching & Lifecycle
- In-memory only. No file or disk persistence (aligns with project security guidance).
- Token cleared on process restart; MCP will re-bootstrap on next start.

## Security Considerations
- Never log `Username`, `Password`, `ApplicationKey`, bearer tokens, or application tokens.
- Generate a strong, unguessable `state` per authorization flow (e.g., 128-bit random, base64url).
- Validate `state` on validate response.
- Minimal log messages: “lookup”, “authorize”, “validate”, “decrypt”, “switch-to-application-header”, and retry events, without sensitive values.

## Implementation Plan (no code yet)
1) Config additions
- Add `UseApplicationToken`, `ApplicationId`, `ApplicationKey` to `TaigaOptions`.
- Validate: if `UseApplicationToken=true`, require `ApplicationId` and `ApplicationKey`.

2) Auth strategy interface
- Introduce an abstraction used by domain APIs (currently `AuthClient`).
- Provide two strategies: Bearer (existing behavior) and ApplicationToken (new flow).

3) ApplicationToken strategy
- Acquire bearer: reuse current username/password login to `/auth`.
- Execute steps 1–4 above; cache decrypted app token in-memory.
- Wrap outbound requests to set `Authorization: Application {token}`.

4) Retry logic
- On `Unauthorized`, re-run exchange once then retry the original request.
- If it still fails, bubble the error.

5) Crypto component
- Use a vetted .NET JWE library supporting `A128KW` + `A256GCM` (e.g., `Jose.JWT`).
- Encapsulate decrypt in a small service to keep dependencies isolated and swappable.

6) DI wiring
- Bind options from env.
- Register the chosen auth strategy based on `UseApplicationToken` at startup.

7) Documentation
- README: add configuration section with the new env vars.
- Mention operational notes and troubleshooting.

8) Testing
- Unit tests using mocked `HttpMessageHandler` for:
  - lookup→authorize→validate happy path
  - 401 on API call triggers re-exchange and success on retry
  - bad `state`, decrypt failure, missing fields
  - ensure Bearer path unchanged when feature disabled
- Crypto test using a known-good JWE fixture for `A128KW`/`A256GCM` and a negative test with wrong key.

## Backward Compatibility & Rollout
- Default behavior unchanged (Bearer only) unless `UseApplicationToken=true`.
- Safe incremental rollout: enable in non-prod, verify, then enable in prod.
- No database or external persistent state changes.

## Open Questions
- Do we need optional disk persistence of the app token? Current guidance says no; in-memory only.
- Any Taiga-specific rotation policy for application tokens we should proactively handle?

## Env Var Quick Reference
- `TAIGA__USEAPPLICATIONTOKEN=true`
- `TAIGA__APPLICATIONID=<uuid>`
- `TAIGA__APPLICATIONKEY=<shared-secret>`
- `TAIGA__USERNAME=<your-login>`
- `TAIGA__PASSWORD=<your-password>`
- `TAIGA__BASEURL=https://api.taiga.io/api/v1/` (optional)

## Operational Notes
- First run after enabling will perform the one-time exchange.
- Subsequent calls would use the Application token; evaluate reliability against the current AuthClient before claiming an improvement.
- If Taiga rotates the application key, reconfigure `TAIGA__APPLICATIONKEY` and restart the MCP server.
