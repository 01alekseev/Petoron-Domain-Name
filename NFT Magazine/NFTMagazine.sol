// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/*
Copyright (c) Ivan Alekseev

Licensed under the PetoronAI Community License (PCL)
or a valid PetoronAI Commercial License.
*/

interface IPDNMagazineCore {
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function canonicalNameOf(uint256 tokenId) external view returns (string memory);
    function isVerified(uint256 tokenId) external view returns (bool);
    function keyNFT() external view returns (address);
}

interface IPDNMagazineKeyNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC165Magazine {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721Magazine is IERC165Magazine {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC1155Magazine is IERC165Magazine {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

contract NFTMagazine {
    uint256 public constant KEY_ONE = 1;
    uint256 public constant KEY_TWO = 2;
    uint256 public constant FEE_BPS = 200;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant WITHDRAW_EXPIRY_BLOCKS = 28_800;

    uint256 public constant USER_LIMIT = 7;
    uint256 public constant PRIME_LIMIT = 14;
    uint256 public constant EXCLUSIVE_LIMIT = 21;

    address public immutable pdnCore;
    address public immutable keyNFT;

    uint256 public nextListingId = 1;
    uint256 public nextWithdrawRequestId = 1;
    uint256 public protocolRevenue;
    uint256 public reservedProtocolRevenue;

    bool private entered;

    enum NFTStandard {
        NONE,
        ERC721,
        ERC1155
    }

    enum ListingStatus {
        NONE,
        ACTIVE,
        SOLD,
        CANCELLED
    }

    enum ParticipantTier {
        NONE,
        USER,
        PRIME,
        EXCLUSIVE
    }

    struct Listing {
        address nftContract;
        uint256 tokenId;
        uint256 amount;
        address seller;
        address payoutAddress;
        uint256 pdnTokenId;
        uint256 price;
        NFTStandard standard;
        ListingStatus status;
    }

    struct WithdrawRequest {
        uint256 amount;
        uint256 createdAtBlock;
        uint256 keyId;
        address requester;
        address recipient;
        address approver;
        bool approved;
        bool cancelled;
        bool executed;
    }

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => uint256) public activeListingsByPDN;
    mapping(address => mapping(uint256 => mapping(NFTStandard => mapping(address => uint256)))) public activeListingByAsset;
    mapping(uint256 => WithdrawRequest) public withdrawRequests;

    uint256 private pendingTokenId;
    uint256 private pendingAmount;
    address private pendingNFT;
    address private pendingDepositor;
    NFTStandard private pendingStandard;

    error ZeroAddress();
    error InvalidValue();
    error InvalidPrice();
    error InvalidListing();
    error NotDepositor();
    error NotActive();
    error NotOwner();
    error NFTNotHeld();
    error NFTNotApproved();
    error InvalidNFTTransfer();
    error UnsupportedNFT();
    error PDNNFTNotAllowed();
    error PDNRequired();
    error DomainOwnershipChanged();
    error ListingLimitReached();
    error Reentrancy();
    error TransferFailed();
    error RequestNotFound();
    error RequestAlreadyApproved();
    error RequestAlreadyCancelled();
    error RequestAlreadyExecuted();
    error RequestNotApproved();
    error RequestNotExpired();
    error RequestExpired();
    error WrongKey();
    error WrongApproverKey();
    error SameKeyHolder();
    error RevenueInsufficient();
    error OnlyDistinctKeyHolders();
    error AmountExceedsAvailableRevenue();

