# NFT Magazine | Technical Documentation

## 1. Contract Overview

`NFTMagazine` is a smart contract for listing and purchasing NFTs that follow the **ERC-721** and **ERC-1155** standards.

The contract provides:
- NFT listing creation;
- temporary custody of listed NFTs in the contract's escrow;
- seller eligibility checks through PDN Core;
- listing limits based on the PDN tier;
- NFT purchases by participants who own at least one PDN domain;
- automatic transfer of the seller's asking price to a designated payout address;
- protocol fee collection;
- cancellation of active listings by their sellers.

The contract is not a general-purpose custodial wallet for NFTs. When an NFT is listed, it is transferred to the contract and held in escrow until the listing is purchased or cancelled.

## 2. Integration with PDN Core

The contract uses the following PDN Core functions:

| Function | Purpose |
|---|---|
| `ownerOf(tokenId)` | Checks the owner of a PDN domain |
| `balanceOf(account)` | Checks whether a buyer owns at least one PDN domain |
| `canonicalNameOf(tokenId)` | Retrieves the canonical name used to determine the participant tier |
| `isVerified(tokenId)` | Checks the PDN domain's verification status |
The PDN Core address is stored in `pdnCore` as an `immutable` value.

## 3. Participant Tiers and Listing Limits

The tier is determined using the specific `pdnTokenId` supplied by the seller when creating a listing.

The contract applies the following checks in order:

1. If the specified PDN domain has no owner, the result is `NONE`.
2. If the PDN domain is verified through `isVerified`, the result is `EXCLUSIVE`.
3. For an unverified PDN domain, the contract checks the character count of `canonicalNameOf`:
   - 1–11 symbol — `PRIME`;
   - 12–21 symbol — `USER`;
   - 0 symbol or more than 21 symbol — `NONE`.

Verification takes priority: a verified PDN domain receives the `EXCLUSIVE` tier regardless of its name length.

| Tier | Condition | Maximum active listings |
|---|---|---:|
| `USER` | Unverified name with a length of 12–21 characters | 7 |
| `PRIME` | Unverified name with a length of 1–11 characters | 14 |
| `EXCLUSIVE` | PDN domain is verified | 21 |
| `NONE` | No eligible tier | 0 |

The limit is tracked separately for each `pdnTokenId`. Only active listings count toward the limit. When a listing is successfully purchased or cancelled, its slot is released.

`participantTier(pdnTokenId)` returns the tier, while `listingLimit(pdnTokenId)` returns the corresponding listing limit.

## 4. Supported NFT Standards

The contract supports two NFT standards.

### ERC-721

- A listing contains one specific NFT.
- Before listing, the contract checks ERC-721 interface support.
- The seller must be the current owner of the token.
- The contract must be authorized to transfer the token, either through token-specific approval using `getApproved(tokenId)` or operator approval using `isApprovedForAll(owner, contract)`.
- Once listed, the NFT is transferred from the seller to the contract.

Only one active listing for a particular ERC-721 token is allowed in this contract.

### ERC-1155

- A listing contains a specified quantity of one `tokenId`.
- The quantity must be greater than zero.
- The seller's balance must be at least the listed quantity.
- The seller must authorize the contract as an operator through `isApprovedForAll`.
- The contract verifies that its escrow balance actually increases by exactly the listed quantity.

Only one active ERC-1155 listing is allowed for the same combination of NFT contract, `tokenId`, and seller. Different sellers may list the same `tokenId`.

**Important:** The entire ERC-1155 quantity in a listing is sold as one lot. Partial purchases are not supported.

### NFT Contract Requirements

- PDN Core NFTs themselves cannot be listed through this contract.
- The NFT contract must contain code and support the relevant ERC-165 interface.
- ERC-721 and ERC-1155 contracts must support the safe transfers required to move NFTs into escrow and later transfer them to the buyer or return them to the seller.
- ERC-1155 batch transfers are not accepted by this contract.

## 5. Creating a Listing

For ERC-721, the contract provides:

`depositERC721(nftContract, tokenId, price, payoutAddress, pdnTokenId)`

For ERC-1155, it provides:

`depositERC1155(nftContract, tokenId, amount, price, payoutAddress, pdnTokenId)`

Parameters:

