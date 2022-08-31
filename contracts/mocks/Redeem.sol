// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

contract RedeemMock  {
    
    struct RedeemInfo {
        address _id;
        uint8 _opType;
        uint _coll;
        uint _debt;
        uint _prevId;
        uint _nextId;
    }
    
    RedeemInfo public info;

    function setSort(address _id, uint8 _opType, uint _coll, uint _debt, uint _prevId, uint _nextId) public {
        info._id = _id;
        info._opType = _opType;
        info._coll = _coll;
        info._debt = _debt;
        info._prevId = _prevId;
        info._nextId = _nextId;
    } 
}
