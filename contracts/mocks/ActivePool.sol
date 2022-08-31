// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;


interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract ActivePool {
    
    struct ActivePoolInfo {
        address pool;
        address account;
        uint amount;
    }
    
    ActivePoolInfo public info;

    address public usda;

    constructor(address _usda) {
        usda = _usda;
    }

    /**
     * @dev Borrow/Leverage/Redeem/Liquidation charge fee with USDA to active-pool
    */
    function receiveUSDAEarned(address _pool, address _account, uint _amount) public {
        IERC20(usda).transferFrom(_account, address(this), _amount);
        info.pool = _pool;
        info.account = _account;
        info.amount = _amount;
    }
}
