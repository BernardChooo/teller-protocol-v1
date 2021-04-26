// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Contracts
import { PausableMods } from "../contexts2/pausable/PausableMods.sol";
import {
    ReentryMods
} from "../contexts2/access-control/reentry/ReentryMods.sol";
import { RolesMods } from "../contexts2/access-control/roles/RolesMods.sol";
import { AUTHORIZED } from "../shared/roles.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Libraries
import { LibLoans } from "./libraries/LibLoans.sol";
import { LibEscrow } from "../escrow/libraries/LibEscrow.sol";
import { LibCollateral } from "./libraries/LibCollateral.sol";
import { LibConsensus } from "./libraries/LibConsensus.sol";
import { LendingLib } from "../lending/LendingLib.sol";
import {
    PlatformSettingsLib
} from "../settings/platform/PlatformSettingsLib.sol";
import { MaxDebtRatioLib } from "../settings/asset/MaxDebtRatioLib.sol";
import { MaxLoanAmountLib } from "../settings/asset/MaxLoanAmountLib.sol";
import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { NumbersLib } from "../shared/libraries/NumbersLib.sol";
import { NFTLib, NftLoanSizeProof } from "../nft/libraries/NFTLib.sol";

// Interfaces
import { ILoansEscrow } from "../escrow/escrow/ILoansEscrow.sol";

// Proxy
import {
    BeaconProxy
} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

// Storage
import {
    LoanRequest,
    LoanResponse,
    LoanStatus,
    LoanTerms,
    Loan,
    MarketStorageLib
} from "../storage/market.sol";
import { AppStorageLib } from "../storage/app.sol";

contract CreateLoanFacet is RolesMods, ReentryMods, PausableMods {
    /**
     * @notice This event is emitted when loan terms have been successfully set
     * @param loanID ID of loan from which collateral was withdrawn
     * @param borrower Account address of the borrower
     * @param recipient Account address of the recipient
     */
    event LoanTermsSet(
        uint256 indexed loanID,
        address indexed borrower,
        address indexed recipient
    );

    /**
     * @notice This event is emitted when a loan has been successfully taken out
     * @param loanID ID of loan from which collateral was withdrawn
     * @param borrower Account address of the borrower
     * @param amountBorrowed Total amount taken out in the loan
     * @param withNFT Boolean indicating if the loan was taken out using NFTs
     */
    event LoanTakenOut(
        uint256 indexed loanID,
        address indexed borrower,
        uint256 amountBorrowed,
        bool withNFT
    );

    /**
     * @notice Creates a loan with the loan request and terms
     * @param request Struct of the protocol loan request
     * @param responses List of structs of the protocol loan responses
     * @param collateralToken Token address to use as collateral for the new loan
     * @param collateralAmount Amount of collateral required for the loan
     */
    function createLoanWithTerms(
        LoanRequest calldata request,
        LoanResponse[] calldata responses,
        address collateralToken,
        uint256 collateralAmount
    )
        external
        payable
        paused("", false)
        nonReentry("")
        authorized(AUTHORIZED, msg.sender)
    {
        CreateLoanLib.verifyCreateLoan(request, collateralToken);
        uint256 loanID =
            CreateLoanLib.initLoan(request, responses, collateralToken);

        // Pay in collateral
        if (collateralAmount > 0) {
            LibCollateral.deposit(loanID, collateralAmount);
        }

        emit LoanTermsSet(loanID, msg.sender, request.recipient);
    }

    function takeOutLoanWithNFTs(
        uint256 loanID,
        uint256 amount,
        NftLoanSizeProof[] calldata proofs
    ) external paused("", false) __takeOutLoan(loanID, amount) {
        uint256 allowedLoanSize;
        for (uint256 i; i < proofs.length; i++) {
            NFTLib.applyToLoan(loanID, proofs[i]);

            allowedLoanSize += proofs[i].baseLoanSize;
            if (allowedLoanSize >= amount) {
                break;
            }
        }
        require(
            amount <= allowedLoanSize,
            "Teller: insufficient NFT loan size"
        );

        // Transfer tokens to the loan escrow.
        CreateLoanLib.fundLoan(
            MarketStorageLib.store().loans[loanID].lendingToken,
            CreateLoanLib.createEscrow(loanID),
            amount
        );

        emit LoanTakenOut(loanID, msg.sender, amount, true);
    }

    modifier __takeOutLoan(uint256 loanID, uint256 amount) {
        Loan storage loan = MarketStorageLib.store().loans[loanID];

        require(msg.sender == loan.loanTerms.borrower, "Teller: not borrower");
        require(loan.status == LoanStatus.TermsSet, "Teller: loan not set");
        require(
            loan.termsExpiry >= block.timestamp,
            "Teller: loan terms expired"
        );
        require(
            LendingLib.debtRatioFor(loan.lendingToken, amount) <=
                MaxDebtRatioLib.get(loan.lendingToken),
            "Teller: max supply-to-debt ratio exceeded"
        );
        require(
            loan.loanTerms.maxLoanAmount >= amount,
            "Teller: max loan amount exceeded"
        );

        loan.borrowedAmount = amount;
        loan.principalOwed = amount;
        loan.interestOwed = LibLoans.getInterestOwedFor(loan.id, amount);
        loan.status = LoanStatus.Active;
        loan.loanStartTime = block.timestamp;

        _;
    }

    /**
     * @notice Take out a loan
     *
     * @dev collateral ratio is a percentage of the loan amount that's required in collateral
     * @dev the percentage will be *(10**2). I.e. collateralRatio of 5244 means 52.44% collateral
     * @dev is required in the loan. Interest rate is also a percentage with 2 decimal points.
     */
    function takeOutLoan(uint256 loanID, uint256 amount)
        external
        paused("", false)
        nonReentry("")
        authorized(AUTHORIZED, msg.sender)
        __takeOutLoan(loanID, amount)
    {
        {
            // Check that enough collateral has been provided for this loan
            (, uint256 neededInCollateral, ) =
                LibLoans.getCollateralNeededInfo(loanID);
            require(
                neededInCollateral <=
                    LibCollateral.e(loanID).loanSupply(loanID),
                "Teller: more collateral required"
            );
        }

        Loan storage loan = MarketStorageLib.store().loans[loanID];
        address loanRecipient;
        bool eoaAllowed =
            LibLoans.canGoToEOAWithCollateralRatio(
                loan.loanTerms.collateralRatio
            );
        if (eoaAllowed) {
            loanRecipient = loan.loanTerms.recipient == address(0)
                ? loan.loanTerms.borrower
                : loan.loanTerms.recipient;
        } else {
            loanRecipient = CreateLoanLib.createEscrow(loanID);
        }

        // Transfer tokens to the recipient.
        CreateLoanLib.fundLoan(loan.lendingToken, loanRecipient, amount);

        // Initialize the escrow token list
        if (!eoaAllowed) {
            LibEscrow.tokenUpdated(loanID, loan.lendingToken);
        }

        emit LoanTakenOut(loanID, msg.sender, amount, false);
    }
}

