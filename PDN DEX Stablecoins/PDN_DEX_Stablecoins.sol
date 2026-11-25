// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/*
Copyright (c) Ivan Alekseev

Licensed under the PetoronAI Community License (PCL)
or a valid PetoronAI Commercial License.
*/

interface IPDNCoreDEX {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC20DEX {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract PDN_DEX_Stablecoins {
    address public constant PDN_CORE = 0x238B9b6De2A247178307d504e9B8DE5A98be4864;
    address public constant ETH = address(0);
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant EURC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
    address public constant EURCV = 0x5F7827FDeb7c20b443265Fc2F40845B715385Ff2;
    address public constant XSGD = 0x70e8dE73cE538DA2bEEd35d14187F6959a8ecA96;
    address public constant JPYC = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29;
    address public constant NZDD = 0x2dD087589ce9C5b2D1b42e20d2519B3c8cF022b7;
    address public constant IDRT = 0x998FFE1E43fAcffb941dc337dD0468d52bA5b48A;
    address public constant TRYB = 0x2C537E5624e4af88A7ae4060C022609376C8D0EB;
    address public constant MXNT = 0xed03Ed872159e199065401b6d0D487d78d9464AA;
    address public constant GBPT = 0x86B4dBE5D203e634a12364C0e428fa242A3FbA98;
    uint256 public constant MAX_MANAGERS_PER_POOL = 7;

    IPDNCoreDEX public immutable pdnCore;
    uint256 public nextPoolId = 1;
    bool private entered;

    enum PoolStatus { NONE, ACTIVE, CLOSED }

    struct Pool {
        uint256 ownerTokenId;
        address sellToken;
        address paymentToken;
        uint256 reserve;
        uint256 reservePayment;
        uint256 priceNumerator;
        uint256 priceDenominator;
        uint256 sellPriceNumerator;
        uint256 sellPriceDenominator;
        PoolStatus status;
        bool paused;
    }

    struct Manager {
        uint256 tokenId;
        uint256 epoch;
        bool active;
    }

    mapping(uint256 => Pool) public pools;
    mapping(bytes32 => uint256) private activePairPools;
    mapping(uint256 => uint256) public managerEpoch;
    mapping(uint256 => mapping(uint256 => Manager)) public managers;
    mapping(uint256 => uint256[]) private managerTokenIds;
    mapping(uint256 => mapping(uint256 => uint256)) private activeManagerIndexPlusOne;

    error InvalidAddress();
    error InvalidToken();
    error InvalidAmount();
    error InvalidPrice();
    error InvalidPool();
    error PoolNotActive();
    error NotPDNOwner();
    error NotPoolOwner();
    error NotManager();
    error SelfTrade();
    error SameAsset();
    error InsufficientReserve();
    error IncorrectETHAmount();
    error UnexpectedETH();
    error Slippage();
    error Reentrancy();
    error TransferFailed();
    error MathOverflow();
    error InvalidManager();
    error ManagerAlreadyActive();
    error ManagerNotActive();
    error PoolPaused();
    error PoolNotPaused();
    error PriceChanged();
    error PairAlreadyExists();

    event PoolCreated(uint256 indexed poolId, uint256 indexed ownerTokenId, address sellToken, address paymentToken, uint256 amount, uint256 priceNumerator, uint256 priceDenominator);
    event PoolFunded(uint256 indexed poolId, uint256 amount, uint256 newReserve);
    event PaymentReserveFunded(uint256 indexed poolId, uint256 amount, uint256 newReserve);
    event PoolWithdrawn(uint256 indexed poolId, uint256 amount, address indexed recipient, uint256 newReserve);
    event PaymentReserveWithdrawn(uint256 indexed poolId, uint256 amount, address indexed recipient, uint256 newReserve);
    event PriceUpdated(uint256 indexed poolId, uint256 numerator, uint256 denominator);
    event SellPriceUpdated(uint256 indexed poolId, uint256 numerator, uint256 denominator);
    event SellTrade(uint256 indexed poolId, uint256 indexed sellerTokenId, address indexed seller, uint256 sellAmount, uint256 paymentAmount);
    event PoolClosed(uint256 indexed poolId);
    event ManagerSet(uint256 indexed poolId, uint256 indexed managerTokenId, bool active, uint256 epoch);
    event PoolPausedStateChanged(uint256 indexed poolId, bool paused);
    event AllManagersRevoked(uint256 indexed poolId, uint256 epoch);
    event Trade(uint256 indexed poolId, uint256 indexed buyerTokenId, address indexed buyer, uint256 sellAmount, uint256 paymentAmount);

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    constructor() {
        if (PDN_CORE.code.length == 0) revert InvalidAddress();
        pdnCore = IPDNCoreDEX(PDN_CORE);
    }

