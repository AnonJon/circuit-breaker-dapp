// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AutomationCompatibleInterface} from "@chainlink/src/v0.8/automation/AutomationCompatible.sol";
import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract CircuitBreaker is AutomationCompatibleInterface {
    address public owner;
    ExternalContract externalContract;
    mapping(address => Limit) public limits;

    struct Limit {
        uint256 low;
        uint256 high;
        bool lowActive;
        bool highActive;
        address feed;
    }

    struct ExternalContract {
        address contractAddress;
        bytes functionSelector;
        bool status;
    }

    event LimitReached(uint256 lowLimit, uint256 highLimit, int256 currentPrice);
    event LimitUpdated(uint256 lowLimit, uint256 highLimit, bool lowActive, bool highActive, address feed);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    modifier onlyContract() {
        require(msg.sender == address(this) || msg.sender == owner, "Only this contract can call this function.");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function _getLatestPrice(address _feed) internal view returns (int256) {
        (, int256 price,,,) = AggregatorV3Interface(_feed).latestRoundData();
        return price;
    }

    function _getLimit(int256 price, address _feed) internal view returns (bool) {
        if (
            limits[_feed].lowActive && uint256(price) <= limits[_feed].low
                || limits[_feed].highActive && uint256(price) >= limits[_feed].high
        ) {
            return true;
        }
        return false;
    }

    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        (address _feed) = abi.decode(checkData, (address));
        int256 price = _getLatestPrice(_feed);
        upkeepNeeded = _getLimit(price, _feed);
        performData = checkData;
    }

    function performUpkeep(bytes calldata performData) external override {
        (address _feed) = abi.decode(performData, (address));
        int256 price = _getLatestPrice(_feed);
        bool upkeepNeeded = _getLimit(price, _feed);
        if (upkeepNeeded) {
            emit LimitReached(limits[_feed].low, limits[_feed].high, price);
            if (externalContract.status) customFunction();
        }
    }

    function customFunction() public onlyContract {
        (bool ok,) = externalContract.contractAddress.call(externalContract.functionSelector);
        require(ok, "External contract function call failed");
    }

    function setLimit(uint256 newLowLimit, uint256 newHighLimit, address _feed) external onlyOwner {
        require(_feed != address(0), "Feed address cannot be 0x");
        require(newLowLimit > 0 || newHighLimit > 0, "At least one limit must be set");
        bool lowActive = newLowLimit > 0;
        bool highActive = newHighLimit > 0;
        limits[_feed] = Limit(newLowLimit, newHighLimit, lowActive, highActive, _feed);
        emit LimitUpdated(newLowLimit, newHighLimit, lowActive, highActive, _feed);
    }

    function setCustomFunction(address externalContractFunction, bytes calldata functionSelectorHex)
        external
        onlyOwner
    {
        require(externalContractFunction != address(0), "Contract address cannot be 0x");
        require(functionSelectorHex.length > 0, "Function selector cannot be empty");
        externalContract = ExternalContract(externalContractFunction, functionSelectorHex, true);
    }
}
