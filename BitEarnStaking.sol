//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TimeVolumeRegistery.sol";

pragma solidity 0.8.8;

contract DSMath {
  function add(uint x, uint y) internal pure returns (uint z) {
    require((z = x + y) >= x, "ds-math-add-overflow");
  }

  function sub(uint x, uint y) internal pure returns (uint z) {
    require((z = x - y) <= x, "ds-math-sub-underflow");
  }

  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
  }

  function min(uint x, uint y) internal pure returns (uint z) {
    return x <= y ? x : y;
  }

  function max(uint x, uint y) internal pure returns (uint z) {
    return x >= y ? x : y;
  }

  function imin(int x, int y) internal pure returns (int z) {
    return x <= y ? x : y;
  }

  function imax(int x, int y) internal pure returns (int z) {
    return x >= y ? x : y;
  }

  uint constant WAD = 10 ** 18;
  uint constant RAY = 10 ** 27;

  function wmul(uint x, uint y) internal pure returns (uint z) {
    z = add(mul(x, y), WAD / 2) / WAD;
  }

  function rmul(uint x, uint y) internal pure returns (uint z) {
    z = add(mul(x, y), RAY / 2) / RAY;
  }

  function wdiv(uint x, uint y) internal pure returns (uint z) {
    z = add(mul(x, WAD), y / 2) / y;
  }

  function rdiv(uint x, uint y) internal pure returns (uint z) {
    z = add(mul(x, RAY), y / 2) / y;
  }

  function rpow(uint x, uint n) internal pure returns (uint z) {
    z = n % 2 != 0 ? x : RAY;

    for (n /= 2; n != 0; n /= 2) {
      x = rmul(x, x);

      if (n % 2 != 0) {
        z = rmul(z, x);
      }
    }
  }
}

interface ICreditFacility {
  function getBorrowerStatus(
    address _borrower,
    uint256 _index
  ) external view returns (uint256);

  function getBorrowTime(address _borrower) external view returns (uint256);

  function getTotalBorrowedBUSD(
    address _borrower,
    uint256 _borrowTime
  ) external view returns (uint256);

  function getTotalRepaidBUSD(
    address _borrower,
    uint256 _borrowTime
  ) external view returns (uint256);

  function getTotalCollateraled8Bit(
    address _borrower,
    uint256 _borrowTime
  ) external view returns (uint256);

  function getBorrowStartTime(
    address _borrower,
    uint256 _borrowTime
  ) external view returns (uint256);

  function getRepaidTime(
    address _borrower,
    uint256 _borrowTime
  ) external view returns (uint256);

  function resetBorrower(address _staker) external;
}

