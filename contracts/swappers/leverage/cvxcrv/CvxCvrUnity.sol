// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "../../../maths/SafeMath.sol";
import "../../../Owner.sol";


interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IUSDA {
    function mint(address to, uint256 amount) external returns (bool);
    function burn(uint256 amount) external returns (bool);
}

// IMetaPool
interface IMetaPool {
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy, address receiver) external returns (uint256);
}

interface ICvxCrvPool {
    function calc_token_amount(uint256[2] memory _amounts, bool _is_deposit) external view returns (uint256);
    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external returns (uint256);
    function get_dy(int128 i, int128 j, uint256 _dx) external view returns (uint256);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256);
}

struct DepositInfo {
    uint256 tokenid; // 0 usda 1 dai 2 usdc 3 usdt 4 stable token e.g. frax,mim 5 cvxlp3crv e.g. cvxFrax3Crv,cvxMIM3CRV 6 cvxcrvFRAX
    uint256 margin;
    uint256 borrow;
    uint256 metaThreeCRVAmount; // deposit amount e.g. fraxThreeCRVAmount
    uint interestTime;
}

interface ILeverageManager {
    function remain(uint256 strategy) external view returns (uint256);
    function deposit(address depositor, uint256 strategy, DepositInfo memory info) external returns (bool);
    function repay(address depositor, uint256 strategy, uint interestTime, uint256 back) external returns (bool);
    function deleverage(address depositor, uint256 strategy) external returns (bool);
    function deposits(address depositor, uint256 strategy) external view returns (DepositInfo memory);
}

interface IAddressFactory {
    function getProxyAddress(address account) external returns(address);
}

interface IProxyAddress {
    function deposit(address depositAddress, address token, uint256 amount) external returns(bool);
    function unstake(address unstakeAddress, uint256 amount, bool claim, address token, address[8] memory rewardTokens, address reciever) external returns(uint256);
}

interface IDeposit {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
}

interface IRewards{
    function pid() external view returns(uint256);
}

interface IRedeem {
    function setSort(address _id, uint8 _opType, uint _coll, uint _debt, uint _prevId, uint _nextId) external;
}

interface IActivePool {
    function receiveUSDAEarned(address _pool, address _account, uint _amount) external;
}

