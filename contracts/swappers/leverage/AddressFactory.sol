// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface IERC20 {
    function balanceOf(address _owner) external view returns (uint256);
    function approve(address _spender, uint256 _value) external returns (bool);
    function transfer(address _to, uint256 _value) external  returns (bool);
}

interface IRewards {
    function stake(uint256 amount) external;
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns(bool);
}

interface IAddressFactory {
    function operators(address operator) external returns(bool);
}

contract ProxyAddress {
    address public owner;
    //address public operator;
    mapping(address => mapping(address => uint256)) public allowed;

    bytes4 constant SIG_BALANCEOF = 0x70a08231;     // balanceOf(address account)
    bytes4 constant SIG_TRANSFER = 0xa9059cbb;      // transfer(address recipient, uint256 amount)
    bytes4 constant SIG_APPROVE = 0x095ea7b3;       // approve(address,uint256)

    constructor() {
        owner = msg.sender;
    }

    function deposit(address depositAddress, address token, uint256 amount) public returns(bool) {
        bool ok = IAddressFactory(owner).operators(msg.sender);
        require(ok, "author fail.");
        uint256 _allowe = allowed[token][depositAddress];
        if (_allowe < amount) {
            //IERC20(token).approve(depositAddress, type(uint256).max);
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SIG_APPROVE, depositAddress, type(uint256).max));
            require(success && (data.length == 0 || abi.decode(data, (bool))), "cvx deposit rewards: approve failed");
            allowed[token][depositAddress] = type(uint256).max;
        }
        IRewards(depositAddress).stake(amount);
        allowed[token][depositAddress] = allowed[token][depositAddress] - amount;
        return true;
    }

    function unstake(address unstakeAddress, uint256 amount, bool claim, address token, address[8] memory rewardTokens, address reciever) public returns(uint256) {
        bool ok = IAddressFactory(owner).operators(msg.sender);
        require(ok, "author fail.");
        uint256 oldBalance = IERC20(token).balanceOf(address(this));
        IRewards(unstakeAddress).withdrawAndUnwrap(amount, claim);
        uint256 newBalance = IERC20(token).balanceOf(address(this));
        uint256 unstakeAmount = newBalance - oldBalance;
        IERC20(token).transfer(msg.sender, unstakeAmount);
        if (claim) {
            for(uint i=0; i < rewardTokens.length; i++) {
                if (rewardTokens[i] == address(0x0)) {
                    break;
                }
                (bool success, bytes memory data) = rewardTokens[i].call(abi.encodeWithSelector(SIG_BALANCEOF, address(this)));
                require(success && (data.length == 32), "get reward token balanceOf failed.");
                uint256 rewardBalance = abi.decode(data, (uint256));
                if (rewardBalance > 0) {
                    (bool tranferSuccess, bytes memory transferData) = rewardTokens[i].call(abi.encodeWithSelector(SIG_TRANSFER, reciever, rewardBalance));
                    require(tranferSuccess && (transferData.length == 0 || abi.decode(transferData, (bool))), "reward token transfer failed");
                }
            }
        }
        return amount;
    }

    function withdraw(address token, address reciever, uint256 amount) public returns (bool) {
        require(msg.sender == owner, "author fail.");
        (bool success, ) = token.call(abi.encodeWithSelector(SIG_TRANSFER, reciever, amount));
        return success;
    }
}

interface IProxyAddress {
    function withdraw(address token, address reciever, uint256 amount) external returns (bool);
}

contract AddressFactory {
    address public owner;
    mapping(address => bool) public operators;
    mapping(address => address) public proxyAddresses;

    event NewProxyAddress(address indexed _native, address indexed _proxy);

    constructor() {
        owner = msg.sender;
    }

    function setOperator(address operator, bool ok) public returns (bool) {
        require(msg.sender == owner, "author fail.");
        operators[operator] = ok;
        return true;
    }

    function _newProxyAddress() private returns (address) {
        require(operators[msg.sender], "author fail.");
        ProxyAddress proxyAddress = new ProxyAddress();
        return address(proxyAddress);
    }

    function getProxyAddress(address account) public returns(address) {
        require(operators[msg.sender], "author fail.");
        address proxyAddress = proxyAddresses[account];
        if (proxyAddress == address(0x0)) {
            proxyAddress = _newProxyAddress();
            proxyAddresses[account] = proxyAddress;
            emit NewProxyAddress(account, proxyAddress);
        }
        return proxyAddress;
    }

    function resetProxyAddress(address account) public returns(bool) {
        require(msg.sender == owner, "author fail.");
        proxyAddresses[account] = address(0x0);
        emit NewProxyAddress(account, proxyAddresses[account]);
        return true;
    }

    function withdrawFor(address proxyAddress, address token, address reciever, uint256 amount) public returns (bool) {
        require(msg.sender == owner, "author fail.");
        return IProxyAddress(proxyAddress).withdraw(token, reciever, amount);
    }
}
