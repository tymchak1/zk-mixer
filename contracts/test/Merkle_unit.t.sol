// SPX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {Poseidon2} from "@poseidon/src/Poseidon2.sol";
import {IncrementalMerkleTree} from "../src/IncrementalMerkleTree.sol";

contract MerkleTreeHarness is IncrementalMerkleTree {
    constructor(uint32 depth, Poseidon2 hasher) IncrementalMerkleTree(depth, hasher) {}

    function insert(bytes32 leaf) external returns (uint32) {
        return _insert(leaf);
    }
}

contract MerkleTreeUnitTest is Test {
    Poseidon2 hasher;
    MerkleTreeHarness tree;
    MerkleTreeHarness deepTree;

    uint32 constant DEPTH = 3;
    uint32 constant DEEP_DEPTH = 6;
    uint32 constant ROOT_HISTORY_SIZE = 30;
    uint256 constant FIELD_SIZE = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    function setUp() public {
        hasher = new Poseidon2();
        tree = new MerkleTreeHarness(DEPTH, hasher);
        deepTree = new MerkleTreeHarness(DEEP_DEPTH, hasher);
    }

    function test_constructor_setsDepth() public view {
        assertEq(tree.getDepth(), DEPTH);
    }

    function test_constructor_setsHasher() public view {
        assertEq(address(tree.getHasher()), address(hasher));
    }

    function test_constructor_initialRootIsKnown() public view {
        bytes32 initialRoot = tree.getLatestRoot();
        assertTrue(tree.isKnownRoot(initialRoot));
    }

    function test_constructor_nextLeafIndexStartsAtZero() public view {
        assertEq(tree.getNextLeafIndex(), 0);
    }

    function test_constructor_currentRootIndexStartsAtZero() public view {
        assertEq(tree.getCurrentRootIndex(), 0);
    }

    function test_revertIf_depthIsZero() public {
        vm.expectRevert(IncrementalMerkleTree.IncrementalMerkleTree__DepthMustBeGreaterThanZero.selector);
        new MerkleTreeHarness(0, hasher);
    }

    function test_revertIf_depthIs32() public {
        vm.expectRevert(
            abi.encodeWithSelector(IncrementalMerkleTree.IncrementalMerkleTree__DepthShouldBeLessThan32.selector, 32)
        );
        new MerkleTreeHarness(32, hasher);
    }

    function test_revertIf_depthExceeds32() public {
        vm.expectRevert(
            abi.encodeWithSelector(IncrementalMerkleTree.IncrementalMerkleTree__DepthShouldBeLessThan32.selector, 33)
        );
        new MerkleTreeHarness(33, hasher);
    }

    function test_hashLeftRight_deterministicOutput() public view {
        bytes32 left = bytes32(uint256(1));
        bytes32 right = bytes32(uint256(2));

        bytes32 hash1 = tree.hashLeftRight(left, right);
        bytes32 hash2 = tree.hashLeftRight(left, right);

        assertEq(hash1, hash2);
    }

    function test_hashLeftRight_orderMatters() public view {
        bytes32 a = bytes32(uint256(1));
        bytes32 b = bytes32(uint256(2));

        assertNotEq(tree.hashLeftRight(a, b), tree.hashLeftRight(b, a));
    }

    function test_hashLeftRight_acceptsZeroInputs() public view {
        bytes32 result = tree.hashLeftRight(bytes32(0), bytes32(0));
        assertNotEq(result, bytes32(0));
    }

    function test_hashLeftRight_acceptsMaxFieldMinusOne() public view {
        bytes32 maxValid = bytes32(FIELD_SIZE - 1);
        tree.hashLeftRight(maxValid, bytes32(0));
        tree.hashLeftRight(bytes32(0), maxValid);
    }

    function test_revertIf_leftExceedsFieldSize() public {
        bytes32 invalid = bytes32(FIELD_SIZE);
        vm.expectRevert(
            abi.encodeWithSelector(IncrementalMerkleTree.IncrementalMerkleTree__LeftValueOutOfRange.selector, invalid)
        );
        tree.hashLeftRight(invalid, bytes32(0));
    }

    function test_revertIf_rightExceedsFieldSize() public {
        bytes32 invalid = bytes32(FIELD_SIZE);
        vm.expectRevert(
            abi.encodeWithSelector(IncrementalMerkleTree.IncrementalMerkleTree__RightValueOutOfRange.selector, invalid)
        );
        tree.hashLeftRight(bytes32(0), invalid);
    }

    function test_revertIf_leftIsMaxUint256() public {
        bytes32 invalid = bytes32(type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IncrementalMerkleTree.IncrementalMerkleTree__LeftValueOutOfRange.selector, invalid)
        );
        tree.hashLeftRight(invalid, bytes32(0));
    }

    function test_insert_returnsZeroIndexForFirstLeaf() public {
        uint32 index = tree.insert(bytes32(uint256(1)));
        assertEq(index, 0);
    }

    function test_insert_returnsIncrementingIndices() public {
        assertEq(tree.insert(bytes32(uint256(1))), 0);
        assertEq(tree.insert(bytes32(uint256(2))), 1);
        assertEq(tree.insert(bytes32(uint256(3))), 2);
    }

    function test_insert_incrementsNextLeafIndex() public {
        assertEq(tree.getNextLeafIndex(), 0);
        tree.insert(bytes32(uint256(1)));
        assertEq(tree.getNextLeafIndex(), 1);
        tree.insert(bytes32(uint256(2)));
        assertEq(tree.getNextLeafIndex(), 2);
    }

    function test_insert_updatesRoot() public {
        bytes32 rootBefore = tree.getLatestRoot();
        tree.insert(bytes32(uint256(1)));
        assertNotEq(rootBefore, tree.getLatestRoot());
    }

    function test_insert_differentLeavesProduceDifferentRoots() public {
        MerkleTreeHarness tree1 = new MerkleTreeHarness(DEPTH, hasher);
        MerkleTreeHarness tree2 = new MerkleTreeHarness(DEPTH, hasher);

        tree1.insert(bytes32(uint256(1)));
        tree2.insert(bytes32(uint256(2)));

        assertNotEq(tree1.getLatestRoot(), tree2.getLatestRoot());
    }

    function test_insert_sameLeavesProduceSameRoots() public {
        MerkleTreeHarness tree1 = new MerkleTreeHarness(DEPTH, hasher);
        MerkleTreeHarness tree2 = new MerkleTreeHarness(DEPTH, hasher);

        tree1.insert(bytes32(uint256(42)));
        tree2.insert(bytes32(uint256(42)));

        assertEq(tree1.getLatestRoot(), tree2.getLatestRoot());
    }

    function test_insert_updatesCurrentRootIndex() public {
        assertEq(tree.getCurrentRootIndex(), 0);
        tree.insert(bytes32(uint256(1)));
        assertEq(tree.getCurrentRootIndex(), 1);
    }

    function test_insert_fillsEntireTree() public {
        uint32 capacity = uint32(2) ** DEPTH;
        for (uint32 i = 0; i < capacity; i++) {
            tree.insert(bytes32(uint256(i + 1)));
        }
        assertEq(tree.getNextLeafIndex(), capacity);
    }

    function test_revertIf_insertIntoFullTree() public {
        uint32 capacity = uint32(2) ** DEPTH;
        for (uint32 i = 0; i < capacity; i++) {
            tree.insert(bytes32(uint256(i + 1)));
        }

        vm.expectRevert(
            abi.encodeWithSelector(IncrementalMerkleTree.IncrementalMerkleTree__MerkleTreeFull.selector, capacity)
        );
        tree.insert(bytes32(uint256(99)));
    }

    function test_isKnownRoot_initialRoot() public view {
        assertTrue(tree.isKnownRoot(tree.getLatestRoot()));
    }

    function test_isKnownRoot_returnsFalseForZeroRoot() public view {
        assertFalse(tree.isKnownRoot(bytes32(0)));
    }

    function test_isKnownRoot_returnsFalseForArbitraryRoot() public view {
        assertFalse(tree.isKnownRoot(bytes32(uint256(0xdead))));
    }

    function test_isKnownRoot_previousRootStillKnown() public {
        bytes32 rootBefore = tree.getLatestRoot();
        tree.insert(bytes32(uint256(1)));

        assertTrue(tree.isKnownRoot(rootBefore));
        assertTrue(tree.isKnownRoot(tree.getLatestRoot()));
    }

    function test_isKnownRoot_allHistoricalRootsKnown() public {
        bytes32[] memory roots = new bytes32[](5);
        roots[0] = tree.getLatestRoot();

        for (uint256 i = 0; i < 4; i++) {
            tree.insert(bytes32(uint256(i + 1)));
            roots[i + 1] = tree.getLatestRoot();
        }

        for (uint256 i = 0; i < 5; i++) {
            assertTrue(tree.isKnownRoot(roots[i]));
        }
    }

    // deep tree needed, >30 inserts to cycle the buffer
    function test_isKnownRoot_oldRootExpiredAfterHistorySizeExceeded() public {
        bytes32 initialRoot = deepTree.getLatestRoot();

        for (uint32 i = 0; i < ROOT_HISTORY_SIZE; i++) {
            deepTree.insert(bytes32(uint256(i + 1)));
        }

        // slot 0 overwritten, initial root evicted
        assertFalse(deepTree.isKnownRoot(initialRoot));
    }

    function test_isKnownRoot_rootJustBeforeEvictionStillKnown() public {
        deepTree.insert(bytes32(uint256(1)));
        bytes32 firstInsertedRoot = deepTree.getLatestRoot();

        for (uint32 i = 1; i < ROOT_HISTORY_SIZE - 1; i++) {
            deepTree.insert(bytes32(uint256(i + 1)));
        }

        assertTrue(deepTree.isKnownRoot(firstInsertedRoot));
    }

    function test_zeros_returnsNonZeroForAllValidIndices() public view {
        for (uint256 i = 0; i <= 31; i++) {
            assertNotEq(tree.zeros(i), bytes32(0));
        }
    }

    function test_zeros_returnsUniqueValuesPerLevel() public view {
        for (uint256 i = 0; i < 31; i++) {
            assertNotEq(tree.zeros(i), tree.zeros(i + 1));
        }
    }

    function test_revertIf_zerosIndexOutOfBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(IncrementalMerkleTree.IncrementalMerkleTree__IndexOutOfBounds.selector, 32)
        );
        tree.zeros(32);
    }

    function test_zeros_deterministic() public view {
        assertEq(tree.zeros(0), tree.zeros(0));
    }

    // deep tree needed, >30 inserts
    function test_rootHistory_currentRootIndexWrapsAround() public {
        for (uint32 i = 0; i < ROOT_HISTORY_SIZE + 5; i++) {
            deepTree.insert(bytes32(uint256(i + 1)));
        }
        assertEq(deepTree.getCurrentRootIndex(), (ROOT_HISTORY_SIZE + 5) % ROOT_HISTORY_SIZE);
    }

    function test_rootHistory_latestRootAlwaysKnown() public {
        for (uint32 i = 0; i < ROOT_HISTORY_SIZE * 2; i++) {
            deepTree.insert(bytes32(uint256(i + 1)));
            assertTrue(deepTree.isKnownRoot(deepTree.getLatestRoot()));
        }
    }

    /* ───── Assembly Optimization Sanity Checks ───── */

    bytes32 constant ZERO_0 = bytes32(0x0d823319708ab99ec915efd4f7e03d11ca1790918e8f04cd14100aceca2aa9ff);
    bytes32 constant ZERO_19 = bytes32(0x1b9421fbd79f6972a348a3dd4721781ec25a5d8d27342942ae00aba80a3904d4);
    bytes32 constant ZERO_31 = bytes32(0x213fb841f9de06958cf4403477bdbff7c59d6249daabfee147f853db7c808082);

    function test_zeros_switchReturnsCorrectFirst() public view {
        assertEq(tree.zeros(0), ZERO_0);
    }

    function test_zeros_switchReturnsCorrectMiddle() public view {
        assertEq(tree.zeros(19), ZERO_19);
    }

    function test_zeros_switchReturnsCorrectLast() public view {
        assertEq(tree.zeros(31), ZERO_31);
    }

    function test_zeros_switchRevertsOn32() public {
        vm.expectRevert(
            abi.encodeWithSelector(IncrementalMerkleTree.IncrementalMerkleTree__IndexOutOfBounds.selector, 32)
        );
        tree.zeros(32);
    }

    function test_insert_bitwiseOps_rootConsistency() public {
        MerkleTreeHarness tree1 = new MerkleTreeHarness(DEPTH, hasher);
        MerkleTreeHarness tree2 = new MerkleTreeHarness(DEPTH, hasher);

        tree1.insert(bytes32(uint256(0xCAFE)));
        tree2.insert(bytes32(uint256(0xCAFE)));

        assertEq(tree1.getLatestRoot(), tree2.getLatestRoot());
    }

    function test_insert_bitwiseOps_evenAndOddPaths() public {
        tree.insert(bytes32(uint256(1)));
        tree.insert(bytes32(uint256(2)));
        assertEq(tree.getNextLeafIndex(), 2);
        assertTrue(tree.isKnownRoot(tree.getLatestRoot()));
    }

    function test_isKnownRoot_unchecked_knownReturnsTrue() public {
        tree.insert(bytes32(uint256(1)));
        assertTrue(tree.isKnownRoot(tree.getLatestRoot()));
    }

    function test_isKnownRoot_unchecked_unknownReturnsFalse() public view {
        assertFalse(tree.isKnownRoot(bytes32(uint256(0xDEAD))));
    }

    function test_isKnownRoot_unchecked_zeroReturnsFalse() public view {
        assertFalse(tree.isKnownRoot(bytes32(0)));
    }
}
