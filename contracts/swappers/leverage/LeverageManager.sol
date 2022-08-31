// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "../../maths/SafeMath.sol";
import "../../Owner.sol";

contract LeverageManager is Owner {
    using SafeMath for uint256;

    struct DepositInfo {
        uint256 tokenid; // 0 usda 1 dai 2 usdc 3 usdt 4 stable token e.g. frax,mim 5 cvxlp3crv e.g. cvxFrax3Crv,cvxMIM3CRV,cvxcrvFRAX
        uint256 margin;  // the latest lptoken amount. e.g. cvxFrax3CRV
        uint256 borrow;  // usda amount
        uint256 metaThreeCRVAmount; // deposit cvxlptoken amount e.g. cvxFrax3CRV
        uint interestTime; // start calc interest time
    }

    // 0 frax 1 mim 2 fraxusdc
    mapping(address => mapping(uint256 => DepositInfo)) public deposits; // address -> strategy -> DepositInfo
    mapping(uint256 => uint256) public thresholds; // usda threshold for every strategy  0 frax 1 mim 2 fraxusdc
    mapping(uint256 => uint256) public borrowed; // usda borrow out amount for every strategy  0 frax 1 mim 2 fraxusdc
    mapping(address => bool) public operators;

    constructor(uint256 remain0, uint256 remain1, uint256 remain2) {
        thresholds[0] = remain0;
        thresholds[1] = remain1;
        thresholds[2] = remain2;
    }

    function setOperator(address operator, bool state) public isOwner returns (bool) {
        operators[operator] = state;
        return true;
    }

    // strategy:  0 frax 1 mim 2 fraxusdc
    function setThreshold(uint256 strategy, uint256 threshold) public isOwner returns (bool) {
        thresholds[strategy] = threshold;
        return true;
    }

    function remain(uint256 strategy) public view returns (uint256) {
        return thresholds[strategy].sub(borrowed[strategy]);
    }

    function deposit(address depositor, uint256 strategy, DepositInfo memory info) public isUnlock returns (bool) {
        require(operators[msg.sender], "operator error.");
        require(deposits[depositor][strategy].margin == 0, "margin already exists.");
        deposits[depositor][strategy] = info;
        borrowed[strategy] = borrowed[strategy].add(info.borrow);
        return true;
    }

    function repay(address depositor, uint256 strategy, uint interestTime, uint256 amount) public isUnlock returns (bool) {
        require(operators[msg.sender], "operator error.");
        deposits[depositor][strategy].interestTime = interestTime;
        deposits[depositor][strategy].borrow = deposits[depositor][strategy].borrow.sub(amount);
        borrowed[strategy] = borrowed[strategy].sub(amount);
        return true;
    }

    function deleverage(address depositor, uint256 strategy) public isUnlock returns (bool) {
        require(operators[msg.sender], "operator error.");
        borrowed[strategy] = borrowed[strategy].sub(deposits[depositor][strategy].borrow);
        deposits[depositor][strategy].tokenid = 0;
        deposits[depositor][strategy].margin = 0;
        deposits[depositor][strategy].borrow = 0;
        deposits[depositor][strategy].metaThreeCRVAmount = 0;
        deposits[depositor][strategy].interestTime = 0;
        return true;
    }
}
