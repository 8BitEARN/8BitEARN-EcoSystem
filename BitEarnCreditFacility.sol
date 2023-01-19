//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity 0.8.8;

interface IStaking{
    function getTotalStaked(address _staker, uint256 _poolId) external view returns(uint256);
    function getStakerEndTime(address _staker, uint256 _poolId) external view returns(uint256);
}

interface DexRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function WETH() external pure returns (address);
}

contract BitBUSDCredit is Ownable {

    /**
     * REPAY => borrowed BUSD, 30 days left for repay
     * DELAY_30 => 30 days passed but not repaid
     * DELAY_45 => 45 days passed but not repaid
     * PAID => paid borrowed BUSD
     */

    modifier onlyOwnerOrStaking() {
        require(msg.sender == owner() || msg.sender == address(stakingContract), "not authorized!");
        _;
    }

    enum BorrowStatus {
        REPAY,
        DELAY_30,
        DELAY_45,
        PAID,
        NOT_IN
    }

    struct Profile{
        BorrowStatus status;
        uint256 borrowedBUSD;
        uint256 collateraled;
        uint256 startingTime;
        uint256 repaid;
        uint256 repaidTime;
    }

    //BUSD Contract
    IERC20 public BUSD;
    uint256 public busdLimit = 300;

    mapping(address=>mapping(uint256=>Profile)) borrowers;
    mapping(address=>uint256) borrowTime;
    uint256 public totalBUSDBorrowed;

    //Staking Contract & token
    IStaking public stakingContract;
    IERC20 public stakingToken = IERC20(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);

    //Dex router
    DexRouter public dex;

    //Events
    event borrowed(address indexed borrower, uint256 indexed borrowAmount, uint256 indexed borrowEndTime);
    event repaid(address indexed borrower, uint256 indexed repayAmount);
    event borrowerReset(address indexed borrower, uint256 indexed borrowTime);


    constructor(address _router) {
        dex = DexRouter(_router);
    }

    function updateDex(address _newDex) external onlyOwner{
        require(_newDex != address(0), "Cant set dex to null address!");
        dex = DexRouter(_newDex);
    }

    function setStakingContract(address _stakingContract) external onlyOwner{
        stakingContract = IStaking(_stakingContract);
    }

    function setStakingToken(address _stakingToken) external onlyOwner{
        stakingToken = IERC20(_stakingToken);
    }

    function setBUSDToken(address _busdToken) external onlyOwner{
        BUSD = IERC20(_busdToken);
    }

    function BorrowBUSD(uint256 _toBorrow) public {
        //Making sure that borrower is staking in credit pool
        uint256 totalStaked = stakingContract.getTotalStaked(msg.sender, 2);
        require(_toBorrow > 0, "Can not borrow zero BUSD!");
        require(totalStaked > 0, "You are not staking any tokens in credit pool!");//@audit tested
        require(stakingContract.getStakerEndTime(msg.sender, 2) > block.timestamp, "Borrwing Time Has Ended!");
        require(stakingContract.getStakerEndTime(msg.sender, 2) - block.timestamp >= 30 days, "Borrowing Time Has Ended!");//@audit tested

        //Getting Profile
        uint256 index = borrowTime[msg.sender];
        Profile memory profile = borrowers[msg.sender][index];

        uint256 currentStatus = getBorrowerStatus(msg.sender, index);
        //Making sure that borrower is not in delay for paying
        //If borrower is in delay, he is considered as a bad actor and we dont want to loan him anymore!
        require(currentStatus == uint8(BorrowStatus.PAID) || currentStatus == uint8(BorrowStatus.REPAY) || currentStatus == uint8(BorrowStatus.NOT_IN), "You did not re-pay your busd!");
        //getting the amount that can be collateraled for getting BUSD, this amount is less than 30% of total staking 8Bit!
        uint256 canBeCollateraled = getCanBeCollateraled(msg.sender, index);

        //toCollateral is the number of tokens that should be collateraled in order to get _toBorrow amount of BUSD, we achieve
        //this number by using pancakeswap router!
        uint256 toCollateral = BUSDTo8Bit(_toBorrow);
        require(toCollateral <= canBeCollateraled, "Insufficient 8Bit Tokens!");
        
        /**
         * Updating profile status to REPAY, meaning that borrower should repay his BUSD
         * Saving Borrowed BUSD
         * Saving Total Collateraled 8Bit
         */
        if(profile.startingTime == 0){
            profile.startingTime = block.timestamp;
        }
        profile.borrowedBUSD += _toBorrow;
        profile.collateraled += toCollateral;

        totalBUSDBorrowed += _toBorrow;

        emit borrowed(msg.sender, _toBorrow, profile.startingTime + 90 days);
        //Saving profile to storage
        borrowers[msg.sender][index] = profile;

        //Transferring BUSD to borrower
        BUSD.transfer(msg.sender, _toBorrow);

    }

    function RepayBUSD(uint256 _repayAmount) public {
        //Getting Profile
        uint256 index = borrowTime[msg.sender];
        Profile memory profile = borrowers[msg.sender][index];
        require(profile.borrowedBUSD > 0 && profile.repaid < profile.borrowedBUSD, "You already repaid, or you did not borrow before");

        //repaying2
        _repayAmount = _repayAmount > profile.borrowedBUSD? profile.borrowedBUSD : _repayAmount;
        profile.repaid += _repayAmount;
        BUSD.transferFrom(msg.sender, address(this), _repayAmount);

        if(profile.repaid == profile.borrowedBUSD){
            profile.repaidTime = block.timestamp;
            borrowTime[msg.sender] += 1;
        }

        totalBUSDBorrowed -= _repayAmount;

        emit repaid(msg.sender, _repayAmount);

        borrowers[msg.sender][index] = profile;
    }

    function resetBorrower(address _staker) public onlyOwnerOrStaking{
        borrowTime[_staker] += 1;
        emit borrowerReset(_staker, borrowTime[_staker]);
    }

    function getBorrowerStatus(address _borrower, uint256 _index) public view returns(uint256) { // getting status based on time and paid values
        //Getting Profile
        Profile memory profile = borrowers[_borrower][_index];

        uint256 startTime = profile.startingTime;
        uint256 elapsed = block.timestamp - startTime;

        //if borrowed and if already paid all => paid status
        if(profile.borrowedBUSD == profile.repaid && profile.borrowedBUSD > 0 && profile.repaidTime > 0){
            return 3;
        }
        if(startTime > 0){
            if(elapsed < 30 days){
                return 0; // repay status
            }else if(elapsed < 45 days && elapsed >= 30 days){
                return 1; // delay 30 => close rewards
            }else if(elapsed >= 45 days){
                return 2; // delay 45 => give access to protocol to withdraw staked tokens
            }
        }
        return 4;
    }

    function setBUSDLimit(uint256 _newLimit) external onlyOwner{
        require(_newLimit <= 1000, "Can not set over 1000");
        busdLimit = _newLimit;
    }


    function getBorrowTime(address _borrower) public view returns(uint256){
        return borrowTime[_borrower];
    }
    

    function getTotalBorrowedBUSD(address _borrower, uint256 _borrowTime) public view returns(uint256){
        Profile memory profile = borrowers[_borrower][_borrowTime];
        return profile.borrowedBUSD;
    }

    
    function getTotalRepaidBUSD(address _borrower, uint256 _borrowTime) public view returns(uint256){
        Profile memory profile = borrowers[_borrower][_borrowTime];
        return profile.repaid;
    }


    function getTotalCollateraled8Bit(address _borrower, uint256 _borrowTime) public view returns(uint256){
        Profile memory profile = borrowers[_borrower][_borrowTime];
        return profile.collateraled;
    }


    function getBorrowStartTime(address _borrower, uint256 _borrowTime) public view returns(uint256){
        Profile memory profile = borrowers[_borrower][_borrowTime];
        return profile.startingTime;
    }


    function getRepaidTime(address _borrower, uint256 _borrowTime) public view returns(uint256){
        Profile memory profile = borrowers[_borrower][_borrowTime];
        return profile.repaidTime;
    }


    function getNotRepaid(address _borrower, uint256 _borrowTime) public view returns(uint256){
        Profile memory profile = borrowers[_borrower][_borrowTime];
        return profile.borrowedBUSD - profile.repaid;
    }


    function getCanBeCollateraled(address _borrower, uint256 _borrowTime) public view returns(uint256){
        uint256 totalStaked = stakingContract.getTotalStaked(_borrower, 2);
        Profile memory profile = borrowers[_borrower][_borrowTime];
        return ((totalStaked * busdLimit) / 1000) - profile.collateraled;
    }


    function getCanBeBorrowedBUSD(address _borrower, uint256 _borrowTime) public view returns(uint256){
        uint256 CanBeCollateraled = getCanBeCollateraled(_borrower, _borrowTime);
        return EightBitToBUSD(CanBeCollateraled);
    }


    function BUSDTo8Bit(uint256 _BUSDAmount) public view returns(uint256){
        if(_BUSDAmount == 0){
            return 0;
        }
        uint256 BNBPrice = getBNBPrice();
        uint256 BitPrice = get8BitPrice();

        uint256 BNBAmount = (_BUSDAmount * 1e18) / BNBPrice;
        return (BNBAmount * 1e18) / BitPrice;
    }


    //Converting 8Bit to BUSD
    function EightBitToBUSD(uint256 _8BitAmount) public view returns(uint256){
        if(_8BitAmount == 0){
            return 0;
        }
        uint256 BNBPrice = getBNBPrice();
        
        uint256 BitPrice = get8BitPrice();
        uint256 BNBAmount = (_8BitAmount * BitPrice) / 1e18;
        return (BNBAmount * BNBPrice) / 1e18;
    }

    function getBNBPrice() public view returns(uint256){
        address[] memory path = new address[](2);
        path[0] = address(dex.WETH());
        path[1] = address(BUSD);
        uint256 BUSDPerWETH = dex.getAmountsOut(1e18, path)[1];
        return BUSDPerWETH;
    }

    function get8BitPrice() public view returns(uint256){
        address[] memory path = new address[](2);
        path[0] = address(stakingToken);
        path[1] = address(dex.WETH());
        uint256 WETHPer8BIT = dex.getAmountsOut(1e18, path)[1];
        return WETHPer8BIT;
    }

    function withdrawBUSDProtocol(uint256 _busdAmount) public onlyOwner{
        BUSD.transfer(msg.sender, _busdAmount);
    }

    function withdrawStuckTokens(address _token) public onlyOwner{
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

    function withdrawStuckBNB() public payable onlyOwner{
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable{}

}