pragma solidity 0.5.17;

// External Libraries
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";

// Common
import "../../../util/AddressLib.sol";

// Contracts
import "../../BaseEscrowDapp.sol";

// Interfaces
import "./IUniswap.sol";
import "../../../providers/uniswap/IUniswapV2Router02.sol";

/*****************************************************************************************************/
/**                                             WARNING                                             **/
/**                      DAPP CONTRACT IS AN EXTENSION OF THE ESCROW CONTRACT                       **/
/**  ---------------------------------------------------------------------------------------------  **/
/**  Because there are multiple dApp contracts, and they all extend the Escrow contract that is     **/
/**  itself upgradeable, they cannot have their own storage variables as they would cause the the   **/
/**  storage slots to be overwritten on the Escrow proxy contract!                                  **/
/**                                                                                                 **/
/**  Visit https://docs.openzeppelin.com/upgrades/2.6/proxies#upgrading-via-the-proxy-pattern for   **/
/**  more information.                                                                              **/
/*****************************************************************************************************/
/**
    @notice This contract is used to define Uniswap dApp actions available. All dapp actions are invoked via 
        delegatecalls from Escrow contract, so this contract's state is really Escrow.
    @author develop@teller.finance
 */
contract Uniswap is IUniswap, BaseEscrowDapp {
    using AddressLib for address;
    using Address for address;

    /* Constants */
    // TODO Add comment why we are using the same address for all the networks.
    IUniswapV2Router02 public constant router = IUniswapV2Router02(
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    );

    // State is shared with Escrow contract as it uses delegateCall() to interact with this contract.

    /**
        @notice Swaps ETH/Tokens for Tokens/ETH using different Uniswap v2 Router 02 methods.
        @param path An array of token addresses. path.length must be >= 2. Pools for each consecutive pair of addresses must exist and have liquidity.
        @param sourceAmount amount of source token to swap.
        @param minDestination The minimum amount of output tokens that must be received for the transaction not to revert.
     */
    function swap(
        address[] memory path,
        uint256 sourceAmount,
        uint256 minDestination
    ) public onlyOwner() {
        _swap(router, path, sourceAmount, minDestination);
    }

    /* Internal Functions */

    /**
        @notice Swaps ETH/Tokens for Tokens/ETH using different Uniswap v2 Router 02 methods.
        @param theRouter The UniswapV2Router instance.
        @param path An array of token addresses. path.length must be >= 2. Pools for each consecutive pair of addresses must exist and have liquidity.
        @param sourceAmount amount of source token to swap.
        @param minDestination The minimum amount of output tokens that must be received for the transaction not to revert.
     */
    function _swap(
        IUniswapV2Router02 theRouter,
        address[] memory path,
        uint256 sourceAmount,
        uint256 minDestination
    ) internal {
        require(path.length >= 2, "UNISWAP_PATH_TOO_SHORT");
        address source = path[0];
        address destination = path[path.length - 1];
        require(_balanceOf(source) >= sourceAmount, "UNISWAP_INSUFFICIENT_SOURCE");
        source.requireNotEqualTo(destination, "UNISWAP_SOURCE_AND_DESTINATION_SAME");
        require(minDestination > 0, "UNISWAP_MIN_DESTINATION_ZERO"); // what if there is no minimum?

        uint256 balanceBeforeSwap = _balanceOf(destination);

        IERC20(source).approve(address(theRouter), sourceAmount);
        uint256[] memory amounts = theRouter.swapExactTokensForTokens(
            sourceAmount,
            minDestination,
            path,
            address(this),
            now
        );

        uint256 balanceAfterSwap = _balanceOf(destination);
        require(
            balanceAfterSwap >= (balanceBeforeSwap + minDestination),
            "UNISWAP_BALANCE_NOT_INCREASED"
        );
        require(amounts.length == path.length, "UNISWAP_ERROR_SWAPPING");
        uint256 destinationAmount = amounts[amounts.length - 1];

        _tokenUpdated(source);
        _tokenUpdated(destination);

        emit UniswapSwapped(source, destination, sourceAmount, destinationAmount);
    }
}