| Parameter | Description |
|---|---|
| `nftContract` | Address of the NFT contract |
| `tokenId` | NFT identifier |
| `amount` | ERC-1155 quantity; always 1 for ERC-721 |
| `price` | Listing price in the network's native currency's smallest units |
| `payoutAddress` | Address that will receive the seller's asking price |
| `pdnTokenId` | PDN domain used to establish the seller's listing eligibility and determine the listing limit |

Before creating a listing, the contract checks that:

1. The NFT is not a PDN Core NFT.
2. The NFT contract address is valid and contains code.
3. The price is greater than zero and does not cause an overflow during fee calculation.
4. `payoutAddress` is not the zero address.
5. The seller owns the specified `pdnTokenId`.
6. The NFT supports the selected standard.
7. The seller owns the NFT or a sufficient ERC-1155 quantity.
8. The contract has the required transfer approval.
9. The listing limit for the specified PDN domain has not been exceeded.
10. No conflicting active listing already exists for the asset.

After all checks pass, the contract creates a listing with the `ACTIVE` status, records the seller, payout address, PDN domain, price, standard, and quantity, and transfers the NFT into escrow.

An NFT transfer is accepted only as part of an expected listing operation. The contract validates the NFT contract, sender, operator, `tokenId`, standard, and quantity. If validation or the safe transfer fails, the entire transaction is reverted.

`nextListingId` starts at 1 and increases whenever a new listing is created.

## 6. Listing Lifecycle

A listing can have the following statuses:

| Status | Meaning |
|---|---|
| `NONE` | No listing has been created with this ID |
| `ACTIVE` | The NFT is held in escrow and is available for purchase |
| `SOLD` | The listing has been successfully purchased |
| `CANCELLED` | The seller has cancelled the listing |

A newly created listing receives the `ACTIVE` status.

There are two user-facing outcomes:

- A buyer calls `buy(listingId)`. If the purchase succeeds, the status changes to `SOLD`.
- The seller calls `cancelListing(listingId)`. If cancellation succeeds, the status changes to `CANCELLED` and the NFT is returned to the seller.

A listing that is no longer `ACTIVE` cannot be purchased or cancelled again.

The contract does not provide a function to change the price or edit an existing listing. To change the sale terms, the seller must cancel the active listing and create a new one.

## 7. Purchasing an NFT

A purchase is made by calling:

`buy(listingId)`

The buyer must send the network's native currency along with the transaction.

Before completing the purchase, the contract checks that:

1. The listing exists.
2. Its status is `ACTIVE`.
3. The buyer is not the seller.
4. The buyer owns at least one PDN domain: `PDN Core.balanceOf(buyer) > 0`.
5. The seller still owns the PDN domain specified when the listing was created.
6. The NFT is still held in the contract's escrow in the required quantity.
7. The amount sent is exactly equal to the listing price plus the fee.

If the seller no longer owns the PDN domain linked to the listing, the purchase is rejected. The buyer's PDN ownership is checked using their total PDN domain balance. The buyer does not need to own the same PDN domain that the seller used for the listing.

After all checks pass, the contract:

1. Changes the listing status to `SOLD`.
2. Decreases the active listing count for the associated PDN domain.
3. Removes the active asset listing index.
4. Adds the fee to `protocolRevenue`.
5. Transfers the listing price to the seller's `payoutAddress`.
6. Transfers the NFT from escrow to the buyer.
7. Emits the `NFTSold` event.

If the payment transfer or NFT transfer fails, the entire transaction is reverted. The status change, balance changes, and fee accounting are also rolled back.

## 8. Price and Protocol Fee

The protocol fee is defined by these constants:

- `FEE_BPS = 200`
- `BPS_DENOMINATOR = 10_000`

This corresponds to a fee of **2% of the listing price**.

The contract calculates the fee as follows:

`fee = price / 50`

`total = price + fee`

The buyer must send exactly `total`. A transaction is rejected if the amount sent is either lower or higher than the required amount.

Payment distribution:

| Recipient | Amount |
|---|---|
| `payoutAddress` | Full listing price |
| Protocol | 2% fee |

The seller specifies `payoutAddress` when creating the listing. It may be different from the seller's own address. Therefore, the listing price is sent to `payoutAddress`, not automatically to `seller`.

The calculation uses integer arithmetic in the network currency's smallest units. Any fractional remainder from division is rounded down. As a result, the effective fee may round down to zero for very small listing prices.

