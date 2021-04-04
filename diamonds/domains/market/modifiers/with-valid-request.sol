// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../../../contracts/interfaces/IPlatformSettings.sol";
import "../../../../contracts/interfaces/IAssetSettings.sol";
import { TellerCommon } from "../../../../contracts/util/TellerCommon.sol";
import { int_is_debt_ratio_valid } from "../internal/is-debt-ratio-valid.sol";

abstract contract mod_with_valid_request_v1 is
    TellerCommon,
    int_is_debt_ratio_valid
{
    modifier withValidLoanRequest(LoanRequest memory loanRequest) {
        uint256 maxLoanDuration =
            IPlatformSettings(PROTOCOL).getMaximumLoanDurationValue();
        require(
            maxLoanDuration >= loanRequest.duration,
            "DURATION_EXCEEDS_MAX_DURATION"
        );

        bool exceedsMaxLoanAmount =
            IAssetSettings(PROTOCOL).exceedsMaxLoanAmount(
                s().lendingToken,
                loanRequest.amount
            );
        require(!exceedsMaxLoanAmount, "AMOUNT_EXCEEDS_MAX_AMOUNT");

        require(
            _isDebtRatioValid(loanRequest.amount),
            "SUPPLY_TO_DEBT_EXCEEDS_MAX"
        );
        _;
    }
}

abstract contract mod_with_valid_request is mod_with_valid_request_v1 {}
