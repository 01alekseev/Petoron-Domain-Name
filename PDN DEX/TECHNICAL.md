# PDN DEX --- Technical Documentation

This document describes the deployed PDN DEX contract's behavior, roles,
state, operations, and interface workflow. It is intended as a technical
companion to [README.md](README.md).

## 1. Deployment and dependencies

  Property           Value
  ------------------ ----------------------------------------------
  Network            Ethereum Mainnet
  Chain ID           `1`
  Contract           `PDN_DEX`
  DEX address        `0xFE24B65c46641C7f4Cb6b1a603D6dc2BB6a0200E`
  PDN Core address   `0x238B9b6De2A247178307d504e9B8DE5A98be4864`

-   [Verified DEX
    source](https://etherscan.io/address/0xFE24B65c46641C7f4Cb6b1a603D6dc2BB6a0200E#code)

The DEX has a fixed PDN Core dependency. The constructor checks that
code exists at the configured PDN Core address. NFT ownership is
validated through the Core contract's `ownerOf` function.

The DEX does not accept an arbitrary NFT contract as a replacement for
PDN Core.

## 2. Roles and authorization

### 2.1 Domain owner

The domain owner is the current owner of the main PDN NFT identified by
`ownerTokenId`.

The owner can:

-   Create pools for the domain.
-   Add and withdraw either reserve.
-   Set buyer and seller prices.
-   Pause and unpause pools.
-   Close pools.
-   Add and remove managers.
-   Revoke all managers.

Ownership is resolved from PDN Core. Rights therefore follow the current
owner of the main NFT.

### 2.2 Manager

A manager is identified by a manager PDN Token ID. The contract checks
the current owner of that NFT when manager permissions are used.

A manager can:

-   Add sell-asset liquidity.
-   Add payment-asset liquidity.
-   Withdraw sell-asset liquidity.
-   Withdraw payment-asset liquidity.
-   Set buyer price.
-   Set seller price.

A manager cannot:

-   Create pools.
-   Close pools.
-   Pause or unpause pools.
-   Add or remove managers.
-   Revoke all managers.

Manager withdrawals are sent to the current owner of the main domain
NFT. A manager cannot specify a different withdrawal recipient.

### 2.3 Manager constraints

-   Maximum: seven active managers per main domain.
-   The limit is shared across all pools belonging to that domain.
-   A manager Token ID cannot be zero.
-   The main domain Token ID cannot be its own manager.
-   A manager NFT cannot be owned by the same wallet as the main domain
    NFT.
-   An already-active manager cannot be added again.

Manager authorization is keyed by the main domain Token ID, not
independently by pool.

### 2.4 Manager epochs

The contract maintains a manager epoch for each domain.

When the owner revokes all managers, the epoch advances and the previous
manager permissions become invalid. This invalidates the old set without
requiring each previous manager authorization to be individually
processed.

## 3. Pool model

A pool stores:

  Field                    Meaning
  ------------------------ -----------------------------------------------
  `ownerTokenId`           Main PDN domain Token ID
  `sellToken`              Asset being bought from or sold into the pool
  `paymentToken`           Asset used to pay for the sell asset
  `reserve`                Available sell-asset reserve
  `reservePayment`         Available payment-asset reserve
  `priceNumerator`         Buyer-price numerator
  `priceDenominator`       Buyer-price denominator
  `sellPriceNumerator`     Seller-price numerator
  `sellPriceDenominator`   Seller-price denominator
  `status`                 `NONE`, `ACTIVE`, or `CLOSED`
  `paused`                 Whether trading is paused

### 3.1 Asset-pair uniqueness

A domain can have only one active pool for a particular pair.

The pair key is canonical: reversing the token order does not create a
different pair.

Example: `ETH/USDC` and `USDC/ETH` are treated as the same pair for
duplicate-active-pool prevention.

Different domains may each create their own pool for the same pair.

When a pool is closed, its active pair registration is released,
allowing a new pool for that pair to be created for the domain.

## 4. Supported assets and units

  Asset   Address                                          Decimals
  ------- ---------------------------------------------- ----------
  ETH     Native ETH                                             18
  WBTC    `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`            8
  USDT    `0xdAC17F958D2ee523a2206206994597C13D831ec7`            6
  USDC    `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`            6

Amounts passed to Solidity functions are integer base units. The
interface must convert human-readable amounts using the decimals of the
relevant token.

Examples:

-   `1 ETH` = `10^18` wei.
-   `1 WBTC` = `10^8` base units.
-   `1 USDT` = `10^6` base units.
-   `1 USDC` = `10^6` base units.

The contract's `getTokenDecimals(address)` returns the supported
decimals and rejects unsupported assets.

## 5. Pool creation

The contract provides two `createPool` overloads.

### 5.1 Single-reserve creation

``` solidity
createPool(
    uint256 ownerTokenId,
    address sellToken,
    address paymentToken,
    uint256 sellAmount,
    uint256 priceNumerator,
    uint256 priceDenominator
)
```

This method:

-   Requires the caller to own `ownerTokenId`.
-   Deposits the initial sell reserve.
-   Sets the buyer price.
-   Starts with no payment reserve.
-   Leaves the seller price unset.

The pool can support buying if it has sell reserve. Selling into the
pool requires payment liquidity and a configured seller price.

### 5.2 Two-reserve creation

``` solidity
createPool(
    uint256 ownerTokenId,
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB,
    uint256 priceABNumerator,
    uint256 priceABDenominator,
    uint256 priceBANumerator,
    uint256 priceBADenominator
)
```

This method deposits both assets and initializes both directional
prices.

The interface must map the selected sell/payment assets and amounts to
the contract's token A/token B arguments consistently.

## 6. Price model and quotes

Buyer and seller prices are separate ratios.

-   Buyer price is used by `quotePayment` and `buy`.
-   Seller price is used by `quoteSell` and `sell`.

They are not automatically derived from each other.

### Example

Assume the pool sells ETH for USDC:

-   Buyer price: 2,500 USDC per ETH.
-   Seller price: 2,450 USDC per ETH.

Buying 2 ETH requires 5,000 USDC before considering token-unit
representation.

Selling 2 ETH returns 4,900 USDC, provided the pool has enough payment
reserve.

These figures illustrate the configured ratios; actual on-chain
calculations use integer base units.

### Rounding

-   Buyer payment rounds up.
-   Seller payment rounds down.

This avoids charging less than the calculated buyer amount or paying
more than the calculated seller amount due to fractional base units.

### Quote functions

``` solidity
quotePayment(uint256 poolId, uint256 sellAmount)
quoteSell(uint256 poolId, uint256 sellAmount)
```

`quotePayment` calculates the buyer-side payment. `quoteSell` calculates
the seller-side payment.

The quote functions do not themselves enforce the pool's paused state.
The actual `buy` and `sell` functions enforce trading restrictions.

## 7. Trading execution

### 7.1 Buy

``` solidity
buy(
    uint256 poolId,
    uint256 buyerTokenId,
    uint256 sellAmount,
    uint256 expectedPriceNumerator,
    uint256 expectedPriceDenominator,
    uint256 maxPaymentAmount
)
```

The contract checks, among other conditions:

1.  The buyer owns the supplied PDN NFT.
2.  The pool is active.
3.  The pool is not paused.
4.  The buyer is not the pool's domain owner.
5.  The buyer is not trading through an authorized manager identity for
    that domain.
6.  The supplied expected buyer price matches the pool's current buyer
    price.
7.  The sell reserve is sufficient.
8.  The calculated payment does not exceed `maxPaymentAmount`.
9.  The correct payment asset is supplied.

For ETH payment, the transaction must include the exact required
`msg.value`. For ERC-20 payment, the buyer must approve the DEX and the
contract transfers the required amount.

The purchased sell asset is transferred to the buyer.

### 7.2 Sell

``` solidity
sell(
    uint256 poolId,
    uint256 sellerTokenId,
    uint256 sellAmount,
    uint256 expectedPriceNumerator,
    uint256 expectedPriceDenominator,
    uint256 minPaymentAmount
)
```

The contract checks, among other conditions:

1.  The seller owns the supplied PDN NFT.
2.  The pool is active.
3.  The pool is not paused.
4.  The seller is not the pool's domain owner.
5.  The seller is not trading through an authorized manager identity for
    that domain.
6.  A seller price has been configured.
7.  The supplied expected seller price matches the pool's current seller
    price.
8.  The payment reserve is sufficient.
9.  The calculated payment is at least `minPaymentAmount`.
10. The correct asset is supplied.

If the sell asset is ETH, the exact required ETH amount must be sent. If
it is an ERC-20 asset, the seller must approve the DEX.

The payment asset is transferred to the seller.

### 7.3 Price-change protection and slippage

The expected price arguments protect against a price change between
quote calculation and transaction execution.

The trade reverts if the expected price does not match the current
configured price.

The explicit limits provide an additional bound:

-   Buy: `maxPaymentAmount`.
-   Sell: `minPaymentAmount`.

These checks do not guarantee execution; they cause the transaction to
revert if the conditions are no longer satisfied.

## 8. Liquidity operations

### Owner functions

``` solidity
addFunds(uint256 poolId, uint256 amount)
addPaymentFunds(uint256 poolId, uint256 amount)
withdrawFunds(uint256 poolId, uint256 amount)
withdrawPaymentFunds(uint256 poolId, uint256 amount)
```

The owner can add or withdraw either reserve. Withdrawals are restricted
by the available reserve and are sent to the current domain owner.

### Manager functions

``` solidity
managerAddFunds(uint256 poolId, uint256 amount)
managerAddPaymentFunds(uint256 poolId, uint256 amount)
managerWithdraw(uint256 poolId, uint256 amount)
managerWithdrawPayment(uint256 poolId, uint256 amount)
```

These operations require valid manager authorization for the pool's main
domain.

Manager withdrawals are also sent to the current domain owner, not to
the manager.

### ETH and ERC-20 handling

-   ETH is supplied as `msg.value`.
-   ERC-20 assets require an allowance for the DEX contract.
-   The contract validates the received ERC-20 amount.
-   Unexpected ETH is rejected.
-   When both pool assets are ERC-20, no ETH should be supplied.

## 9. Pool administration and lifecycle

### Update prices

``` solidity
setPrice(uint256 poolId, uint256 numerator, uint256 denominator)
setSellPrice(uint256 poolId, uint256 numerator, uint256 denominator)
```

The owner or an authorized manager can update the buyer and seller
prices independently.

### Pause and unpause

``` solidity
pausePool(uint256 poolId)
unpausePool(uint256 poolId)
```

These operations are restricted to the domain owner. While paused, the
pool cannot execute buys or sells.

### Close

``` solidity
closePool(uint256 poolId)
```

Only the domain owner can close a pool.

The contract closes the pool, clears both reserves, and returns the
remaining sell and payment assets to the current owner of the main
domain NFT. The pair registration is released so that a new pool can
later be created for the same domain and pair.

A closed pool is not reopened.

## 10. Interface operating guide

The interface is organized around **PDN Seller** and **PDN Buyer**
workflows.

### 10.1 Connect

1.  Connect to Ethereum Mainnet.
2.  Confirm the displayed wallet address and network.
3.  Use the interface's refresh/disconnect controls as needed.

If the interface uses a private-key input, treat it as sensitive: use
only a trusted local environment and never enter the key on a shared
computer.

### 10.2 Load owned domains

In **PDN Seller**, use **Load my domains** in the domain section.

The interface reads PDN Core ownership and displays the Token IDs held
by the connected wallet. Use the relevant Token ID when creating or
managing pools.

### 10.3 Create a pool

In **Create Liquidity Pool**:

1.  Select the main domain Token ID.
2.  Select the sell asset and payment asset.
3.  Enter the initial reserve amounts.
4.  Enter the buyer and seller price settings supported by the selected
    creation mode.
5.  Approve ERC-20 assets when required.
6.  Submit the pool creation transaction.

ETH is supplied as transaction value. ERC-20 assets require approval
before transfer.

For a single-reserve pool, the payment reserve starts at zero and the
seller price is unset. Add payment liquidity and configure the seller
price before enabling the sell direction.

### 10.4 Load and manage pools

Use **Load pools for my domains** in **My Pools**.

In **Manage Pool**, select or enter the Pool ID to perform
owner-authorized actions:

-   Add liquidity.
-   Withdraw liquidity.
-   Update buyer price.
-   Update seller price.
-   Pause.
-   Unpause.
-   Close.

The contract remains authoritative: an interface control does not grant
permission that the caller does not have on-chain.

### 10.5 Manage PDN managers

In **PDN Managers**, provide the pool/domain context and manager PDN
Token ID.

The owner can:

-   Add a manager.
-   Remove a manager.
-   Revoke all managers.
-   View active manager Token IDs and related ownership/epoch
    information exposed by the interface.

The seven-manager limit applies to the main domain across its pools, not
separately to each pool.

### 10.6 Manager operations

An authorized manager selects an existing pool and can:

-   Add sell liquidity.
-   Add payment liquidity.
-   Withdraw sell liquidity.
-   Withdraw payment liquidity.
-   Update buyer price.
-   Update seller price.

The manager cannot create or close pools, pause or unpause pools, or
change manager permissions.

Withdrawals go to the current domain owner.

### 10.7 Browse and trade

In **PDN Buyer**, load active pools.

For a buy:

1.  Enter the Pool ID.
2.  Enter the buyer's PDN Token ID.
3.  Enter the sell amount.
4.  Calculate the payment quote.
5.  Set the maximum payment amount.
6.  Submit the buy transaction.

For a sell:

1.  Enter the Pool ID.
2.  Enter the seller's PDN Token ID.
3.  Enter the sell amount.
4.  Calculate the payment quote.
5.  Set the minimum payment amount.
6.  Submit the sell transaction.

The seller direction requires a configured seller price and sufficient
payment reserve.

### 10.8 Transaction status

The interface may display transaction hashes and pending/confirmed
status. ERC-20 approval and the actual pool operation are separate
transactions where approval is required.

Always verify important transactions.

## 11. Contract function reference

  -----------------------------------------------------------------------
  Function                            Access / purpose
  ----------------------------------- -----------------------------------
  `createPool`                        Domain owner creates a pool

  `addFunds`                          Domain owner adds sell reserve

  `addPaymentFunds`                   Domain owner adds payment reserve

  `withdrawFunds`                     Domain owner withdraws sell reserve

  `withdrawPaymentFunds`              Domain owner withdraws payment
                                      reserve

  `managerAddFunds`                   Manager adds sell reserve

  `managerAddPaymentFunds`            Manager adds payment reserve

  `managerWithdraw`                   Manager initiates sell reserve
                                      withdrawal to domain owner

  `managerWithdrawPayment`            Manager initiates payment reserve
                                      withdrawal to domain owner

  `setPrice`                          Owner or manager updates buyer
                                      price

  `setSellPrice`                      Owner or manager updates seller
                                      price

  `setManager`                        Domain owner adds/removes a manager

  `revokeAllManagers`                 Domain owner revokes all managers

  `pausePool`                         Domain owner pauses trading

  `unpausePool`                       Domain owner resumes trading

  `closePool`                         Domain owner closes pool and
                                      receives reserves

  `buy`                               Eligible PDN NFT holder buys sell
                                      asset

  `sell`                              Eligible PDN NFT holder sells sell
                                      asset

  `quotePayment`                      Calculates buyer-side payment

  `quoteSell`                         Calculates seller-side payment

  `getTokenDecimals`                  Returns supported token decimals

  `getManagerTokenIds`                Returns active manager Token IDs
                                      for a pool's domain
  -----------------------------------------------------------------------

Public state/getters include pool data, `nextPoolId`, `managerEpoch`,
manager mappings, `PDN_CORE`, `pdnCore`, and `MAX_MANAGERS_PER_POOL`.

## 12. Security properties and boundaries

The implementation includes:

-   PDN NFT ownership checks through PDN Core.
-   Domain-owner and manager authorization checks.
-   Self-trading restrictions.
-   Active-pool and pause-state checks for trades.
-   Expected-price checks.
-   Maximum/minimum payment constraints.
-   Reserve sufficiency checks.
-   Supported-asset validation.
-   ETH value validation.
-   ERC-20 transfer result and received-amount checks.
-   Reentrancy protection around sensitive operations.

These describe implemented contract checks. They are not a substitute
for an independent audit and do not imply that smart-contract risk is
eliminated.

## 13. Fees

The contract does not deduct a protocol-level trading fee from swaps.

Users still pay Ethereum network gas. ERC-20 approvals can require a
separate transaction and gas payment.

## 14. Licensing

The repository-root `LICENSE` file is authoritative.

Commercial interaction with the official deployed contracts and
independent integration through their public interfaces are distinct
from copying or deploying the protected PDN implementation.

A PCL-C license is not required solely to interact commercially with the
official deployed contracts or to build an independent integration that
communicates with them. Copying, modifying, forking, redistributing, or
independently deploying the protected implementation requires the
applicable rights under the root license, including valid PCL-C rights
where the license requires them.

Read the complete root `LICENSE` before using, modifying,
redistributing, or deploying PDN source code. If this summary conflicts
with the license, the license controls.
