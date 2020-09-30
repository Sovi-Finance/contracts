pragma solidity 0.6.2;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract HopeSoviet is ERC20("Hope Soviet", "hSOV"), Ownable {
    uint256 transferRewardBase;
    uint256 maxReward;
    uint256 maxRewardCount;
    uint256 rewardEndBlock;
    uint256 rewardAmount;
    uint256 maxRefLevel;

    struct UserInfo {
        mapping(address => uint256) rewards;
        uint256 rewardCount;
        address[] invitees;
        address[] referrals;
    }

    mapping(address => UserInfo) public uInfo;
    mapping(address => address) public refMap;

    constructor(
    ) public {
        transferRewardBase = 100 * (10 ** uint256(decimals()));
        maxReward = 20000000 * (10 ** uint256(decimals()));
        maxRewardCount = 3;
        maxRefLevel = 12;
        _mint(msg.sender, 15000000 * (10 ** uint256(decimals())));
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner.
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if (ERC20.transfer(recipient, amount)) {
            sendReward(_msgSender(), recipient, amount);
            setRef(_msgSender(), recipient);
        }
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if (ERC20.transferFrom(sender, recipient, amount)) {
            sendReward(sender, recipient, amount);
            setRef(sender, recipient);
        }
        return true;
    }

    function setEnd(uint256 _rewardEndBlock) public onlyOwner {
        rewardEndBlock = _rewardEndBlock;
    }

    function addReferral(address _sender, address _recipient) public onlyOwner {
        setRef(_sender, _recipient);
    }

    function getReferrals(address _addr) public view returns (address[] memory){
        return uInfo[_addr].referrals;
    }

    function getInvitees(address _addr) public view returns (address[] memory){
        return uInfo[_addr].invitees;
    }

    function myArmy(address _addr) public view returns (uint256 totalCount, uint256 totalAmount) {
        return selectInvitees(_addr);
    }

    function selectInvitees(address _addr) internal view returns (uint256 totalCount, uint256 totalAmount) {
        address[] memory _invitees = uInfo[_addr].invitees;
        uint256 _total_count;
        uint256 _total_amount;
        for (uint256 idx; idx < _invitees.length; idx ++) {
            address u = _invitees[idx];
            _total_count += 1;
            _total_amount += balanceOf(u);
            if (uInfo[u].invitees.length > 0) {
                (uint256 _count, uint256 _amount) = selectInvitees(u);
                _total_count += _count;
                _total_amount += _amount;
            }
        }
        return (_total_count, _total_amount);
    }

    function sendReward(address sender, address recipient, uint256 amount) internal returns (bool){
        if ((rewardEndBlock > 0 && block.number >= rewardEndBlock) || rewardAmount >= maxReward) {
            return false;
        }
        if (amount < transferRewardBase || sender == recipient) {
            return false;
        }
        uint256 _rewardCount = uInfo[sender].rewardCount;
        if (_rewardCount >= maxRewardCount || uInfo[sender].rewards[recipient] > 0) {
            return false;
        }
        uint256 _reward = _rewardCount.add(2).mul(transferRewardBase);
        uint256 _remainReward = maxReward - rewardAmount;
        _reward = (_remainReward > _reward ? _reward : _remainReward);
        _mint(sender, _reward);
        uInfo[sender].rewards[recipient] = _reward;
        uInfo[sender].rewardCount += 1;
        rewardAmount += _reward;
        return true;
    }

    function setRef(address sender, address recipient) internal {
        if (refMap[recipient] != address(0) || uInfo[recipient].invitees.length > 0) {
            return;
        }
        uInfo[sender].invitees.push(recipient);
        refMap[recipient] = sender;
        address[] storage refs = uInfo[recipient].referrals;
        refs.push(sender);
        address _ref = sender;
        for (uint level; level < maxRefLevel; level ++) {
            _ref = refMap[_ref];
            if (_ref == address(0)) {
                return;
            }
            refs.push(_ref);
        }
    }
}
