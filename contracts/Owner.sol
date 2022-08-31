// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

/*
    Owner manager
*/
contract Owner {
	// Owner of this contract
    address public owner;
    
    // permit transaction
    bool isLock = false;

    // event for EVM logging
    event SetOwner(address indexed oldOwner, address indexed newOwner);
    event Unlock(address indexed owner, bool islock);
    
    constructor() {
        owner = msg.sender; // 'msg.sender' is sender of current call, contract deployer for a constructor
        emit SetOwner(address(0), owner);
    }

    modifier isOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
	
	modifier isUnlock() {
	    require(isLock == false, "constract has been locked");
        _;
    }
    
    /**
     * @dev Change owner
     * @param newOwner address of new owner
     */
    function changeOwner(address newOwner) public isOwner {
        owner = newOwner;
        emit SetOwner(owner, newOwner);
    }

    /**
    * unlock contract. Only after unlock can it be traded.
    */
    function unlock() public isOwner returns (bool) {
        isLock = false;
        emit Unlock(msg.sender, true);
        return isLock;
    }
    
    /**
    * lock contract
    */
    function lock() public isOwner returns (bool) {
        isLock = true;
        emit Unlock(msg.sender, false);
        return isLock;
    }

    function status() public view returns(bool) {
        return !isLock;
    }
}