library CreateLoanLib {
    function verifyCreateLoan(
        LoanRequest calldata request,
        address collateralToken
    ) internal {
        // Perform loan request checks
        require(msg.sender == request.borrower, "Teller: not loan requester");
        require(
            PlatformSettingsLib.getMaximumLoanDurationValue() >=
                request.duration,
            "Teller: max loan duration exceeded"
        );
        // Verify collateral token is acceptable
        require(
            EnumerableSet.contains(
                MarketStorageLib.store().collateralTokens[request.assetAddress],
                collateralToken
            ),
            "Teller: collateral token not allowed"
        );
        require(
            MaxLoanAmountLib.get(request.assetAddress) > request.amount,
            "Teller: max loan amount exceeded"
        );
    }

    function initLoan(
        LoanRequest calldata request,
        LoanResponse[] calldata responses,
        address collateralToken
    ) internal returns (uint256 loanID_) {
        // Get consensus values from request
        (uint256 interestRate, uint256 collateralRatio, uint256 maxLoanAmount) =
            LibConsensus.processLoanTerms(request, responses);

        // Get and increment new loan ID
        loanID_ = CreateLoanLib.newID();
        LibLoans.loan(loanID_).id = loanID_;
        LibLoans.loan(loanID_).status = LoanStatus.TermsSet;
        LibLoans.loan(loanID_).lendingToken = request.assetAddress;
        LibLoans.loan(loanID_).collateralToken = collateralToken;
        LibLoans.loan(loanID_).termsExpiry =
            block.timestamp +
            PlatformSettingsLib.getTermsExpiryTimeValue();
        LibLoans.loan(loanID_).loanTerms = LoanTerms({
            borrower: request.borrower,
            recipient: request.recipient,
            interestRate: interestRate,
            collateralRatio: collateralRatio,
            maxLoanAmount: maxLoanAmount,
            duration: request.duration
        });

        // Add loanID to borrower list
        MarketStorageLib.store().borrowerLoans[request.borrower].push(loanID_);
    }

    function fundLoan(
        address asset,
        address recipient,
        uint256 amount
    ) internal {
        // Pull funds from Teller token LP
        MarketStorageLib.store().tTokens[asset].fundLoan(recipient, amount);
        // Increase total borrowed amount
        MarketStorageLib.store().totalBorrowed[asset] += amount;
    }

    function newID() internal returns (uint256 id_) {
        Counters.Counter storage counter =
            MarketStorageLib.store().loanIDCounter;
        id_ = Counters.current(counter);
        Counters.increment(counter);
    }

    function createEscrow(uint256 loanID) internal returns (address escrow_) {
        // Create escrow
        escrow_ = AppStorageLib.store().loansEscrowBeacon.cloneProxy("");
        ILoansEscrow(escrow_).init();
        // Save escrow address for loan
        MarketStorageLib.store().loanEscrows[loanID] = ILoansEscrow(escrow_);
    }
}
