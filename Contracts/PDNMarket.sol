// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPDNCore {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function displayNameOf(uint256 tokenId) external view returns (string memory);
    function canonicalNameOf(uint256 tokenId) external view returns (string memory);
    function getApproved(uint256 tokenId) external view returns (address);
    function keyNFT() external view returns (address);
}

interface IKeyNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract PDNMarket {
    uint256 public constant KEY_ONE = 1;
    uint256 public constant KEY_TWO = 2;
    uint256 public constant FEE_BPS = 200;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant WITHDRAW_EXPIRY_BLOCKS = 28_800;

    address public immutable pdnCore;
    address public immutable keyNFT;

    uint256 public nextListingId = 1;
    uint256 public nextWithdrawRequestId = 1;
    uint256 public protocolRevenue;
    uint256 public reservedProtocolRevenue;

    bool private entered;
    uint256 private pendingTokenId;
    address private pendingDepositor;

    enum ListingStatus {
        NONE,
        ACTIVE,
        SOLD,
        CANCELLED
    }

    struct Listing {
        uint256 tokenId;
        address originalDepositor;
        address payoutAddress;
        uint256 price;
        ListingStatus status;
        string displayName;
        string canonicalName;
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
    mapping(uint256 => uint256) public activeListingByToken;
    mapping(uint256 => WithdrawRequest) public withdrawRequests;

    error ZeroAddress();
    error InvalidValue();
    error InvalidPrice();
    error InvalidListing();
    error NotDepositor();
    error NotActive();
    error NotOwner();
    error NFTNotHeld();
    error NFTNotApprovedForDeposit();
    error InvalidNFTTransfer();
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

    event NFTDeposited(uint256 indexed listingId, uint256 indexed tokenId, address indexed depositor, address payoutAddress, uint256 price, string domainName);
    event ListingCancelled(uint256 indexed listingId, uint256 indexed tokenId, address indexed depositor);
    event NFTSold(uint256 indexed listingId, uint256 indexed tokenId, address indexed buyer, address seller, address payoutAddress, uint256 price, uint256 protocolFee);
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
        address keyNFTAddress = IPDNCore(pdnCoreAddress).keyNFT();
        if (keyNFTAddress == address(0) || keyNFTAddress.code.length == 0) revert ZeroAddress();
        pdnCore = pdnCoreAddress;
        keyNFT = keyNFTAddress;
    }

    function depositNFT(uint256 tokenId, uint256 price, address payoutAddress) external nonReentrant returns (uint256 listingId) {
        if (price == 0) revert InvalidPrice();
        if (payoutAddress == address(0)) revert ZeroAddress();
        if (IPDNCore(pdnCore).ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (IPDNCore(pdnCore).getApproved(tokenId) != address(this)) revert NFTNotApprovedForDeposit();
        if (activeListingByToken[tokenId] != 0) revert InvalidListing();

        listingId = nextListingId++;
        pendingTokenId = tokenId;
        pendingDepositor = msg.sender;

        IPDNCore(pdnCore).safeTransferFrom(msg.sender, address(this), tokenId);

        if (IPDNCore(pdnCore).ownerOf(tokenId) != address(this)) revert NFTNotHeld();

        string memory displayName = IPDNCore(pdnCore).displayNameOf(tokenId);
        string memory canonicalName = IPDNCore(pdnCore).canonicalNameOf(tokenId);

        listings[listingId] = Listing({
            tokenId: tokenId,
            originalDepositor: msg.sender,
            payoutAddress: payoutAddress,
            price: price,
            status: ListingStatus.ACTIVE,
            displayName: displayName,
            canonicalName: canonicalName
        });

        activeListingByToken[tokenId] = listingId;
        pendingTokenId = 0;
        pendingDepositor = address(0);

        emit NFTDeposited(listingId, tokenId, msg.sender, payoutAddress, price, displayName);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata) external view returns (bytes4) {
        if (
            msg.sender != pdnCore ||
            operator != address(this) ||
            from == address(0) ||
            from != pendingDepositor ||
            tokenId != pendingTokenId ||
            pendingTokenId == 0
        ) revert InvalidNFTTransfer();
        return this.onERC721Received.selector;
    }

    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.status == ListingStatus.NONE) revert InvalidListing();
        if (listing.originalDepositor != msg.sender) revert NotDepositor();
        if (listing.status != ListingStatus.ACTIVE) revert NotActive();
        if (IPDNCore(pdnCore).ownerOf(listing.tokenId) != address(this)) revert NFTNotHeld();

        listing.status = ListingStatus.CANCELLED;
        delete activeListingByToken[listing.tokenId];

        IPDNCore(pdnCore).transferFrom(address(this), listing.originalDepositor, listing.tokenId);

        emit ListingCancelled(listingId, listing.tokenId, listing.originalDepositor);
    }

    function buy(uint256 listingId) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.status == ListingStatus.NONE) revert InvalidListing();
        if (listing.status != ListingStatus.ACTIVE) revert NotActive();
        if (msg.sender == listing.originalDepositor) revert NotOwner();
        if (IPDNCore(pdnCore).ownerOf(listing.tokenId) != address(this)) revert NFTNotHeld();

        uint256 fee = listing.price * FEE_BPS / BPS_DENOMINATOR;
        uint256 total = listing.price + fee;
        if (msg.value != total) revert InvalidValue();

        address seller = listing.originalDepositor;
        address payout = listing.payoutAddress;
        address buyer = msg.sender;
        uint256 tokenId = listing.tokenId;
        uint256 price = listing.price;

        listing.status = ListingStatus.SOLD;
        delete activeListingByToken[tokenId];

        protocolRevenue += fee;

        (bool paidSeller, ) = payable(payout).call{value: price}("");
        if (!paidSeller) revert TransferFailed();

        IPDNCore(pdnCore).safeTransferFrom(address(this), buyer, tokenId);

        emit NFTSold(listingId, tokenId, buyer, seller, payout, price, fee);
    }

    function requestWithdraw(uint256 keyId, address recipient, uint256 amount) external {
        if (keyId != KEY_ONE && keyId != KEY_TWO) revert WrongKey();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidValue();

        address keyOneOwner = IKeyNFT(keyNFT).ownerOf(KEY_ONE);
        address keyTwoOwner = IKeyNFT(keyNFT).ownerOf(KEY_TWO);
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

        address keyOneOwner = IKeyNFT(keyNFT).ownerOf(KEY_ONE);
        address keyTwoOwner = IKeyNFT(keyNFT).ownerOf(KEY_TWO);
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

        address keyOneOwner = IKeyNFT(keyNFT).ownerOf(KEY_ONE);
        address keyTwoOwner = IKeyNFT(keyNFT).ownerOf(KEY_TWO);
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

        address keyOneOwner = IKeyNFT(keyNFT).ownerOf(KEY_ONE);
        address keyTwoOwner = IKeyNFT(keyNFT).ownerOf(KEY_TWO);
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
