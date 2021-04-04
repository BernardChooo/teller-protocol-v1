// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./get-storage.sol";
import "../data.sol";
import "./is-admin-for-role.sol";

abstract contract int_revokeRole_AccessControl_v1 is
    int_get_sto_AccessControl_v1,
    int_isAdminForRole_AccessControl_v1,
    dat_AccessControl_v1
{
    function _revokeRole(bytes32 role, address account) internal {
        require(_isAdminForRole(role, msg.sender), "NOT_ADMIN");
        getStorage().roles[role].members[account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }
}

abstract contract int_revokeRole_AccessControl is
    int_revokeRole_AccessControl_v1
{}