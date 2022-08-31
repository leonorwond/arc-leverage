// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "./CvxUnity.sol";

interface ILp3CrvOracle {
    function get() external view returns (uint256);
}

contract CvxCvxlpThreeCRVSwapper is CvxUnity {
    using SafeMath for uint256;

    uint256 private tokenid = 5;
    
    ILp3CrvOracle public oracle;

    uint256 private depositAmount;
    uint256 private leverage;
    uint256 private borrow;
    uint256 private swapUSDAAmount;
    uint256 private expectedBorrow;
    uint256 private meta3CRVAmount;
    uint256 private pid;
    uint private previd;
    uint private nextid;
    address private debtor;
    uint256 private mimUSDAAmount;

    constructor(address[4] memory _coins, address[3] memory _pools) {
        usda = _coins[0];
        usdt = _coins[1];
        threeCRV = _coins[2];
        cvxlp3Crv = _coins[3];
        pools = _pools;

        IERC20(usda).approve(pools[2], type(uint256).max);
        // usdt.approve(threepool, type(uint256).max);
        (bool success, bytes memory data) = usdt.call(abi.encodeWithSelector(SIG_APPROVE, pools[0], type(uint256).max));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDT: approve failed");

        IERC20(threeCRV).approve(pools[1], type(uint256).max);
        IERC20(threeCRV).approve(pools[2], type(uint256).max);
    }

    function setCoins(address[2] memory _coins, address _threeCRV, address _cvxlp3Crv) public isOwner returns (bool) {
        usda = _coins[0];
        usdt = _coins[1];
        threeCRV = _threeCRV;
        cvxlp3Crv = _cvxlp3Crv;
        return true;
    }

    function setOracle(address _oracle) public isOwner returns (bool) {
        oracle = ILp3CrvOracle(_oracle);
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

        IERC20(cvxlp3Crv).transferFrom(msg.sender, address(this), _amount);

        // cvxlptoken == usda e.g. cvxFrax3Crv == usda
        uint256 price = oracle.get(); // cvxlptoken/usd
        swapUSDAAmount = depositAmount.mul(PRICE_DENOMINATOR).div(price);

        // leverage 0x0 -> USDA
        uint256 fee;
        (borrow, fee) = _expected(swapUSDAAmount, leverage);
        uint256 left = ILeverageManager(leverageManager).remain(strategy);
        require(left >= borrow, "balance not enough.");
        IUSDA(usda).mint(address(this), borrow);
        expectedBorrow = borrow.sub(fee);

        // fee -> ActivePool
        IActivePool(activePool).receiveUSDAEarned(address(this),address(this), fee);

        // USDA -> USDT
        uint256 dy = IMetaPool(pools[2]).get_dy_underlying(0, 3, expectedBorrow);
        uint256 mimUsdtAmount = _mimAmount(swap, dy);
        uint256 usdtAmount = IMetaPool(pools[2]).exchange_underlying(0, 3, expectedBorrow, mimUsdtAmount, address(this));
    
        // USDT -> 3CRV
        uint256 old_balance = IERC20(threeCRV).balanceOf(address(this));
        uint256[3] memory amountsAdded = [0, 0, usdtAmount];
        IThreePool(pools[0]).add_liquidity(amountsAdded, 0);
        uint256 new_balance = IERC20(threeCRV).balanceOf(address(this));
        uint256 threeCRVAmount = new_balance.sub(old_balance);

        // 3CRV -> meta3CRV e.g. 3CRV -> frax3CRV
        meta3CRVAmount =  IMetaPool(pools[1]).add_liquidity([0, threeCRVAmount], 0);

        // lptoken -> cvxlptoken e.g. frax3CRV -> cvxFrax3CRV
        pid = IRewards(rewards).pid();
        uint256 oldCvxlp3CRVAmount = IERC20(cvxlp3Crv).balanceOf(address(this));
        IDeposit(depositpool).deposit(pid, meta3CRVAmount, false);
        uint256 newCvxlp3CRVAmount = IERC20(cvxlp3Crv).balanceOf(address(this));
        uint256 totalCvxFrax3CRVAmount = newCvxlp3CRVAmount.sub(oldCvxlp3CRVAmount).add(depositAmount);

        // cvxlptoken -> rewards e.g. cvxFrax3CRV -> rewards
        address proxy = IAddressFactory(addressFactory).getProxyAddress(msg.sender);
        IERC20(cvxlp3Crv).transfer(proxy, totalCvxFrax3CRVAmount);
        IProxyAddress(proxy).deposit(rewards, cvxlp3Crv, totalCvxFrax3CRVAmount);

        DepositInfo memory info;
        info.tokenid = tokenid;
        info.margin = depositAmount;
        info.borrow = borrow;
        info.metaThreeCRVAmount = totalCvxFrax3CRVAmount;
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

        // rewards -> cvxMeta3CRV -> meta3CRV e.g. rewards -> cvxFrax3CRV -> frax3CRV
        address proxy = IAddressFactory(addressFactory).getProxyAddress(debtor);
        uint256 lp3CRVAmount = IProxyAddress(proxy).unstake(rewards, info.metaThreeCRVAmount, true, pools[1], extraRewards, msg.sender);

        // meta3CRV -> 3CRV  e.g. frax3CRV -> 3CRV
        uint256 threeCRVAmount = IMetaPool(pools[1]).remove_liquidity_one_coin(lp3CRVAmount, 1, 0);

        // deleverage fee
        (uint256 value,  uint256 fee) = _deleverageFee(threeCRVAmount);
        if (fee == 0) {
            value = value - 1;
            fee = 1;
        }

        // interest
        uint256 interestAmount = _interest(info.borrow, info.interestTime);
        uint256 usdaDebtAmount = info.borrow.add(interestAmount);

        // 3CRV == USDA
        uint256 price = IMetaPool(pools[2]).get_dy(1, 0, 1e18);
        uint256 swapThreeCRVAmount = usdaDebtAmount.mul(PRICE_DENOMINATOR).div(price);
        swapThreeCRVAmount = swapThreeCRVAmount.add(fee);
        
        if (swapThreeCRVAmount < value) {
            uint256 balanceThreeCRVAmount = threeCRVAmount.sub(swapThreeCRVAmount);
            // 3CRV -> meta3CRV e.g. 3CRV -> frax3CRV
            uint256 balanceFrax3CRVAmount =  IMetaPool(pools[1]).add_liquidity([0, balanceThreeCRVAmount], 0);
            // meta3CRV -> cvxlptoken e.g. frax3CRV -> cvxFrax3CRV
            pid = IRewards(rewards).pid();
            uint256 oldCvxlp3CRVAmount = IERC20(cvxlp3Crv).balanceOf(address(this));
            IDeposit(depositpool).deposit(pid, balanceFrax3CRVAmount, false);
            uint256 newCvxlp3CRVAmount = IERC20(cvxlp3Crv).balanceOf(address(this));
            uint256 cvxlp3CRVAmount = newCvxlp3CRVAmount.sub(oldCvxlp3CRVAmount);
            IERC20(cvxlp3Crv).transfer(msg.sender, cvxlp3CRVAmount);
        } else {
            swapThreeCRVAmount = threeCRVAmount;
        }
        
        // 3CRV -> USDA
        uint256 dy = IMetaPool(pools[2]).get_dy(1, 0, swapThreeCRVAmount);
        mimUSDAAmount = _mimAmount(swap, dy);
        uint256 usdaAmount = IMetaPool(pools[2]).exchange(1, 0, swapThreeCRVAmount, mimUSDAAmount, address(this));

        // interest -> ActivePool
        if (info.borrow > 0) {
            IUSDA(usda).burn(info.borrow);
        }
        uint256 deleverageAmount = usdaAmount.sub(info.borrow);
        IActivePool(activePool).receiveUSDAEarned(address(this),address(this), deleverageAmount);
        
        ILeverageManager(leverageManager).deleverage(debtor, strategy);

        // notify redeem
        if (redeem != address(0x0)) {
            IRedeem(redeem).setSort(debtor, opType, 0, 0, previd, nextid);
        }

        emit Deleverage(debtor, strategy);

        return true;
    }
}
