// SPX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IVerifier} from "./Verifier.sol";
import {IncrementalMerkleTree, Poseidon2} from "./IncrementalMerkleTree.sol";

contract Mixer is IncrementalMerkleTree, ReentrancyGuard {
    /* ───── ERRORS ───── */
    error Mixer__AlreadyCommited(bytes32 commitment);
    error Mixer__InvalidAmount(uint256 sent, uint256 expected);
    error Mixer__NulifierAlreadyUsed(bytes32 nullifierHash);
    error Mixer__InvalidProof();
    error Mixer__TransferFailed(address recipient);

    /* ───── STATE VARIABLES ───── */
    uint256 public constant DENOMINATION = 0.001 ether;

    IVerifier private immutable i_verifier;

    mapping(bytes32 => bool) private s_commitments;
    mapping(bytes32 => bool) private s_nullifierHashes;

    /* ───── EVENTS ───── */
    event DepositSuccess(bytes32 indexed commitment, uint32 leafIndex, uint256 timestamp);
    event WithdrawalSuccess(address indexed recepient, bytes32 nulifierHash, uint256 timestamp);

    /* ───── CONSTRUCTOR ───── */
    constructor(IVerifier verifier, uint32 depth, Poseidon2 hasher) IncrementalMerkleTree(depth, hasher) {
        i_verifier = verifier;
    }

    /* ───── EXTERNAL ───── */
    // commitment (nulifier+secret)- off-chain
    function deposit(bytes32 commitment) external payable {
        if (s_commitments[commitment]) {
            revert Mixer__AlreadyCommited(commitment);
        }
        if (msg.value != DENOMINATION) {
            revert Mixer__InvalidAmount(msg.value, DENOMINATION);
        }

        uint32 insertedIndex = _insert(commitment);
        s_commitments[commitment] = true;

        emit DepositSuccess(commitment, insertedIndex, block.timestamp);
    }

    function withdraw(bytes calldata proof, bytes32 root, bytes32 nulifierHash, address recepient)
        external
        nonReentrant
    {
        if (!isKnownRoot(root)) {
            revert Mixer__InvalidProof();
        }
        if (s_nullifierHashes[nulifierHash]) {
            revert Mixer__NulifierAlreadyUsed(nulifierHash);
        }

        // Verifier
        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = root;
        publicInputs[1] = nulifierHash;
        publicInputs[2] = bytes32(uint256(uint160(recepient)));

        i_verifier.verify(proof, publicInputs);

        s_nullifierHashes[nulifierHash] = true;

        (bool success,) = payable(recepient).call{value: DENOMINATION}("");
        if (!success) {
            revert Mixer__TransferFailed(recepient);
        }

        emit WithdrawalSuccess(recepient, nulifierHash, block.timestamp);
    }

    /* ───── GETTERS ───── */
    function getVerifier() external view returns (IVerifier) {
        return i_verifier;
    }

    function isCommitted(bytes32 commitment) external view returns (bool) {
        return s_commitments[commitment];
    }

    function isNullifierUsed(bytes32 nullifierHash) external view returns (bool) {
        return s_nullifierHashes[nullifierHash];
    }
}
