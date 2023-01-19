//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity 0.8.8;

contract dateTime {

    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
    uint256 constant SECONDS_PER_HOUR = 60 * 60;
    uint256 constant SECONDS_PER_MINUTE = 60;
    int256 constant OFFSET19700101 = 2440588;

    uint256 constant DOW_MON = 1;
    uint256 constant DOW_TUE = 2;
    uint256 constant DOW_WED = 3;
    uint256 constant DOW_THU = 4;
    uint256 constant DOW_FRI = 5;
    uint256 constant DOW_SAT = 6;
    uint256 constant DOW_SUN = 7;

    function _daysToDate(uint256 _days) internal pure returns (uint256 year, uint256 month, uint256 day) {
        unchecked {
            int256 __days = int256(_days);

            int256 L = __days + 68569 + OFFSET19700101;
            int256 N = (4 * L) / 146097;
            L = L - (146097 * N + 3) / 4;
            int256 _year = (4000 * (L + 1)) / 1461001;
            L = L - (1461 * _year) / 4 + 31;
            int256 _month = (80 * L) / 2447;
            int256 _day = L - (2447 * _month) / 80;
            L = _month / 11;
            _month = _month + 2 - 12 * L;
            _year = 100 * (N - 49) + _year + L;

            year = uint256(_year);
            month = uint256(_month);
            day = uint256(_day);
        }
    }

    function getYear(uint256 timestamp) internal pure returns (uint256 year) {
        (year,,) = _daysToDate(timestamp / SECONDS_PER_DAY);
    }

    function getMonth(uint256 timestamp) public pure returns (uint256 month) {
        (, month,) = _daysToDate(timestamp / SECONDS_PER_DAY);
    }

    function getDay(uint256 timestamp) public pure returns (uint256 day) {
        (,, day) = _daysToDate(timestamp / SECONDS_PER_DAY);
    }

    function getHour(uint256 timestamp) public pure returns (uint256 hour) {
        uint256 secs = timestamp % SECONDS_PER_DAY;
        hour = secs / SECONDS_PER_HOUR;
    }

    function getMinute(uint256 timestamp) public pure returns (uint256 minute) {
        uint256 secs = timestamp % SECONDS_PER_HOUR;
        minute = secs / SECONDS_PER_MINUTE;
    }

    function getSecond(uint256 timestamp) public pure returns (uint256 second) {
        second = timestamp % SECONDS_PER_MINUTE;
    }
}

contract TimeVolumeRegistery is Ownable, dateTime{

    mapping(uint256=>mapping(uint256=>mapping(uint256=>uint256))) timeVolume;
    mapping(uint256=>mapping(uint256=>mapping(uint256=>bool))) isZero;

    uint256 public lastSubmissionYear;
    uint256 public lastSubmissionMonth;
    uint256 public lastSubmissionDay;
    uint256 public lastSubmitedVolume;
    uint256 public firstNonZeroSubmission;
    

    function submitNewVolume(uint256 volume) external onlyOwner{
        uint256 submitedyear = getYear(block.timestamp);
        uint256 submitedMonth = getMonth(block.timestamp);
        uint256 submitedDay = getDay(block.timestamp); 
        if(submitedyear > lastSubmissionYear){
            lastSubmissionYear = submitedyear;
            lastSubmissionMonth = submitedMonth;
            lastSubmissionDay = submitedDay;
        }
        if(submitedMonth > lastSubmissionMonth){
            lastSubmissionMonth = submitedMonth;
            lastSubmissionDay = submitedDay;
        }
        if(submitedDay > lastSubmissionDay){
            lastSubmissionDay = submitedDay;
        }

        submitedyear = lastSubmissionYear;
        submitedMonth = lastSubmissionMonth;
        submitedDay = lastSubmissionDay;

        timeVolume[submitedyear][submitedMonth][submitedDay] = volume;

        if(volume == 0){
            isZero[submitedyear][submitedMonth][submitedDay] = true;
        }else{
            isZero[submitedyear][submitedMonth][submitedDay] = false;
            if(firstNonZeroSubmission == 0){
                firstNonZeroSubmission = block.timestamp;
            }
        }

        lastSubmitedVolume = volume;
    }


    function getVolume(uint256 ts) external view returns(uint256) {
        uint256 year = getYear(ts);
        uint256 month = getMonth(ts);
        uint256 day = getDay(ts);        
        return timeVolume[year][month][day];
    }

    function getlastWeekVolume() external view returns(uint256[] memory) {
        uint256 currentTime = block.timestamp;
        uint256 year;
        uint256 month;
        uint256 day;
        uint256 dayVolume;
        bool isZeroVolume;
        uint256 lastVolume = lastSubmitedVolume;
        uint256[] memory volumes = new uint256[](7);
        for(uint i = 0; i < 7; i++){
            year = getYear(currentTime);
            month = getMonth(currentTime);
            day = getDay(currentTime);
            dayVolume = timeVolume[year][month][day];
            isZeroVolume = isZero[year][month][day]; 
            if(dayVolume != lastVolume){
                if(dayVolume == 0){
                    if(isZeroVolume){
                        lastVolume = dayVolume;
                    }else if(firstNonZeroSubmission > currentTime) {
                        volumes[i] = dayVolume;
                    }else{
                        volumes[i] = lastVolume;
                    }
                }else{
                    volumes[i] = dayVolume;
                    lastVolume = dayVolume;
                } 
            }else{
                volumes[i] = lastVolume; 
            }
            currentTime -= 1 days; //going back by 1 day
        }
        return volumes;
    } 

}