    event NFTDeposited(uint256 indexed listingId, address indexed nftContract, uint256 indexed tokenId, address seller, uint256 pdnTokenId, uint256 amount, uint256 price, NFTStandard standard);
    event ListingCancelled(uint256 indexed listingId, address indexed seller);
    event NFTSold(uint256 indexed listingId, address indexed nftContract, uint256 indexed tokenId, address buyer, address seller, uint256 pdnTokenId, uint256 amount, uint256 price, uint256 protocolFee);
    event WithdrawRequested(uint256 indexed requestId, uint256 indexed keyId, address indexed requester, address recipient, uint256 amount);
    event WithdrawApproved(uint256 indexed requestId, address indexed approver);
    event WithdrawCancelled(uint256 indexed requestId);
    event WithdrawExpired(uint256 indexed requestId);
    event WithdrawExecuted(uint256 indexed requestId, address indexed recipient, uint256 amount);

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    constructor(address pdnCoreAddress) {
        if (pdnCoreAddress == address(0) || pdnCoreAddress.code.length == 0) revert ZeroAddress();
        address keyNFTAddress = IPDNMagazineCore(pdnCoreAddress).keyNFT();
        if (keyNFTAddress == address(0) || keyNFTAddress.code.length == 0) revert ZeroAddress();
        pdnCore = pdnCoreAddress;
        keyNFT = keyNFTAddress;
    }

    function participantTier(uint256 pdnTokenId) public view returns (ParticipantTier) {
        address domainOwner = IPDNMagazineCore(pdnCore).ownerOf(pdnTokenId);
        if (domainOwner == address(0)) return ParticipantTier.NONE;
        if (IPDNMagazineCore(pdnCore).isVerified(pdnTokenId)) return ParticipantTier.EXCLUSIVE;
        uint256 nameLength = bytes(IPDNMagazineCore(pdnCore).canonicalNameOf(pdnTokenId)).length;
        if (nameLength == 0 || nameLength > 21) return ParticipantTier.NONE;
        if (nameLength <= 11) return ParticipantTier.PRIME;
        return ParticipantTier.USER;
    }

    function listingLimit(uint256 pdnTokenId) public view returns (uint256) {
        ParticipantTier tier = participantTier(pdnTokenId);
        if (tier == ParticipantTier.EXCLUSIVE) return EXCLUSIVE_LIMIT;
        if (tier == ParticipantTier.PRIME) return PRIME_LIMIT;
        if (tier == ParticipantTier.USER) return USER_LIMIT;
        return 0;
    }

