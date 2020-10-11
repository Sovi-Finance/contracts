pragma solidity 0.6.2;

interface IBadgePool {
    // Return mining rate percent
    function miningRate(address _addr) external returns (uint256 rate);
}

contract BadgePool is IBadgePool {
    function miningRate(address _addr) external override returns (uint256 rate){
        return 100;
    }
}