    receive() external payable {
        revert UnexpectedETH();
    }

    fallback() external payable {
        revert UnexpectedETH();
    }

    function createPool(
        uint256 ownerTokenId,
        address sellToken,
        address paymentToken,
        uint256 sellAmount,
        uint256 priceNumerator,
        uint256 priceDenominator
    ) external payable nonReentrant returns (uint256 poolId) {
        _requirePDNOwner(ownerTokenId, msg.sender);
        _validatePair(sellToken, paymentToken);
        bytes32 pairKey = _pairKey(ownerTokenId, sellToken, paymentToken);
        if (activePairPools[pairKey] != 0) revert PairAlreadyExists();
        if (sellAmount == 0 || priceNumerator == 0 || priceDenominator == 0) revert InvalidAmount();
        _receiveAsset(sellToken, msg.sender, sellAmount);
        poolId = nextPoolId++;
        activePairPools[pairKey] = poolId;
        pools[poolId] = Pool({
            ownerTokenId: ownerTokenId,
            sellToken: sellToken,
            paymentToken: paymentToken,
            reserve: sellAmount,
            reservePayment: 0,
            priceNumerator: priceNumerator,
            priceDenominator: priceDenominator,
            sellPriceNumerator: 0,
            sellPriceDenominator: 0,
            status: PoolStatus.ACTIVE,
            paused: false
        });
        emit PoolCreated(poolId, ownerTokenId, sellToken, paymentToken, sellAmount, priceNumerator, priceDenominator);
    }

    function createPool(
        uint256 ownerTokenId,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 priceABNumerator,
        uint256 priceABDenominator,
        uint256 priceBANumerator,
        uint256 priceBADenominator
    ) external payable nonReentrant returns (uint256 poolId) {
        _requirePDNOwner(ownerTokenId, msg.sender);
        _validatePair(tokenA, tokenB);
        if (activePairPools[_pairKey(ownerTokenId, tokenA, tokenB)] != 0) revert PairAlreadyExists();
        if (
            amountA == 0 ||
            amountB == 0 ||
            priceABNumerator == 0 ||
            priceABDenominator == 0 ||
            priceBANumerator == 0 ||
            priceBADenominator == 0
        ) revert InvalidAmount();
        _receivePairAssets(tokenA, tokenB, msg.sender, amountA, amountB);
        poolId = nextPoolId++;
        activePairPools[_pairKey(ownerTokenId, tokenA, tokenB)] = poolId;
        pools[poolId] = Pool({
            ownerTokenId: ownerTokenId,
            sellToken: tokenA,
            paymentToken: tokenB,
            reserve: amountA,
            reservePayment: amountB,
            priceNumerator: priceABNumerator,
            priceDenominator: priceABDenominator,
            sellPriceNumerator: priceBANumerator,
            sellPriceDenominator: priceBADenominator,
            status: PoolStatus.ACTIVE,
            paused: false
        });
        emit PoolCreated(poolId, ownerTokenId, tokenA, tokenB, amountA, priceABNumerator, priceABDenominator);
        emit PaymentReserveFunded(poolId, amountB, amountB);
        emit SellPriceUpdated(poolId, priceBANumerator, priceBADenominator);
    }

    function addFunds(uint256 poolId, uint256 amount) external payable nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        if (amount == 0) revert InvalidAmount();
        _receiveAsset(pool.sellToken, msg.sender, amount);
        pool.reserve += amount;
        emit PoolFunded(poolId, amount, pool.reserve);
    }

    function managerAddFunds(uint256 poolId, uint256 amount) external payable nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requireManager(poolId, msg.sender);
        if (amount == 0) revert InvalidAmount();
        _receiveAsset(pool.sellToken, msg.sender, amount);
        pool.reserve += amount;
        emit PoolFunded(poolId, amount, pool.reserve);
    }

