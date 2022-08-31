// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

// Chainlink Aggregator

interface IAggregator {
    function latestAnswer() external view returns (int256 answer);
}

interface ICurvePool {
    function get_virtual_price() external view returns (uint256 price);
}

contract CvxCvrFraxOracle {
    ICurvePool public constant FraxUSDC = ICurvePool(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2);
    IAggregator public constant FRAX = IAggregator(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);
    IAggregator public constant USDC = IAggregator(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

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
        uint256 minStable = min(uint256(FRAX.latestAnswer()), uint256(USDC.latestAnswer()));

        uint256 yVCurvePrice = FraxUSDC.get_virtual_price() * minStable;

        return yVCurvePrice / 1e8;
    }
}
