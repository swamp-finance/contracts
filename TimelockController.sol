/**
 *Submitted for verification at BscScan.com on 2021-01-09
*/

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;


import "./interfaces/IERC20.sol";

import "./libraries/SafeERC20.sol";

import "./helpers/AccessControl.sol";

import "./helpers/ReentrancyGuard.sol";

/**
 * @dev NativeFarm functions that do not require less than the min timelock
 */
interface INativeFarm {
    function add(
        uint256 _allocPoint,
        address _want,
        bool _withUpdate,
        address _strat
    ) external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;
}

/**
 * @dev Strategy functions that do not require timelock or have a timelock less than the min timelock
 */
interface IStrategy {
    // Main want token compounding function
    function earn() external;

    function farm() external;

    function pause() external;

    function unpause() external;

    function rebalance(uint256 _borrowRate, uint256 _borrowDepth) external;

    function deleverageOnce() external; 

    function wrapBNB() external; // Specifically for the Venus WBNB vault.

    // In case new vaults require functions without a timelock as well, hoping to avoid having multiple timelock contracts
    function noTimeLockFunc1() external;

    function noTimeLockFunc2() external;

    function noTimeLockFunc3() external;
}

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/TimelockController.sol";
/**
 * @dev Contract module which acts as a timelocked controller. When set as the
 * owner of an `Ownable` smart contract, it enforces a timelock on all
 * `onlyOwner` maintenance operations. This gives time for users of the
 * controlled contract to exit before a potentially dangerous maintenance
 * operation is applied.
 *
 * By default, this contract is self administered, meaning administration tasks
 * have to go through the timelock process. The proposer (resp executor) role
 * is in charge of proposing (resp executing) operations. A common use case is
 * to position this {TimelockController} as the owner of a smart contract, with
 * a multisig or a DAO as the sole proposer.
 *
 * _Available since v3.3._
 */