    function depositERC721(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        address payoutAddress,
        uint256 pdnTokenId
    ) external nonReentrant returns (uint256 listingId) {
        if (nftContract == pdnCore) revert PDNNFTNotAllowed();
        if (nftContract == address(0) || nftContract.code.length == 0) revert UnsupportedNFT();
        _validatePrice(price);
        if (payoutAddress == address(0)) revert ZeroAddress();
        _requireSellerPDN(msg.sender, pdnTokenId);
        if (!IERC165Magazine(nftContract).supportsInterface(0x80ac58cd)) revert UnsupportedNFT();
        if (IERC721Magazine(nftContract).ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (
            IERC721Magazine(nftContract).getApproved(tokenId) != address(this) &&
            !IERC721Magazine(nftContract).isApprovedForAll(msg.sender, address(this))
        ) revert NFTNotApproved();
        if (activeListingByAsset[nftContract][tokenId][NFTStandard.ERC721][address(0)] != 0) revert InvalidListing();

        listingId = _createListing(nftContract, tokenId, 1, price, payoutAddress, pdnTokenId, NFTStandard.ERC721);

        pendingTokenId = tokenId;
        pendingAmount = 1;
        pendingNFT = nftContract;
        pendingDepositor = msg.sender;
        pendingStandard = NFTStandard.ERC721;

        IERC721Magazine(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        if (IERC721Magazine(nftContract).ownerOf(tokenId) != address(this)) revert NFTNotHeld();
        _clearPending();

        emit NFTDeposited(listingId, nftContract, tokenId, msg.sender, pdnTokenId, 1, price, NFTStandard.ERC721);
    }

    function depositERC1155(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        address payoutAddress,
        uint256 pdnTokenId
    ) external nonReentrant returns (uint256 listingId) {
        if (nftContract == pdnCore) revert PDNNFTNotAllowed();
        if (nftContract == address(0) || nftContract.code.length == 0) revert UnsupportedNFT();
        if (amount == 0) revert InvalidValue();
        _validatePrice(price);
        if (payoutAddress == address(0)) revert ZeroAddress();
        _requireSellerPDN(msg.sender, pdnTokenId);
        if (!IERC165Magazine(nftContract).supportsInterface(0xd9b67a26)) revert UnsupportedNFT();
        if (IERC1155Magazine(nftContract).balanceOf(msg.sender, tokenId) < amount) revert NotOwner();
        if (!IERC1155Magazine(nftContract).isApprovedForAll(msg.sender, address(this))) revert NFTNotApproved();

        if (activeListingByAsset[nftContract][tokenId][NFTStandard.ERC1155][msg.sender] != 0) revert InvalidListing();

        listingId = _createListing(nftContract, tokenId, amount, price, payoutAddress, pdnTokenId, NFTStandard.ERC1155);

        pendingTokenId = tokenId;
        pendingAmount = amount;
        pendingNFT = nftContract;
        pendingDepositor = msg.sender;
        pendingStandard = NFTStandard.ERC1155;

        uint256 escrowBalanceBefore = IERC1155Magazine(nftContract).balanceOf(address(this), tokenId);
        IERC1155Magazine(nftContract).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        uint256 escrowBalanceAfter = IERC1155Magazine(nftContract).balanceOf(address(this), tokenId);
        if (escrowBalanceAfter < escrowBalanceBefore || escrowBalanceAfter - escrowBalanceBefore != amount) revert NFTNotHeld();
        _clearPending();

        emit NFTDeposited(listingId, nftContract, tokenId, msg.sender, pdnTokenId, amount, price, NFTStandard.ERC1155);
    }

    function _createListing(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        address payoutAddress,
        uint256 pdnTokenId,
        NFTStandard standard
    ) private returns (uint256 listingId) {
        uint256 limit = listingLimit(pdnTokenId);
        if (limit == 0 || activeListingsByPDN[pdnTokenId] >= limit) revert ListingLimitReached();

        listingId = nextListingId++;
        listings[listingId] = Listing({
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            seller: msg.sender,
            payoutAddress: payoutAddress,
            pdnTokenId: pdnTokenId,
            price: price,
            standard: standard,
            status: ListingStatus.ACTIVE
        });

        activeListingByAsset[nftContract][tokenId][standard][standard == NFTStandard.ERC1155 ? msg.sender : address(0)] = listingId;
        activeListingsByPDN[pdnTokenId] += 1;
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata) external view returns (bytes4) {
        if (
            msg.sender != pendingNFT ||
            pendingStandard != NFTStandard.ERC721 ||
            operator != address(this) ||
            from != pendingDepositor ||
            tokenId != pendingTokenId ||
            pendingAmount != 1
        ) revert InvalidNFTTransfer();
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address operator, address from, uint256 tokenId, uint256 amount, bytes calldata) external view returns (bytes4) {
        if (
            msg.sender != pendingNFT ||
            pendingStandard != NFTStandard.ERC1155 ||
            operator != address(this) ||
            from != pendingDepositor ||
            tokenId != pendingTokenId ||
            amount != pendingAmount
        ) revert InvalidNFTTransfer();
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        revert InvalidNFTTransfer();
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 ||
            interfaceId == 0x150b7a02 ||
            interfaceId == 0x4e2312e0;
    }

    function _clearPending() private {
        pendingTokenId = 0;
        pendingAmount = 0;
        pendingNFT = address(0);
        pendingDepositor = address(0);
        pendingStandard = NFTStandard.NONE;
    }

    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.status == ListingStatus.NONE) revert InvalidListing();
        if (listing.seller != msg.sender) revert NotDepositor();
        if (listing.status != ListingStatus.ACTIVE) revert NotActive();

        _requireHeld(listing);
        listing.status = ListingStatus.CANCELLED;
        activeListingsByPDN[listing.pdnTokenId] -= 1;
        delete activeListingByAsset[listing.nftContract][listing.tokenId][listing.standard][
            listing.standard == NFTStandard.ERC1155 ? listing.seller : address(0)
        ];

        _transferNFT(listing, listing.seller);

        emit ListingCancelled(listingId, listing.seller);
    }

