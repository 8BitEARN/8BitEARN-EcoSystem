pragma solidity =0.5.16;

import "./ProDexV2Pair.sol";

contract CC {
    bytes32 public cc;

    constructor() public {
        cc = keccak256(type(ProDexV2Pair).creationCode);
    }
}
