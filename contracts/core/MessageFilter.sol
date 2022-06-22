pragma solidity ^0.8.8;

interface IMessageFilter {
    function isValidMessage(uint64 branchChainId, bytes memory message) view external 
        returns(bool isValid, string memory error);

    function handleMessage(uint64 branchChainId, bytes memory message) external 
        returns(bool success, string memory error);
}

contract FreeAccess is IMessageFilter{

    function isValidMessage(uint64 branchChainId, bytes memory message) view public returns(bool isValid, string memory error) {
        return (true,"");
    }

    function handleMessage(uint64 branchChainId, bytes memory message) external returns(bool success, string memory error) {
        return (true,"");
    }
}