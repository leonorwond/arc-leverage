// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

// Chainlink Aggregator

interface IAggregator {
    function latestAnswer() external view returns (int256 answer);
}

interface ICurvePool {
    function get_virtual_price() external view returns (uint256 price);
}

contract Frax3CrvOracle {
    ICurvePool public frax3crv = ICurvePool(0x2f21328E188cCd4eab5dd6Fd2b0A2B75b99dD768); // 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B 0x687c5e0951F84100A2114D8265763d53858B755b
    IAggregator public FRAX = IAggregator(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);   // 100006858
    IAggregator public DAI = IAggregator(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);    // 100054748
    IAggregator public USDC = IAggregator(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);   // 100024509
    IAggregator public USDT = IAggregator(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D);   // 100005929
    
    /**
     * @dev Returns the smallest of two numbers.
     */
    // FROM: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/6d97f0919547df11be9443b54af2d90631eaa733/contracts/utils/math/Math.sol
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // Calculates the lastest exchange rate
    // Uses both divide and multiply only for tokens not supported directly by Chainlink, for example MKR/USD
    function get() public view returns (uint256) {
        // As the price should never be negative, the unchecked conversion is acceptable
        /*uint256 minStable = min(
            uint256(DAI.latestAnswer()),
            min(uint256(USDC.latestAnswer()), min(uint256(USDT.latestAnswer()), uint256(FRAX.latestAnswer())))
        );*/
        uint256 minStable = min(
            uint256(100054748),
            min(uint256(100024509), min(uint256(100005929), uint256(100006858)))
        );

        uint256 yVCurvePrice = frax3crv.get_virtual_price() * minStable;

        return yVCurvePrice / 1e8;
    }
}
