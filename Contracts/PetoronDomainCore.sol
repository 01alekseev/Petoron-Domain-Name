// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/*
Copyright (c) Ivan Alekseev

Licensed under the PetoronAI Community License (PCL)
or a valid PetoronAI Commercial License.
*/

interface IPDNERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

interface IPDNVaultKeyNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract PetoronDomainCore {
    string public constant name = "Petoron Domain Name";
    string public constant symbol = "PDN";

    uint256 public constant MAX_NAME_LENGTH = 21;
    uint256 public constant PRICE_ONE_CHARACTER = 10 ether;
    uint256 public constant PRICE_TWO_CHARACTERS = 5 ether;
    uint256 public constant PRICE_THREE_CHARACTERS = 3 ether;
    uint256 public constant PRICE_FOUR_TO_SEVEN_CHARACTERS = 2 ether;
    uint256 public constant PRICE_EIGHT_TO_ELEVEN_CHARACTERS = 1 ether;
    uint256 public constant KEY_ONE = 1;
    uint256 public constant KEY_TWO = 2;
    uint256 public constant WITHDRAW_REQUEST_EXPIRE_BLOCKS = 28800;

    address public immutable initializer;
    address public market;
    IPDNVaultKeyNFT public keyNFT;

    uint256 public nextTokenId = 1;
    uint256 public nextWithdrawRequestId = 1;
    uint256 public nextVerificationRequestId = 1;
    uint256 public protocolRevenue;
    uint256 public reservedProtocolRevenue;
    bool private entered;

    mapping(uint256 => address) private owners;
    mapping(address => uint256) private balances;
    mapping(uint256 => address) private tokenApprovals;

    mapping(string => uint256) public tokenIdByName;
    mapping(uint256 => string) private displayNames;
    mapping(uint256 => string) private canonicalNames;

    struct WithdrawRequest {
        address requester;
        address approver;
        uint256 requesterTokenId;
        uint256 approverTokenId;
        address payable recipient;
        uint256 amount;
        uint256 createdAtBlock;
        bool approved;
        bool executed;
        bool cancelled;
    }

    mapping(uint256 => WithdrawRequest) public withdrawRequests;

    struct VerificationRequest {
        address requester;
        address approver;
        uint256 requesterTokenId;
        uint256 approverTokenId;
        uint256 domainTokenId;
        uint256 createdAtBlock;
        bool verified;
        bool executed;
        bool cancelled;
    }

    mapping(uint256 => bool) public isVerified;
    mapping(uint256 => VerificationRequest) public verificationRequests;
    mapping(uint256 => uint256) public activeVerificationRequestByDomain;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event MarketConfigured(address indexed market);
    event ProtocolFeeReceived(address indexed sender, uint256 amount);
    event WithdrawRequested(uint256 indexed requestId, address indexed requester, uint256 indexed requesterTokenId, address recipient, uint256 amount);
    event WithdrawApproved(uint256 indexed requestId, address indexed approver, uint256 indexed approverTokenId);
    event WithdrawExecuted(uint256 indexed requestId, address indexed recipient, uint256 amount);
    event WithdrawCancelled(uint256 indexed requestId);
    event WithdrawExpired(uint256 indexed requestId);
    event VerificationRequested(uint256 indexed requestId, uint256 indexed domainTokenId, bool verified, address indexed requester);
    event VerificationApproved(uint256 indexed requestId, uint256 indexed domainTokenId, bool verified, address approver);
    event VerificationCancelled(uint256 indexed requestId);
    event VerificationExpired(uint256 indexed requestId);
    event DomainVerificationChanged(uint256 indexed domainTokenId, bool verified);
    event DomainRegistered(
        address indexed owner,
        uint256 indexed tokenId,
        string displayName,
        string canonicalName,
        uint256 mintPrice
    );
    event ETHPayment(
        address indexed sender,
        address indexed recipient,
        uint256 indexed tokenId,
        string displayName,
        uint256 amount
    );

