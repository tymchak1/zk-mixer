import { Barretenberg, randomBytes } from "@aztec/bb.js";
import { ethers } from "ethers";

function randomField(): Uint8Array {
  // Generate random 32 bytes within BN254 field
  const bytes = randomBytes(32);
  bytes[0] &= 0x1f; // Ensure < field modulus
  return bytes;
}

export default async function generateCommitment(): Promise<string> {
  const bb = await Barretenberg.new();

  const nullifier = randomField();
  const secret = randomField();
  const { hash: commitment } = await bb.poseidon2Hash({ inputs: [nullifier, secret] });

  const result = ethers.AbiCoder.defaultAbiCoder().encode(
    ["bytes32", "bytes32", "bytes32"],
    [commitment, nullifier, secret]
  );

  return result;
}

(async () => {
  generateCommitment()
    .then((result) => {
      process.stdout.write(result);
      process.exit(0);
    })
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
})();
