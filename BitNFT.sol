//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

pragma solidity 0.8.8;

contract BitNFT is ERC721 {

    uint256 public tokenId;
    constructor() ERC721("8Bit", "8BitNFT"){
       
    }

    function mint() public {
        tokenId += 1;
        _mint(msg.sender, tokenId);
    }

}