contract BitStaking is DSMath, Ownable {
  using SafeERC20 for IERC20;

  struct StakingPool {
    bool Locked;
    uint256 LockTime;
    uint256 APY;
    uint256 fee;
    uint256 minToStake;
  }

  //Each staker has a StakeProfile for each pool, this profiles are stored in "stakers" mapping
  struct StakeProfile {
    uint256 totalStaked;
    uint256 unlockTime;
    uint256 lastClaimTime;
    uint256 stakingStart;
    uint256 totalClaimed;
  }

  struct APYCheckPoint {
    uint256[3] APYs;
    uint256 startTime;
  }

  //Staking token, pools and stakers
  uint256 public totalStaked;
  IERC20 public stakingToken;
  ICreditFacility public creditFacility;
  mapping(uint256 => StakingPool) Pools;
  mapping(address => mapping(uint256 => StakeProfile)) stakers;
  mapping(uint256 => uint256) poolStaked;
  APYCheckPoint[] apyCheckpoints;

  //NFT Contracts, To Check If Someone holds NFT or not
  address[] public NFTs;
  uint256 public stakingStart = 0;
  address public RewardsFeeReceiver =
    0x5236925F1a6d86c5819Cf25AFa41B979620d3eC2;
  uint256 public tokenDecimals;
  address public stakingVault;
  TimeVolumeRegistery public timeVolumeRegistery;

  //events
  event StakingStarted(uint256 indexed startTime);
  event Staked(
    address indexed staker,
    uint256 indexed amount,
    uint256 indexed poolid
  );
  event Unstaked(
    address indexed staker,
    uint256 indexed amount,
    uint256 indexed poolId
  );
  event Penaltied(address indexed staker, uint256 indexed penaltyAmount);
  event EmergencyWithdrawed(address indexed staker, uint256 indexed poolId);
  event Claimed(address indexed staker, uint256 indexed amount);

  constructor(address _stakingToken) {
    /**
     * Pools:
     * Id-0 : Standard pool 30 days period
     * Id-1 : NFT pool 30 days period
     * Id-2 : Credit Pool
     */
    stakingToken = IERC20(_stakingToken);
    uint256 decimals = 18;
    tokenDecimals = decimals;

    //Standard Pools => not locked, 30days, 12% APY, 20% fee for early unstake, 5, 000 8Bit minimum for staking
    Pools[0] = StakingPool(false, 30 days, 12, 200, 5000 * 10 ** decimals);

    //NFT Pools => not locked, 30 days, 36% APY, 20% fee for early unstake, 25, 000 8Bit minimum for staking
    Pools[1] = StakingPool(false, 30 days, 36, 200, 25000 * 10 ** decimals);

    //Credit Pool => locked, 90 days period, 36% APY, 0 Fee as its locked, 150, 000 8Bit minimum for staking
    Pools[2] = StakingPool(true, 90 days, 36, 0, 150000 * 10 ** decimals);

    timeVolumeRegistery = new TimeVolumeRegistery();
  }

  function setCreditFacility(address facility) public onlyOwner {
    creditFacility = ICreditFacility(facility);
  }

  function setStakingToken(address _stakingToken) public onlyOwner {
    stakingToken = ERC20(_stakingToken);
  }

  function setStakingVault(address _valut) external onlyOwner {
    stakingVault = _valut;
  }

  function StartStaking() external onlyOwner {
    require(stakingStart == 0, "Staking already started!");
    stakingStart = block.timestamp;

    uint256[3] memory APYs = [uint256(12), uint256(36), uint256(36)];
    apyCheckpoints.push(APYCheckPoint(APYs, block.timestamp));

    emit StakingStarted(block.timestamp);
  }

  function changeAPY(uint256 _poolId, uint256 _newAPY) external onlyOwner {
    Pools[_poolId].APY = _newAPY;
    APYCheckPoint memory lastPoint = apyCheckpoints[apyCheckpoints.length - 1];
    lastPoint.APYs[_poolId] = _newAPY;
    lastPoint.startTime = block.timestamp;
    apyCheckpoints.push(lastPoint);
  }

  function changeMinTokensToEnter(
    uint256 _poolId,
    uint256 _newMin
  ) external onlyOwner {
    Pools[_poolId].minToStake = _newMin;
  }

  function AddNFT(address _newNFT) external onlyOwner {
    NFTs.push(_newNFT);
  }

  function removeNFT(address _NFT) external onlyOwner {
    address[] memory nfts = NFTs;
    for (uint256 i = 0; i < nfts.length; i++) {
      if (nfts[i] == _NFT) {
        NFTs[i] = nfts[nfts.length - 1];
        NFTs.pop();
        break;
      }
    }
  }

  function StakeTokens(uint256 poolId, uint256 toStake) external {
    //Saving our target pool in memory to save gas!
    StakingPool memory targetPool = Pools[poolId];
    //Getting balance of holder to make sure he is not staking all of his tokens! (more than 90%)
    uint256 balance = stakingToken.balanceOf(msg.sender);

    //Validating Here
    require(poolId < 3, "Invalid Pool!");
    require(stakingStart > 0, "Staking not started yet!");
    require(
      toStake >= targetPool.minToStake,
      "You cant stake less than minimum!"
    );
    require(
      (toStake * 10000) / balance <= 9999,
      "You cant stake more than 99% of your holdings!"
    );

    //For NFT pools we want to make sure that staker is nft holder or not, so we will check his balance across all of
    //NFT contracts
    if (poolId == 1) {
      require(
        checkIfHoldsNFT(msg.sender) == true,
        "You cant stake in nft pool, since you dont have any nfts!"
      );
    }

    //Updating staker profile
    //first we save staker profile in memory to save a huge amount of gas!
    StakeProfile memory profile = stakers[msg.sender][poolId];

    //Updating total staked and also lock time
    profile.totalStaked += toStake;
    profile.unlockTime = block.timestamp + targetPool.LockTime;
    if (profile.stakingStart == 0) {
      profile.stakingStart = block.timestamp;
      profile.lastClaimTime = block.timestamp;
    }

    //Saving profile back to storage!
    stakers[msg.sender][poolId] = profile;
    poolStaked[poolId] += toStake;

    //finally we transfer the tokens to the pool
    totalStaked += toStake;
    stakingToken.safeTransferFrom(msg.sender, address(this), toStake);

    timeVolumeRegistery.submitNewVolume(getPoolStakedTokens(2));

    emit Staked(msg.sender, toStake, poolId);
  }

  function Unstake(uint256 _poolId, uint256 _toUnstake) public {
    StakingPool memory targetPool = Pools[_poolId];
    StakeProfile memory profile = stakers[msg.sender][_poolId];

    require(profile.totalStaked > 0, "You did not stake any 8Bit!");
    require(_poolId < 3, "Invalid Pool!");
    require(_toUnstake <= profile.totalStaked, "Insufficient staking balance!");

    if (_poolId == 2) {
      require(
        profile.unlockTime <= block.timestamp,
        "You can not unstake now!"
      );
      uint256 borrowIndex = creditFacility.getBorrowTime(msg.sender);
      uint256 borrowStatus = creditFacility.getBorrowerStatus(
        msg.sender,
        borrowIndex
      );
      require(
        borrowStatus != 1 && borrowStatus != 2,
        "You are in delay for repaying BUSD, so you can not unstake!"
      );
    }

    uint256 earlyFee = targetPool.fee;
    uint256 rewards = getRewards(msg.sender, _poolId);
    if (rewards > 0 && earlyFee > 0) {
      if (profile.unlockTime >= block.timestamp) {
        stakingToken.safeTransferFrom(
          stakingVault,
          RewardsFeeReceiver,
          (rewards * earlyFee) / 1000
        );
        rewards -= (rewards * earlyFee) / 1000;
      }
    }

    profile.totalStaked -= _toUnstake;
    profile.lastClaimTime = block.timestamp;
    profile.totalClaimed += rewards;
    if (profile.totalStaked == 0) {
      profile.unlockTime = 0;
      profile.stakingStart = 0;
      profile.lastClaimTime = 0;
      if (_poolId == 2) {
        creditFacility.resetBorrower(msg.sender);
      }
    }
    totalStaked -= _toUnstake;

    stakers[msg.sender][_poolId] = profile;
    poolStaked[_poolId] -= _toUnstake;

    stakingToken.safeTransfer(msg.sender, _toUnstake);

    if (rewards > 0) {
      stakingToken.safeTransferFrom(stakingVault, msg.sender, rewards);
    }

    timeVolumeRegistery.submitNewVolume(getPoolStakedTokens(2));
    emit Unstaked(msg.sender, _toUnstake, _poolId);
  }

  function claimRewards(uint256 _poolId) public {
    StakeProfile memory profile = stakers[msg.sender][_poolId];
    require(profile.totalStaked > 0, "You did not stake any 8Bit!");

    if (_poolId == 2) {
      uint256 borrowIndex = creditFacility.getBorrowTime(msg.sender);
      uint256 borrowStatus = creditFacility.getBorrowerStatus(
        msg.sender,
        borrowIndex
      );
      require(
        borrowStatus != 1 && borrowStatus != 2,
        "You cant claim rewards!"
      );
    }

    uint256 rewards = getRewards(msg.sender, _poolId);
    profile.lastClaimTime = block.timestamp;
    profile.totalClaimed += rewards;
    stakers[msg.sender][_poolId] = profile;

    stakingToken.safeTransferFrom(stakingVault, msg.sender, rewards);

    timeVolumeRegistery.submitNewVolume(getPoolStakedTokens(2));
    emit Claimed(msg.sender, rewards);
  }

  //Emergency withdraw only for standard and nft pools
  function emergencyWithdraw(uint256 _poolId) public {
    //Saving our target pool & staker profile in memory to save gas!
    StakeProfile memory profile = stakers[msg.sender][_poolId];

    require(profile.totalStaked > 0, "You did not stake any 8Bit!");

    if (_poolId == 2) {
      require(
        profile.unlockTime <= block.timestamp,
        "You can not unstake now!"
      );
      uint256 borrowIndex = creditFacility.getBorrowTime(msg.sender);
      uint256 borrowStatus = creditFacility.getBorrowerStatus(
        msg.sender,
        borrowIndex
      );
      require(
        borrowStatus != 1 && borrowStatus != 2,
        "You are in delay for repaying BUSD, so you can not unstake!"
      );
    }

    uint256 amountStaked = profile.totalStaked;
    profile.totalStaked -= amountStaked;
    totalStaked -= amountStaked;
    profile.unlockTime = 0;
    profile.stakingStart = 0;
    profile.lastClaimTime = 0;
    stakers[msg.sender][_poolId] = profile;
    stakingToken.safeTransfer(msg.sender, amountStaked);
    poolStaked[_poolId] -= amountStaked;
    timeVolumeRegistery.submitNewVolume(getPoolStakedTokens(2));
    emit EmergencyWithdrawed(msg.sender, _poolId);
  }

  function penaltyCreditPoolStaker(
    address _creditPoolStaker,
    address _to
  ) external onlyOwner {
    //Getting Stake Profile
    StakeProfile memory profile = stakers[_creditPoolStaker][2];
    uint256 rewards = getRewards(_creditPoolStaker, 2);
    uint256 staked = profile.totalStaked;
    uint256 borrowIndex = creditFacility.getBorrowTime(_creditPoolStaker);
    uint256 borrowStatus = creditFacility.getBorrowerStatus(
      _creditPoolStaker,
      borrowIndex
    );
    require(borrowStatus == 2, "You can not penalty this staker yet!");
    creditFacility.resetBorrower(_creditPoolStaker);
    profile.totalStaked = 0;
    profile.unlockTime = 0;
    profile.stakingStart = 0;
    profile.lastClaimTime = 0;
    totalStaked -= staked;
    stakingToken.safeTransfer(_to, staked);
    stakingToken.safeTransferFrom(stakingVault, _to, rewards);
    stakers[_creditPoolStaker][2] = profile;
    poolStaked[2] -= staked;
    timeVolumeRegistery.submitNewVolume(getPoolStakedTokens(2));
    emit Penaltied(_creditPoolStaker, staked);
  }

  function massPenaltyCreditPoolStakers(
    address[] memory _creditPoolStakers,
    address _to
  ) external onlyOwner {
    //Getting Stake Profile
    uint256 borrowIndex;
    uint256 borrowStatus;
    uint256 rewards;
    uint256 staked;
    address staker;
    uint256 totalStakePenaltied = 0;
    uint256 totalRewardsPenaltied = 0;
    StakeProfile memory profile;
    for (uint256 i = 0; i < _creditPoolStakers.length; i++) {
      staker = _creditPoolStakers[i];
      profile = stakers[staker][2];
      borrowIndex = creditFacility.getBorrowTime(staker);
      borrowStatus = creditFacility.getBorrowerStatus(staker, borrowIndex);
      if (borrowStatus == 2) {
        rewards = getRewards(staker, 2);
        creditFacility.resetBorrower(staker);
        staked = profile.totalStaked;
        profile.totalStaked = 0;
        profile.unlockTime = 0;
        profile.stakingStart = 0;
        profile.lastClaimTime = 0;
        totalStaked -= staked;
        totalStakePenaltied += staked;
        totalRewardsPenaltied += rewards;
        poolStaked[2] -= staked;
        emit Penaltied(staker, staked);
        stakers[staker][2] = profile;
      } else {
        continue;
      }
    }
    stakingToken.safeTransfer(_to, totalStakePenaltied);
    stakingToken.safeTransferFrom(stakingVault, _to, totalRewardsPenaltied);
    timeVolumeRegistery.submitNewVolume(getPoolStakedTokens(2));
  }

  function getRewards(
    address _staker,
    uint256 _poolId
  ) public view returns (uint256) {
    require(_poolId < 3, "Invalid Pool!");

    StakeProfile memory profile = stakers[_staker][_poolId];
    uint256 startTime = profile.lastClaimTime;
    uint256 endTime = block.timestamp;
    uint256 totalRewards;

    if (profile.totalStaked == 0) {
      return 0;
    }
    if (startTime == endTime) {
      return 0;
    }

    if (_poolId == 2) {
      uint256 borrowIndex = creditFacility.getBorrowTime(_staker);
      uint256 borrowStatus = creditFacility.getBorrowerStatus(
        _staker,
        borrowIndex
      );
      if (borrowStatus == 1 || borrowStatus == 2) {
        startTime = profile.lastClaimTime;
        endTime = profile.stakingStart + 30 days;
      } else if (borrowStatus == 3) {
        if (profile.lastClaimTime < profile.stakingStart + 30 days) {
          uint256 repaidTime = creditFacility.getRepaidTime(
            _staker,
            borrowIndex
          );
          totalRewards += _calculateRewardsTimeRange(
            _staker,
            _poolId,
            profile.lastClaimTime,
            profile.stakingStart + 30 days
          );
          startTime = repaidTime;
          endTime = block.timestamp;
        }
      }
    }

    totalRewards += _calculateRewardsTimeRange(
      _staker,
      _poolId,
      startTime,
      endTime
    );
    return totalRewards;
  }

  function _calculateRewardsTimeRange(
    address _staker,
    uint256 _poolId,
    uint256 _startTime,
    uint256 _endTime
  ) internal view returns (uint256) {
    StakeProfile memory profile = stakers[_staker][_poolId];
    if (_poolId == 1) {
      if (profile.totalStaked > 0) {
        if (checkIfHoldsNFT(_staker) == false) {
          _poolId = 0;
        }
      }
    }
    APYCheckPoint[] memory array = apyCheckpoints;
    uint256 startCheckPoint = findAPYAtTimestamp(_startTime);
    uint256 endCheckPoint = findAPYAtTimestamp(_endTime);
    uint256 endTime;
    uint256 totalRewards;
    if (startCheckPoint == endCheckPoint) {
      return
        calculateInteresetInSeconds(
          profile.totalStaked,
          array[startCheckPoint].APYs[_poolId],
          _endTime - _startTime
        ) - profile.totalStaked;
    }
    for (uint256 i = startCheckPoint; i <= endCheckPoint; i++) {
      if (i == endCheckPoint) {
        //if we are at last checkpoint
        endTime = _endTime;
      } else {
        //if we are not at last checkpoint
        endTime = array[i + 1].startTime;
      }
      totalRewards +=
        calculateInteresetInSeconds(
          profile.totalStaked,
          array[i].APYs[_poolId],
          endTime - _startTime
        ) -
        profile.totalStaked;
      if (i < endCheckPoint) {
        _startTime = array[i + 1].startTime;
      }
    }
    return totalRewards;
  }

  function calculateInteresetInSeconds(
    uint256 principal,
    uint256 apy,
    uint256 _seconds
  ) internal pure returns (uint256) {
    //Calculating the ratio per second
    //ratio per seconds
    uint256 _ratio = ratio(apy);
    //Interest after _seconds
    return accrueInterest(principal, _ratio, _seconds);
  }

  function ratio(uint256 n) internal pure returns (uint256) {
    uint256 numerator = n * 10 ** 25;
    uint256 denominator = 365 * 86400;
    uint256 result = uint256(10 ** 27) + uint256(numerator / denominator);
    return result;
  }

  function accrueInterest(
    uint _principal,
    uint _rate,
    uint _age
  ) internal pure returns (uint) {
    return rmul(_principal, rpow(_rate, _age));
  }

  function average(uint256 a, uint256 b) internal pure returns (uint256) {
    return (a & b) + (a ^ b) / 2;
  }

  function findAPYAtTimestamp(uint256 element) internal view returns (uint256) {
    APYCheckPoint[] memory array = apyCheckpoints;
    if (array.length == 0) {
      return 0;
    }
    uint256 low = 0;
    uint256 high = array.length;
    while (low < high) {
      uint256 mid = average(low, high);
      // Note that mid will always be strictly less than high (i.e. it will be a valid array index)
      // because Math.average rounds down (it does integer division with truncation).
      if (array[mid].startTime > element) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    if (low > 0) {
      return low - 1;
    }
    return low;
  }

  function checkIfHoldsNFT(address _staker) public view returns (bool) {
    //Saving Array To Memory To Save A Huge Amount Of Gas!
    address[] memory nfts = NFTs;
    if (nfts.length == 0) {
      return false;
    }

    for (uint256 i = 0; i < nfts.length; i++) {
      if (IERC721(nfts[i]).balanceOf(_staker) > 0) {
        return true;
      }
    }
    return false;
  }

  function getVolumeAtTimeStamp(uint256 ts) external view returns (uint256) {
    return timeVolumeRegistery.getVolume(ts);
  }

  function getLastWeekVolume() external view returns (uint256[] memory) {
    return timeVolumeRegistery.getlastWeekVolume();
  }

  //Getters
  function getPoolStakedTokens(uint256 _poolId) public view returns (uint256) {
    return poolStaked[_poolId];
  }

  function getTotalStaked(
    address _staker,
    uint256 _poolId
  ) public view returns (uint256) {
    return stakers[_staker][_poolId].totalStaked;
  }

  function getStakerEndTime(
    address _staker,
    uint256 _poolId
  ) public view returns (uint256) {
    return stakers[_staker][_poolId].unlockTime;
  }

  function getStakerStartTime(
    address _staker,
    uint256 _poolId
  ) public view returns (uint256) {
    return stakers[_staker][_poolId].stakingStart;
  }

  function getRemainingStakeTime(
    address _staker,
    uint256 _poolId
  ) public view returns (uint256) {
    if (block.timestamp >= getStakerEndTime(_staker, _poolId)) {
      return 0;
    }
    return getStakerEndTime(_staker, _poolId) - block.timestamp;
  }

  function getStakerLastClaimTime(
    address _staker,
    uint256 _poolId
  ) public view returns (uint256) {
    return stakers[_staker][_poolId].lastClaimTime;
  }

  function getAPYCheckPoint(
    uint256 index
  ) public view returns (APYCheckPoint memory) {
    return apyCheckpoints[index];
  }

  function getTotalClaimed(
    address _staker,
    uint256 _poolId
  ) public view returns (uint256) {
    return stakers[_staker][_poolId].totalClaimed;
  }

  function getPoolAPY(uint256 _poolId) public view returns (uint256) {
    return Pools[_poolId].APY;
  }

  function getPoolMinToEnter(uint256 _poolId) public view returns (uint256) {
    return Pools[_poolId].minToStake;
  }
}
