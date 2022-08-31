// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./interfaces/IEIP20.sol";
import "./maths/SafeMath.sol";
import "./Owner.sol";

contract ERC20 is IEIP20, Owner {
    using SafeMath for uint256;

    string  _name;
    string  _symbol;
    uint8  _decimals;
    uint256  _totalSupply;
    mapping(address => uint256)  _balances;
    mapping(address => mapping(address => uint256)) _allowances;

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) public isUnlock override returns (bool) {
        require(value <= _balances[msg.sender]);
        require(to != address(0));
        
        _balances[msg.sender] = _balances[msg.sender].sub(value);
        _balances[to] = _balances[to].add(value);

        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public isUnlock override returns (bool) {
        require(value <= _balances[from]);
        require(value <= _allowances[from][msg.sender]);
        require(to != address(0));
        
        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(value);
        _allowances[from][msg.sender] = _allowances[from][msg.sender].sub(value);

        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public isUnlock override returns (bool) {
        require(spender != address(0));

        _allowances[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
}
