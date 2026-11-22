# PDN DEX --- Petoron Domain Exchange

**A domain-owned decentralized exchange on Ethereum, built for the
Petoron Domain Name (PDN) ecosystem.**

PDN DEX lets owners of PDN NFT domains create and control liquidity
pools. Other PDN NFT holders can trade through those pools. Pool
ownership and management permissions are checked on-chain through PDN
Core.

## The core rule

**A valid PDN NFT is required to create a pool or execute a trade.**

A wallet without a PDN NFT can inspect public on-chain data, but cannot
create pools or buy/sell through PDN DEX.

-   **Domain owner:** owns the main PDN NFT and controls its pools.
-   **Manager:** owns a PDN NFT that the domain owner has authorized.
    Managers can operate liquidity and prices within limited
    permissions.
-   **Trader:** owns a valid PDN NFT and can trade through eligible
    pools, subject to the contract's restrictions.

A pool belongs to a PDN domain Token ID. The contract checks the current
NFT owner through PDN Core, so domain ownership rights follow the NFT.

## Deployed contract

  Property           Value
  ------------------ ----------------------------------------------
  Network            Ethereum Mainnet
  Chain ID           `1`
  Contract           `PDN_DEX`
  Contract address   `0xFE24B65c46641C7f4Cb6b1a603D6dc2BB6a0200E`
  PDN Core           `0x238B9b6De2A247178307d504e9B8DE5A98be4864`

-   [Contract and verified source on
    Etherscan](https://etherscan.io/address/0xFE24B65c46641C7f4Cb6b1a603D6dc2BB6a0200E#code)

The contract source is verified on Etherscan.

## Supported assets

  Asset   Ethereum Mainnet address                         Decimals
  ------- ---------------------------------------------- ----------
  ETH     Native ETH                                             18
  WBTC    `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`            8
  USDT    `0xdAC17F958D2ee523a2206206994597C13D831ec7`            6
  USDC    `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`            6

The contract accepts only these assets.

## How it works

1.  A PDN domain owner creates a pool for an asset pair and deposits
    liquidity.
2.  The owner configures a buyer price and, independently, a seller
    price.
3.  The owner can authorize up to seven PDN NFT managers for the domain.
4.  Managers can add or withdraw liquidity and update prices, but cannot
    create or close pools, pause pools, or appoint managers.
5.  Other eligible PDN NFT holders can buy or sell assets, subject to
    pool liquidity and the contract's checks.

A domain can have only one active pool for a given asset pair. The pair
is treated as the same regardless of token order.

## Key features

-   **Domain-owned pools:** each pool is associated with a PDN domain
    Token ID.
-   **PDN-gated trading:** traders must own a valid PDN NFT.
-   **Two-sided pricing:** buyer and seller prices are configured
    independently.
-   **Two pool creation modes:** initialize both reserves, or create a
    sell-reserve-only pool.
-   **Delegated management:** up to seven active managers per domain.
-   **Owner-controlled withdrawals:** manager-initiated withdrawals are
    sent to the current domain owner.
-   **Slippage limits:** buys enforce a maximum payment; sells enforce a
    minimum payment.
-   **Price-change protection:** trades include expected price
    parameters and revert if the configured price has changed.
-   **Pool controls:** owners can add liquidity, withdraw liquidity,
    pause, unpause, update prices, and close pools.
-   **No protocol trading fee:** the contract does not deduct a
    protocol-level percentage from trades. Ethereum gas fees still
    apply.

See [TECHNICAL.md](TECHNICAL.md) for contract behavior, permissions,
calculations, function reference, and interface instructions.

## Interface

The interface has two main areas:

-   **PDN Seller:** load your PDN domains, create pools, manage
    liquidity and prices, control pools, and manage authorized managers.
-   **PDN Buyer:** browse active pools and buy or sell assets.

Typical workflow:

1.  Connect an Ethereum Mainnet wallet.
2.  Load the PDN domains owned by the connected wallet.
3.  As a domain owner, create a pool and fund its reserves.
4.  Configure both trading prices if you want both directions enabled.
5.  Optionally authorize PDN NFT managers.
6.  Traders load active pools, enter their PDN Token ID, calculate the
    quote, set a payment limit, and submit the trade.

For detailed interface steps and the exact on-chain rules, read
[TECHNICAL.md](TECHNICAL.md).

**Security note:** If the interface uses a private-key connection, only
use it on a trusted computer and with a wallet you control. Never enter
a private key on a public or shared device.

## Licensing

The licensing terms in the repository root `LICENSE` file govern use of
the PDN software. Read that file before copying, modifying,
redistributing, or independently deploying the implementation.

There is an important distinction between interacting with the official
deployed contracts and copying the protected implementation:

-   Anyone may commercially interact with the official PDN DEX contracts
    on Ethereum, subject to applicable law and the protocol's on-chain
    requirements.
-   Independent applications, interfaces, analytics, APIs, and other
    services may integrate with the public interfaces of the official
    deployed contracts. Merely interacting with the official contracts
    does not itself require a PCL-C license.
-   This permission to interact with the official deployment does
    **not** grant unrestricted rights to copy, modify, fork,
    redistribute, or independently deploy the PDN software.
-   Activities requiring commercial rights to the protected
    implementation must be covered by the applicable license, including
    a valid PCL-C license where required by the root `LICENSE`.

PDN NFT ownership and software licensing are separate matters. Owning a
PDN NFT does not, by itself, grant rights to copy or deploy the PDN
software.

**The root `LICENSE` file is authoritative.** If this summary differs
from the license text, the license text controls.

## Important limitations

-   The deployed instance is on Ethereum Mainnet.
-   Pool creation and trading require PDN NFT ownership.
-   Only ETH, WBTC, USDT, and USDC are supported.
-   Each domain can have only one active pool per asset pair.
-   A maximum of seven active managers is allowed per main domain; this
    is shared across that domain's pools.
-   Managers cannot create or close pools, pause pools, or change
    manager permissions.
-   Manager withdrawals are sent to the current main domain owner.
-   Selling requires a configured seller price and sufficient payment
    reserve.
-   Paused pools cannot execute trades.
-   Ethereum gas fees apply to on-chain operations.

## Technical documentation

Read [TECHNICAL.md](TECHNICAL.md) for the detailed contract
specification, pool lifecycle, manager permissions, trading flow, price
arithmetic, security checks, and interface guide.
