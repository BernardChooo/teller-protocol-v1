// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import "@openzeppelin/contracts/utils/Address.sol";

// Interfaces
import "../interfaces/loans/ILoanManager.sol";
import "../interfaces/loans/ILoanStorage.sol";
import "../interfaces/loans/ILoanTermsConsensus.sol";
import "../interfaces/LendingPoolInterface.sol";
import "../interfaces/SettingsInterface.sol";
import "../interfaces/IMarketFactory.sol";
import "../interfaces/IMarketRegistry.sol";
import "../interfaces/ITToken.sol";

// Contracts
import "./Base.sol";
import "./proxies/InitializeableDynamicProxy.sol";
import "./MarketRegistry.sol";
import "./Factory.sol";

/*****************************************************************************************************/
/**                                             WARNING                                             **/
/**                                  THIS CONTRACT IS UPGRADEABLE!                                  **/
/**  ---------------------------------------------------------------------------------------------  **/
/**  Do NOT change the order of or PREPEND any storage variables to this or new versions of this    **/
/**  contract as this will cause the the storage slots to be overwritten on the proxy contract!!    **/
/**                                                                                                 **/
/**  Visit https://docs.openzeppelin.com/upgrades/2.6/proxies#upgrading-via-the-proxy-pattern for   **/
/**  more information.                                                                              **/
/*****************************************************************************************************/
/**
    @notice This contract offers functions to manage markets.

    @author develop@teller.finance
 */
contract MarketFactory is IMarketFactory, Base, Factory {
    using Address for address;

    /* State Variables */

    IMarketRegistry public override marketRegistry;

    /**
     * @notice It holds the address of a deployed InitializeableDynamicProxy contract.
     * @dev It is used to deploy a new proxy contract with minimal gas cost using the logic in the Factory contract.
     */
    address public initDynamicProxyLogic;

    /** External Functions */

    /**
        @notice It creates a new market for a given lending and collateral tokens.
        @dev It uses the Settings.ETH_ADDRESS to represent the ETHER.
        @param lendingToken the token address used to create the lending pool and TToken.
        @param collateralToken the collateral token address.
     */
    function createMarket(address lendingToken, address collateralToken)
        external
        override
        whenNotPaused
        onlyPauser
    {
        require(
            !marketRegistry.marketExists(lendingToken, collateralToken),
            "MARKET_ALREADY_EXISTS"
        );
        require(lendingToken.isContract(), "BORROWED_TOKEN_MUST_BE_CONTRACT");
        require(
            collateralToken == settings.ETH_ADDRESS() ||
                collateralToken.isContract(),
            "COLL_TOKEN_MUST_BE_CONTRACT"
        );

        address loanManagerAddress =
            _createDynamicProxy(keccak256("LoanManager"), true);

        LendingPoolInterface lendingPool =
            LendingPoolInterface(marketRegistry.lendingPools(lendingToken));
        if (address(lendingPool) == address(0)) {
            lendingPool = _createLendingPool(lendingToken);
        }

        // Initializing Loans
        ILoanManager(loanManagerAddress).initialize(
            address(lendingPool),
            address(settings),
            collateralToken,
            initDynamicProxyLogic
        );

        marketRegistry.registerMarket(address(lendingPool), loanManagerAddress);

        emit NewMarketCreated(
            msg.sender,
            lendingToken,
            collateralToken,
            loanManagerAddress,
            address(lendingPool)
        );
    }

    /**
        @notice It initializes this market factory instance.
     */
    function initialize() external override {
        _initialize(msg.sender);

        initDynamicProxyLogic = settings.initDynamicProxyLogic();

        marketRegistry = IMarketRegistry(
            _createDynamicProxy(keccak256("MarketRegistry"), false)
        );
        marketRegistry.initialize();
    }

    /** Internal Functions */

    /**
        @notice It creates a InitializeableDynamicProxy instance for a given logic name.
        @dev It is used to create all the market contracts as strict dynamic proxies.
     */
    function _createDynamicProxy(bytes32 logicName, bool strict)
        internal
        returns (address proxyAddress)
    {
        proxyAddress = _clone(initDynamicProxyLogic);
        IInitializeableDynamicProxy(proxyAddress).initialize(
            address(logicRegistry),
            logicName,
            strict
        );
    }

    /**
        @notice Creates a proxy contract for LendingPool and its TToken.
        @param lendingToken the token address used to create the lending pool and TToken.
        @return lendingPool a new LendingPool instance.
     */
    function _createLendingPool(address lendingToken)
        internal
        returns (LendingPoolInterface lendingPool)
    {
        lendingPool = LendingPoolInterface(
            _createDynamicProxy(keccak256("LendingPool"), true)
        );

        ITToken tToken =
            ITToken(_createDynamicProxy(keccak256("TToken"), true));

        lendingPool.initialize(
            marketRegistry,
            lendingToken,
            address(tToken),
            address(settings)
        );
        tToken.initialize(address(lendingPool));
    }
}