    function addPaymentFunds(uint256 poolId, uint256 amount) external payable nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        if (amount == 0) revert InvalidAmount();
        _receiveAsset(pool.paymentToken, msg.sender, amount);
        pool.reservePayment += amount;
        emit PaymentReserveFunded(poolId, amount, pool.reservePayment);
    }

    function managerAddPaymentFunds(uint256 poolId, uint256 amount) external payable nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requireManager(poolId, msg.sender);
        if (amount == 0) revert InvalidAmount();
        _receiveAsset(pool.paymentToken, msg.sender, amount);
        pool.reservePayment += amount;
        emit PaymentReserveFunded(poolId, amount, pool.reservePayment);
    }

    function withdrawFunds(uint256 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        _withdraw(poolId, pool, amount);
    }

    function managerWithdraw(uint256 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requireManager(poolId, msg.sender);
        _withdraw(poolId, pool, amount);
    }

    function withdrawPaymentFunds(uint256 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        _withdrawPayment(poolId, pool, amount);
    }

    function managerWithdrawPayment(uint256 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requireManager(poolId, msg.sender);
        _withdrawPayment(poolId, pool, amount);
    }

    function setPrice(uint256 poolId, uint256 numerator, uint256 denominator) external {
        Pool storage pool = _activePool(poolId);
        if (numerator == 0 || denominator == 0) revert InvalidPrice();
        if (!_isPoolOwner(pool, msg.sender)) _requireManager(poolId, msg.sender);
        pool.priceNumerator = numerator;
        pool.priceDenominator = denominator;
        emit PriceUpdated(poolId, numerator, denominator);
    }

    function setSellPrice(uint256 poolId, uint256 numerator, uint256 denominator) external {
        Pool storage pool = _activePool(poolId);
        if (numerator == 0 || denominator == 0) revert InvalidPrice();
        if (!_isPoolOwner(pool, msg.sender)) _requireManager(poolId, msg.sender);
        pool.sellPriceNumerator = numerator;
        pool.sellPriceDenominator = denominator;
        emit SellPriceUpdated(poolId, numerator, denominator);
    }

    function setManager(uint256 poolId, uint256 managerTokenId, bool active) external {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        if (managerTokenId == 0 || managerTokenId == pool.ownerTokenId) revert InvalidManager();
        address managerOwner = pdnCore.ownerOf(managerTokenId);
        if (managerOwner == pdnCore.ownerOf(pool.ownerTokenId)) revert InvalidManager();
        uint256 domainTokenId = pool.ownerTokenId;
        Manager storage manager = managers[domainTokenId][managerTokenId];
        bool currentlyActive = manager.active && manager.epoch == managerEpoch[domainTokenId];
        if (active) {
            if (currentlyActive) revert ManagerAlreadyActive();
            if (managerTokenIds[domainTokenId].length >= MAX_MANAGERS_PER_POOL) revert InvalidManager();
            manager.tokenId = managerTokenId;
            manager.epoch = managerEpoch[domainTokenId];
            manager.active = true;
            managerTokenIds[domainTokenId].push(managerTokenId);
            activeManagerIndexPlusOne[domainTokenId][managerTokenId] = managerTokenIds[domainTokenId].length;
        } else {
            if (!currentlyActive) revert ManagerNotActive();
            _removeManager(domainTokenId, managerTokenId);
            manager.active = false;
        }
        emit ManagerSet(poolId, managerTokenId, active, managerEpoch[domainTokenId]);
    }

    function revokeAllManagers(uint256 poolId) external {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        uint256 domainTokenId = pool.ownerTokenId;
        uint256[] storage ids = managerTokenIds[domainTokenId];
        for (uint256 i; i < ids.length; ++i) {
            uint256 tokenId = ids[i];
            managers[domainTokenId][tokenId].active = false;
            activeManagerIndexPlusOne[domainTokenId][tokenId] = 0;
        }
        delete managerTokenIds[domainTokenId];
        managerEpoch[domainTokenId]++;
        emit AllManagersRevoked(poolId, managerEpoch[domainTokenId]);
    }

    function pausePool(uint256 poolId) external {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        if (pool.paused) revert PoolPaused();
        pool.paused = true;
        emit PoolPausedStateChanged(poolId, true);
    }

    function unpausePool(uint256 poolId) external {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        if (!pool.paused) revert PoolNotPaused();
        pool.paused = false;
        emit PoolPausedStateChanged(poolId, false);
    }

    function closePool(uint256 poolId) external nonReentrant {
        Pool storage pool = _activePool(poolId);
        _requirePoolOwner(pool, msg.sender);
        uint256 amount = pool.reserve;
        uint256 paymentAmount = pool.reservePayment;
        pool.reserve = 0;
        pool.reservePayment = 0;
        pool.status = PoolStatus.CLOSED;
        delete activePairPools[_pairKey(pool.ownerTokenId, pool.sellToken, pool.paymentToken)];
        if (amount != 0) _sendAsset(pool.sellToken, msg.sender, amount);
        if (paymentAmount != 0) _sendAsset(pool.paymentToken, msg.sender, paymentAmount);
        emit PoolWithdrawn(poolId, amount, msg.sender, 0);
        emit PaymentReserveWithdrawn(poolId, paymentAmount, msg.sender, 0);
        emit PoolClosed(poolId);
    }

    function buy(
        uint256 poolId,
        uint256 buyerTokenId,
        uint256 sellAmount,
        uint256 expectedPriceNumerator,
        uint256 expectedPriceDenominator,
        uint256 maxPaymentAmount
    ) external payable nonReentrant {
        _requirePDNOwner(buyerTokenId, msg.sender);
        Pool storage pool = _activePool(poolId);
        if (pool.paused) revert PoolPaused();
        if (pool.priceNumerator != expectedPriceNumerator || pool.priceDenominator != expectedPriceDenominator) revert PriceChanged();
        address poolOwner = pdnCore.ownerOf(pool.ownerTokenId);
        if (poolOwner == msg.sender || buyerTokenId == pool.ownerTokenId) revert SelfTrade();
        if (_isManagerToken(poolId, buyerTokenId) || _isManagerAddress(poolId, msg.sender)) revert SelfTrade();
        if (sellAmount == 0 || sellAmount > pool.reserve) revert InsufficientReserve();
        uint256 paymentAmount = _mulDivUp(sellAmount, pool.priceNumerator, pool.priceDenominator);
        if (paymentAmount == 0) revert InvalidPrice();
        if (paymentAmount > maxPaymentAmount) revert Slippage();
        pool.reserve -= sellAmount;
        pool.reservePayment += paymentAmount;
        _receiveAsset(pool.paymentToken, msg.sender, paymentAmount);
        _sendAsset(pool.sellToken, msg.sender, sellAmount);
        emit Trade(poolId, buyerTokenId, msg.sender, sellAmount, paymentAmount);
    }

    function sell(
        uint256 poolId,
        uint256 sellerTokenId,
        uint256 sellAmount,
        uint256 expectedPriceNumerator,
        uint256 expectedPriceDenominator,
        uint256 minPaymentAmount
    ) external payable nonReentrant {
        _requirePDNOwner(sellerTokenId, msg.sender);
        Pool storage pool = _activePool(poolId);
        if (pool.paused) revert PoolPaused();
        if (
            pool.sellPriceNumerator != expectedPriceNumerator ||
            pool.sellPriceDenominator != expectedPriceDenominator ||
            expectedPriceNumerator == 0 ||
            expectedPriceDenominator == 0
        ) revert PriceChanged();
        address poolOwner = pdnCore.ownerOf(pool.ownerTokenId);
        if (poolOwner == msg.sender || sellerTokenId == pool.ownerTokenId) revert SelfTrade();
        if (_isManagerToken(poolId, sellerTokenId) || _isManagerAddress(poolId, msg.sender)) revert SelfTrade();
        if (sellAmount == 0) revert InvalidAmount();
        uint256 paymentAmount = _mulDivDown(sellAmount, pool.sellPriceNumerator, pool.sellPriceDenominator);
        if (paymentAmount == 0) revert InvalidPrice();
        if (paymentAmount < minPaymentAmount) revert Slippage();
        if (paymentAmount > pool.reservePayment) revert InsufficientReserve();
        pool.reserve += sellAmount;
        pool.reservePayment -= paymentAmount;
        _receiveAsset(pool.sellToken, msg.sender, sellAmount);
        _sendAsset(pool.paymentToken, msg.sender, paymentAmount);
        emit SellTrade(poolId, sellerTokenId, msg.sender, sellAmount, paymentAmount);
    }

    function getTokenDecimals(address token) external pure returns (uint8) {
        if (token == ETH) return 18;
        if (token == USDC || token == USDT || token == EURC || token == XSGD || token == NZDD || token == TRYB || token == MXNT) return 6;
        if (token == EURCV || token == JPYC || token == GBPT) return 18;
        if (token == IDRT) return 2;
        revert InvalidToken();
    }

    function quotePayment(uint256 poolId, uint256 sellAmount) external view returns (uint256) {
        Pool storage pool = _activePool(poolId);
        if (sellAmount == 0) revert InvalidAmount();
        uint256 paymentAmount = _mulDivUp(sellAmount, pool.priceNumerator, pool.priceDenominator);
        if (paymentAmount == 0) revert InvalidPrice();
        return paymentAmount;
    }

    function quoteSell(uint256 poolId, uint256 sellAmount) external view returns (uint256) {
        Pool storage pool = _activePool(poolId);
        if (sellAmount == 0) revert InvalidAmount();
        if (pool.sellPriceNumerator == 0 || pool.sellPriceDenominator == 0) revert InvalidPrice();
        return _mulDivDown(sellAmount, pool.sellPriceNumerator, pool.sellPriceDenominator);
    }

    function getManagerTokenIds(uint256 poolId) external view returns (uint256[] memory) {
        return managerTokenIds[pools[poolId].ownerTokenId];
    }

    function _activePool(uint256 poolId) private view returns (Pool storage pool) {
        pool = pools[poolId];
        if (pool.status == PoolStatus.NONE) revert InvalidPool();
        if (pool.status != PoolStatus.ACTIVE) revert PoolNotActive();
        pdnCore.ownerOf(pool.ownerTokenId);
    }

    function _requirePDNOwner(uint256 tokenId, address account) private view {
        if (tokenId == 0 || pdnCore.ownerOf(tokenId) != account) revert NotPDNOwner();
    }

    function _isPoolOwner(Pool storage pool, address account) private view returns (bool) {
        return pdnCore.ownerOf(pool.ownerTokenId) == account;
    }

    function _requirePoolOwner(Pool storage pool, address account) private view {
        if (!_isPoolOwner(pool, account)) revert NotPoolOwner();
    }

    function _requireManager(uint256 poolId, address account) private view {
        uint256 domainTokenId = pools[poolId].ownerTokenId;
        uint256 length = managerTokenIds[domainTokenId].length;
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = managerTokenIds[domainTokenId][i];
            Manager storage manager = managers[domainTokenId][tokenId];
            if (manager.active && manager.epoch == managerEpoch[domainTokenId] && pdnCore.ownerOf(tokenId) == account) return;
        }
        revert NotManager();
    }

    function _isManagerToken(uint256 poolId, uint256 tokenId) private view returns (bool) {
        uint256 domainTokenId = pools[poolId].ownerTokenId;
        Manager storage manager = managers[domainTokenId][tokenId];
        return manager.active && manager.epoch == managerEpoch[domainTokenId];
    }

    function _isManagerAddress(uint256 poolId, address account) private view returns (bool) {
        uint256 domainTokenId = pools[poolId].ownerTokenId;
        uint256 length = managerTokenIds[domainTokenId].length;
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = managerTokenIds[domainTokenId][i];
            Manager storage manager = managers[domainTokenId][tokenId];
            if (manager.active && manager.epoch == managerEpoch[domainTokenId] && pdnCore.ownerOf(tokenId) == account) return true;
        }
        return false;
    }

    function _removeManager(uint256 domainTokenId, uint256 tokenId) private {
        uint256 indexPlusOne = activeManagerIndexPlusOne[domainTokenId][tokenId];
        if (indexPlusOne == 0) revert ManagerNotActive();
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = managerTokenIds[domainTokenId].length - 1;
        if (index != lastIndex) {
            uint256 lastTokenId = managerTokenIds[domainTokenId][lastIndex];
            managerTokenIds[domainTokenId][index] = lastTokenId;
            activeManagerIndexPlusOne[domainTokenId][lastTokenId] = index + 1;
        }
        managerTokenIds[domainTokenId].pop();
        activeManagerIndexPlusOne[domainTokenId][tokenId] = 0;
    }

    function _withdraw(uint256 poolId, Pool storage pool, uint256 amount) private {
        if (amount == 0 || amount > pool.reserve) revert InsufficientReserve();
        address recipient = pdnCore.ownerOf(pool.ownerTokenId);
        pool.reserve -= amount;
        _sendAsset(pool.sellToken, recipient, amount);
        emit PoolWithdrawn(poolId, amount, recipient, pool.reserve);
    }

    function _withdrawPayment(uint256 poolId, Pool storage pool, uint256 amount) private {
        if (amount == 0 || amount > pool.reservePayment) revert InsufficientReserve();
        address recipient = pdnCore.ownerOf(pool.ownerTokenId);
        pool.reservePayment -= amount;
        _sendAsset(pool.paymentToken, recipient, amount);
        emit PaymentReserveWithdrawn(poolId, amount, recipient, pool.reservePayment);
    }

    function _pairKey(uint256 ownerTokenId, address tokenA, address tokenB) private pure returns (bytes32) {
        address first = tokenA;
        address second = tokenB;
        if (first > second) {
            first = tokenB;
            second = tokenA;
        }
        return keccak256(abi.encode(ownerTokenId, first, second));
    }

    function _validatePair(address sellToken, address paymentToken) private pure {
        if (!_isSupported(sellToken) || !_isSupported(paymentToken)) revert InvalidToken();
        if (sellToken == paymentToken) revert SameAsset();
    }

    function _isSupported(address token) private pure returns (bool) {
        return
            token == ETH ||
            token == USDC ||
            token == USDT ||
            token == EURC ||
            token == EURCV ||
            token == XSGD ||
            token == JPYC ||
            token == NZDD ||
            token == IDRT ||
            token == TRYB ||
            token == MXNT ||
            token == GBPT;
    }

    function _receivePairAssets(address tokenA, address tokenB, address from, uint256 amountA, uint256 amountB) private {
        if (tokenA == ETH) {
            if (msg.value != amountA) revert IncorrectETHAmount();
            _receiveERC20(tokenB, from, amountB);
        } else if (tokenB == ETH) {
            if (msg.value != amountB) revert IncorrectETHAmount();
            _receiveERC20(tokenA, from, amountA);
        } else {
            if (msg.value != 0) revert UnexpectedETH();
            _receiveERC20(tokenA, from, amountA);
            _receiveERC20(tokenB, from, amountB);
        }
    }

    function _receiveERC20(address token, address from, uint256 amount) private {
        uint256 beforeBalance = IERC20DEX(token).balanceOf(address(this));
        _safeTransferFrom(token, from, address(this), amount);
        uint256 received = IERC20DEX(token).balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert TransferFailed();
    }

    function _receiveAsset(address token, address from, uint256 amount) private {
        if (token == ETH) {
            if (msg.value != amount) revert IncorrectETHAmount();
            return;
        }
        if (msg.value != 0) revert UnexpectedETH();
        _receiveERC20(token, from, amount);
    }

    function _sendAsset(address token, address to, uint256 amount) private {
        if (to == address(0) || to == address(this)) revert InvalidAddress();
        if (token == ETH) {
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            _safeTransfer(token, to, amount);
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20DEX.transfer.selector, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20DEX.transferFrom.selector, from, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _mulDivDown(uint256 x, uint256 y, uint256 denominator) private pure returns (uint256 result) {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (prod1 == 0) return prod0 / denominator;
            if (denominator <= prod1) revert MathOverflow();
            uint256 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;
            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            result = prod0 * inverse;
        }
    }

    function _mulDivUp(uint256 x, uint256 y, uint256 denominator) private pure returns (uint256 result) {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (prod1 == 0) {
                result = prod0 / denominator;
                if (prod0 % denominator != 0) result++;
                return result;
            }
            if (denominator <= prod1) revert MathOverflow();
            uint256 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;
            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            result = prod0 * inverse;
            if (remainder != 0) {
                if (result == type(uint256).max) revert MathOverflow();
                result++;
            }
        }
    }
}
