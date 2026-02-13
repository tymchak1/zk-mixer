// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Field} from "@poseidon/src/Field.sol";
import {Poseidon2} from "@poseidon/src/Poseidon2.sol";

abstract contract IncrementalMerkleTree {
    /* ───── ERRORS ───── */
    error IncrementalMerkleTree__DepthMustBeGreaterThanZero();
    error IncrementalMerkleTree__DepthShouldBeLessThan32(uint32 depth);
    error IncrementalMerkleTree__MerkleTreeFull(uint32 nextIndex);
    error IncrementalMerkleTree__LeftValueOutOfRange(bytes32 left);
    error IncrementalMerkleTree__RightValueOutOfRange(bytes32 right);
    error IncrementalMerkleTree__IndexOutOfBounds(uint256 index);

    /* ───── STATE VARIABLES ───── */
    uint256 public constant FIELD_SIZE = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint32 public constant ROOT_HISTORY_SIZE = 30;

    Poseidon2 private immutable i_hasher;
    uint32 private immutable i_depth;

    mapping(uint256 => bytes32) private s_cachedSubtrees;
    mapping(uint256 => bytes32) private s_roots;

    uint32 private s_currentRootIndex = 0;
    uint32 private s_nextLeafIndex = 0;

    /* ───── CONSTRUCTOR ───── */
    constructor(uint32 depth, Poseidon2 hasher) {
        if (depth == 0) {
            revert IncrementalMerkleTree__DepthMustBeGreaterThanZero();
        }
        if (depth >= 32) {
            revert IncrementalMerkleTree__DepthShouldBeLessThan32(depth);
        }

        i_depth = depth;
        i_hasher = hasher;

        s_roots[0] = zeros(depth);
    }

    /* ───── PUBLIC ───── */
    function hashLeftRight(bytes32 left, bytes32 right) public view returns (bytes32) {
        if (uint256(left) >= FIELD_SIZE) {
            revert IncrementalMerkleTree__LeftValueOutOfRange(left);
        }
        if (uint256(right) >= FIELD_SIZE) {
            revert IncrementalMerkleTree__RightValueOutOfRange(right);
        }

        return Field.toBytes32(i_hasher.hash_2(Field.toField(left), Field.toField(right)));
    }

    function isKnownRoot(bytes32 root) public view returns (bool) {
        if (root == bytes32(0)) {
            return false;
        }
        uint32 currentRootIndex = s_currentRootIndex;
        uint32 i = currentRootIndex;
        do {
            if (root == s_roots[i]) {
                return true;
            }
            unchecked {
                if (i == 0) {
                    i = ROOT_HISTORY_SIZE;
                }
                --i;
            }
        } while (i != currentRootIndex);
        return false;
    }

    /* ───── INTERNAL ───── */
    function _insert(bytes32 leaf) internal returns (uint32 index) {
        uint32 nextLeafIndex = s_nextLeafIndex;
        if (nextLeafIndex == uint32(2) ** i_depth) {
            revert IncrementalMerkleTree__MerkleTreeFull(nextLeafIndex);
        }

        uint32 currentIndex = nextLeafIndex;
        bytes32 currentHash = leaf;
        uint32 depth = i_depth;

        for (uint32 i = 0; i < depth;) {
            if (currentIndex & 1 == 0) {
                s_cachedSubtrees[i] = currentHash;
                currentHash = hashLeftRight(currentHash, zeros(i));
            } else {
                currentHash = hashLeftRight(s_cachedSubtrees[i], currentHash);
            }
            currentIndex >>= 1;
            unchecked { ++i; }
        }

        unchecked {
            uint32 newRootIndex = (s_currentRootIndex + 1) % ROOT_HISTORY_SIZE;
            s_currentRootIndex = newRootIndex;
            s_roots[newRootIndex] = currentHash;
            s_nextLeafIndex = nextLeafIndex + 1;
        }

        return nextLeafIndex;
    }

    /* ───── GETTERS ───── */
    function getHasher() external view returns (Poseidon2) {
        return i_hasher;
    }

    function getDepth() external view returns (uint32) {
        return i_depth;
    }

    function getCurrentRootIndex() external view returns (uint32) {
        return s_currentRootIndex;
    }

    function getNextLeafIndex() external view returns (uint32) {
        return s_nextLeafIndex;
    }

    function getLatestRoot() external view returns (bytes32) {
        return s_roots[s_currentRootIndex];
    }

    function zeros(uint256 i) public pure returns (bytes32 result) {
        assembly {
            switch i
            case 0  { result := 0x0d823319708ab99ec915efd4f7e03d11ca1790918e8f04cd14100aceca2aa9ff }
            case 1  { result := 0x170a9598425eb05eb8dc06986c6afc717811e874326a79576c02d338bdf14f13 }
            case 2  { result := 0x273b1a40397b618dac2fc66ceb71399a3e1a60341e546e053cbfa5995e824caf }
            case 3  { result := 0x16bf9b1fb2dfa9d88cfb1752d6937a1594d257c2053dff3cb971016bfcffe2a1 }
            case 4  { result := 0x1288271e1f93a29fa6e748b7468a77a9b8fc3db6b216ce5fc2601fc3e9bd6b36 }
            case 5  { result := 0x1d47548adec1068354d163be4ffa348ca89f079b039c9191378584abd79edeca }
            case 6  { result := 0x0b98a89e6827ef697b8fb2e280a2342d61db1eb5efc229f5f4a77fb333b80bef }
            case 7  { result := 0x231555e37e6b206f43fdcd4d660c47442d76aab1ef552aef6db45f3f9cf2e955 }
            case 8  { result := 0x03d0dc8c92e2844abcc5fdefe8cb67d93034de0862943990b09c6b8e3fa27a86 }
            case 9  { result := 0x1d51ac275f47f10e592b8e690fd3b28a76106893ac3e60cd7b2a3a443f4e8355 }
            case 10 { result := 0x16b671eb844a8e4e463e820e26560357edee4ecfdbf5d7b0a28799911505088d }
            case 11 { result := 0x115ea0c2f132c5914d5bb737af6eed04115a3896f0d65e12e761ca560083da15 }
            case 12 { result := 0x139a5b42099806c76efb52da0ec1dde06a836bf6f87ef7ab4bac7d00637e28f0 }
            case 13 { result := 0x0804853482335a6533eb6a4ddfc215a08026db413d247a7695e807e38debea8e }
            case 14 { result := 0x2f0b264ab5f5630b591af93d93ec2dfed28eef017b251e40905cdf7983689803 }
            case 15 { result := 0x170fc161bf1b9610bf196c173bdae82c4adfd93888dc317f5010822a3ba9ebee }
            case 16 { result := 0x0b2e7665b17622cc0243b6fa35110aa7dd0ee3cc9409650172aa786ca5971439 }
            case 17 { result := 0x12d5a033cbeff854c5ba0c5628ac4628104be6ab370699a1b2b4209e518b0ac5 }
            case 18 { result := 0x1bc59846eb7eafafc85ba9a99a89562763735322e4255b7c1788a8fe8b90bf5d }
            case 19 { result := 0x1b9421fbd79f6972a348a3dd4721781ec25a5d8d27342942ae00aba80a3904d4 }
            case 20 { result := 0x087fde1c4c9c27c347f347083139eee8759179d255ec8381c02298d3d6ccd233 }
            case 21 { result := 0x1e26b1884cb500b5e6bbfdeedbdca34b961caf3fa9839ea794bfc7f87d10b3f1 }
            case 22 { result := 0x09fc1a538b88bda55a53253c62c153e67e8289729afd9b8bfd3f46f5eecd5a72 }
            case 23 { result := 0x14cd0edec3423652211db5210475a230ca4771cd1e45315bcd6ea640f14077e2 }
            case 24 { result := 0x1d776a76bc76f4305ef0b0b27a58a9565864fe1b9f2a198e8247b3e599e036ca }
            case 25 { result := 0x1f93e3103fed2d3bd056c3ac49b4a0728578be33595959788fa25514cdb5d42f }
            case 26 { result := 0x138b0576ee7346fb3f6cfb632f92ae206395824b9333a183c15470404c977a3b }
            case 27 { result := 0x0745de8522abfcd24bd50875865592f73a190070b4cb3d8976e3dbff8fdb7f3d }
            case 28 { result := 0x2ffb8c798b9dd2645e9187858cb92a86c86dcd1138f5d610c33df2696f5f6860 }
            case 29 { result := 0x2612a1395168260c9999287df0e3c3f1b0d8e008e90cd15941e4c2df08a68a5a }
            case 30 { result := 0x10ebedce66a910039c8edb2cd832d6a9857648ccff5e99b5d08009b44b088edf }
            case 31 { result := 0x213fb841f9de06958cf4403477bdbff7c59d6249daabfee147f853db7c808082 }
            default {
                mstore(0x00, 0x76de023800000000000000000000000000000000000000000000000000000000)
                mstore(0x04, i)
                revert(0x00, 0x24)
            }
        }
    }
}
