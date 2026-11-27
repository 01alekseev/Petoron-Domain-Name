# NFT Magazine

**A PDN-powered marketplace for ERC-721 and ERC-1155 NFTs.**

NFT Magazine lets eligible PDN domain owners list NFTs for sale and lets other PDN domain owners purchase them. Listed NFTs are held by the smart contract until they are sold or the seller cancels the listing.

## Contract

**Ethereum Mainnet**

`0xD51D05902Cc17D2609fD30c0c64fc8CEb50BCEFD`

[View contract on Etherscan](https://etherscan.io/address/0xD51D05902Cc17D2609fD30c0c64fc8CEb50BCEFD)

## What makes NFT Magazine different?

- **PDN-based access:** A seller must own the PDN domain used for their listing. A buyer only needs to own at least one PDN domain.
- **Tier-based listing limits:** The number of active listings depends on the seller's PDN domain tier.
- **NFT escrow:** When an NFT is listed, it moves into the contract. It is transferred to the buyer after a successful purchase, or returned to the seller if the listing is cancelled.
- **Two NFT standards:** Both ERC-721 and ERC-1155 are supported.
- **Automatic 2% fee:** The buyer pays the listing price plus a 2% protocol fee. The full listing price goes to the payout address selected by the seller.
- **Domain ownership check at purchase:** The seller must still own the PDN domain linked to the listing when someone buys it.

## PDN tiers and listing limits

Each listing is linked to one PDN domain. Its tier determines how many active listings can be created using that domain.

| PDN domain tier | Eligibility | Maximum active listings |
|---|---|---:|
| **USER** | Unverified canonical name with 12–21 bytes | 7 |
| **PRIME** | Unverified canonical name with 1–11 bytes | 14 |
| **EXCLUSIVE** | Verified PDN domain | 21 |

A verified domain receives the **EXCLUSIVE** tier regardless of its name length. The contract measures the canonical name in bytes; for standard English letters and numbers, one character corresponds to one byte.

The limit applies separately to each PDN domain. Only active listings count. A completed sale or cancellation frees a listing slot.

## How it works

### 1. List an NFT

The seller chooses an ERC-721 or ERC-1155 NFT, sets the price, selects the PDN domain that qualifies the listing, and specifies the address that should receive the sale proceeds.

Before listing, the seller must authorize the contract to transfer the NFT. The contract checks ownership, approval, PDN domain eligibility, the tier limit, and whether the asset already has an active listing.

Once the listing is created, the NFT is transferred into the contract's escrow.

### 2. A buyer purchases it

A buyer who owns at least one PDN domain can purchase an active listing.

The contract checks that the seller still owns the PDN domain linked to the listing, then verifies the exact payment. After a successful purchase, the NFT is transferred from escrow to the buyer and the sale proceeds are sent to the seller's selected payout address.

### 3. Or the seller cancels it

The seller can cancel their own active listing at any time. The NFT is returned from escrow to the seller, and the listing slot becomes available again.

## Simple examples

### Example A - Listing limit

A seller owns an unverified PDN domain with the canonical name `petoron`.

- The name is 7 bytes long.
- The domain receives the **PRIME** tier.
- The seller can have up to **14 active listings** linked to that domain.

If the seller completes a sale or cancels one of the listings, that slot is freed.

### Example B - Buying an NFT

An NFT is listed for **1 ETH**.

- Listing price: 1 ETH
- Protocol fee: 0.02 ETH
- Buyer pays: **1.02 ETH**
- Seller's payout address receives: **1 ETH**
- Protocol fee: **0.02 ETH**

The buyer must send the exact total amount. The contract does not accept an underpayment or overpayment.

### Example C - ERC-1155 listing

A seller lists 100 units of an ERC-1155 token.

The listing is sold as one complete lot: the buyer receives all 100 units. Buying only part of the listed quantity is not supported.

## Important rules

- The seller must own the NFT and the PDN domain linked to the listing.
- The buyer must own at least one PDN domain.
- Buyers cannot purchase their own listings.
- The seller must still own the linked PDN domain at the moment of purchase.
- The NFT stays in contract escrow while the listing is active.
- ERC-1155 listings are sold in full, not partially.
- The seller can cancel only their own active listing.
- The sale price is sent to the payout address chosen by the seller. This address can be different from the seller's wallet.
- The protocol fee is 2% of the listing price. The contract rounds the fee down to the nearest smallest unit of the network currency.

## Commercial use and building on NFT Magazine

NFT Magazine is free to use for commercial purposes through its official smart contract deployed on Ethereum Mainnet.

Developers and businesses may build products and services on top of the official deployment, including interfaces, integrations, analytics, APIs, wallets, and other applications that interact with the contract. These products may be operated commercially and generate revenue. No separate PCL-C license, Petoron permission, or royalty is required solely for integrating with and building around the official deployed contract.

This permission does not grant the right to copy, modify, fork, redistribute, or independently redeploy the protected NFT Magazine implementation as a competing version or marketplace. The source code and its derivative versions remain subject to the applicable PetoronAI Community License (PCL) or PetoronAI Commercial License (PCL-C).

**In short: build, integrate, and commercialize your own products and services on top of the official NFT Magazine and other deployed PDN contracts on Ethereum Mainnet. You are free to develop independent applications and integrations, while copying, modifying, or redistributing the protected source code and its derivative versions remains subject to the PetoronAI - PCL or PCL-C license terms.**

## Supported assets

- **ERC-721:** one NFT per listing.
- **ERC-1155:** a specified quantity of one token ID per listing; the full quantity is sold together.

The PDN Core domain NFTs themselves cannot be listed in NFT Magazine.

---

**NFT Magazine — NFT trading with PDN-based participation, transparent listing limits, escrow, and automatic settlement.**

---

Petoron | Ivan Alekseev 