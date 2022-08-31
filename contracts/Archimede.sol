// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./ERC2612.sol";

contract Archimede is ERC2612 {
    using SafeMath for uint256;

    mapping(address => bool)  public minters;

    struct Minting {
        uint256 time;
        uint256 amount;
    }

    Minting public lastMint;
    uint256 private constant MINTING_PERIOD = 24 hours;
    uint256 public mintingThreshold = 0;
    
    event Minter(address indexed _minter, bool status);
    event MintThreshold(address indexed _minter, uint256 threshold);

    constructor(string memory name, string memory symbol, uint8 decimals) {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        minters[msg.sender] = true;
        lastMint.time =  block.timestamp; 
    }

    modifier isMinter(address _minter) {
        require(minters[_minter], "Caller is not owner");
        _;
    }

    function setMinter(address _minter) public isOwner returns (bool) {
        require(_minter != address(0), "_minter is 0x0");
        minters[_minter] = true;
        emit Minter(_minter, true);
        return true;
    }

    function disableMinter(address _minter) public isOwner returns (bool) {
        require(minters[_minter], "_minter error");
        minters[_minter] = false;
        emit Minter(_minter, false);
        return true;
    }

    function setThreshold(uint256 _threshold) public isOwner returns (bool) {
        mintingThreshold = _threshold;
        emit MintThreshold(msg.sender, _threshold);
        return true;
    }

    function mint(address to, uint256 amount) public isMinter(msg.sender) returns (bool) {
        require(to != address(0), "to is 0x0");
        require(amount > 0, "amount error");

        // Limits the amount minted per period to a convergence function, with the period duration restarting on every mint
        bool isDay = lastMint.time < (block.timestamp - MINTING_PERIOD);
        uint256 threshold = uint256(isDay ? 0 : lastMint.amount).add(amount);
        require(mintingThreshold == 0 || threshold < mintingThreshold, "mint amont out of threshold");
        if (isDay) {
            lastMint.time = block.timestamp; 
        }
        lastMint.amount = threshold;

        _totalSupply = _totalSupply.add(amount);
        _balances[to] = _balances[to].add(amount);

        emit Transfer(address(0), to, amount);
        return true;
    }
    
    function burn(uint256 amount) public isMinter(msg.sender) returns (bool) {
        require(amount <= _balances[msg.sender], "balances not enough");
        require(amount > 0, "balances error");

        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _totalSupply = _totalSupply.sub(amount);

        emit Transfer(msg.sender, address(0), amount);
        return true;
    }

}
