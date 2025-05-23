//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainlinkOracle} from "./ChainlinkOracle.sol";
import "hardhat/console.sol";
/**
 * @title MultiSig Wallet Assignment
 * @notice A contract to handle multi signature wallet transactions, with upto 25 owners. 
 */
contract MultiSigWallet is UUPSUpgradeable, OwnableUpgradeable {

    /// @dev Struct to store transaction details
    struct Transaction {
        address payable to;
        uint256 value;
        bool executed;
        uint256 approvalCount;
        bool transfersToken;
    }

    uint256 public approvalsRequired;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 private constant MAX_OWNER_COUNT = 25;
    ///TODO: add comments for state declarations as wel.
    mapping(uint256 => Transaction) private transactions;
    mapping(uint256 => mapping(address => bool)) private approval;
    mapping(address => bool) private isOwner;
    uint256[] private readyToExecute;
    uint256 private transactionsCount;
    address[] private _owners;
    IERC20 token;
    ChainlinkOracle linkVRF;
    address owner;
    /**
     * @notice emitted when a new owner is added
     * @param owner : Address of new owner
     */
    event OwnerAdded(address indexed owner);
    
    /**
     * @notice emitted when a requirement is changed
     * @param required : New requirement
     */
    event RequirementChanged(uint required);

    /**
     * @notice emitted when a Approval is revoked by approved owner
     * @param owner : Approved owner who revoke his approval
     * @param txId : Id of transaction whose approval is revoked
     */
    event ApprovalRevoked(address indexed owner, uint256 indexed txId);

    /**
     * @notice emitted when a transaction is submitted by approved owner
     * @param owner : Approved owner who submit the transaction
     * @param txId : Id of submitted transaction
     */
    event TransactionSubmitted(address indexed owner, uint256 indexed txId);

    /**
     * @notice emitted when a transaction is approved by owner
     * @param owner : Owner address who appprove the transaction
     * @param txId : Id of transaction  which gets the approval
     */
    event TransactionApproved(address indexed owner, uint256 indexed txId);

    /**
     * @notice emitted when a transaction is emitted
     * @param owner : Address of executing user
     * @param txId : Id of transaction which is executed
     * @param to : reciever's address
     * @param value : amount that is transfered
     */
    event TransactionExecuted(
        address indexed owner,
        uint256 indexed txId,
        address to,
        uint256 value
    );

    /**
     * @notice reverted when sender is not wallet
     */
    error MultiSigWalletSenderNotWallet();
    /**
     * @notice reverted when there is an invalid owner
     */
    error MultiSigWalletInvalidOwner();

    /**
     * @notice reverted when there is an invalid requirement
     */
    error MultiSigWalletInvalidRequirement();

    /**
     * @notice reverted when amount is zero
     */
    error MultiSigWalletAmountZero();

    /**
     * @notice reverted when owner is already added
     */
    error MultiSigWalletApprovedOwner();

    /**
     * @notice reverted when sender is not owner
     */
    error MultiSigWalletSenderNotOwner();

    /**
     * @notice reverted when transaction is already executed
     */
    error MultiSigWalletTransactionAlreadyExecuted();

    /**
     * @notice reverted when address is invalid
     */
    error MultiSigWalletInvalidAddress();

    /**
     * @notice reverted when transaction is invalid
     */
    error MultiSigWalletInvalidTransaction();

    /**
     * @notice reverted when transaction is not approved by sender
     */
    error MultiSigWalletTransactionNotApprovedBySender();

    /**
     * @notice reverted when there is no transaction to execute
     */
    error MultiSigWalletNoPendingTransaction();


    modifier onlyWallet() {
        if (msg.sender != address(this))
            revert MultiSigWalletSenderNotWallet();
        _;
    }

    modifier onlyOwners() {
        if(!isOwner[msg.sender])
            revert MultiSigWalletSenderNotOwner();
        _;
    }

    modifier notOwner(address _address) {
        if(isOwner[_address])
            revert MultiSigWalletApprovedOwner();
        _;
    }

    modifier notZero(uint256 _value) {
        if (_value == 0)
            revert MultiSigWalletAmountZero();
        _;
    }

    modifier notNull(address _address) {
        if (_address == address(0))
            revert MultiSigWalletInvalidAddress();
        _;
    }

    modifier validRequirements(uint ownerCount, uint _required) {
        if (   ownerCount > MAX_OWNER_COUNT
            || _required > ownerCount
            || _required == 0
            || ownerCount == 0)
            revert MultiSigWalletInvalidRequirement();
        _;
    }

    constructor() {
        // __Ownable_init(msg.);
    }

    /**
     * @notice sets value of approvals count and contract owner
     * @param _approvalsRequired : number of approvals required to execute a transaction
     */
    function initialize(
        address[] memory owners,
        uint256 _approvalsRequired,
        address _token,
        address chainLinkOracle
        // uint256 _maxOwnerCount
    ) external validRequirements(owners.length, _approvalsRequired) initializer {
        /// DOS ATTACK: OWners can be of any count. Figure this out
        for (uint i; i<owners.length; ++i) {
            if (isOwner[owners[i]] || owners[i] == address(0))
                revert MultiSigWalletInvalidOwner();
            isOwner[owners[i]] = true;
            _owners.push(owners[i]);
        }
        approvalsRequired = _approvalsRequired;
        token = IERC20(_token);
        linkVRF = ChainlinkOracle(chainLinkOracle);
        /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
        // MAX_OWNER_COUNT = _max OwnerCount;
    }

    /**
     * @notice Fallback function to recieve ether
     */
    receive() external payable {}


    /**
     * @notice allow approved owners to submit transactions
     * @dev    Only approved owner can submit a transaction
     *         Reciever's address should not be invalid
     * @param _to : reciever address
     * @param _value : amount to transfer
     * Emit a {TransactionSubmitted} event
     */
    function submitTransaction(
        address payable _to,
        uint256 _value,
        bool _isTokenTransfer
    ) external onlyOwners notNull(_to) notZero(_value){
        uint256 txId = ++transactionsCount;
        transactions[txId] = Transaction(
            _to,
            _value,
            false,
            1,
            _isTokenTransfer
        );
        approval[txId][msg.sender] = true;
        emit TransactionSubmitted(msg.sender, txId);
    }

    /**
     * @notice owners can randomly approve a transaction
     * @dev    Only approved owners can approve a transaction
     *         Transaction to approve must exist
     *         Transaction to approve must not have executed
     *         Owner must not have approved the same transaction before
     * Emit a {TransactionApproved} Event
     */
    function approveTransaction() external onlyOwners {
        uint256 _size = transactionsCount;
        uint256 _txId = _generateRandomNumber(_size);
        // console.log(_txId);
        transactionExists(_txId);
        isTxExecuted(_txId);
        approval[_txId][msg.sender] = true;
        transactions[_txId].approvalCount += 1;
        if (transactions[_txId].approvalCount == approvalsRequired) {
            readyToExecute.push(_txId);
        }
        emit TransactionApproved(msg.sender, _txId);
    }

    /**
     * @notice owners can revoke their approval on a transaction
     * @dev     Only approved onwer can revoke transaction
     *          Transaction from which approval has to be revoke must exist
     *          Transaction must not have executed
     *          Transaction need to be approved before revoking its approval by the owner
     * Emit a {ApprovalRevoked} event
     */
    function revokeApproval() external onlyOwners{
        uint256 _size = readyToExecute.length;
        uint256 _txId = _generateRandomNumber(_size);
        transactionExists(_txId);
        isTxExecuted(_txId);

        if(!approval[_txId][msg.sender]) {
            revert MultiSigWalletTransactionNotApprovedBySender();
        }
        approval[_txId][msg.sender] = false;
        transactions[_txId].approvalCount -= 1;
        if (transactions[_txId].approvalCount == approvalsRequired - 1) {
            _removeFromReadyToExecute(_txId);
        }
        emit ApprovalRevoked(msg.sender, _txId);
    }

    /**
     * @notice anyone can randomly execute a transaction when it has recieved enough approval
     * @dev    Atleast one transaction must be ready to execute
     * Emits a {Transaction} evenExecutedt
     */
    function executeTransaction() external payable {
        console.log("executeTransaction entered");
        uint256 size = readyToExecute.length;
        checkPendingTransactions(size);
        uint256 randomNumber = _generateRandomNumber(size);
        console.log("randomGenerated");
        uint256 _txId = readyToExecute[randomNumber];
        transactionExists(_txId);
        isTxExecuted(_txId);
        address payable _to = transactions[_txId].to;
        uint256 _value = transactions[_txId].value;
        if (transactions[_txId].transfersToken == true) {
            token.transferFrom(msg.sender, _to, _value);
        } else {
            _to.transfer(_value);
        }
        transactions[_txId].executed = true;
        _removeFromReadyToExecute(_txId);
        emit TransactionExecuted(msg.sender, _txId, _to, _value);
    }

    /**
     * @notice Approved owners can execute all the transaction that are ready to execute
     * @dev    Only Approved owners can execute batch Execute transactions
     *         Atleast one transaction should have required approval
     * Emits {Transaction} evenExecutedt
     */
    function batchTransaction() external payable onlyOwners {
        uint256 size = readyToExecute.length;
        checkPendingTransactions(size);
        for (uint256 i = 0; i < size; i++) {
            uint256 _txId = readyToExecute[i];
            address payable _to = transactions[_txId].to;
            uint256 _value = transactions[_txId].value;
            if (transactions[_txId].transfersToken == true) {
                token.transferFrom(msg.sender, _to, _value);
            } else {
                _to.transfer(_value);
            }
            transactions[_txId].executed = true;
            emit TransactionExecuted(msg.sender, _txId, _to, _value);
        }
        delete readyToExecute;
    }

    /**
     * @notice Approved owners can add other owner
     * @dev    Only Wallet can add others as owner
     *         User address passed should not be invalid
     *         Address to be added as owner must not already be a owner
     * @param _address : address to be added as owner
     */
    function addOwner(
        address _address
    ) external onlyWallet notNull(_address) notOwner(_address) {
        isOwner[_address] = true;
        emit OwnerAdded(_address);
    }

    /**
    * @notice Allows to change the number of required approvals.
    * @dev Transaction has to be sent by wallet.
    * @param _required Number of required approvals.
    */
    function changeRequirement(uint _required)
        public
        onlyWallet
        validRequirements(_owners.length, _required)
    {
        approvalsRequired = _required;
        emit RequirementChanged(_required);
    }

    /**
     * @notice getter function to get number of approval on a transaction
     * @dev    Transaction whose approval is needed must exist
     * @param _txId : Id of transaction whose approval count is needed
     * @return number of approval on a transaction
     */
    function getTransactionApprovalCount(
        uint256 _txId
    ) public view returns (uint256) {
        transactionExists(_txId);
        return transactions[_txId].approvalCount;
    }

    /**
     * @notice getter function to get number of transaction that are ready to execute
     * @return Transactions ready to execute
     */
    function readyTransactionCount() public view returns (uint256){
        return readyToExecute.length;
    }

    /**
     * @notice reverts if the transaction is invalid
     * @param _txId : ID of transaction to check for
     */
    function transactionExists(uint256 _txId) internal view{
        if ( transactions[_txId].to == address(0))
            revert MultiSigWalletInvalidTransaction();
    }

    /**
     * @notice reverts if the transaction is already executed
     * @param _txId : ID of transaction to check for
     */
    function isTxExecuted(uint256 _txId) internal view {
        if(transactions[_txId].executed)
            revert MultiSigWalletTransactionAlreadyExecuted();
    }

    function checkPendingTransactions(uint256 _size) internal pure {
        if (_size == 0)
            revert MultiSigWalletNoPendingTransaction();
    }

    /**
     * @notice A private function for generating a random number less than passed variable
     * @param _size : size of array (readyToExecute)
     * @return A random number less than the passed size variable
     */
    function _generateRandomNumber(uint256 _size) private returns (uint256) {
        uint256 reqId = linkVRF.requestRandomWords();
        (bool fulfilled, uint256[] memory randomWord) = linkVRF.getRequestStatus(reqId);
        if (fulfilled) {
            return randomWord[0] % _size;
        }
    }

    /**
     * @notice Private function to remove transaction from readyToExecute[] after it have executed
     * @param _txId : Transaction Id that need to be removed
     */
    function _removeFromReadyToExecute(uint256 _txId) private {
        uint256 size = readyToExecute.length;
        readyToExecute[_txId] = readyToExecute[size - 1];
        readyToExecute.pop();
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address newImplementation) internal override onlyOwners {}
}