    function buy(uint256 listingId) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.status == ListingStatus.NONE) revert InvalidListing();
        if (listing.status != ListingStatus.ACTIVE) revert NotActive();
        if (msg.sender == listing.seller) revert NotOwner();
        if (IPDNMagazineCore(pdnCore).balanceOf(msg.sender) == 0) revert PDNRequired();
        if (IPDNMagazineCore(pdnCore).ownerOf(listing.pdnTokenId) != listing.seller) revert DomainOwnershipChanged();
        _requireHeld(listing);

        uint256 fee = listing.price / (BPS_DENOMINATOR / FEE_BPS);
        uint256 total = listing.price + fee;
        if (msg.value != total) revert InvalidValue();

        address seller = listing.seller;
        address payout = listing.payoutAddress;
        address nftContract = listing.nftContract;
        uint256 tokenId = listing.tokenId;
        uint256 amount = listing.amount;
        uint256 price = listing.price;
        NFTStandard standard = listing.standard;

        listing.status = ListingStatus.SOLD;
        activeListingsByPDN[listing.pdnTokenId] -= 1;
        delete activeListingByAsset[nftContract][tokenId][standard][
            standard == NFTStandard.ERC1155 ? seller : address(0)
        ];

        protocolRevenue += fee;

        (bool paidSeller, ) = payable(payout).call{value: price}("");
        if (!paidSeller) revert TransferFailed();

        _transferNFT(listing, msg.sender);

        emit NFTSold(listingId, nftContract, tokenId, msg.sender, seller, listing.pdnTokenId, amount, price, fee);
    }

    function _requireHeld(Listing storage listing) private view {
        if (listing.standard == NFTStandard.ERC721) {
            if (IERC721Magazine(listing.nftContract).ownerOf(listing.tokenId) != address(this)) revert NFTNotHeld();
        } else if (listing.standard == NFTStandard.ERC1155) {
            if (IERC1155Magazine(listing.nftContract).balanceOf(address(this), listing.tokenId) < listing.amount) revert NFTNotHeld();
        } else {
            revert UnsupportedNFT();
        }
    }

    function _transferNFT(Listing storage listing, address recipient) private {
        if (listing.standard == NFTStandard.ERC721) {
            IERC721Magazine(listing.nftContract).safeTransferFrom(address(this), recipient, listing.tokenId);
        } else if (listing.standard == NFTStandard.ERC1155) {
            IERC1155Magazine(listing.nftContract).safeTransferFrom(address(this), recipient, listing.tokenId, listing.amount, "");
        } else {
            revert UnsupportedNFT();
        }
    }

    function _validatePrice(uint256 price) private pure {
        if (price == 0 || price > type(uint256).max - price / (BPS_DENOMINATOR / FEE_BPS)) revert InvalidPrice();
    }

    function _requireSellerPDN(address seller, uint256 pdnTokenId) private view {
        if (IPDNMagazineCore(pdnCore).ownerOf(pdnTokenId) != seller) revert NotOwner();
    }

    function requestWithdraw(uint256 keyId, address recipient, uint256 amount) external {
        if (keyId != KEY_ONE && keyId != KEY_TWO) revert WrongKey();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidValue();

        address keyOneOwner = IPDNMagazineKeyNFT(keyNFT).ownerOf(KEY_ONE);
        address keyTwoOwner = IPDNMagazineKeyNFT(keyNFT).ownerOf(KEY_TWO);
        if (keyOneOwner == keyTwoOwner) revert SameKeyHolder();

        address requiredOwner = keyId == KEY_ONE ? keyOneOwner : keyTwoOwner;
        if (msg.sender != requiredOwner) revert OnlyDistinctKeyHolders();
        if (protocolRevenue - reservedProtocolRevenue < amount) revert RevenueInsufficient();

        uint256 requestId = nextWithdrawRequestId++;
        withdrawRequests[requestId] = WithdrawRequest({
            amount: amount,
            createdAtBlock: block.number,
            keyId: keyId,
            requester: msg.sender,
            recipient: recipient,
            approver: address(0),
            approved: false,
            cancelled: false,
            executed: false
        });

        reservedProtocolRevenue += amount;
        emit WithdrawRequested(requestId, keyId, msg.sender, recipient, amount);
    }

