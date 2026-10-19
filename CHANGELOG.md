# Changelog

## [0.1.2](https://github.com/leapingfrogs/mealplan/compare/v0.1.1...v0.1.2) (2026-10-19)


### Bug Fixes

* run the database and backups as uid 10999, and deploy config-only changes ([#16](https://github.com/leapingfrogs/mealplan/issues/16)) ([0488f70](https://github.com/leapingfrogs/mealplan/commit/0488f70190e90d7a56c4dcbc28eadb9e588746bb))
* update the TrueNAS app through the API client instead of midclt ([#15](https://github.com/leapingfrogs/mealplan/issues/15)) ([161bd7d](https://github.com/leapingfrogs/mealplan/commit/161bd7dd186acaabc4c5a374cf5ac5ec37c90761))

## [0.1.1](https://github.com/leapingfrogs/mealplan/compare/v0.1.0...v0.1.1) (2026-10-19)


### Bug Fixes

* name TRUSTED_PROXIES in the startup error for an invalid value ([#12](https://github.com/leapingfrogs/mealplan/issues/12)) ([f915283](https://github.com/leapingfrogs/mealplan/commit/f9152836d9cea4c94f9c17a204ac1701f50d28a7))


### Build and Dependencies

* add just deploy and just rollback for the TrueNAS app ([#14](https://github.com/leapingfrogs/mealplan/issues/14)) ([8575be7](https://github.com/leapingfrogs/mealplan/commit/8575be72942b4abbd0ab716a6e5cc21fb49cbe45))
* render compose.yaml for the TrueNAS Custom App ([#11](https://github.com/leapingfrogs/mealplan/issues/11)) ([804f9cc](https://github.com/leapingfrogs/mealplan/commit/804f9ccbf91516da3edeceed3ae4d94a4c5ac9b3))

## 0.1.0 (2026-10-19)


### Features

* add invite-only authentication ([008e4db](https://github.com/leapingfrogs/mealplan/commit/008e4dbe35b65afa763eaa482f3de5c44a060ffe))
* add JSON logging and self-hosted error tracking ([6fc50e9](https://github.com/leapingfrogs/mealplan/commit/6fc50e953212dcda9fd88bb88271cb3641c220a7))
* add liveness and readiness health endpoints ([52de3cf](https://github.com/leapingfrogs/mealplan/commit/52de3cf583ec641d882f579bf79c99266d353900))
* add nightly pg_dump backup sidecar ([#6](https://github.com/leapingfrogs/mealplan/issues/6)) ([5238a72](https://github.com/leapingfrogs/mealplan/commit/5238a72c2cd6c5d0ae51dce9068d7336b6620931))
* add production compose stack for TrueNAS ([#5](https://github.com/leapingfrogs/mealplan/issues/5)) ([189f079](https://github.com/leapingfrogs/mealplan/commit/189f079065631ceaf494ed93c14e87aa4c224e2a))
* configure Elixir release with migrations on start ([cf5d9f3](https://github.com/leapingfrogs/mealplan/commit/cf5d9f3bbcd79603a45f64b54505635f404962d3))
* harden security headers, proxy trust and login rate limits ([7cb0885](https://github.com/leapingfrogs/mealplan/commit/7cb088576d3cfe466497d97d27ffa6cf55aa669f))
* send email via SMTP relay in production ([8e9eff1](https://github.com/leapingfrogs/mealplan/commit/8e9eff15ae217d4f74b70fc3b889e479149ac61d))


### Build and Dependencies

* add devenv environment with pinned Elixir/OTP and tooling ([19b1994](https://github.com/leapingfrogs/mealplan/commit/19b1994e265141ab4f2b96d2f56aa1bc2936cf9a))
* add devenv-managed Postgres 18 service ([6fe8c3d](https://github.com/leapingfrogs/mealplan/commit/6fe8c3d2de1e46cab118c76d82a908fc8d920f72))
* add hardened production Dockerfile and image CI job ([#3](https://github.com/leapingfrogs/mealplan/issues/3)) ([6c90391](https://github.com/leapingfrogs/mealplan/commit/6c90391b770e266b1517479da4a10d25ef083aa8))
* **deps:** bump daisyui from v5.5.20 to v5.7.47 ([#4](https://github.com/leapingfrogs/mealplan/issues/4)) ([3b2a8d8](https://github.com/leapingfrogs/mealplan/commit/3b2a8d84928c6cf859e47b2ea7c9eee8a619a477))
* **deps:** bump the mix-minor-patch group with 2 updates ([#2](https://github.com/leapingfrogs/mealplan/issues/2)) ([5794a4a](https://github.com/leapingfrogs/mealplan/commit/5794a4a1cc6733b1ec12206766f30fe032ad83c3))
