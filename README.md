# Petoron Domain Name (PDN)

**PDN turns a domain name into an ERC-721 NFT on Ethereum.**  
Each registered name is linked to a permanent `tokenId`. When the NFT is transferred, ownership changes while the domain name and `tokenId` remain the same.

## Features

- Receive ETH using a domain name instead of a wallet address.
- Transfer your domain NFT to any Ethereum address.
- Use your domain as a digital identifier.
- Build websites, applications, services, and infrastructure around your domain.
- List your domain for sale on the native PDN Market.
- Buy domains and transfer them to other owners.
- Use your domain in custom identity, coordination, voting, and access-control systems when the relevant integration is implemented.

PDN provides NFT ownership and its core on-chain operations. Voting, access control, and other application-level use cases are not built-in contract features; they require separate integrations.

## Ethereum Mainnet Contracts

| Contract | Address |
|---|---|
| PDN Core | [`0x238B9b6De2A247178307d504e9B8DE5A98be4864`](https://etherscan.io/address/0x238B9b6De2A247178307d504e9B8DE5A98be4864) |
| PDN Market | [`0x458293FfE82f370e43b1A49F5eb09d0a01B215eB`](https://etherscan.io/address/0x458293FfE82f370e43b1A49F5eb09d0a01B215eB) |

Network: Ethereum Mainnet
Chain ID: 1

## Run the local interface

```bash
cd ~/Downloads/Petoron-Domain-Name/PDN-Wallet
./start.sh
```

Open in your browser:

[http://127.0.0.1:8788](http://127.0.0.1:8788)

## Domain registration

The contract validates the name, checks its uniqueness, and requires the exact registration payment. Sending more or less than the required amount causes the transaction to revert.

The price is determined by the **length of the canonical name**, not the original input string.

| Canonical name length | Price |
|---|---:|
| 1 character | 10 ETH |
| 2 characters | 5 ETH |
| 3 characters | 3 ETH |
| 4–7 characters | 2 ETH |
| 8–11 characters | 1 ETH |
| 12–21 characters | Free |

### Canonicalization rules

The following characters are supported:
- Latin letters `a-z` (case-insensitive);
- digits `0-9`;
- single separators: space (` `), hyphen (`-`), period (`.`), underscore (`_`).

Separators are removed when the canonical name is created. They cannot appear at the beginning or end of a name, and cannot be repeated consecutively. Maximum input length: **21 bytes**. Cyrillic and other non-ASCII characters are not allowed.

**Cannot register both — these inputs produce the same canonical name:**

| First input | Second input | Canonical name |
|---|---|---|
| `CRYPTOGRAPHY` | `cryptography` | `cryptography` |
| `Crypto-graphy` | `crypto.graphy` | `cryptography` |
| `COIN` | `c-o-i-n` | `coin` |

Only one NFT can exist for each canonical name.

**Can register both — these inputs produce different canonical names:**

| First domain | Second domain | Canonical names |
|---|---|---|
| `Coin` | `Coin1` | `coin` / `coin1` |
| `Crypto` | `Crypt0` | `crypto` / `crypt0` |
| `Coin` | `C0in` | `coin` / `c0in` |

The contract converts uppercase Latin letters to lowercase and removes supported separators. It does not remove digits, replace characters, or detect visually similar names. For example, the letter `o` and the digit `0` are different characters.

Example: `my-domain` becomes `mydomain` (8 characters), so its registration price is **1 ETH**.

## Receive ETH using a domain name

The sender calls the `sendETH` function with a domain name and an ETH amount. When the transaction executes, the contract resolves the NFT's current owner and sends the **full amount** to that address.

If the domain has been transferred, future payments are sent to its new owner. `sendETH` does not deduct a separate protocol fee.

## Transfer a domain

The owner can transfer the NFT to any Ethereum address using a standard ERC-721 transfer. The domain name and `tokenId` remain unchanged; only ownership changes.

After the transfer, the new owner controls the actions supported by the contract and receives future ETH payments addressed to that domain.

## PDN Market

PDN Market allows users to list domains for sale and purchase listed domains.

**Selling a domain:**
1. The owner approves the native PDN Market to move that specific NFT.
2. The owner creates a listing by specifying the `tokenId`, asking price, and payout address.
3. While the listing is active, the NFT is held by the Market contract.
4. Only the original depositor can cancel the listing. When cancelled, the NFT is returned to that depositor.

Only one active listing can exist for a token at a time.

**Buying a domain:**
- The buyer pays the seller's asking price **plus a 2% Market fee**.
- The seller receives 100% of the asking price at the payout address saved in the listing.
- The buyer receives the NFT.
- A seller cannot purchase their own listing.
- The transaction must include the exact total payment.

Example: the domain is listed for **7 ETH**. The buyer's fee is **0.14 ETH**. The buyer pays **7.14 ETH**, the seller receives **7 ETH**, and **0.14 ETH** is accounted for as protocol revenue. The fee is not deducted from the seller's asking price.

## NFT approval security

PDN Core disables blanket `setApprovalForAll` delegation. Individual `approve` is permitted only for the configured native PDN Market address or for revoking approval by setting the address to zero. This restricts the use of the standard approval mechanism to delegate NFTs to third-party marketplaces.

When a domain is listed on PDN Market, the NFT is transferred to and held by the Market contract until the listing is purchased or cancelled.

## Domain verification

A domain has an on-chain True `verified` / False `unverified` status.

The status is displayed when the domain is viewed. The on-chain status flag does not, by itself, verify a person's identity, company registration, trademark rights, or other off-chain documents. If a domain belongs to a public figure, brand, organization, or government, an authenticity review should include a separate examination of supporting evidence outside the blockchain; the result can then be reflected on-chain through the protocol's verification process. Verification is not sold as a paid feature.

## Ownership, expiration, and licensing

- PDN NFTs have no built-in expiration date, subscription, or mandatory renewal.
- The contracts do not include an administrative function for unilateral seizure of a user's domain.
- Ownership changes through an authorized NFT transfer or sale.
- PCL and PCL-C apply to PetoronAI software and code, not to PDN NFTs acquired by users.
- Owners may use, sell, transfer, and commercialize their NFT domains, and build products and infrastructure around them, without a separate PCL/PCL-C license for the domain itself.

Use of the software and deployment of independent instances of the smart contracts are governed by the applicable PetoronAI licensing terms. Ownership of an NFT domain does not transfer ownership of Petoron software, trademarks, or other intellectual property.

## Diagrams and documentation

For visual explanations, see:

- `PDN.png` — domain registration, receiving ETH by domain name, and NFT transfers.
- `PDNMarket.png` — listing a domain for sale and purchasing it through the Market.

Full user guide: `PDN_User_Guide.pdf`.

## Important notes

- All operations take place on Ethereum and require network gas.
- Registration requires the exact payment amount calculated by the contract.
- Verify contract addresses and payout addresses before confirming transactions.
- Interface, RPC provider, and Ethereum network availability depend on the relevant external services.

This README describes user-facing functionality implemented by the supplied versions of PDN Core and PDN Market.

---

### Verify Domain on Etherscan

[PDN Core - Read Contract](https://etherscan.io/address/0x238B9b6De2A247178307d504e9B8DE5A98be4864#readContract)

Open **Contract → Read Contract**.

- `displayNameOf` — NFT domain name.
- `canonicalNameOf` — canonical domain name.
- `isVerified` — verification status (`true` = verified).

All data is read directly from Ethereum Mainnet.

---

Petoron | Ivan Alekseev | PetoronAI Community License (PCL)
