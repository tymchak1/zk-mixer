# ZK Mixer

Private ETH mixer — deposit 0.001 ETH, withdraw anonymously to any address.
A zero-knowledge proof lets you prove you deposited without revealing which deposit is yours. Privacy grows with the anonymity set — more deposits means harder to trace.

**Noir** · **Barretenberg** · **Solidity** · **Foundry** · **Poseidon2**

## Highlights

**Circuit (Noir)**
- Proves "I made one of these deposits" without showing which one
- Proves the user knows the secret behind the deposit
- Proof is locked to a specific recipient so nobody can steal it mid-transaction

**On-chain (Solidity)**
- Verifies ZK proofs using UltraHonk verifier
- Poseidon2 hashing written in Huff for lower gas costs
- Deposits stored in an incremental Merkle tree (depth-20, keeps last 30 roots)
- Nullifiers prevent withdrawing the same deposit twice
- Everyone deposits the same amount — this is what makes it private

**Testing (Foundry)**
- Integration tests compile circuits and generate real proofs via FFI

## Build

```bash
# Circuit → verification key → Solidity verifier
cd circuits
nargo compile
bb write_vk --oracle_hash keccak -b ./target/circuits.json -o ./target
bb write_solidity_verifier -k ./target/vk -o ./target/Verifier.sol
cp ./target/Verifier.sol ../contracts/src/Verifier.sol

# Contracts
cd ../contracts
forge build
forge test
```

> **Note:** Tests require `ffi = true` in `foundry.toml` — this allows Foundry to execute shell commands (nargo, bb) for proof generation. Only run on trusted code.
