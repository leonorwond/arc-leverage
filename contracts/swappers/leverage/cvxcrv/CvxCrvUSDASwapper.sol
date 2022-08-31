// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "./CvxCvrUnity.sol";

contract CvxCrvUSDASwapper is CvxCrvUnity {
    using SafeMath for uint256;

    uint256 private tokenid = 0;

    uint256 private depositAmount;
    uint256 private leverage;
    uint private previd;
    uint private nextid;
    uint256 private expectedBorrow;
    address private debtor;
    
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
        require(_amount >= 2*1e12, "out of min.");

        depositAmount = _amount;
        leverage = _leverage;
        previd = _previd;
        nextid = _nextid;

        if (mode == 1) {
            require(_leverage <= recovery, "leverage error");
        }
 
        IERC20(usda).transferFrom(msg.sender, address(this), depositAmount);

        // leverage 0x0 -> USDA
        (uint256 borrow, uint256 fee) = _expected(depositAmount, _leverage);
        uint256 left = ILeverageManager(leverageManager).remain(strategy);
        require(left >= borrow, "balance not enough.");
        IUSDA(usda).mint(address(this), borrow);
        expectedBorrow = borrow.sub(fee);

        // fee -> ActivePool
        IActivePool(activePool).receiveUSDAEarned(address(this),address(this), fee);

        // USDA -> USDC
        uint256 usdaAmount = depositAmount.add(expectedBorrow);
        uint256 dy = IMetaPool(pools[1]).get_dy_underlying(0, 2, usdaAmount);
        uint256 mimUsdcAmount = _mimAmount(swap, dy);
        uint256 usdcAmount = IMetaPool(pools[1]).exchange_underlying(0, 2, usdaAmount, mimUsdcAmount, address(this));

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
        margin = margin.div(usdaAmount);
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

        // USDC -> USDA
        uint256 dy = IMetaPool(pools[1]).get_dy_underlying(2, 0, usdcToken);
        uint256 mimUSDAAmount = _mimAmount(swap, dy);
        uint256 usdaAmount = IMetaPool(pools[1]).exchange_underlying(2, 0, usdcToken, mimUSDAAmount, address(this));

        // deleverage fee
        (uint256 value,  uint256 fee) = _deleverageFee(usdaAmount);
        // interest
        uint256 interestAmount = _interest(info.borrow, info.interestTime);
        uint256 balance = value.sub(info.borrow).sub(interestAmount);

        // interest -> ActivePool
        IActivePool(activePool).receiveUSDAEarned(address(this),address(this), interestAmount.add(fee));
        if (info.borrow > 0) {
            IUSDA(usda).burn(info.borrow);
        }
        IERC20(usda).transfer(msg.sender, balance);
        
        ILeverageManager(leverageManager).deleverage(debtor, strategy);

        // notify redeem
        if (redeem != address(0x0)) {
            IRedeem(redeem).setSort(debtor, opType, 0, 0, previd, nextid);
        }

        emit Deleverage(debtor, strategy);

        return true;
    }
}