    error ZeroAddress();
    error SelfTransferNotAllowed();
    error SelfPaymentNotAllowed();
    error InvalidName();
    error NameTooLong();
    error NameAlreadyRegistered();
    error InvalidValue();
    error IncorrectMintPayment();
    error InvalidTokenId();
    error NotOwner();
    error NotAuthorized();
    error ApprovalsDisabled();
    error MarketNotConfigured();
    error MarketAlreadyConfigured();
    error OnlyInitializer();
    error TransferFailed();
    error Reentrancy();
    error ReceiverRejected();
    error InvalidKey();
    error NotKeyHolder();
    error SameKeyHolder();
    error RequestNotFound();
    error RequestAlreadyApproved();
    error RequestAlreadyExecuted();
    error RequestAlreadyCancelled();
    error ApprovalRequired();
    error RequestExpired();
    error RequestNotExpired();
    error WrongApproverKey();
    error RevenueInsufficient();
    error VerificationRequestNotFound();
    error VerificationRequestPending();
    error VerificationAlreadyInRequestedState();

    constructor() {
        initializer = msg.sender;
        address keyNFTAddress = 0x9259426A7d3D0207Bc65c8217fE13F9D1bf1B7d0;
        if (keyNFTAddress.code.length == 0) revert ZeroAddress();
        keyNFT = IPDNVaultKeyNFT(keyNFTAddress);

        owners[1] = msg.sender;
        owners[2] = msg.sender;
        balances[msg.sender] = 2;
        displayNames[1] = "Petoron";
        displayNames[2] = "Ivan Alekseev";
        canonicalNames[1] = "petoron";
        canonicalNames[2] = "ivanalekseev";
        tokenIdByName["petoron"] = 1;
        tokenIdByName["ivanalekseev"] = 2;
        nextTokenId = 3;

        emit Transfer(address(0), msg.sender, 1);
        emit DomainRegistered(msg.sender, 1, "Petoron", "petoron", 0);
        emit Transfer(address(0), msg.sender, 2);
        emit DomainRegistered(msg.sender, 2, "Ivan Alekseev", "ivanalekseev", 0);
    }

    modifier nonReentrant() {
        if (entered) {
            revert Reentrancy();
        }

        entered = true;
        _;
        entered = false;
    }

