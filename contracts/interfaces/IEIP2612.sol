// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/blob/master/EIPS/eip-2612.md
 */

interface IEIP2612 {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool);
    function nonces(address owner) external view returns (uint);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    event Permit(address indexed owner, address indexed spender, uint256 value, uint deadline, uint8 v, bytes32 r, bytes32 s);
}
