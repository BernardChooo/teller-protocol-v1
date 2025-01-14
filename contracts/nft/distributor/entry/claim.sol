// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Contracts
import "../store.sol";
import "../internal/distributor.sol";

// Utils
import { ClaimNFTRequest, DistributorEvents } from "../data.sol";

contract ent_claim_NFTDistributor_v1 is
    sto_NFTDistributor,
    int_distributor_NFT_v1
{
    /**
     * @notice Claims TellerNFTs for a given verifiable merkle proofs for each tier.
     * @param account The address to claim NFTs on behalf.
     * @param requests An array requests data generated from the merkle tree.
     *
     * Requirements:
     *  - Node in the merkle root must not be claimed already
     *  - Proof of the node must match the merkle tree
     */
    function claim(address account, ClaimNFTRequest[] calldata requests)
        external
    {
        for (uint256 i; i < requests.length; i++) {
            require(
                !_isClaimed(requests[i].merkleIndex, requests[i].nodeIndex),
                "TellerNFT Distributor: already claimed"
            );
            require(
                _verifyProof(account, requests[i]),
                "TellerNFT Distributor: invalid proof"
            );

            // Mark it claimed and send the token.
            _setClaimed(requests[i].merkleIndex, requests[i].nodeIndex);
            uint256 tierIndex = distributorStore()
                .merkleRoots[requests[i].merkleIndex]
                .tierIndex;
            for (uint256 j; j < requests[i].amount; j++) {
                distributorStore().nft.mint(account, uint128(tierIndex), 1);
            }
        }

        emit DistributorEvents.Claimed(account);
    }
}