contract TimelockController is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant TIMELOCK_ADMIN_ROLE =
        keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    uint256 internal constant _DONE_TIMESTAMP = uint256(1);

    mapping(bytes32 => uint256) private _timestamps;
    uint256 public minDelay = 60; // seconds - to be increased in production
    uint256 public minDelayReduced = 30; // seconds - to be increased in production

    address payable public devWalletAddress = 0xa9eb7Ad908107e13757CA837435EC713Fb55589B;
    /**
     * @dev Emitted when a call is scheduled as part of operation `id`.
     */
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    /**
     * @dev Emitted when a call is scheduled as part of operation `id`.
     */
    event SetScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate,
        bytes32 predecessor,
        uint256 delay
    );

    /**
     * @dev Emitted when a call is performed as part of operation `id`.
     */
    event CallExecuted(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data
    );

    /**
     * @dev Emitted when operation `id` is cancelled.
     */
    event Cancelled(bytes32 indexed id);

    /**
     * @dev Emitted when the minimum delay for future operations is modified.
     */
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    event MinDelayReducedChange(uint256 oldDuration, uint256 newDuration);

    event SetScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    /**
     * @dev Initializes the contract with a given `minDelay`.
     */
    constructor()
        public
    // address[] memory proposers, address[] memory executors
    {
        _setRoleAdmin(TIMELOCK_ADMIN_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(PROPOSER_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(EXECUTOR_ROLE, TIMELOCK_ADMIN_ROLE);

        // deployer + self administration
        _setupRole(TIMELOCK_ADMIN_ROLE, _msgSender());
        _setupRole(TIMELOCK_ADMIN_ROLE, address(this));

        // register proposers
        // for (uint256 i = 0; i < proposers.length; ++i) {
        //     _setupRole(PROPOSER_ROLE, proposers[i]);
        // }
        _setupRole(PROPOSER_ROLE, devWalletAddress);

        // // register executors
        // for (uint256 i = 0; i < executors.length; ++i) {
        //     _setupRole(EXECUTOR_ROLE, executors[i]);
        // }
        _setupRole(EXECUTOR_ROLE, devWalletAddress);

        emit MinDelayChange(0, minDelay);
    }

    /**
     * @dev Modifier to make a function callable only by a certain role. In
     * addition to checking the sender's role, `address(0)` 's role is also
     * considered. Granting a role to `address(0)` is equivalent to enabling
     * this role for everyone.
     */
    modifier onlyRole(bytes32 role) {
        require(
            hasRole(role, _msgSender()) || hasRole(role, address(0)),
            "TimelockController: sender requires permission"
        );
        _;
    }

    /**
     * @dev Contract might receive/hold ETH as part of the maintenance process.
     */
    receive() external payable {}

    /**
     * @dev Returns whether an operation is pending or not.
     */
    function isOperationPending(bytes32 id) public view returns (bool pending) {
        return _timestamps[id] > _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns whether an operation is ready or not.
     */
    function isOperationReady(bytes32 id) public view returns (bool ready) {
        // solhint-disable-next-line not-rely-on-time
        return
            _timestamps[id] > _DONE_TIMESTAMP &&
            _timestamps[id] <= block.timestamp;
    }

    /**
     * @dev Returns whether an operation is done or not.
     */
    function isOperationDone(bytes32 id) public view returns (bool done) {
        return _timestamps[id] == _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns the timestamp at with an operation becomes ready (0 for
     * unset operations, 1 for done operations).
     */
    function getTimestamp(bytes32 id) public view returns (uint256 timestamp) {
        return _timestamps[id];
    }

    /**
     * @dev Returns the minimum delay for an operation to become valid.
     *
     * This value can be changed by executing an operation that calls `updateDelay`.
     */
    function getMinDelay() public view returns (uint256 duration) {
        return minDelay;
    }

    /**
     * @dev Returns the identifier of an operation containing a single
     * transaction.
     */
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32 hash) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    /**
     * @dev Returns the identifier of an operation containing a batch of
     * transactions.
     */
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32 hash) {
        return keccak256(abi.encode(targets, values, datas, predecessor, salt));
    }

    /**
     * @dev Schedule an operation containing a single transaction.
     *
     * Emits a {CallScheduled} event.
     *
     * Requirements:
     *
     * - the caller must have the 'proposer' role.
     */
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyRole(PROPOSER_ROLE) {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _schedule(id, delay);
        emit CallScheduled(id, 0, target, value, data, predecessor, delay);
    }

    /**
     * @dev Schedule an operation containing a batch of transactions.
     *
     * Emits one {CallScheduled} event per transaction in the batch.
     *
     * Requirements:
     *
     * - the caller must have the 'proposer' role.
     */
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyRole(PROPOSER_ROLE) {
        require(
            targets.length == values.length,
            "TimelockController: length mismatch"
        );
        require(
            targets.length == datas.length,
            "TimelockController: length mismatch"
        );

        bytes32 id =
            hashOperationBatch(targets, values, datas, predecessor, salt);
        _schedule(id, delay);
        for (uint256 i = 0; i < targets.length; ++i) {
            emit CallScheduled(
                id,
                i,
                targets[i],
                values[i],
                datas[i],
                predecessor,
                delay
            );
        }
    }

    /**
     * @dev Schedule an operation that is to becomes valid after a given delay.
     */
    function _schedule(bytes32 id, uint256 delay) private {
        require(
            _timestamps[id] == 0,
            "TimelockController: operation already scheduled"
        );
        require(delay >= minDelay, "TimelockController: insufficient delay");
        // solhint-disable-next-line not-rely-on-time
        _timestamps[id] = SafeMath.add(block.timestamp, delay);
    }

    /**
     * @dev Cancel an operation.
     *
     * Requirements:
     *
     * - the caller must have the 'proposer' role.
     */
    function cancel(bytes32 id) public virtual onlyRole(PROPOSER_ROLE) {
        require(
            isOperationPending(id),
            "TimelockController: operation cannot be cancelled"
        );
        delete _timestamps[id];

        emit Cancelled(id);
    }

    /**
     * @dev Execute an (ready) operation containing a single transaction.
     *
     * Emits a {CallExecuted} event.
     *
     * Requirements:
     *
     * - the caller must have the 'executor' role.
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRole(EXECUTOR_ROLE) nonReentrant {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _beforeCall(predecessor);
        _call(id, 0, target, value, data);
        _afterCall(id);
    }

    /**
     * @dev Execute an (ready) operation containing a batch of transactions.
     *
     * Emits one {CallExecuted} event per transaction in the batch.
     *
     * Requirements:
     *
     * - the caller must have the 'executor' role.
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRole(EXECUTOR_ROLE) nonReentrant {
        require(
            targets.length == values.length,
            "TimelockController: length mismatch"
        );
        require(
            targets.length == datas.length,
            "TimelockController: length mismatch"
        );

        bytes32 id =
            hashOperationBatch(targets, values, datas, predecessor, salt);
        _beforeCall(predecessor);
        for (uint256 i = 0; i < targets.length; ++i) {
            _call(id, i, targets[i], values[i], datas[i]);
        }
        _afterCall(id);
    }

    /**
     * @dev Checks before execution of an operation's calls.
     */
    function _beforeCall(bytes32 predecessor) private view {
        require(
            predecessor == bytes32(0) || isOperationDone(predecessor),
            "TimelockController: missing dependency"
        );
    }

    /**
     * @dev Checks after execution of an operation's calls.
     */
    function _afterCall(bytes32 id) private {
        require(
            isOperationReady(id),
            "TimelockController: operation is not ready"
        );
        _timestamps[id] = _DONE_TIMESTAMP;
    }

    /**
     * @dev Execute an operation's call.
     *
     * Emits a {CallExecuted} event.
     */
    function _call(
        bytes32 id,
        uint256 index,
        address target,
        uint256 value,
        bytes calldata data
    ) private {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = target.call{value: value}(data);
        require(success, "TimelockController: underlying transaction reverted");

        emit CallExecuted(id, index, target, value, data);
    }

    /**
     * @dev Changes the minimum timelock duration for future operations.
     *
     * Emits a {MinDelayChange} event.
     *
     * Requirements:
     *
     * - the caller must be the timelock itself. This can only be achieved by scheduling and later executing
     * an operation where the timelock is the target and the data is the ABI-encoded call to this function.
     */
    function updateMinDelay(uint256 newDelay) external virtual {
        require(msg.sender == address(this), "TimelockController: caller must be timelock");
        emit MinDelayChange(minDelay, newDelay);
        minDelay = newDelay;
    }

    function updateMinDelayReduced(uint256 newDelay) external virtual {
        require(msg.sender == address(this), "TimelockController: caller must be timelock");
        emit MinDelayReducedChange(minDelayReduced, newDelay);
        minDelayReduced = newDelay;
    }

    function setDevWalletAddress(address payable _devWalletAddress) public {
        require(msg.sender == address(this), "TimelockController: caller must be timelock");
        require(tx.origin == devWalletAddress, "tx.origin != devWalletAddress");
        require(_devWalletAddress != address(0), "_devWalletAddress can not be zero address");
        devWalletAddress = _devWalletAddress;
    }

    /**
     * @dev Reduced timelock functions
     */
    function scheduleSet(
        address _nativefarmAddress,
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate,
        bytes32 predecessor,
        bytes32 salt
    ) public onlyRole(EXECUTOR_ROLE) {
        bytes32 id =
            keccak256(
                abi.encode(
                    _nativefarmAddress,
                    _pid,
                    _allocPoint,
                    _withUpdate,
                    predecessor,
                    salt
                )
            );

        require(
            _timestamps[id] == 0,
            "TimelockController: operation already scheduled"
        );

        _timestamps[id] = SafeMath.add(block.timestamp, minDelayReduced);
        emit SetScheduled(
            id,
            0,
            _pid,
            _allocPoint,
            _withUpdate,
            predecessor,
            minDelayReduced
        );
    }

    function executeSet(
        address _nativefarmAddress,
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRole(EXECUTOR_ROLE) nonReentrant {
        bytes32 id =
            keccak256(
                abi.encode(
                    _nativefarmAddress,
                    _pid,
                    _allocPoint,
                    _withUpdate,
                    predecessor,
                    salt
                )
            );

        _beforeCall(predecessor);
        INativeFarm(_nativefarmAddress).set(_pid, _allocPoint, _withUpdate);
        _afterCall(id);
    }

    /**
     * @dev No timelock functions
     */
    function withdrawBNB() public payable {
        require(msg.sender == devWalletAddress, "!devWalletAddress");
        devWalletAddress.transfer(address(this).balance);
    }

    function withdrawBEP20(address _tokenAddress) public payable {
        require(msg.sender == devWalletAddress, "!devWalletAddress");
        uint256 tokenBal = IERC20(_tokenAddress).balanceOf(address(this));
        IERC20(_tokenAddress).safeIncreaseAllowance(devWalletAddress, tokenBal);
        IERC20(_tokenAddress).transfer(devWalletAddress, tokenBal);
    }

    function add(
        address _nativefarmAddress,
        address _want,
        bool _withUpdate,
        address _strat
    ) public onlyRole(EXECUTOR_ROLE) {
        INativeFarm(_nativefarmAddress).add(0, _want, _withUpdate, _strat); // allocPoint = 0. Schedule set (timelocked) to increase allocPoint.
    }

    function earn(address _stratAddress) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_stratAddress).earn();
    }

    function farm(address _stratAddress) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_stratAddress).farm();
    }

    function pause(address _stratAddress) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_stratAddress).pause();
    }

    function unpause(address _stratAddress) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_stratAddress).unpause();
    }

    function rebalance(
        address _stratAddress,
        uint256 _borrowRate,
        uint256 _borrowDepth
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_stratAddress).rebalance(_borrowRate, _borrowDepth);
    }

    
    function deleverageOnce(address _stratAddress) public onlyRole(EXECUTOR_ROLE) nonReentrant {
        IStrategy(_stratAddress).deleverageOnce();
    }

    function wrapBNB(address _stratAddress) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_stratAddress).wrapBNB();
    }

    // // In case new vaults require functions without a timelock as well, hoping to avoid having multiple timelock contracts
    function noTimeLockFunc1(address _stratAddress)
        public
        onlyRole(EXECUTOR_ROLE)
    {
        IStrategy(_stratAddress).noTimeLockFunc1();
    }

    function noTimeLockFunc2(address _stratAddress)
        public
        onlyRole(EXECUTOR_ROLE)
    {
        IStrategy(_stratAddress).noTimeLockFunc2();
    }

    function noTimeLockFunc3(address _stratAddress)
        public
        onlyRole(EXECUTOR_ROLE)
    {
        IStrategy(_stratAddress).noTimeLockFunc3();
    }
}
