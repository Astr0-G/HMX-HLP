// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libraries/math/SafeMath.sol";
import "./libraries/token/IERC20.sol";

contract HLP is IERC20 {
    using SafeMath for uint256;

    string public constant name = "HLP";
    string public constant symbol = "HLP";
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    address public gov;

    bool public maintenancestate = false;
    uint256 public migrationTime;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    mapping(address => bool) public admins;

    // only checked when maintenancestate is true
    // this can be used to block the AMM pair as a recipient
    // and protect liquidity providers during a migration
    // by disabling the selling of HLP
    mapping(address => bool) public blockedRecipients;

    // only checked when maintenancestate is true
    // this can be used for:
    // - only allowing tokens to be transferred by the distribution contract
    // during the initial distribution phase, this would prevent token buyers
    // from adding liquidity before the initial liquidity is seeded
    // - only allowing removal of HLP liquidity and no other actions
    // during the migration phase
    mapping(address => bool) public allowedMsgSenders;

    modifier onlyGov() {
        require(msg.sender == gov, "HLP: forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "HLP: forbidden");
        _;
    }

    constructor(uint256 _initialSupply) public {
        gov = msg.sender;
        admins[msg.sender] = true;
        _mint(msg.sender, _initialSupply);
    }

    function maintenance() external onlyAdmin {
        maintenancestate = !maintenancestate;
    }

    function addBlockedRecipient(address _recipient) external onlyGov {
        blockedRecipients[_recipient] = true;
    }

    function removeBlockedRecipient(address _recipient) external onlyGov {
        blockedRecipients[_recipient] = false;
    }

    function addMsgSender(address _msgSender) external onlyGov {
        allowedMsgSenders[_msgSender] = true;
    }

    function removeMsgSender(address _msgSender) external onlyGov {
        allowedMsgSenders[_msgSender] = false;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).transfer(_account, _amount);
    }

    function balanceOf(address _account)
        external
        view
        override
        returns (uint256)
    {
        return balances[_account];
    }

    function transfer(address _recipient, uint256 _amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender)
        external
        view
        override
        returns (uint256)
    {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external override returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(
            _amount,
            "HLP: transfer amount exceeds allowance"
        );
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        require(_sender != address(0), "HLP: transfer from the zero address");
        require(_recipient != address(0), "HLP: transfer to the zero address");

        if (maintenancestate) {
            require(allowedMsgSenders[msg.sender], "HLP: forbidden msg.sender");
            require(!blockedRecipients[_recipient], "HLP: forbidden recipient");
        }

        balances[_sender] = balances[_sender].sub(
            _amount,
            "HLP: transfer amount exceeds balance"
        );
        balances[_recipient] = balances[_recipient].add(_amount);

        emit Transfer(_sender, _recipient, _amount);
    }

    function _mint(address _account, uint256 _amount) public {
        require(_account != address(0), "HLP: mint to the zero address");

        totalSupply = totalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);

        emit Transfer(address(0), _account, _amount);
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(_owner != address(0), "HLP: approve from the zero address");
        require(_spender != address(0), "HLP: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }
}
