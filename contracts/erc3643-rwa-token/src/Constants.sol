// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/// @dev ERC-735 claim topic: the investor passed the issuer's KYC / AML checks.
uint256 constant CLAIM_TOPIC_KYC = uint256(keccak256('erc3643-rwa-token.claim.kyc'));

/// @dev ERC-735 claim topic: the investor is verified as an accredited investor (SEC Rule 501(a)).
/// Rule 506(c) requires the issuer to take reasonable steps to verify this status, not to rely on self-certification.
uint256 constant CLAIM_TOPIC_ACCREDITED_INVESTOR = uint256(keccak256('erc3643-rwa-token.claim.accredited-investor'));

/// @dev ERC-735 claim scheme for an ECDSA signature, the only one `ClaimIssuer.isClaimValid` verifies.
uint256 constant CLAIM_SCHEME_ECDSA = 1;

/// @dev ISO 3166-1 numeric country codes, the format stored by the `IdentityRegistry`.
uint16 constant COUNTRY_US = 840;
uint16 constant COUNTRY_GB = 826;

/// @dev Shares are whole units, so the token has no fractional part.
uint8 constant SHARE_DECIMALS = 0;

/// @dev Rule 144(d) holding period for restricted securities of a non-reporting issuer: one year,
/// rounded up so that it also covers a leap year.
uint256 constant RULE_144_HOLDING_PERIOD = 366 days;
