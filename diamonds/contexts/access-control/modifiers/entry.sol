// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { sto_AccessControl } from "../storage/roles.sol";

abstract contract mod_entry_AccessControl_v1 is sto_AccessControl {
    modifier entry {
        sto_AccessControl_v2.Layout_v1 storage layout =
            sto_AccessControl.getv1();
        require(layout.notEntered, "RE_ENTRANCY");
        layout.notEntered = false;
        _;
        layout.notEntered = true;
    }
}