contract CvxCrvUnity is Owner {
    using SafeMath for uint256;

    address public usda;
    address public usdc;
    address public crvToken;
    address public cvxcrvToken;
    address[2] public pools; // 0: crvpool e.g. StableSwap (crvfrax pool) 1: usdapool(usda3CRV)

    address public depositpool; // booster
    address public rewards; // rewards
    address[8] public extraRewards; // [crv, cvx]
    uint256 public strategy = 2;   // leverageManager: 0 frax 1 mim 2 usdcFrax
 
    uint256 public recovery = 400;
    uint256 public borrowFee = 100;
    uint256 public aprFee = 100;
    uint256 public leverageFee = 50;
    uint256 public deleverageFee = 100;
    
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant SWAP_DENOMINATOR = 1000;
    uint256 public constant COLLATERAL_DENOMINATOR = 100;
    uint256 public constant PRICE_DENOMINATOR = 1e18;
    uint public constant DAY = 86400;
    uint public constant YEAR = 365*DAY+21600;

    address public leverageManager;
    uint256 public leverageMax = 800;
    address public addressFactory;
    address public redeem;
    address public activePool;
    uint8 opType = 2;

    bytes4 constant SIG_BALANCEOF = 0x70a08231;     // balanceOf(address account)
    bytes4 constant SIG_TRANSFER = 0xa9059cbb;      // transfer(address recipient, uint256 amount)
    bytes4 constant SIG_TRANSFERFROM = 0x23b872dd;  // transferFrom(address from, address to, uint256 amount)
    bytes4 constant SIG_APPROVE = 0x095ea7b3;       // approve(address,uint256)

    event Deposit(address indexed _from, uint256 _strategy, uint256 _leverage, uint256 _value);
    event Repay(address indexed _from, uint256 _strategy, uint256 _value);
    event Deleverage(address indexed _from, uint256 _strategy);
    event BadDebt(address indexed _from, uint256 _value);

    function approveBooster(uint256 amount) public isOwner returns (bool) {
        IERC20(crvToken).approve(depositpool, amount);
        return true;
    }

    function setPools(address[2] memory _pools) public isOwner returns (bool) {
        pools = _pools;
        return true;
    }

    function setConvex(address _booster, address _rewards, address[8] memory _extraRewards) public isOwner returns (bool) {
        depositpool =  _booster;
        IERC20(crvToken).approve(depositpool, type(uint256).max);
        rewards = _rewards;
        extraRewards = _extraRewards;
        return true;
    }

    function setStrategy(uint256 _strategy) public isOwner returns (bool) {
        strategy = _strategy;
        return true;
    }

    function setRecovery(uint256 _recovery) public isOwner returns(bool) {
        recovery = _recovery;
        return true;
    }

    function setLeverageManager(address _manager) public isOwner returns(bool) {
        leverageManager = _manager;
        return true;
    }

    function setAddressFactory(address _factory) public isOwner returns(bool) {
        addressFactory = _factory;
        return true;
    }

    function setActivePool(address _pool) public isOwner returns (bool) {
        activePool = _pool;
        IERC20(usda).approve(activePool, type(uint256).max);
        return true;
    }

    function setRedeem(address _redeem) public isOwner returns(bool) {
        redeem = _redeem;
        return true;
    }

    function setLeverageMax(uint256 _leverage) public isOwner returns(bool) {
        leverageMax = _leverage;
        return true;
    }

    function setBorrowFee(uint256 _fee) public isOwner returns(bool) {
        borrowFee = _fee;
        return true;
    }

    function setAprFee(uint256 _fee) public isOwner returns(bool) {
        aprFee = _fee;
        return true;
    }

    function setLeverageFee(uint256 _fee) public isOwner returns(bool) {
        leverageFee = _fee;
        return true;
    }

    function setDeleverageFee(uint256 _fee) public isOwner returns(bool) {
        deleverageFee = _fee;
        return true;
    }

    function _repay(uint256 _amount, uint256 _strategy, uint _previd, uint _nextid) internal isUnlock returns (bool) {
        IERC20(usda).transferFrom(msg.sender, address(this), _amount);

        DepositInfo memory info = ILeverageManager(leverageManager).deposits(msg.sender, _strategy);

        uint256 interest = _interest(info.borrow, info.interestTime);
        if (interest > _amount) {
            // interest -> ActivePool
            IActivePool(activePool).receiveUSDAEarned(address(this),address(this), _amount);
            uint delay = _delayTime(_amount, info.borrow);
            ILeverageManager(leverageManager).repay(msg.sender, _strategy, info.interestTime.add(delay), 0);
        } else if (interest == _amount) {
            // interest -> ActivePool
            IActivePool(activePool).receiveUSDAEarned(address(this),address(this), _amount);
            ILeverageManager(leverageManager).repay(msg.sender, _strategy, block.timestamp, 0);
        } else {
            uint256 balance = _amount.sub(interest);
            // interest -> ActivePool
            IActivePool(activePool).receiveUSDAEarned(address(this),address(this), interest);
            if (balance > info.borrow) {
                uint256 back = balance.sub(info.borrow);
                IUSDA(usda).burn(info.borrow);
                ILeverageManager(leverageManager).repay(msg.sender, _strategy, block.timestamp, info.borrow);
                // notify redeem
                if (redeem != address(0x0)) {
                    IRedeem(redeem).setSort(msg.sender, opType, info.metaThreeCRVAmount, 0, _previd, _nextid);
                }
                IERC20(usda).transfer(msg.sender, back);
            } else {
                IUSDA(usda).burn(balance);
                ILeverageManager(leverageManager).repay(msg.sender, _strategy, block.timestamp, balance);
                // notify redeem
                if (redeem != address(0x0)) {
                    IRedeem(redeem).setSort(msg.sender, opType, info.metaThreeCRVAmount, info.borrow.sub(balance), _previd, _nextid);
                }
            }
        }

        emit Repay(msg.sender, _strategy, _amount);

        return true;
    }

    function _mimAmount(uint256 swap, uint256 dy) internal pure returns(uint256) {
        require(swap <= SWAP_DENOMINATOR, "swap error");
        uint256 value = SWAP_DENOMINATOR.sub(swap);
        uint256 mimAmount = dy.mul(value);
        return mimAmount.div(SWAP_DENOMINATOR);
    }

    function _expected(uint256 _amount, uint256 _collateral) internal view returns (uint256, uint256) {
        require(_collateral <= leverageMax, "leverage error");
        uint256 feePercent = borrowFee.add(leverageFee);
        uint256 borrow = _amount.mul(_collateral);
        uint256 fee = borrow.mul(feePercent);
        uint256 DENOMINATOR = FEE_DENOMINATOR.mul(COLLATERAL_DENOMINATOR);
        return (borrow.div(COLLATERAL_DENOMINATOR), fee.div(DENOMINATOR));
    }

    function _interest(uint256 _amount, uint _startTime) internal view returns(uint256) {
        uint nowTime = block.timestamp;
        uint spead = nowTime.sub(_startTime);
        uint speadDay = spead.div(DAY);
        uint256 value = _amount.mul(aprFee);
        value = value.mul(speadDay);
        value = value.div(YEAR);
        return value.div(FEE_DENOMINATOR);
    }

    function _deleverageFee(uint256 _amount) internal view returns(uint256, uint256) {
        uint256 fee = _amount.mul(deleverageFee).div(FEE_DENOMINATOR);
        return (_amount.sub(fee), fee);
    }

    function _delayTime(uint256 _amount, uint256 _borrow) internal view returns(uint) {
        uint256 amount = _amount.mul(YEAR);
        uint256 debt = _borrow.mul(aprFee);
        amount = amount.mul(FEE_DENOMINATOR);
        return uint(amount.div(debt));
    }
}
