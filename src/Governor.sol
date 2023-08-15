// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Governor {

    uint256 public signaturesRequired;
    address[] public admins;
    mapping(address => bool) public isAdmin;

    /**
     * @notice data structure used to make function calls and send native currency
     */
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        address proposedBy;
        bool active;
        bool executed;
        uint8 numSignatures;
    }
    Transaction[] private transactions;
    mapping(uint256 => mapping(address => bool)) private hasSigned;

    event TransactionProposed(
        uint256 txIndex,
        address to,
        uint256 value,
        bytes data,
        address proposedBy
    );
    event TransactionSigned(uint256 txIndex, address admin, uint256 numSignatures);
    event TransactionExecuted(uint256 txIndex, address to, uint256 value, bytes data);
    event SignatureRevoked(uint256 txIndex, address admin, uint256 numSignatures);
    event TransactionCancelled(uint256 txIndex);
    event AdminAdded(address newAdmin);
    // event AdminAdded(address newAdmin, uint256 numSigsRequired);
    event AdminRemoved(address adminRemoved);
    // event AdminRemoved(address adminRemoved, uint256 numSigsRequired);
    event SignaturesRequiredChanged(uint256 signaturesRequired);

    error Governor__DuplicateAdminAddress();
    error Governor__ZeroAddress();
    error Governor__TooManySignaturesRequired();
    error Governor__TooFewSignaturesRequired();
    error Governor__OnlyAdmin();
    error Governor__TransactionNotActive();
    error Governor__DuplicateSignature();
    error Governor__InsufficientSignatures();
    error Governor__TransactionFailed();
    error Governor__UserHasNotSigned();
    error Governor__OnlyProposerCanCancel();
    error Governor__OnlyGovernor();
    error Governor__AddressIsNotAdmin();
    error Governor__TwoAdminMinimum();

    modifier onlyAdmin() {
        if(!isAdmin[msg.sender]) revert Governor__OnlyAdmin();
        _;
    }

    modifier onlyActive(uint256 txIndex) {
        if(!transactions[txIndex].active) revert Governor__TransactionNotActive();
        _;
    }

    modifier onlyGovernor() {
        if(msg.sender != address(this)) revert Governor__OnlyGovernor();
        _;
    }

    constructor(address[] memory _admins, uint256 _sigsRequired) {
        for(uint i = 0; i < _admins.length; ++i) {
            _addAdmin(_admins[i]);
        }
        require(_checkNumSigs(_sigsRequired, admins.length));
        signaturesRequired = _sigsRequired;
    }

    fallback() external payable {}
    receive() external payable {}

    /**
     * @notice create a Transaction object which will be executed when enough admins sign
     * @dev caller automatically signs Transaction
     */
    function proposeTransaction(
        address _to, 
        uint256 _value, 
        bytes calldata _data
    ) 
        external 
        onlyAdmin 
        returns (uint256) 
    {
        uint256 txIndex = transactions.length;
        Transaction memory transaction;
        transaction.to = _to;
        transaction.value = _value;
        transaction.data = _data;
        transaction.proposedBy = msg.sender;
        transaction.active = true;
        transactions.push(transaction);
        emit TransactionProposed(txIndex, _to, _value, _data, msg.sender);
        signTransaction(txIndex);
        return txIndex;
    }

    /**
     * @notice approve a Transaction - if approval reaches required signatures, Transaction will be executed
     */
    function signTransaction(uint256 _txIndex) public onlyAdmin onlyActive(_txIndex) {
        if(hasSigned[_txIndex][msg.sender]) revert Governor__DuplicateSignature();
        Transaction storage transaction = transactions[_txIndex];
        transaction.numSignatures += 1;
        hasSigned[_txIndex][msg.sender] = true;
        emit TransactionSigned(_txIndex, msg.sender, transaction.numSignatures);
        if(transaction.numSignatures >= signaturesRequired) executeTransaction(_txIndex);
    }

    /**
     * @dev used to manually execute transactions which were not executed automatically by signTransaction().
     * For example, if the number of signatures required is reduced.
     */
    function executeTransaction(uint256 _txIndex) public onlyAdmin onlyActive(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];
        if(transaction.numSignatures < signaturesRequired) revert Governor__InsufficientSignatures();
        transaction.executed = true;
        transaction.active = false;
        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        if(!success) revert Governor__TransactionFailed();
        emit TransactionExecuted(_txIndex, transaction.to, transaction.value, transaction.data);
    }

    /**
     * @notice remove signature from Transaction 
     */
    function revokeSignature(uint256 _txIndex) public onlyAdmin onlyActive(_txIndex) {
        if(!hasSigned[_txIndex][msg.sender]) revert Governor__UserHasNotSigned();
        Transaction storage transaction = transactions[_txIndex];
        transaction.numSignatures -= 1;
        hasSigned[_txIndex][msg.sender] = false;
        emit SignatureRevoked(_txIndex, msg.sender, transaction.numSignatures);
    }

    /**
     * @notice Admin who initially proposed transaction may make it inactive
     */
    function cancelTransaction(uint256 _txIndex) public onlyAdmin onlyActive(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];
        if(msg.sender != transaction.proposedBy) revert Governor__OnlyProposerCanCancel();
        transaction.active = false;
        emit TransactionCancelled(_txIndex);
    }

    /**
     * @notice add an address with admin permission 
     */
    function addAdmin(address _newAdmin) public onlyGovernor {
        _addAdmin(_newAdmin);
        emit AdminAdded(_newAdmin);
    }

    /**
     * @notice remove admin permission 
     * @dev will revert if removing an admin results less than two admins total
     */
    function removeAdmin(address _toRemove) public onlyGovernor {
        if(!isAdmin[_toRemove]) revert Governor__AddressIsNotAdmin();
        if(admins.length - 1 < 2) revert Governor__TwoAdminMinimum();
        isAdmin[_toRemove] = false;
        for(uint i; i < admins.length; ++i) {
            if(admins[i] == _toRemove) {
                address temp = admins[admins.length - 1];
                admins[i] = temp;
                admins[admins.length - 1] = _toRemove;
                admins.pop();
            }  
        }
        if(signaturesRequired > admins.length) {
            signaturesRequired = admins.length;
        }
        emit AdminRemoved(_toRemove);
    }

    /**
     * @notice change the number of signatures needed to execute a Transaction
     */
    function changeSignaturesRequired(uint256 _newSigsRequired) public onlyGovernor {
        require(_checkNumSigs(_newSigsRequired, admins.length));
        signaturesRequired = _newSigsRequired;
        emit SignaturesRequiredChanged(_newSigsRequired);
    }
 
    function _addAdmin(address _admin) private {
        if(isAdmin[_admin]) revert Governor__DuplicateAdminAddress();
        if(_admin == address(0)) revert Governor__ZeroAddress();
        admins.push(_admin);
        isAdmin[_admin] = true;
    }

    function _checkNumSigs(uint256 _numSigs, uint256 _numAdmins) private pure returns (bool) {
        if(_numSigs > _numAdmins) revert Governor__TooManySignaturesRequired();
        if(_numSigs < 2) revert Governor__TooFewSignaturesRequired();
        return true;
    }

    function getTransaction(uint256 txIndex) public view returns (Transaction memory) {
        return transactions[txIndex];
    }

    function adminHasSigned(uint256 txIndex, address admin) public view returns (bool) {
        return hasSigned[txIndex][admin];
    }

    function getAllTransactions() public view returns (Transaction[] memory) {
        return transactions;
    }

    function getNumTransactions() public view returns (uint256) {
        return transactions.length;
    }

    function getAdmins() public view returns (address[] memory) {
        return admins;
    }

}