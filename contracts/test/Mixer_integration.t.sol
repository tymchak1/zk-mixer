// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";

import {Poseidon2} from "../src/IncrementalMerkleTree.sol";
import {HonkVerifier, BaseZKHonkVerifier} from "../src/Verifier.sol";

import {Mixer} from "../src/Mixer.sol";

contract MixerIntegrationTest is Test {
    HonkVerifier verifier;
    Mixer mixer;
    Poseidon2 hasher;

    uint256 constant TREE_DEPTH = 20;

    address internal recipient;

    function setUp() public virtual {
        recipient = makeAddr("recipient");
        vm.deal(address(this), 10 ether);

        hasher = new Poseidon2();
        verifier = new HonkVerifier();

        mixer = new Mixer(verifier, uint32(TREE_DEPTH), hasher);
    }

    function _getCommitment() internal returns (bytes32 commitment, bytes32 nullifier, bytes32 secret) {
        string[] memory inputs = new string[](3);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/generateCommitment.ts";

        bytes memory result = vm.ffi(inputs);
        (commitment, nullifier, secret) = abi.decode(result, (bytes32, bytes32, bytes32));
    }

    function _getProof(bytes32 _nullifier, bytes32 _secret, address _recipient, bytes32[] memory leaves)
        internal
        returns (bytes memory proof, bytes32[] memory publicInputs)
    {
        string[] memory inputs = new string[](6 + leaves.length);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/generateProof.ts";
        inputs[3] = vm.toString(_nullifier);
        inputs[4] = vm.toString(_secret);
        inputs[5] = vm.toString(bytes32(uint256(uint160(_recipient))));

        for (uint256 i = 0; i < leaves.length; i++) {
            inputs[6 + i] = vm.toString(leaves[i]);
        }

        bytes memory result = vm.ffi(inputs);
        (proof, publicInputs) = abi.decode(result, (bytes, bytes32[]));
    }

    function test_integration_fullDepositWithdrawFlow() public {
        (bytes32 commitment, bytes32 nullifier, bytes32 secret) = _getCommitment();

        mixer.deposit{value: mixer.DENOMINATION()}(commitment);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = commitment;
        (bytes memory proof, bytes32[] memory publicInputs) = _getProof(nullifier, secret, recipient, leaves);

        mixer.withdraw(proof, publicInputs[0], publicInputs[1], address(uint160(uint256(publicInputs[2]))));

        // invariant: balance == denomination * (deposits - withdrawals)
        assertEq(address(mixer).balance, 0);
        assertEq(recipient.balance, mixer.DENOMINATION());
        assertTrue(mixer.isNullifierUsed(publicInputs[1]));
    }

    function test_integration_multipleDepositsOneWithdraw() public {
        // three independent deposits, withdraw only the second
        bytes32[3] memory commitments;
        bytes32[3] memory nullifiers;
        bytes32[3] memory secrets;

        for (uint256 i = 0; i < 3; i++) {
            (commitments[i], nullifiers[i], secrets[i]) = _getCommitment();
            mixer.deposit{value: mixer.DENOMINATION()}(commitments[i]);
        }

        assertEq(address(mixer).balance, mixer.DENOMINATION() * 3);

        bytes32[] memory leaves = new bytes32[](3);
        for (uint256 i = 0; i < 3; i++) {
            leaves[i] = commitments[i];
        }

        (bytes memory proof, bytes32[] memory publicInputs) = _getProof(nullifiers[1], secrets[1], recipient, leaves);

        mixer.withdraw(proof, publicInputs[0], publicInputs[1], address(uint160(uint256(publicInputs[2]))));

        // only one withdrawal happened
        assertEq(address(mixer).balance, mixer.DENOMINATION() * 2);
        assertEq(recipient.balance, mixer.DENOMINATION());
    }

    function test_integration_verifierRejectsWrongRecipient() public {
        (bytes32 commitment, bytes32 nullifier, bytes32 secret) = _getCommitment();
        mixer.deposit{value: mixer.DENOMINATION()}(commitment);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = commitment;
        (bytes memory proof, bytes32[] memory publicInputs) = _getProof(nullifier, secret, recipient, leaves);

        // proof was generated for `recipient`, passing `attacker` makes verifier reject
        // note: bb 3.x verifier reverts with SumcheckFailed() instead of returning false
        address attacker = makeAddr("attacker");
        vm.expectRevert(BaseZKHonkVerifier.SumcheckFailed.selector);
        mixer.withdraw(proof, publicInputs[0], publicInputs[1], attacker);

        // nothing changed
        assertEq(address(mixer).balance, mixer.DENOMINATION());
        assertEq(attacker.balance, 0);
    }

    function test_integration_revertIf_doubleSpend() public {
        (bytes32 commitment, bytes32 nullifier, bytes32 secret) = _getCommitment();

        // fund a second withdrawal attempt
        vm.deal(address(mixer), mixer.DENOMINATION() * 2);
        mixer.deposit{value: mixer.DENOMINATION()}(commitment);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = commitment;
        (bytes memory proof, bytes32[] memory publicInputs) = _getProof(nullifier, secret, recipient, leaves);

        address proofRecipient = address(uint160(uint256(publicInputs[2])));
        mixer.withdraw(proof, publicInputs[0], publicInputs[1], proofRecipient);

        // same nullifier hash cannot be used again
        vm.expectRevert(abi.encodeWithSelector(Mixer.Mixer__NulifierAlreadyUsed.selector, publicInputs[1]));
        mixer.withdraw(proof, publicInputs[0], publicInputs[1], proofRecipient);
    }

    function test_integration_revertIf_duplicateDeposit() public {
        (bytes32 commitment,,) = _getCommitment();

        uint256 denomination = mixer.DENOMINATION();
        mixer.deposit{value: denomination}(commitment);

        vm.expectRevert(abi.encodeWithSelector(Mixer.Mixer__AlreadyCommited.selector, commitment));
        mixer.deposit{value: denomination}(commitment);
    }

    function test_integration_revertIf_wrongDenomination() public {
        (bytes32 commitment,,) = _getCommitment();

        vm.expectRevert(abi.encodeWithSelector(Mixer.Mixer__InvalidAmount.selector, 0.002 ether, mixer.DENOMINATION()));
        mixer.deposit{value: 0.002 ether}(commitment);
    }

    /* ───── GETTER TESTS ───── */

    function test_getVerifier_returnsDeployedVerifier() public view {
        assertEq(address(mixer.getVerifier()), address(verifier));
    }

    function test_isCommitted_falseBeforeDeposit() public view {
        assertFalse(mixer.isCommitted(bytes32(uint256(1))));
    }

    function test_isCommitted_trueAfterDeposit() public {
        (bytes32 commitment,,) = _getCommitment();
        mixer.deposit{value: mixer.DENOMINATION()}(commitment);
        assertTrue(mixer.isCommitted(commitment));
    }

    function test_isNullifierUsed_falseByDefault() public view {
        assertFalse(mixer.isNullifierUsed(bytes32(uint256(1))));
    }

    /* ───── REVERT TESTS ───── */

    function test_integration_revertIf_unknownRoot() public {
        (bytes32 commitment, bytes32 nullifier, bytes32 secret) = _getCommitment();
        mixer.deposit{value: mixer.DENOMINATION()}(commitment);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = commitment;
        (bytes memory proof, bytes32[] memory publicInputs) = _getProof(nullifier, secret, recipient, leaves);

        // tamper with root
        bytes32 fakeRoot = bytes32(uint256(publicInputs[0]) ^ 1);
        vm.expectRevert(Mixer.Mixer__InvalidProof.selector);
        mixer.withdraw(proof, fakeRoot, publicInputs[1], address(uint160(uint256(publicInputs[2]))));
    }

    function test_integration_depositEmitsCorrectEvent() public {
        (bytes32 commitment,,) = _getCommitment();

        vm.expectEmit(true, false, false, true);
        emit Mixer.DepositSuccess(commitment, 0, block.timestamp);

        mixer.deposit{value: mixer.DENOMINATION()}(commitment);
    }

    function test_integration_withdrawEmitsCorrectEvent() public {
        (bytes32 commitment, bytes32 nullifier, bytes32 secret) = _getCommitment();
        mixer.deposit{value: mixer.DENOMINATION()}(commitment);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = commitment;
        (bytes memory proof, bytes32[] memory publicInputs) = _getProof(nullifier, secret, recipient, leaves);

        vm.expectEmit(true, false, false, true);
        emit Mixer.WithdrawalSuccess(recipient, publicInputs[1], block.timestamp);

        mixer.withdraw(proof, publicInputs[0], publicInputs[1], address(uint160(uint256(publicInputs[2]))));
    }

    function test_integration_balanceInvariantAfterMultipleOps() public {
        // deposit 3, withdraw 2, verify balance == 1 * DENOMINATION
        bytes32[3] memory commitments;
        bytes32[3] memory nullifiers;
        bytes32[3] memory secrets;

        for (uint256 i = 0; i < 3; i++) {
            (commitments[i], nullifiers[i], secrets[i]) = _getCommitment();
            mixer.deposit{value: mixer.DENOMINATION()}(commitments[i]);
        }

        bytes32[] memory leaves = new bytes32[](3);
        for (uint256 i = 0; i < 3; i++) {
            leaves[i] = commitments[i];
        }

        // withdraw first
        address recipient1 = makeAddr("recipient1");
        (bytes memory proof1, bytes32[] memory pi1) = _getProof(nullifiers[0], secrets[0], recipient1, leaves);
        mixer.withdraw(proof1, pi1[0], pi1[1], address(uint160(uint256(pi1[2]))));

        // withdraw third
        address recipient2 = makeAddr("recipient2");
        (bytes memory proof2, bytes32[] memory pi2) = _getProof(nullifiers[2], secrets[2], recipient2, leaves);
        mixer.withdraw(proof2, pi2[0], pi2[1], address(uint160(uint256(pi2[2]))));

        // invariant: balance == denomination * (3 deposits - 2 withdrawals)
        assertEq(address(mixer).balance, mixer.DENOMINATION());
        assertEq(recipient1.balance, mixer.DENOMINATION());
        assertEq(recipient2.balance, mixer.DENOMINATION());
    }
}
