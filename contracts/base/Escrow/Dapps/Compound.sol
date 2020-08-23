pragma solidity 0.5.17;

// External Libraries
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

// Common
import "../../../util/AddressLib.sol";

// Contracts
import "./Dapp.sol";

// Interfaces
import "./ICompound.sol";
import "../../../providers/compound/CErc20Interface.sol";


/**
    @notice This contract is used to define Compound dApp actions available. All dapp 
    @author develop@teller.finance
 */
 contract Compound is Dapp, ICompound {
    using AddressLib for address;

    /**
        @notice Returns this contract's balance for the specified token.
        @param cTokenAddress token address.
        @return this contract's balance.
     */
    function balance(address cTokenAddress) public view returns (uint256) {
        return _balance(cTokenAddress);
    }

    /**
        @notice Helper function to return this contract's balance for the specified token.
        @param cToken token address.
        @return this contract's balance.
     */
    function _balance(address cToken) internal view returns (uint256) {
        return CErc20Interface(cToken).balanceOf(address(this));
    }

    /**
        @notice To lend we first have to approve the cToken to access the token balance then mint. 
        @param cTokenAddress address of the token.
        @param amount amount of tokens to mint. 
    */
    function lend(address cTokenAddress, uint256 amount) internal {
        CErc20Interface cToken = CErc20Interface(cTokenAddress);
        uint256 balanceBeforeMint = cToken.balanceOf(address(this));
        IERC20 underlying = IERC20(cToken.underlying());
        require(
            underlying.balanceOf(address(this)) >= amount,
            "COMPOUND_INSUFFICIENT_UNDERLYING"
        );
        underlying.approve(cTokenAddress, amount);
        uint256 result = cToken.mint(amount);
        require(result == 0, "COMPOUND_DEPOSIT_ERROR");
        uint256 balanceAfterMint = cToken.balanceOf(address(this));
        require(balanceAfterMint >= (balanceBeforeMint + amount), "COMPOUND_BALANCE_NOT_INCREASED");
        emit CompoundLended(msg.sender, address(this), cTokenAddress, address(underlying), amount);
    }

    /**
        @notice This function calls Compound redeemUnderlying().
        @param cTokenAddress address of the token.
        @param amount amount of underlying tokens to redeem.
    */
    function redeem(address cTokenAddress, uint256 amount) internal {
        require(_balance(cTokenAddress) >= amount, "COMPOUND_INSUFFICIENT_BALANCE");
        CErc20Interface cToken = CErc20Interface(cTokenAddress);
        IERC20 underlying = IERC20(cToken.underlying());
        uint256 balanceBeforeMint = underlying.balanceOf(address(this));
        uint256 result = cToken.redeemUnderlying(amount);
        require(result == 0, "COMPOUND_WITHDRAWAL_ERROR");
        uint256 balanceAfterMint = underlying.balanceOf(address(this));
        require(balanceAfterMint >= (balanceBeforeMint + amount), "COMPOUND_BALANCE_NOT_INCREASED");
        emit CompoundRedeemed(msg.sender, address(this), cTokenAddress, address(cToken.underlying()), balanceBeforeMint + amount);
    }

    /**
        @notice This function redeems complete token balance.
        @param cTokenAddress address of the token.
    */
    function redeem(address cTokenAddress) internal {
        uint256 amount = _balance(cTokenAddress);
        redeem(cTokenAddress, amount);
    }
}
