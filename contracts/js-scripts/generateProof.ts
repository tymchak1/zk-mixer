import { Barretenberg, UltraHonkBackend } from "@aztec/bb.js";
import { ethers } from "ethers";
import { merkleTree } from "./merkleTree.js";

// @ts-ignore
import { Noir } from "@noir-lang/noir_js";

import path from "path";
import fs from "fs";

const circuit = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, "../../circuits/target/circuits.json"), "utf8")
);

function hexToBuffer(hex: string): Uint8Array {
  return Uint8Array.from(Buffer.from(hex.replace("0x", "").padStart(64, "0"), "hex"));
}

function bufferToHex(buf: Uint8Array): string {
  return "0x" + Buffer.from(buf).toString("hex");
}

export default async function generateProof(): Promise<string> {
  const bb = await Barretenberg.new();

  const inputs = process.argv.slice(2);

  // args: nullifier, secret, recipient, ...leaves
  const nullifier = hexToBuffer(inputs[0]);
  const secret = hexToBuffer(inputs[1]);

  const { hash: nullifierHash } = await bb.poseidon2Hash({ inputs: [nullifier] });

  const leaves = inputs.slice(3);

  const tree = await merkleTree(leaves);
  const { hash: commitment } = await bb.poseidon2Hash({ inputs: [nullifier, secret] });
  const commitmentHex = bufferToHex(commitment);
  const merkleProof = tree.proof(tree.getIndex(commitmentHex));

  try {
    const noir = new Noir(circuit);
    const honk = new UltraHonkBackend(circuit.bytecode, bb);

    const input = {
      // Public inputs
      root: merkleProof.root,
      nullifier_hash: bufferToHex(nullifierHash),
      _recepient: inputs[2],

      // Private inputs
      nullifier: bufferToHex(nullifier),
      secret: bufferToHex(secret),
      merkle_proof: merkleProof.pathElements.map((i: string) => i.toString()),
      is_even: merkleProof.pathIndices.map((i: number) => i % 2 == 0),
    };

    const { witness } = await noir.execute(input);

    const originalLog = console.log;
    console.log = () => {};

    const { proof, publicInputs } = await honk.generateProof(witness, { verifierTarget: "evm" });

    console.log = originalLog;

    const result = ethers.AbiCoder.defaultAbiCoder().encode(
      ["bytes", "bytes32[]"],
      [proof, publicInputs]
    );

    return result;
  } catch (error) {
    console.error(error);
    throw error;
  }
}

(async () => {
  generateProof()
    .then((result) => {
      process.stdout.write(result);
      process.exit(0);
    })
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
})();
