use poseidon::poseidon2::Poseidon2;
mod merkle_tree;
fn main(
    root: pub Field,
    nullifier_hash: pub Field,
    recepient: pub Field,
    // private
    nullifier: Field,
    secret: Field,
    merkle_proof: [Field; 20],
    is_even: [bool; 20],
) {
    let commitment: Field = Poseidon2::hash([nullifier, secret], 2); // recalculate root (if ok - continue)
    let computed_nullifier_hash: Field = Poseidon2::hash([nullifier], 1);
    assert(computed_nullifier_hash == nullifier_hash);

    let computed_root = merkle_tree::compute_merkle_root(commitment, merkle_proof, is_even);
    assert(computed_root == root);

    let recepient_binding = recepient * recepient;
    assert(recepient_binding == recepient * recepient);
}
