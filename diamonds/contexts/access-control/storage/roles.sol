// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./data.sol";

abstract contract sto_AccessControl_Roles {
    bytes32 internal constant POS =
        keccak256("teller_protocol.storage.access_control.roles");

    struct AccessControlRolesStorage {
        mapping(bytes32 => dat_AccessControl_v1.RoleData) roles;
    }

    function accessControlRolesStore()
        internal
        pure
        returns (AccessControlRolesStorage storage s)
    {
        bytes32 position = POS;

        assembly {
            s.slot := position
        }
    }
}