    function approveWithdraw(uint256 requestId) external {
        WithdrawRequest storage request = withdrawRequests[requestId];
        if (request.createdAtBlock == 0) revert RequestNotFound();
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (request.approved) revert RequestAlreadyApproved();
        if (block.number > request.createdAtBlock + WITHDRAW_EXPIRY_BLOCKS) revert RequestExpired();

        address keyOneOwner = IPDNMagazineKeyNFT(keyNFT).ownerOf(KEY_ONE);
        address keyTwoOwner = IPDNMagazineKeyNFT(keyNFT).ownerOf(KEY_TWO);
        if (keyOneOwner == keyTwoOwner) revert SameKeyHolder();

        address approver = request.keyId == KEY_ONE ? keyTwoOwner : keyOneOwner;
        if (msg.sender != approver) revert WrongApproverKey();
        if (msg.sender == request.requester) revert OnlyDistinctKeyHolders();

        address requesterKeyOwner = request.keyId == KEY_ONE ? keyOneOwner : keyTwoOwner;
        if (request.requester != requesterKeyOwner) revert OnlyDistinctKeyHolders();

        request.approver = msg.sender;
        request.approved = true;
        emit WithdrawApproved(requestId, msg.sender);
    }

    function executeWithdraw(uint256 requestId) external nonReentrant {
        WithdrawRequest storage request = withdrawRequests[requestId];
        if (request.createdAtBlock == 0) revert RequestNotFound();
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (!request.approved) revert RequestNotApproved();
        if (block.number > request.createdAtBlock + WITHDRAW_EXPIRY_BLOCKS) revert RequestExpired();

        address keyOneOwner = IPDNMagazineKeyNFT(keyNFT).ownerOf(KEY_ONE);
        address keyTwoOwner = IPDNMagazineKeyNFT(keyNFT).ownerOf(KEY_TWO);
        if (keyOneOwner == keyTwoOwner) revert SameKeyHolder();

        address requesterKeyOwner = request.keyId == KEY_ONE ? keyOneOwner : keyTwoOwner;
        address approverKeyOwner = request.keyId == KEY_ONE ? keyTwoOwner : keyOneOwner;
        if (request.requester != requesterKeyOwner) revert OnlyDistinctKeyHolders();
        if (request.approver != approverKeyOwner) revert WrongApproverKey();
        if (request.requester == approverKeyOwner) revert SameKeyHolder();
        if (request.amount > protocolRevenue) revert AmountExceedsAvailableRevenue();

        request.executed = true;
        reservedProtocolRevenue -= request.amount;
        protocolRevenue -= request.amount;

        (bool success, ) = payable(request.recipient).call{value: request.amount}("");
        if (!success) revert TransferFailed();

        emit WithdrawExecuted(requestId, request.recipient, request.amount);
    }

    function cancelWithdraw(uint256 requestId) external {
        WithdrawRequest storage request = withdrawRequests[requestId];
        if (request.createdAtBlock == 0) revert RequestNotFound();
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();

        address keyOneOwner = IPDNMagazineKeyNFT(keyNFT).ownerOf(KEY_ONE);
        address keyTwoOwner = IPDNMagazineKeyNFT(keyNFT).ownerOf(KEY_TWO);
        if (
            msg.sender != request.requester &&
            msg.sender != keyOneOwner &&
            msg.sender != keyTwoOwner
        ) revert OnlyDistinctKeyHolders();

        request.cancelled = true;
        reservedProtocolRevenue -= request.amount;
        emit WithdrawCancelled(requestId);
    }

    function expireWithdraw(uint256 requestId) external {
        WithdrawRequest storage request = withdrawRequests[requestId];
        if (request.createdAtBlock == 0) revert RequestNotFound();
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (block.number <= request.createdAtBlock + WITHDRAW_EXPIRY_BLOCKS) revert RequestNotExpired();

        request.cancelled = true;
        reservedProtocolRevenue -= request.amount;
        emit WithdrawExpired(requestId);
    }

    function availableProtocolRevenue() external view returns (uint256) {
        return protocolRevenue - reservedProtocolRevenue;
    }

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    receive() external payable {
        revert InvalidValue();
    }

    fallback() external payable {
        revert InvalidValue();
    }
}
