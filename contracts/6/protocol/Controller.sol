// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./interfaces/IBundleFactory.sol";
import "./interfaces/IBundle.sol";
import "./interfaces/IUnbinder.sol";
import "./interfaces/IRebalancer.sol";

contract Controller is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    event LogDefaultWhitelist(
        address indexed caller,
        address[]       swapWhitelist
    );

    /* ========== Constants ========== */

    uint256 internal constant MAX_DELAY = 14 days;
    uint256 internal constant INIT_DELAY = 7 days;
    uint256 internal constant MIN_DELAY = 1 days;

    /* ========== Storage ========== */

    struct BundleMetadata {
        address unbinder;
        bool    isInitialized;
        bool    isSetup;
        uint256 lastUpdateTime;
    }

    IBundleFactory private _factory;
    IRebalancer private _rebalancer;

    address private _router;
    uint256 private _delay;

    mapping(address => BundleMetadata) private _bundles;
    address[] private _swapWhitelist;

    /* ========== Initialization ========== */

    function initialize(address factory, address router)
        public
        initializer
    {
        __Ownable_init();
        _factory = IBundleFactory(factory);
        _router = router;
        _delay = INIT_DELAY;
    }

    function setRebalancer(address rebalancer)
        external
        onlyOwner
    {
        require(address(_rebalancer) == address(0), "ERR_REBALANCER_SET");
        _rebalancer = IRebalancer(rebalancer);
    }

    function setDefaultWhitelist(address[] calldata whitelist)
        external
        onlyOwner
    {
        _swapWhitelist = whitelist;
        emit LogDefaultWhitelist(msg.sender, _swapWhitelist);
    }

    function setDelay(uint256 delay)
        external
        onlyOwner
    {
        require(delay >= MIN_DELAY && delay <= MAX_DELAY, "ERR_BAD_DELAY");
        _delay = delay;
    }

    /* ========== Bundle Deployment ========== */

    function deploy(
        string calldata name,
        string calldata symbol
    ) 
        external
        onlyOwner
    {
        require(address(_rebalancer) != address(0), "ERR_REBALANCER_NOT_SET");

        // Deploy new proxies via factory
        (address bundle, address unbinder) = _factory.deploy(name, symbol);

        // Initialize contracts
        IBundle(bundle).initialize(address(this), address(_rebalancer), unbinder, name, symbol);
        IUnbinder(unbinder).initialize(bundle, _router, address(this), _swapWhitelist);

        _bundles[bundle] = BundleMetadata({
            unbinder: unbinder,
            isInitialized: true,
            isSetup: false,
            lastUpdateTime: 0
        });
    }

    function setup(
        address bundle,
        address[] calldata tokens,
        uint256[] calldata balances,
        uint256[] calldata denorms,
        address tokenProvider
    )
        external
        onlyOwner
    {
        require(_bundles[bundle].isInitialized && !_bundles[bundle].isSetup, "ERR_SETUP");
        IBundle(bundle).setup(tokens, balances, denorms, tokenProvider);
        _bundles[bundle].isSetup = true;
        _bundles[bundle].lastUpdateTime = block.timestamp;
        _rebalancer.setWhitelist(bundle, true);
    }

    /* ========== Rebalancer ========== */

    function setPremium(uint256 premium) external onlyOwner {
        _rebalancer.setPremium(premium);
    }

    function setWhitelist(address bundle, bool flag) external onlyOwner {
        _rebalancer.setWhitelist(bundle, flag);
    }

    function setRebalancerSwapWhitelist(address token, bool flag) external onlyOwner {
        _rebalancer.setSwapWhitelist(token, flag);
    }

    function setOracle(address oracle) external onlyOwner {
        _rebalancer.setOracle(oracle);
    }

    function setGap(uint256 gap) external onlyOwner {
        _rebalancer.setGap(gap);
    }

    /* ========== Unbinder ========== */

    function setUnbinderPremium(
        address[] calldata unbinders,
        uint256 premium
    ) 
        external 
        onlyOwner 
    {
        for (uint256 i = 0; i < unbinders.length; i++) {
            IUnbinder(unbinders[i]).setPremium(premium);
        }
    }

    function setUnbinderSwapWhitelist(
        address[] calldata unbinders,
        address token,
        bool flag
    ) 
        external
        onlyOwner
    {
        for (uint256 i = 0; i < unbinders.length; i++) {
            IUnbinder(unbinders[i]).setSwapWhitelist(token, flag);
        }
    }

    /* ========== Bundle ========== */

    function setSwapFee(address bundle, uint256 swapFee) external onlyOwner {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        IBundle(bundle).setSwapFee(swapFee);
    }

    function setRebalancable(address bundle, bool flag) external onlyOwner {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        IBundle(bundle).setRebalancable(flag);
    }

    function setMinBalance(
        address bundle, 
        address token,
        uint256 minBalance
    ) 
        external 
        onlyOwner 
    {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        IBundle(bundle).setMinBalance(token, minBalance);
    }

    function setStreamingFee(address bundle, uint256 streamingFee) external onlyOwner {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        IBundle(bundle).setStreamingFee(streamingFee);
    }

    function setExitFee(address bundle, uint256 exitFee) external onlyOwner {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        IBundle(bundle).setExitFee(exitFee);
    }

    function setTargetDelta(address bundle, uint256 targetDelta) external onlyOwner {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        IBundle(bundle).setTargetDelta(targetDelta);
    }

    function collectStreamingFee(address bundle) external onlyOwner {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        IBundle(bundle).collectStreamingFee();
    }

    /* ========== Bundle Asset Controls ========== */

    function reweighTokens(
        address bundle,
        address[] calldata tokens,
        uint256[] calldata targetDenorms
    )
        external
        onlyOwner
    {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        require(block.timestamp >= _bundles[bundle].lastUpdateTime.add(_delay), "ERR_DELAY");
        IBundle(bundle).reweighTokens(tokens, targetDenorms);
        _bundles[bundle].lastUpdateTime = block.timestamp;
    }

    function reindexTokens(
        address bundle,
        address[] calldata tokens,
        uint256[] calldata targetDenorms,
        uint256[] calldata minBalances
    )
        external
        onlyOwner
    {
        require(_bundles[bundle].isSetup, "ERR_BUNDLE_NOT_SETUP");
        require(block.timestamp >= _bundles[bundle].lastUpdateTime.add(_delay), "ERR_DELAY");
        IBundle(bundle).reindexTokens(tokens, targetDenorms, minBalances);
        _bundles[bundle].lastUpdateTime = block.timestamp;
    }

    /* ========== Getters ========== */

    function getBundleMetadata(
        address bundle
    ) 
        external view 
        returns (
            address unbinder, 
            bool isInitialized, 
            bool isSetup, 
            uint256 lastUpdateTime
        )
    {
        return (
            _bundles[bundle].unbinder,
            _bundles[bundle].isInitialized,
            _bundles[bundle].isSetup,
            _bundles[bundle].lastUpdateTime
        );
    }

    function getDelay() external view returns (uint256) {
        return _delay;
    }

    function getRebalancer() external view returns (address) {
        return address(_rebalancer);
    }

    function getDefaultWhitelist() external view returns (address[] memory) {
        return _swapWhitelist;
    }

    /* ========== Misc ========== */

    function collectTokens(
        address[] calldata tokens,
        uint256[] calldata balances,
        address to
    ) 
        external 
        onlyOwner 
    {
        require(tokens.length == balances.length, "ERR_LENGTH_MISMATCH");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Upgradeable(tokens[i]).safeTransfer(to, balances[i]);
        }
    }
}