## 9. Cancelling a Listing

A listing is cancelled by calling:

`cancelListing(listingId)`

The following conditions apply:

- the listing must exist;
- only the address recorded as `seller` may call the function;
- the listing status must be `ACTIVE`;
- the NFT must actually be held in escrow in the required quantity.

When cancellation succeeds, the contract:

1. Changes the listing status to `CANCELLED`.
2. Decreases the active listing count for the associated PDN domain.
3. Removes the active asset listing index.
4. Returns the ERC-721 token or the specified ERC-1155 quantity to the seller.
5. Emits the `ListingCancelled` event.

If the NFT cannot be returned, the entire transaction is reverted and the listing remains active.

## 10. Reading Contract Data and Indexes

The contract exposes public data that can be read without sending a transaction.

| Function / Variable | Description |
|---|---|
| `getListing(listingId)` | Returns the complete listing structure |
| `listings(listingId)` | Returns the listing fields by ID |
| `nextListingId` | ID that will be assigned to the next listing |
| `activeListingsByPDN(pdnTokenId)` | Number of active listings associated with a PDN domain |
| `activeListingByAsset(...)` | ID of the active listing for the specified asset combination |
| `participantTier(pdnTokenId)` | Tier of the PDN domain |
| `listingLimit(pdnTokenId)` | Listing limit for the PDN domain |
| `protocolRevenue` | Recorded protocol fee revenue |
| `reservedProtocolRevenue` | Reserved portion of the recorded protocol fee revenue |
| `availableProtocolRevenue()` | `protocolRevenue - reservedProtocolRevenue` |
| `FEE_BPS` | Fee value in basis points |
| `BPS_DENOMINATOR` | Denominator used for fee calculation |

`activeListingByAsset` uses different keys for the two standards:

- ERC-721: NFT contract, `tokenId`, ERC-721 standard, and the zero address as the final key.
- ERC-1155: NFT contract, `tokenId`, ERC-1155 standard, and the seller's address as the final key.

These indexes are intended to locate active listings. Listing records and history can be read by `listingId` through `getListing`.

## 11. Events

The contract emits events that an interface or indexer can use to track operations:

| Event | When it is emitted |
|---|---|
| `NFTDeposited` | An NFT is successfully placed in escrow and a listing is created |
| `ListingCancelled` | An active listing is cancelled and the NFT is returned to the seller |
| `NFTSold` | A purchase is completed and the NFT is transferred to the buyer |

The deposit and sale events include the listing ID, NFT contract, `tokenId`, participant addresses, PDN ID, quantity, price, and other operation parameters. These events make it possible to build an activity history without continuously polling every listing in the contract.

## 12. Security and Error Handling

The user-facing listing, cancellation, and purchase operations use `nonReentrant`. This prevents a protected function from being entered again while it is already executing.

The contract also:

- verifies actual ownership and the presence of NFTs in escrow;
- uses safe ERC-721 and ERC-1155 transfers;
- validates callback parameters when NFTs are received;
- rejects ERC-1155 batch transfers;
- rejects direct receipt of native currency through `receive` and `fallback`;
- reverts an operation if a payment or NFT transfer fails.

Sending native currency directly to the contract address is not a deposit or purchase method. Purchases must be made through `buy(listingId)` with the exact required payment.

## 13. Essential User Rules

1. To create a listing, the seller must own both the selected PDN domain and the NFT being listed.
2. The seller must grant the contract transfer approval before listing.
3. The PDN tier determines the maximum number of simultaneously active listings for that specific PDN domain.
4. While a listing is active, the NFT is held in the contract's escrow.
5. A buyer only needs to own at least one PDN domain to purchase.
6. A buyer cannot purchase their own listing.
7. The PDN domain linked to a listing must still belong to the seller when the purchase takes place.
8. The buyer pays the listing price plus the 2% fee.
9. The listing price is sent to the `payoutAddress` specified by the seller.
10. An ERC-1155 listing is sold in full, in the quantity specified when it was created.
11. A seller can cancel only their own active listing.
12. After a purchase or cancellation, the NFT leaves escrow and the active listing slot is released.

---

**This document describes the user-facing logic implemented in the `NFTMagazine` source code.** Internal administrative procedures and protocol fund management are outside its scope.
