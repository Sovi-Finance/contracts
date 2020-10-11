pragma solidity 0.6.2;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SovietToken.sol";
import "./BadgePool.sol";


interface IReferral {
    function getReferrals(address _addr) external view returns (address[] memory);

    function getInvitees(address _addr) external view returns (address[] memory);
}

// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SOV is sufficiently
// distributed and the community can show to govern itself.
contract Soviet is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 refReward;
        uint256 harvested;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. SOVs to distribute per block.
        uint256 lastRewardBlock;    // Last block number that SOVs distribution occurs.
        uint256 accRewardPerShare;   // Accumulated SOVs per share, times 1e18. See below.
        bool enableRefReward;
        uint256 totalAmount;
    }

    // The SOV TOKEN!
    SovietToken public SOV;
    IReferral public iRef;
    IBadgePool public badgePool;
    // Dev address.
    address public devaddr;
    // Block number when bonus SOV period ends.
    uint256 public bonusEndBlock;
    // SOV tokens created per block.
    uint256 public rewardPerBlock;
    uint256 public refRewards;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when SOV mining starts.
    uint256 public startBlock;
    // Reduction
    uint256 public reductionBlockCount;
    uint256 public maxReductionCount;
    uint256 public nextReductionBlock;
    uint256 public reductionCounter;
    uint256 public reductionPercent;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        SovietToken _SOV,
        address _devaddr,
        uint256 _startBlock,
        IReferral _iReferral
    ) public {
        SOV = _SOV;
        devaddr = _devaddr;
        startBlock = _startBlock;
        /*rewardPerBlock = 10;
        reductionBlockCount = 49000;
        maxReductionCount = 7;
        reductionPercent = 80;*/
        rewardPerBlock = 1000 * (10 ** uint256(_SOV.decimals()));
        reductionBlockCount = 10000;
        maxReductionCount = 7;
        reductionPercent = 80;
        bonusEndBlock = _startBlock + reductionBlockCount * maxReductionCount;
        nextReductionBlock = _startBlock + reductionBlockCount;
        iRef = _iReferral;
        badgePool = new BadgePool();
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP/BPT token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate, bool _enableRefReward) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accRewardPerShare : 0,
        enableRefReward : _enableRefReward,
        totalAmount : 0
        }));
    }

    // Update the given pool's SOV allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the badgePool contract. Can only be called by the owner.
    function setBadgePool(IBadgePool _badgePool) public onlyOwner {
        badgePool = _badgePool;
    }

    // Return reward multiplier over the given _from to _to block.
    function getBlocksReward(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_from >= bonusEndBlock) {
            return 0;
        }
        uint256 prevReductionBlock = nextReductionBlock - reductionBlockCount;
        _to = (_to > bonusEndBlock ? bonusEndBlock : _to);
        if (_from >= prevReductionBlock && _to <= nextReductionBlock)
        {
            return getBlockReward(_to - _from, rewardPerBlock, reductionCounter);
        }
        else if (_from < prevReductionBlock && _to < nextReductionBlock)
        {
            uint256 part1 = getBlockReward(_to - prevReductionBlock, rewardPerBlock, reductionCounter);
            uint256 part2 = getBlockReward(prevReductionBlock - _from, rewardPerBlock, reductionCounter - 1);
            return part1 + part2;
        }
        else
        {
            uint256 part1 = getBlockReward(_to - nextReductionBlock, rewardPerBlock, reductionCounter + 1);
            uint256 part2 = getBlockReward(nextReductionBlock - _from, rewardPerBlock, reductionCounter);
            return part1 + part2;
        }
    }

    // Return reward per block
    function getBlockReward(uint256 _blockCount, uint256 _rewardPerBlock, uint256 _reductionCounter) internal view returns (uint256) {
        uint256 _reward = _blockCount * _rewardPerBlock;
        if (_reductionCounter == 0) {
            return _reward;
        }
        return _reward * (reductionPercent ** _reductionCounter) / (100 ** _reductionCounter);
    }

    // View function to see pending SOVs on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256, uint256, uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.totalAmount;
        uint256 blockReward;
        uint256 poolReward;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            blockReward = getBlocksReward(pool.lastRewardBlock, block.number);
            poolReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(poolReward.mul(1e18).div(lpSupply));
        }
        return (user.amount.mul(accRewardPerShare).div(1e18).add(user.refReward).sub(user.rewardDebt), user.harvested, user.refReward);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (block.number > nextReductionBlock) {
            nextReductionBlock += reductionBlockCount;
            reductionCounter += 1;
        }
        uint256 lpSupply = pool.totalAmount;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockReward = getBlocksReward(pool.lastRewardBlock, block.number);
        uint256 poolReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        uint256 extraReward = poolReward.div(10);
        SOV.mint(devaddr, extraReward);
        // Extra 10% rebate
        SOV.mint(address(this), poolReward.add(extraReward));
        pool.accRewardPerShare = pool.accRewardPerShare.add(poolReward.mul(1e18).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Update referral reward when pool.enableRefWard is true
    function updateRefReward(address _addr, uint256 _reward, uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (!pool.enableRefReward) {
            return;
        }
        address[] memory refs = iRef.getReferrals(_addr);
        if (refs.length == 0) {
            return;
        }
        uint256 ref0Reward = _reward.div(10).div(2);
        userInfo[_pid][refs[0]].refReward += ref0Reward;
        if (refs.length > 1) {
            uint256 refnReward = ref0Reward.div(refs.length - 1);
            for (uint256 idx = 1; idx < refs.length; idx ++) {
                userInfo[_pid][refs[idx]].refReward += refnReward;
            }
        }
    }

    function harvest(address _addr, uint256 _amount, uint256 _pid) internal {
        safeTokenTransfer(_addr, _amount);
        userInfo[_pid][msg.sender].harvested = userInfo[_pid][msg.sender].harvested.add(_amount);
        updateRefReward(_addr, _amount, _pid);
        uint256 _miningRatePercent = badgePool.miningRate(_addr);
        if (_miningRatePercent > 100) {
            SOV.mint(_addr, _amount.mul(_miningRatePercent).div(100));
        }
    }

    // Deposit BPT/LP tokens to Soviet for SOV allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0 || user.refReward > 0) {
            uint256 pending = totalReward(pool, user).sub(user.rewardDebt);
            if (pending > 0) {
                harvest(msg.sender, pending, _pid);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
        }
        user.rewardDebt = totalReward(pool, user);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw BPT/LP tokens from Soviet.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = totalReward(pool, user).sub(user.rewardDebt);
        if (pending > 0) {
            harvest(msg.sender, pending, _pid);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = totalReward(pool, user).add(user.refReward);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function totalReward(PoolInfo storage _pool, UserInfo storage _user) internal returns (uint256){
        return _user.amount.mul(_pool.accRewardPerShare).div(1e18).add(_user.refReward);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.refReward = 0;
    }

    // Safe SOV transfer function, just in case if rounding error causes pool to not have enough SOVs.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 bal = SOV.balanceOf(address(this));
        if (_amount > bal) {
            SOV.transfer(_to, bal);
        } else {
            SOV.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
