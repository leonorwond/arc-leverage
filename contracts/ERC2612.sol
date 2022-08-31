// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./interfaces/IEIP2612.sol";
import "./maths/SafeMath.sol";
import "./Domain.sol";
import "./ERC20.sol";

contract ERC2612 is IEIP2612, Domain, ERC20 {
    mapping(address => uint) _nonces;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant PERMIT_SIGNATURE_HASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) public isUnlock override returns (bool) {
        require(owner != address(0), "Owner cannot be 0");
        require(spender != address(0), "Spender cannot be 0");
        require(value > 0, "value error");
        require(block.timestamp < deadline, "Timestamp Expired");

        bytes32 dataHash = keccak256(abi.encode(PERMIT_SIGNATURE_HASH, owner, spender, value, _nonces[owner]++, deadline));
        require( ecrecover(_getDigest(dataHash), v, r, s) == owner, "ERC20: Invalid Signature" );
        _allowances[owner][spender] = value;
        
        emit Approval(owner, spender, value);
        return true;
    }

    function nonces(address owner) public view override returns (uint) {
        return _nonces[owner];
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return _domainSeparator();
    }
}
