// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "./CvxCvrUnity.sol";

contract CvxxCrvUSDCSwapper is CvxCrvUnity {
    using SafeMath for uint256;

    uint256 private tokenid = 2;

    uint256 private depositAmount;
    uint256 private leverage;
    uint256 private swapUSDAAmount;
    uint256 private expectedBorrow;
    uint private previd;
    uint private nextid;
    address private debtor;
    uint256 private interestAmount;
    uint256 private usdaDebtAmount;
    uint256 private mimUSDAAmount;
    bool private normal;

    constructor(address[4] memory _coins, address[2] memory _pools) {
        usda = _coins[0];
        usdc = _coins[1];
        crvToken = _coins[2];
        cvxcrvToken = _coins[3];
        pools = _pools;

        IERC20(usda).approve(pools[1], type(uint256).max);
        IERC20(usdc).approve(pools[0], type(uint256).max);
        IERC20(usdc).approve(pools[1], type(uint256).max);
    }

    function setCoins(address[2] memory _coins, address _crvToken, address _cvxcrvToken) public isOwner returns (bool) {
        usda = _coins[0];
        usdc = _coins[1];
        crvToken = _crvToken;
        cvxcrvToken = _cvxcrvToken;
        return true;
    }

    function deposit(uint256 _amount, uint256 _leverage, uint8 mode, uint256 swap, uint _previd, uint _nextid) public isUnlock returns (bool) {
        require(activePool != address(0x0), "activePool address error.");

        depositAmount = _amount;
        leverage = _leverage;
        previd = _previd;
        nextid = _nextid;

        if (mode == 1) {
            require(_leverage <= recovery, "leverage error");
        }

        IERC20(usdc).transferFrom(msg.sender, address(this), depositAmount);

        // usdc == usda
        swapUSDAAmount = IMetaPool(pools[1]).get_dy_underlying(2, 0, depositAmount);

        // leverage 0x0 -> USDA
        (uint256 borrow, uint256 fee) = _expected(swapUSDAAmount, leverage);
        uint256 left = ILeverageManager(leverageManager).remain(strategy);
        require(left >= borrow, "balance not enough.");
        IUSDA(usda).mint(address(this), borrow);
        expectedBorrow = borrow.sub(fee);

        // fee -> ActivePool
        IActivePool(activePool).receiveUSDAEarned(address(this),address(this), fee);

        // USDA -> USDC
        uint256 dy = IMetaPool(pools[1]).get_dy_underlying(0, 2, expectedBorrow);
        uint256 mimUsdcAmount = _mimAmount(swap, dy);
        uint256 usdcAmount = IMetaPool(pools[1]).exchange_underlying(0, 2, expectedBorrow, mimUsdcAmount, address(this));
        usdcAmount = usdcAmount.add(depositAmount);

        // USDC -> meta pool lptoken crvToken e.g. crvFRAX
        uint256 crvTokenAmount =  ICvxCrvPool(pools[0]).add_liquidity([0, usdcAmount], 0);

        // crvToken -> cvxcrvToken e.g. crvFRAX -> cvxcrvFRAX
        uint256 pid = IRewards(rewards).pid();
        uint256 oldCvxCrvTokenAmount = IERC20(cvxcrvToken).balanceOf(address(this));
        IDeposit(depositpool).deposit(pid, crvTokenAmount, false);
        uint256 newCvxCrvTokenAmount = IERC20(cvxcrvToken).balanceOf(address(this));
        uint256 cvxcrvTokenAmount = newCvxCrvTokenAmount.sub(oldCvxCrvTokenAmount);

        // cvxcrvToken -> rewards e.g. cvxcrvFRAX -> rewards
        address proxy = IAddressFactory(addressFactory).getProxyAddress(msg.sender);
        IERC20(cvxcrvToken).transfer(proxy, cvxcrvTokenAmount);
        IProxyAddress(proxy).deposit(rewards, cvxcrvToken, cvxcrvTokenAmount);

        uint256 margin = cvxcrvTokenAmount.mul(depositAmount);
        margin = margin.div(usdcAmount);
        DepositInfo memory info;
        info.tokenid = tokenid;
        info.margin = margin;
        info.borrow = borrow;
        info.metaThreeCRVAmount = cvxcrvTokenAmount;
        info.interestTime = block.timestamp;
        ILeverageManager(leverageManager).deposit(msg.sender, strategy, info);

        // notify redeem
        if (redeem != address(0x0)) {
            IRedeem(redeem).setSort(msg.sender, opType, info.metaThreeCRVAmount, info.borrow, previd, nextid);
        }

        emit Deposit(msg.sender, strategy, leverage, depositAmount);

        return true;
    }

    function repay(uint256 _amount, uint _previd, uint _nextid) public returns (bool) {
        return _repay(_amount, strategy, _previd, _nextid);
    }

    function deleverage(uint256 swap, uint _previd, uint _nextid) public returns (bool) {
        return _deleverage(msg.sender, swap, _previd, _nextid);
    } 

    function deleverageFor(uint256 swap, address _debtor, uint _previd, uint _nextid) public returns (bool) {
        require(msg.sender == redeem, "operator error.");
        return _deleverage(_debtor, swap, _previd, _nextid);
    }

    function _deleverage(address _debtor, uint256 swap, uint _previd, uint _nextid) internal isUnlock returns (bool) {
        debtor = _debtor;
        previd = _previd;
        nextid = _nextid;

        DepositInfo memory info = ILeverageManager(leverageManager).deposits(debtor, strategy);
        require(info.tokenid == tokenid, "deleverage address error.");

        // rewards -> cvxcrvToken -> crvToken e.g. rewards -> cvxcrvFrax -> crvFrax
        address proxy = IAddressFactory(addressFactory).getProxyAddress(debtor);
        uint256 crvTokenAmount = IProxyAddress(proxy).unstake(rewards, info.metaThreeCRVAmount, true, crvToken, extraRewards, msg.sender);

        // crvToken -> usdc e.g. crvFrax -> usdc
        uint256 usdcToken = ICvxCrvPool(pools[0]).remove_liquidity_one_coin(crvTokenAmount, 1, 0);

        // deleverage fee
        (uint256 value,  uint256 fee) = _deleverageFee(usdcToken);
        if (fee == 0) {
            value = value - 1;
            fee = 1;
        }

        // interest
        interestAmount = _interest(info.borrow, info.interestTime);
        usdaDebtAmount = info.borrow.add(interestAmount);

        // USDC == USDA
        uint256 price = IMetaPool(pools[1]).get_dy_underlying(2, 0, 1e6);
        uint256 swapAmount = usdaDebtAmount.mul(1e6).div(price);
        swapAmount = swapAmount.add(fee);
        if (swapAmount > value) {
            swapAmount = usdcToken;
        }

        // USDC -> USDA
        uint256 dy = IMetaPool(pools[1]).get_dy_underlying(2, 0, swapAmount);
        mimUSDAAmount = _mimAmount(swap, dy);
        uint256 usdaAmount = IMetaPool(pools[1]).exchange_underlying(2, 0, swapAmount, mimUSDAAmount, address(this));
        uint256 balance = usdcToken.sub(swapAmount);
        if (balance > 0) {
            IERC20(usdc).transfer(msg.sender, balance);
        }
        
        // interest -> ActivePool
        normal = true;
        if (info.borrow > 0) {
            if (usdaAmount >= info.borrow) {
                IUSDA(usda).burn(info.borrow);
            } else {
                IUSDA(usda).burn(usdaAmount);
                normal = false;
                emit BadDebt(debtor, info.borrow - usdaAmount);
            }
            
        }
        if (normal) {
            IActivePool(activePool).receiveUSDAEarned(address(this),address(this), usdaAmount.sub(info.borrow));
        } 
        

        ILeverageManager(leverageManager).deleverage(debtor, strategy);

        // notify redeem
        if (redeem != address(0x0)) {
            IRedeem(redeem).setSort(debtor, opType, 0, 0, previd, nextid);
        }

        emit Deleverage(debtor, strategy);

        return true;
    }
}
