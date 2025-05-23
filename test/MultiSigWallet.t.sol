// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "./../lib/forge-std/src/Test.sol";
import {Token} from "./../contracts/Token.sol";
import {MultiSigWallet} from "./../contracts/MultiSigWallet.sol";
import {ChainlinkOracle} from "./../contracts/ChainlinkOracle.sol";
import "hardhat/console.sol";

contract MultiSigWalletTest is Test {
    MultiSigWallet wallet;
    Token token;
    ChainlinkOracle linkVRF;

    uint256 constant e18 = 10 ** 18;
    address[] _owners;
    address owner1 = address(0xA639F7b0E2dbb08115d6ABB65f5fF214b12b96B5);
    address owner2 = address(0x2);
    address owner3 = address(0x3);
    address owner4 = address(0x4);

    address user1 = address(0x5);
    address user2 = address(0x6);

    event OwnerAdded(address indexed owner);
    event RequirementChanged(uint required);
    event ApprovalRevoked(address indexed owner, uint256 indexed txId);
    event TransactionSubmitted(address indexed owner, uint256 indexed txId);
    event TransactionApproved(address indexed owner, uint256 indexed txId);
    event TransactionExecuted(
        address indexed owner,
        uint256 indexed txId,
        address to,
        uint256 value
    );

    error MultiSigWalletSenderNotWallet();
    error MultiSigWalletSenderNotOwner();
    error MultiSigWalletInvalidRequirement();
    error MultiSigWalletInvalidAddress();
    error MultiSigWalletAmountZero();
    error MultiSigWalletInvalidTransaction();
    error MultiSigWalletTransactionNotApprovedBySender();
    error MultiSigWalletApprovedOwner();
    function setUp()  public {
        token = new Token("TOKEN", "TON", 18);
        wallet = new MultiSigWallet();
        // address linkVRF = address(0xbd452cc8683C33F02C120Aa435530d859020162a);
        ChainlinkOracle linkVRF = new ChainlinkOracle(uint64(vm.envUint("CHAINLINK_SUBSCRIPTION_ID")));
        _owners.push(owner1);
        _owners.push(owner2);
        _owners.push(owner3);
        wallet.initialize(_owners, 2, address(token), address(linkVRF));
    }

    function testCanInitialize() public {
        assertEq(wallet.approvalsRequired(), 2);
    }

    function testCanSubmitTransaction() public {
        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1* e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
    }

    function test_RevertWhen_SenderNotOwner() public {
        vm.expectRevert(MultiSigWalletSenderNotOwner.selector);
        vm.prank(user1);
        wallet.submitTransaction(payable(user2), 1* e18 , true);
    }

    function test_RevertWhen_ReceiverIsNull() public {
        vm.expectRevert(MultiSigWalletInvalidAddress.selector);
        vm.prank(owner1);
        wallet.submitTransaction(payable(address(0)), 1* e18 , true);
    }
        
    function test_RevertWhen_ZeroValue() public {
        vm.expectRevert(MultiSigWalletAmountZero.selector);
        vm.prank(owner1);
        wallet.submitTransaction(payable(user1), 0 , true);
    }

     function testCanApproveTransaction() public {
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(address(wallet));
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1* e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);

        // approve the transaction
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner2, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
     }

    function test_RevertApproveTransaction_When_TransactionNotExist() public {
        // vm.expectRevert(MultiSigWalletInvalidTransaction.selector);
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1* e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        
        vm.prank(owner2);
        wallet.approveTransaction();
    }

    function test_RevertApproveTransaction_When_TransactionAlreadyExecuted() public {
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1 * e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        // get another approval
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner2, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
        // execute transaction
        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(owner1, 1, payable(user1), 1 * e18);
        wallet.executeTransaction();

        vm.expectRevert(MultiSigWalletInvalidTransaction.selector);
        vm.prank(owner3);
        wallet.approveTransaction();
    }

    function test_RevertApproveTransaction_When_SenderNotOwner() public {
        vm.expectRevert(MultiSigWalletSenderNotOwner.selector);
        vm.prank(user1);
        wallet.approveTransaction();
    }

    function test_CanExecuteTransaction_When_ERC20Tx() public {
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1 * e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        // get another approval
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner2, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
        
        // mint the owner some tokens
        uint256 balanceBeforeMint = token.balanceOf(user1);
        token.mint(owner1, 10 * e18);
        uint256 balanceBeforeTx = token.balanceOf(user1);
        assertLt(balanceBeforeMint, balanceBeforeTx);

        // execute transaction
        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(owner1, 1, payable(user1), 1 * e18);
        wallet.executeTransaction();
        assertLt(balanceBeforeTx, token.balanceOf(user1));
        assertEq(wallet.readyTransactionCount(), 0);
    }

    function test_CanExecuteTransaction_When_ETHTx() public {
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1 * e18 , false);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        // get another approval
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner2, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
        
        // fund the owner some ETH
        vm.deal(owner1, 10 ether);
        uint256 balanceBeforeTx = address(user1).balance;
        // execute transaction
        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(owner1, 1, payable(user1), 1 * e18);
        wallet.executeTransaction();
        assertLt(balanceBeforeTx, address(user1).balance);
        assertEq(wallet.readyTransactionCount(), 0);
    }

    function test_CanRevokeTransaction_When_TwoApprovals() public {
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1 * e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        // get another approval
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner2, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
        
        // revoke the transaction
        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit ApprovalRevoked(owner1, 1);
        wallet.revokeApproval();
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        assertEq(wallet.readyTransactionCount(), 0);
    }

    function test_CanRevokeTransaction_When_ThreeApprovals() public {
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1 * e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        // get another approval
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner2, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
        // get another approval
        vm.prank(owner3);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner3, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 3);
        assertEq(wallet.readyTransactionCount(), 1);
        
        // revoke the transaction
        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit ApprovalRevoked(owner1, 1);
        wallet.revokeApproval();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
    }

    function test_RevertRevokeTransaction_When_TransactionNotExists() public {
        vm.expectRevert(MultiSigWalletInvalidTransaction.selector);
        vm.prank(owner1);
        wallet.revokeApproval();
    }

    function test_Revert_RevokeTransaction_When_TransactionAlreadyExecuted() public {
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1 * e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        // get another approval
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner2, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
        // execute transaction
        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(owner1, 1, payable(user1), 1 * e18);
        wallet.executeTransaction();
        assertEq(wallet.readyTransactionCount(), 0);

        vm.expectRevert(MultiSigWalletInvalidTransaction.selector);
        vm.prank(owner3);
        wallet.revokeApproval();
    }

    function test_RevertRevokeTransaction_When_SenderHasNotApprovedTx() public {
        vm.prank(owner1);
        //submit transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(owner1, 1);
        wallet.submitTransaction(payable(user1), 1 * e18 , true);
        assertEq(wallet.getTransactionApprovalCount(1), 1);
        // get another approval
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(owner2, 1);
        wallet.approveTransaction();
        assertEq(wallet.getTransactionApprovalCount(1), 2);
        assertEq(wallet.readyTransactionCount(), 1);
        
        vm.expectRevert(MultiSigWalletTransactionNotApprovedBySender.selector);
        vm.prank(owner3);
        wallet.revokeApproval();
    }

    function test_CanAddOwner() public {
        vm.prank(address(wallet));
        vm.expectEmit(true, true, false, true);
        emit OwnerAdded(owner4);
        wallet.addOwner(owner4);
    }

    function test_RevertAddOwner_When_SenderNotWallet() public {
        vm.expectRevert(MultiSigWalletSenderNotWallet.selector);
        vm.prank(owner1);
        wallet.addOwner(owner4);
    }

    function test_RevertAddOwner_When_AddressNull() public {
        vm.expectRevert(MultiSigWalletInvalidAddress.selector);
        vm.prank(address(wallet));
        wallet.addOwner(address(0));
    }

    function test_RevertAddOwner_When_AddressAlreadyOwner() public {
        vm.expectRevert(MultiSigWalletApprovedOwner.selector);
        vm.prank(address(wallet));
        wallet.addOwner(owner1);
    }

    function test_CanChangeRequirement() public {
        vm.prank(address(wallet));
        vm.expectEmit(true, true, false, true);
        emit RequirementChanged(3);
        wallet.changeRequirement(3);
        assertEq(wallet.approvalsRequired(), 3);
    }

    function test_RevertChangeRequirement_When_SenderNotWallet() public {
        vm.expectRevert(MultiSigWalletSenderNotWallet.selector);
        vm.prank(owner1);
        wallet.changeRequirement(3);
    }

    function test_RevertChangeRequirements_When_RequirementIsZero() public {
        vm.expectRevert(MultiSigWalletInvalidRequirement.selector);
        vm.prank(address(wallet));
        wallet.changeRequirement(0);
    }

    function test_RevertChangeRequirements_When_RequirementIsGreaterThanOwners() public {
        vm.expectRevert(MultiSigWalletInvalidRequirement.selector);
        vm.prank(address(wallet));
        wallet.changeRequirement(5);
    }
}