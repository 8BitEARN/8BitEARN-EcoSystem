//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity 0.8.8;

contract Bitdistributor is Ownable {

    mapping(address=>mapping(uint256=>mapping(address=>uint256))) claimAmounts;
    mapping(uint256=>mapping(address=>uint256)) poolClaimed;
    mapping(uint256=>mapping(address=>uint256)) PoolsToClaim; // assigned claim amount for each address in a pool
    mapping(uint256=>ERC20) poolTokens;

    //events
    event claimed(address indexed claimer, uint256 indexed claimAmount, uint256 indexed claimPool);
    event claimSet(address indexed claimer, uint256 indexed claimAmount, uint256 indexed claimPool);

    function setClaimToken(address _claimToken, uint256 _poolId) external onlyOwner {
        poolTokens[_poolId] = ERC20(_claimToken);
    }

    //0 => vested
    //1 => diamond hand
    //2 => revenue
    function setClaimAmount(address _claimer, uint256 _toClaim, uint256 _claimPool) external onlyOwner {
        PoolsToClaim[_claimPool][_claimer] = _toClaim;
        emit claimSet(_claimer, _toClaim, _claimPool);
    }


    function setClaimBatch(address[] calldata _claimers, uint256[] calldata _toClaims, uint256 _claimPool) external onlyOwner{
        require(_claimers.length == _toClaims.length, "Length Mismatch!");
        for(uint256 i = 0; i < _claimers.length; i++){
            PoolsToClaim[_claimPool][_claimers[i]] = _toClaims[i];
            emit claimSet(_claimers[i], _toClaims[i], _claimPool);
        }
    }


    function claim(uint256 _claimPool) external {
        uint256 toClaim = PoolsToClaim[_claimPool][msg.sender];

        //Validating
        require(toClaim > 0, "You are not eligible to claim any tokens!");

        ERC20 _poolToken = poolTokens[_claimPool];

        //Transferring tokens
        _poolToken.transfer(msg.sender, toClaim);

        //Zeroing claim amount and also emitting an event
        PoolsToClaim[_claimPool][msg.sender] = 0;
        claimAmounts[msg.sender][_claimPool][address(_poolToken)] += toClaim;
        poolClaimed[_claimPool][address(_poolToken)] += toClaim;

        emit claimed(msg.sender, toClaim, _claimPool);
    }

    function withdrawTokens(address token) external onlyOwner{
        ERC20(token).transfer(msg.sender, ERC20(token).balanceOf(address(this)));
    }

    function unClaimed(address _claimer, uint256 _claimPool) public view returns(uint256){
        return PoolsToClaim[_claimPool][_claimer];
    }

    function Claimed(address _claimer, uint256 _poolId) public view returns(uint256){
        address _poolToken = address(poolTokens[_poolId]);
        return claimAmounts[_claimer][_poolId][address(_poolToken)];
    }

    function totalPoolClaimed(uint256 _claimPool, address _token) public view returns(uint256){
        return poolClaimed[_claimPool][_token];
    }

    function getPoolToken(uint256 _claimPool) public view returns(address){
        return address(poolTokens[_claimPool]);
    } 

    function getPoolTokenName(uint256 _claimPool) public view returns(string memory){
        return poolTokens[_claimPool].name();
    }

    function getPoolTokenSymbol(uint256 _claimPool) public view returns(string memory){
        return poolTokens[_claimPool].symbol();
    }

    function getPoolTokenDecimals(uint256 _claimPool) public view returns(uint256){
        return poolTokens[_claimPool].decimals();
    }

    function getPoolTokenHoldings(uint256 _claimPool, address _claimer) public view returns(uint256){
        return poolTokens[_claimPool].balanceOf(_claimer);
    }

}