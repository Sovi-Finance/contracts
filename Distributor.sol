pragma solidity 0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HopeSoviet.sol";


contract Distributor is Ownable {
    struct PoolInfo {
        IERC20 token;
        uint256 claimAmt;
    }

    struct ClaimInfo {
        bool claimed;
        uint256 claimedAmt;
    }

    uint256 maxReward;
    uint256 claimedAmount;
    uint256 rewardEndBlock;
    uint256 inviteReward;
    HopeSoviet internal hSOV;
    PoolInfo[] internal pool;
    mapping(address => bool) internal isClaimed;

    constructor(
        HopeSoviet _hSOV
    ) public {
        hSOV = _hSOV;
        maxReward = 10000000 * (10 ** uint256(_hSOV.decimals()));
        inviteReward = 100 * (10 ** uint256(_hSOV.decimals()));
    }

    function add(IERC20 _token, uint256 _claimAmt) public onlyOwner {
        pool.push(PoolInfo({
        token : _token,
        claimAmt : _claimAmt
        }));
    }

    function update(uint256 _pid, uint256 _claimAmt) public onlyOwner {
        pool[_pid].claimAmt = _claimAmt;
    }

    function setEnd(uint256 _rewardEndBlock) public onlyOwner {
        rewardEndBlock = _rewardEndBlock;
        hSOV.setEnd(_rewardEndBlock);
    }

    function check() public view returns (bool, uint256){
        if (isClaimed[msg.sender]) {
            return (false, 0);
        }
        for (uint256 pid = 0; pid < pool.length; pid++) {
            uint256 bal = pool[pid].token.balanceOf(msg.sender);
            if (bal > 0) {
                return (true, pid);
            }
        }
        return (false, 0);
    }

    function claim(address inviter) public {
        require(claimedAmount < maxReward, 'SOVIET: No ration left, comrade!');
        require(rewardEndBlock == 0 || (rewardEndBlock > 0 && block.number < rewardEndBlock), 'SOVIET: You missed out, comrade!');
        (bool isPass, uint256 pid) = check();
        require(isPass, 'SOVIET: Leave it to those in need, comrade!');

        uint256 _claimReward = pool[pid].claimAmt;
        if (inviter != msg.sender && inviter != address(0)) {
            sendReward(inviter, inviteReward);
            _claimReward += inviteReward;
            hSOV.addReferral(inviter, msg.sender);
        }
        sendReward(msg.sender, _claimReward);
        isClaimed[msg.sender] = true;
    }

    function sendReward(address _addr, uint256 _rewardAmt) internal {
        uint256 remainReward = maxReward - claimedAmount;
        uint256 _reward = _rewardAmt <= remainReward ? _rewardAmt : remainReward;
        hSOV.mint(_addr, _reward);
        claimedAmount += _reward;
    }
}
