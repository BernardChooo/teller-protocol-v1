// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Contracts
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

// Libraries
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Interfaces

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
 * @notice This contract is used by borrowers to call Dapp functions (using delegate calls).
 * @notice This contract should only be constructed using it's upgradeable Proxy contract.
 * @notice In order to call a Dapp function, the Dapp must be added in the DappRegistry instance.
 *
 * @author develop@teller.finance
 */
contract TellerNFT_V2 is ERC1155Upgradeable, AccessControlUpgradeable {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;

    /* Constants */

    string public constant name = "Teller NFT";
    string public constant symbol = "TNFT";

    uint256 private constant ID_PADDING = 10000;

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant MINTER = keccak256("MINTER");

    /* State Variables */

    struct Tier {
        uint256 baseLoanSize;
        address contributionAsset;
        uint256 contributionSize;
        uint8 contributionMultiplier;
    }

    // It holds the total number of tokens in existence.
    uint256 public totalSupply;

    // It holds the total number of tiers.
    uint128 internal _tierCount;

    // It holds how many tokens types exists in a tier.
    mapping(uint128 => uint256) internal _tierTokenCount;

    // It holds the information about a tier.
    mapping(uint256 => Tier) internal _tiers;

    // It holds the URI hash containing the token metadata
    mapping(uint256 => string) internal _idToUriHash;
    // It is a reverse lookup of the token ID given the metadata hash
    mapping(string => uint256) internal _uriHashToId;

    // Hash to the contract metadata
    string private _contractURIHash;

    /* Public Functions */

    /**
     * @notice checks if an interface is supported by ITellerNFT or AccessControlUpgradeable
     * @param interfaceId the identifier of the interface
     * @return bool stating whether or not our interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC1155MetadataURI-uri}.
     *
     * This implementation returns the same URI for *all* token types. It relies
     * on the token type ID substitution mechanism
     * https://eips.ethereum.org/EIPS/eip-1155#metadata[defined in the EIP].
     *
     * Clients calling this function must replace the `\{id\}` substring with the
     * actual token type ID.
     */
    function uri(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return
            string(abi.encodePacked(super.uri(tokenId), _idToUriHash[tokenId]));
    }

    /* External Functions */

    /**
     * @notice The contract metadata URI.
     * @return the contract URI hash
     */
    function contractURI() external view returns (string memory) {
        // URI returned from parent just returns base URI
        return string(abi.encodePacked(super.uri(0), _contractURIHash));
    }

    /**
     * @notice It returns information about a Tier for a token ID.
     * @param tokenId ID of the token to get Tier info.
     * @return tierId_ the index of the tier the tokenId belongs to
     * @return tierTokenId_ the tokenId in tier
     */
    function getTokenTierId(uint256 tokenId)
        external
        view
        returns (uint128 tierId_, uint128 tierTokenId_)
    {
        (tierId_, tierTokenId_) = _splitTokenId(tokenId);
    }

    /**
     * @notice It returns Base Loan Size for a token ID.
     * @param tokenId ID of the token to get info.
     */
    function tokenBaseLoanSize(uint256 tokenId) public view returns (uint256) {
        (uint128 tierId, ) = _splitTokenId(tokenId);
        return _tiers[tierId].baseLoanSize;
    }

    /**
     * @notice It returns Contribution Asset for a token ID.
     * @param tokenId ID of the token to get info.
     */
    function tokenContributionAsset(uint256 tokenId)
        public
        view
        returns (address)
    {
        (uint128 tierId, ) = _splitTokenId(tokenId);
        return _tiers[tierId].contributionAsset;
    }

    /**
     * @notice It returns Contribution Size for a token ID.
     * @param tokenId ID of the token to get info.
     */
    function tokenContributionSize(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        (uint128 tierId, ) = _splitTokenId(tokenId);
        return _tiers[tierId].contributionSize;
    }

    /**
     * @notice It returns Contribution Multiplier for a token ID.
     * @param tokenId ID of the token to get info.
     */
    function tokenContributionMultiplier(uint256 tokenId)
        public
        view
        returns (uint8)
    {
        (uint128 tierId, ) = _splitTokenId(tokenId);
        return _tiers[tierId].contributionMultiplier;
    }

    struct TokenBalance {
        uint256 tokenId;
        uint256 balance;
    }

    /**
     * @notice It returns an array of token IDs owned by an address.
     * @dev It uses a EnumerableSet to store values and loops over each element to add to the array.
     * @dev Can be costly if calling within a contract for address with many tokens.
     * @return owned_ the array of tokenIDs owned by the address
     */
    function getOwnedTokens(address owner)
        external
        view
        returns (TokenBalance[] memory owned_)
    {
        uint256[] memory tokenIds = getTokenIds();
        owned_ = new TokenBalance[](tokenIds.length);
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 balance = balanceOf(owner, tokenIds[i]);
            if (balance > 0) {
                owned_[i] = TokenBalance(tokenIds[i], balance);
            }
        }
    }

    function getTokenIds() public view returns (uint256[] memory ids_) {
        uint256 tokenCount;
        for (uint128 tierId = 1; tierId <= _tierCount; tierId++) {
            tokenCount += _tierTokenCount[tierId];
        }

        ids_ = new uint256[](tokenCount);
        uint256 currentIndex;
        for (uint128 tierId = 1; tierId < _tierCount; tierId++) {
            for (
                uint128 tierTokenId;
                tierTokenId <= _tierTokenCount[tierId];
                tierTokenId++
            ) {
                ids_[currentIndex] = _mergeTokenId(tierId, tierTokenId);
                currentIndex++;
            }
        }
    }

    /**
     * @notice It mints a new token for a Tier index.
     * @param tierIndex Tier to mint token on.
     * @param owner The owner of the new token.
     *
     * Requirements:
     *  - Caller must be an authorized minter
     */
    function mint(uint256 tierIndex, address owner) external onlyRole(MINTER) {
        // Get the token ID to mint for the user
        // On a fresh mint, the exact token ID minted is determined on tx execution
        //  with sudo randomness using the block number
        //        uint128 tokenId = block.number % _tierTokenCount[tierIndex];
        //
        //        // Mint and set the token to the tier index
        //        _safeMint(owner, tokenId);
        //
        //        // Set owner
        //        _setOwner(owner, tokenId);
    }

    /**
     * @notice Creates new Tiers to be minted with the given information.
     * @dev It auto increments the index of the next tier to add.
     * @param newTiers Information about the new tiers to add.
     * @param tierHashes Metadata hashes belonging to the tiers.
     *
     * Requirements:
     *  - Caller must have the {ADMIN} role
     */
    function createTiers(
        Tier[] calldata newTiers,
        string[][] calldata tierHashes
    ) external onlyRole(ADMIN) {
        require(
            newTiers.length == tierHashes.length,
            "Teller: array length mismatch"
        );

        for (uint256 i; i < newTiers.length; i++) {
            _createTier(newTiers[i], tierHashes[i]);
        }
    }

    function _createTier(Tier calldata newTier, string[] calldata tierHashes)
        internal
    {
        // Increment tier counter to use
        Tier storage tier = _tiers[++_tierCount];

        tier.baseLoanSize = newTier.baseLoanSize;
        tier.contributionAsset = newTier.contributionAsset;
        tier.contributionSize = newTier.contributionSize;
        tier.contributionMultiplier = newTier.contributionMultiplier;

        // Store how many tokens are on the tier
        _tierTokenCount[_tierCount] = tierHashes.length;
        // Set the token URI hash
        for (uint128 i; i < tierHashes.length; i++) {
            uint256 tokenId = _mergeTokenId(_tierCount, i);
            _idToUriHash[tokenId] = tierHashes[i];
            _uriHashToId[tierHashes[i]] = tokenId;
        }
    }

    /**
     * @dev See {_setURI}.
     *
     * Requirements:
     *
     * - `newURI` must be prepended with a forward slash (/)
     */
    function setURI(string memory newURI) external onlyRole(ADMIN) {
        _setURI(newURI);
    }

    /**
     * @notice Sets the contract level metadata URI hash.
     * @param contractURIHash The hash to the initial contract level metadata.
     */
    function setContractURIHash(string memory contractURIHash)
        public
        onlyRole(ADMIN)
    {
        _contractURIHash = contractURIHash;
    }

    /**
     * @notice Initializes the TellerNFT.
     * @param minters The addresses that should allowed to mint tokens.
     */
    function initialize(address[] calldata minters) public virtual initializer {
        // Set the initial URI
        __ERC1155_init("https://gateway.pinata.cloud/ipfs/");
        __AccessControl_init();

        // Set admin role for admins
        _setRoleAdmin(ADMIN, ADMIN);
        // Set the initial admin
        _setupRole(ADMIN, _msgSender());

        // Set admin role for minters
        _setRoleAdmin(MINTER, ADMIN);
        // Set the initial minters
        for (uint256 i; i < minters.length; i++) {
            _setupRole(MINTER, minters[i]);
        }

        // Set initial contract URI hash
        setContractURIHash("QmWAfQFFwptzRUCdF2cBFJhcB2gfHJMd7TQt64dZUysk3R");
    }

    /* Internal Functions */

    /**
     * @dev Runs super function and then increases total supply.
     *
     * See {ERC1155Upgradeable._mint}.
     */
    function _mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal override {
        super._mint(account, id, amount, data);

        totalSupply += amount;
    }

    /**
     * @dev Runs super function and then increases total supply.
     *
     * See {ERC1155Upgradeable._mintBatch}.
     */
    function _mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        super._mintBatch(to, ids, amounts, data);

        for (uint256 i; i < amounts.length; i++) {
            totalSupply += amounts[i];
        }
    }

    /**
     * @dev Runs super function and then decreases total supply.
     *
     * See {ERC1155Upgradeable._burn}.
     */
    function _burn(
        address account,
        uint256 id,
        uint256 amount
    ) internal override {
        super._burn(account, id, amount);

        totalSupply -= amount;
    }

    /**
     * @dev Runs super function and then decreases total supply.
     *
     * See {ERC1155Upgradeable._burnBatch}.
     */
    function _burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal override {
        super._burnBatch(account, ids, amounts);

        for (uint256 i; i < amounts.length; i++) {
            totalSupply -= amounts[i];
        }
    }

    /**
     * @dev Checks if a token ID exists. To exists the ID must have a URI hash associated.
     * @param tokenId ID of the token to check.
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return bytes(_idToUriHash[tokenId]).length > 0;
    }

    /**
     * @dev Creates a V2 token ID from a tier ID and tier token ID.
     * @param tierId Index of the tier to use.
     * @param tierTokenId ID of the token within the given tier.
     * @return tokenId_ V2 NFT token ID.
     */
    function _mergeTokenId(uint128 tierId, uint128 tierTokenId)
        internal
        pure
        returns (uint256 tokenId_)
    {
        tokenId_ = tierId * ID_PADDING;
        tokenId_ += tierTokenId;
    }

    /**
     * @dev Creates a V2 token ID from a tier ID and tier token ID.
     * @param tokenId V2 NFT token ID.
     * @return tierId_ Index of the token tier.
     * @return tierTokenId_ ID of the token within the tier.
     */
    function _splitTokenId(uint256 tokenId)
        internal
        pure
        returns (uint128 tierId_, uint128 tierTokenId_)
    {
        tierId_ = SafeCast.toUint128(tokenId / ID_PADDING);
        tierTokenId_ = SafeCast.toUint128(tokenId % ID_PADDING);
    }
}