    function setMarket(address marketAddress) external {
        if (msg.sender != initializer) {
            revert OnlyInitializer();
        }

        if (market != address(0)) {
            revert MarketAlreadyConfigured();
        }

        if (marketAddress == address(0) || marketAddress.code.length == 0) {
            revert ZeroAddress();
        }

        market = marketAddress;

        emit MarketConfigured(marketAddress);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 ||
            interfaceId == 0x80ac58cd;
    }

    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) {
            revert ZeroAddress();
        }

        return balances[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = owners[tokenId];

        if (tokenOwner == address(0)) {
            revert InvalidTokenId();
        }

        return tokenOwner;
    }

    function displayNameOf(uint256 tokenId) external view returns (string memory) {
        ownerOf(tokenId);
        return displayNames[tokenId];
    }

    function canonicalNameOf(uint256 tokenId) external view returns (string memory) {
        ownerOf(tokenId);
        return canonicalNames[tokenId];
    }

    function approve(address approved, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);

        if (msg.sender != tokenOwner) {
            revert NotOwner();
        }

        if (market == address(0)) {
            revert MarketNotConfigured();
        }

        if (approved != address(0) && approved != market) {
            revert ApprovalsDisabled();
        }

        tokenApprovals[tokenId] = approved;

        emit Approval(tokenOwner, approved, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        ownerOf(tokenId);
        return tokenApprovals[tokenId];
    }

    function setApprovalForAll(address, bool) external pure {
        revert ApprovalsDisabled();
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) {
            revert ZeroAddress();
        }

        if (to == from) {
            revert SelfTransferNotAllowed();
        }

        address tokenOwner = ownerOf(tokenId);

        if (tokenOwner != from) {
            revert NotOwner();
        }

        if (
            msg.sender != tokenOwner &&
            msg.sender != tokenApprovals[tokenId]
        ) {
            revert NotAuthorized();
        }

        delete tokenApprovals[tokenId];

        unchecked {
            balances[from] -= 1;
            balances[to] += 1;
        }

        owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        transferFrom(from, to, tokenId);

        if (to.code.length != 0) {
            bytes4 result = IPDNERC721Receiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                data
            );

            if (result != IPDNERC721Receiver.onERC721Received.selector) {
                revert ReceiverRejected();
            }
        }
    }

    function mint(string calldata requestedName) external payable returns (uint256 tokenId) {
        (string memory displayName, string memory canonicalName, uint256 canonicalLength) =
            _normalizeName(requestedName);

        if (tokenIdByName[canonicalName] != 0) {
            revert NameAlreadyRegistered();
        }

        uint256 requiredPayment = _mintPrice(canonicalLength);

        if (msg.value != requiredPayment) {
            revert IncorrectMintPayment();
        }

        tokenId = nextTokenId;
        nextTokenId = tokenId + 1;

        tokenIdByName[canonicalName] = tokenId;
        displayNames[tokenId] = displayName;
        canonicalNames[tokenId] = canonicalName;

        owners[tokenId] = msg.sender;
        balances[msg.sender] += 1;

        emit Transfer(address(0), msg.sender, tokenId);
        protocolRevenue += requiredPayment;

        emit DomainRegistered(
            msg.sender,
            tokenId,
            displayName,
            canonicalName,
            requiredPayment
        );
    }

    function sendETH(string calldata requestedName) external payable nonReentrant {
        if (msg.value == 0) {
            revert InvalidValue();
        }

        (, string memory canonicalName, ) = _normalizeName(requestedName);

        uint256 tokenId = tokenIdByName[canonicalName];

        if (tokenId == 0) {
            revert InvalidTokenId();
        }

        address recipient = ownerOf(tokenId);

        if (recipient == msg.sender) {
            revert SelfPaymentNotAllowed();
        }

        (bool success, ) = payable(recipient).call{value: msg.value}("");

        if (!success) {
            revert TransferFailed();
        }

        emit ETHPayment(
            msg.sender,
            recipient,
            tokenId,
            displayNames[tokenId],
            msg.value
        );
    }

    function receiveProtocolFee() external payable {
        if (msg.sender != market) revert NotAuthorized();
        if (msg.value == 0) revert InvalidValue();
        protocolRevenue += msg.value;
        emit ProtocolFeeReceived(msg.sender, msg.value);
    }

    function requestWithdraw(
        uint256 requesterTokenId,
        address payable recipient,
        uint256 amount
    ) external returns (uint256 requestId) {
        if (!_isValidKey(requesterTokenId)) revert InvalidKey();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidValue();
        if (reservedProtocolRevenue > protocolRevenue) revert RevenueInsufficient();
        if (amount > protocolRevenue - reservedProtocolRevenue) revert RevenueInsufficient();
        if (keyNFT.ownerOf(requesterTokenId) != msg.sender) revert NotKeyHolder();

        uint256 approverTokenId = _otherKey(requesterTokenId);
        if (keyNFT.ownerOf(approverTokenId) == msg.sender) revert SameKeyHolder();

        requestId = nextWithdrawRequestId++;
        reservedProtocolRevenue += amount;

        withdrawRequests[requestId] = WithdrawRequest({
            requester: msg.sender,
            approver: address(0),
            requesterTokenId: requesterTokenId,
            approverTokenId: approverTokenId,
            recipient: recipient,
            amount: amount,
            createdAtBlock: block.number,
            approved: false,
            executed: false,
            cancelled: false
        });

        emit WithdrawRequested(requestId, msg.sender, requesterTokenId, recipient, amount);
    }

    function approveWithdraw(uint256 requestId) external {
        WithdrawRequest storage request = withdrawRequests[requestId];
        _requireExistingWithdraw(request);
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (request.approved) revert RequestAlreadyApproved();
        if (block.number > request.createdAtBlock + WITHDRAW_REQUEST_EXPIRE_BLOCKS) revert RequestExpired();
        if (keyNFT.ownerOf(request.requesterTokenId) != request.requester) revert NotKeyHolder();
        if (keyNFT.ownerOf(request.approverTokenId) != msg.sender) revert WrongApproverKey();
        if (msg.sender == request.requester) revert SameKeyHolder();

        request.approver = msg.sender;
        request.approved = true;
        emit WithdrawApproved(requestId, msg.sender, request.approverTokenId);
    }

    function executeWithdraw(uint256 requestId) external nonReentrant {
        WithdrawRequest storage request = withdrawRequests[requestId];
        _requireExistingWithdraw(request);
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (!request.approved) revert ApprovalRequired();
        if (block.number > request.createdAtBlock + WITHDRAW_REQUEST_EXPIRE_BLOCKS) revert RequestExpired();
        if (keyNFT.ownerOf(request.requesterTokenId) != request.requester) revert NotKeyHolder();
        if (keyNFT.ownerOf(request.approverTokenId) != request.approver) revert WrongApproverKey();
        if (keyNFT.ownerOf(KEY_ONE) == keyNFT.ownerOf(KEY_TWO)) revert SameKeyHolder();
        if (request.amount > protocolRevenue) revert RevenueInsufficient();

        request.executed = true;
        reservedProtocolRevenue -= request.amount;
        protocolRevenue -= request.amount;
        (bool success, ) = request.recipient.call{value: request.amount}("");
        if (!success) revert TransferFailed();
        emit WithdrawExecuted(requestId, request.recipient, request.amount);
    }

    function cancelWithdraw(uint256 requestId) external {
        WithdrawRequest storage request = withdrawRequests[requestId];
        _requireExistingWithdraw(request);
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (
            msg.sender != request.requester &&
            msg.sender != keyNFT.ownerOf(KEY_ONE) &&
            msg.sender != keyNFT.ownerOf(KEY_TWO)
        ) revert NotKeyHolder();
        request.cancelled = true;
        reservedProtocolRevenue -= request.amount;
        emit WithdrawCancelled(requestId);
    }

    function expireWithdraw(uint256 requestId) external {
        WithdrawRequest storage request = withdrawRequests[requestId];
        _requireExistingWithdraw(request);
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (block.number <= request.createdAtBlock + WITHDRAW_REQUEST_EXPIRE_BLOCKS) revert RequestNotExpired();
        request.cancelled = true;
        reservedProtocolRevenue -= request.amount;
        emit WithdrawExpired(requestId);
    }

    function requestVerification(
        uint256 domainTokenId,
        uint256 requesterKeyTokenId,
        bool verified
    ) external returns (uint256 requestId) {
        ownerOf(domainTokenId);
        if (!_isValidKey(requesterKeyTokenId)) revert InvalidKey();
        if (keyNFT.ownerOf(requesterKeyTokenId) != msg.sender) revert NotKeyHolder();
        if (isVerified[domainTokenId] == verified) revert VerificationAlreadyInRequestedState();
        if (activeVerificationRequestByDomain[domainTokenId] != 0) revert VerificationRequestPending();

        uint256 approverKeyTokenId = _otherKey(requesterKeyTokenId);
        if (keyNFT.ownerOf(approverKeyTokenId) == msg.sender) revert SameKeyHolder();

        requestId = nextVerificationRequestId++;
        verificationRequests[requestId] = VerificationRequest({
            requester: msg.sender,
            approver: address(0),
            requesterTokenId: requesterKeyTokenId,
            approverTokenId: approverKeyTokenId,
            domainTokenId: domainTokenId,
            createdAtBlock: block.number,
            verified: verified,
            executed: false,
            cancelled: false
        });
        activeVerificationRequestByDomain[domainTokenId] = requestId;
        emit VerificationRequested(requestId, domainTokenId, verified, msg.sender);
    }

    function approveVerification(uint256 requestId) external {
        VerificationRequest storage request = verificationRequests[requestId];
        if (request.createdAtBlock == 0) revert VerificationRequestNotFound();
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (block.number > request.createdAtBlock + WITHDRAW_REQUEST_EXPIRE_BLOCKS) revert RequestExpired();
        if (keyNFT.ownerOf(request.requesterTokenId) != request.requester) revert NotKeyHolder();
        if (keyNFT.ownerOf(request.approverTokenId) != msg.sender) revert WrongApproverKey();
        if (msg.sender == request.requester) revert SameKeyHolder();
        if (isVerified[request.domainTokenId] == request.verified) revert VerificationAlreadyInRequestedState();

        request.approver = msg.sender;
        request.executed = true;
        isVerified[request.domainTokenId] = request.verified;
        delete activeVerificationRequestByDomain[request.domainTokenId];
        emit VerificationApproved(requestId, request.domainTokenId, request.verified, msg.sender);
        emit DomainVerificationChanged(request.domainTokenId, request.verified);
    }

    function cancelVerificationRequest(uint256 requestId) external {
        VerificationRequest storage request = verificationRequests[requestId];
        if (request.createdAtBlock == 0) revert VerificationRequestNotFound();
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (
            msg.sender != request.requester &&
            msg.sender != keyNFT.ownerOf(KEY_ONE) &&
            msg.sender != keyNFT.ownerOf(KEY_TWO)
        ) revert NotKeyHolder();

        request.cancelled = true;
        delete activeVerificationRequestByDomain[request.domainTokenId];
        emit VerificationCancelled(requestId);
    }

    function expireVerificationRequest(uint256 requestId) external {
        VerificationRequest storage request = verificationRequests[requestId];
        if (request.createdAtBlock == 0) revert VerificationRequestNotFound();
        if (request.cancelled) revert RequestAlreadyCancelled();
        if (request.executed) revert RequestAlreadyExecuted();
        if (block.number <= request.createdAtBlock + WITHDRAW_REQUEST_EXPIRE_BLOCKS) revert RequestNotExpired();

        request.cancelled = true;
        delete activeVerificationRequestByDomain[request.domainTokenId];
        emit VerificationExpired(requestId);
    }

    function _requireExistingWithdraw(WithdrawRequest storage request) private view {
        if (request.createdAtBlock == 0) revert RequestNotFound();
    }

    function _isValidKey(uint256 tokenId) private pure returns (bool) {
        return tokenId == KEY_ONE || tokenId == KEY_TWO;
    }

    function _otherKey(uint256 tokenId) private pure returns (uint256) {
        if (tokenId == KEY_ONE) return KEY_TWO;
        if (tokenId == KEY_TWO) return KEY_ONE;
        revert InvalidKey();
    }

    function mintPrice(string calldata requestedName) external pure returns (uint256) {
        (, , uint256 canonicalLength) = _normalizeName(requestedName);
        return _mintPrice(canonicalLength);
    }

    function canonicalize(string calldata requestedName) external pure returns (string memory) {
        (, string memory canonicalName, ) = _normalizeName(requestedName);
        return canonicalName;
    }

    function _mintPrice(uint256 canonicalLength) private pure returns (uint256) {
        if (canonicalLength == 1) {
            return PRICE_ONE_CHARACTER;
        }

        if (canonicalLength == 2) {
            return PRICE_TWO_CHARACTERS;
        }

        if (canonicalLength == 3) {
            return PRICE_THREE_CHARACTERS;
        }

        if (canonicalLength <= 7) {
            return PRICE_FOUR_TO_SEVEN_CHARACTERS;
        }

        if (canonicalLength <= 11) {
            return PRICE_EIGHT_TO_ELEVEN_CHARACTERS;
        }

        return 0;
    }

    function _normalizeName(
        string calldata requestedName
    )
        private
        pure
        returns (
            string memory displayName,
            string memory canonicalName,
            uint256 canonicalLength
        )
    {
        bytes calldata input = bytes(requestedName);
        uint256 inputLength = input.length;

        if (inputLength == 0) {
            revert InvalidName();
        }

        if (inputLength > MAX_NAME_LENGTH) {
            revert NameTooLong();
        }

        bytes memory canonicalBuffer = new bytes(inputLength);
        bool previousSeparator;
        bool hasCharacter;

        for (uint256 i; i < inputLength; ++i) {
            uint8 character = uint8(input[i]);

            if (character >= 65 && character <= 90) {
                character += 32;
            }

            bool isLetter = character >= 97 && character <= 122;
            bool isDigit = character >= 48 && character <= 57;
            bool isSeparator =
                character == 32 ||
                character == 45 ||
                character == 46 ||
                character == 95;

            if (!isLetter && !isDigit && !isSeparator) {
                revert InvalidName();
            }

            if (isSeparator) {
                if (i == 0 || i == inputLength - 1 || previousSeparator) {
                    revert InvalidName();
                }

                previousSeparator = true;
                continue;
            }

            previousSeparator = false;
            canonicalBuffer[canonicalLength] = bytes1(character);
            canonicalLength += 1;
            hasCharacter = true;
        }

        if (!hasCharacter || previousSeparator) {
            revert InvalidName();
        }

        assembly {
            mstore(canonicalBuffer, canonicalLength)
        }

        displayName = string(input);
        canonicalName = string(canonicalBuffer);
    }

    receive() external payable {
        revert InvalidValue();
    }

    fallback() external payable {
        revert InvalidValue();
    }
}
