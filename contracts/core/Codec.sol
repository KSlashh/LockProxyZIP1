pragma solidity ^0.8.0;

import "../libs/common/ZeroCopySink.sol";
import "../libs/common/ZeroCopySource.sol";

library Codec {

    bytes1 constant LOCK_TAG = 0x01;
    bytes1 constant UNLOCK_TAG = 0x02;
    bytes1 constant ROLLBACK_TAG = 0x03;
    bytes1 constant ADD_LIQUIDITY_TAG = 0x04;
    bytes1 constant REMOVE_LIQUIDITY_TAG = 0x05;
    bytes1 constant PAUSE_TAG = 0x06;
    bytes1 constant UNPAUSE_TAG = 0x07;

    function getTag(bytes memory message) pure public returns(bytes1) {
        return message[0];
    }
    

    function encodeLockMessage(bytes memory fromAsset, bytes memory toAddress, bytes memory refundAddress,  uint64 toChainId, uint amount) pure public returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            LOCK_TAG,
            ZeroCopySink.WriteVarBytes(fromAsset),
            ZeroCopySink.WriteVarBytes(toAddress),
            ZeroCopySink.WriteVarBytes(refundAddress),
            ZeroCopySink.WriteUint64(toChainId),
            ZeroCopySink.WriteUint255(amount)
            );
        return buff;
    }
    function decodeLockMessage(bytes memory rawData) pure public returns(bytes memory fromAsset, bytes memory toAddress, bytes memory refundAddress, uint64 toChainId, uint amount) {
        require(rawData[0] == LOCK_TAG, "Not lock message");
        uint256 off = 1;
        (fromAsset, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (toAddress, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (refundAddress, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (toChainId, off) = ZeroCopySource.NextUint64(rawData, off);
        (amount, off) = ZeroCopySource.NextUint255(rawData, off);
    }


    function encodeUnlockMessage(bytes memory toAsset, bytes memory toAddress, uint amount) pure public returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            UNLOCK_TAG,
            ZeroCopySink.WriteVarBytes(toAsset),
            ZeroCopySink.WriteVarBytes(toAddress),
            ZeroCopySink.WriteUint255(amount)
            );
        return buff;
    }
    function decodeUnlockMessage(bytes memory rawData) pure public returns(bytes memory toAsset, bytes memory toAddress, uint amount) {
        require(rawData[0] == UNLOCK_TAG, "Not unlock message");
        uint256 off = 1;
        (toAsset, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (toAddress, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (amount, off) = ZeroCopySource.NextUint255(rawData, off);
    }
    

    function encodeRollBackMessage(bytes memory fromAsset, bytes memory refundAddress, uint amount) pure public returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            ROLLBACK_TAG,
            ZeroCopySink.WriteVarBytes(fromAsset),
            ZeroCopySink.WriteVarBytes(refundAddress),
            ZeroCopySink.WriteUint255(amount)
            );
        return buff;
    }
    function decodeRollBackMessage(bytes memory rawData) pure public returns(bytes memory fromAsset, bytes memory refundAddress, uint amount) {
        require(rawData[0] == ROLLBACK_TAG, "Not rollback message");
        uint256 off = 1;
        (fromAsset, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (refundAddress, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (amount, off) = ZeroCopySource.NextUint255(rawData, off);
    }


    function encodeAddLiquidityMessage(bytes memory fromAsset, bytes memory beneficiary, bytes memory refundAddress, uint64 beneficiaryChainId, uint amount) pure public returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            ADD_LIQUIDITY_TAG,
            ZeroCopySink.WriteVarBytes(fromAsset),
            ZeroCopySink.WriteVarBytes(beneficiary),
            ZeroCopySink.WriteVarBytes(refundAddress),
            ZeroCopySink.WriteUint64(beneficiaryChainId),
            ZeroCopySink.WriteUint255(amount)
            );
        return buff;
    }
    function decodeAddLiquidityMessage(bytes memory rawData) pure public returns(bytes memory fromAsset, bytes memory beneficiary, bytes memory refundAddress, uint64 beneficiaryChainId, uint amount) {
        require(rawData[0] == ADD_LIQUIDITY_TAG, "Not add_liquidity message");
        uint256 off = 1;
        (fromAsset, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (beneficiary, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (refundAddress, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (beneficiaryChainId, off) = ZeroCopySource.NextUint64(rawData, off);
        (amount, off) = ZeroCopySource.NextUint255(rawData, off);
    }


    function encodeRemoveLiquidityMessage(bytes memory toAsset, bytes memory provider, bytes memory toAddress, uint64 toChainId, uint amount) pure public returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            REMOVE_LIQUIDITY_TAG,
            ZeroCopySink.WriteVarBytes(toAsset),
            ZeroCopySink.WriteVarBytes(provider),
            ZeroCopySink.WriteVarBytes(toAddress),
            ZeroCopySink.WriteUint64(toChainId),
            ZeroCopySink.WriteUint255(amount)
            );
        return buff;
    }
    function decodeRemoveLiquidityMessage(bytes memory rawData) pure public returns(bytes memory toAsset, bytes memory provider, bytes memory toAddress, uint64 toChainId, uint amount) {
        require(rawData[0] == REMOVE_LIQUIDITY_TAG, "Not remove_liquidity message");
        uint256 off = 1;
        (toAsset, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (provider, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (toAddress, off) = ZeroCopySource.NextVarBytes(rawData, off);
        (toChainId, off) = ZeroCopySource.NextUint64(rawData, off);
        (amount, off) = ZeroCopySource.NextUint255(rawData, off);
    }


    function encodePauseMessage(bool needWait) pure public returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            PAUSE_TAG,
            ZeroCopySink.WriteBool(needWait)
            );
        return buff;
    }
    function decodePauseMessage(bytes memory rawData) pure public returns(bool needWait) {
        require(rawData[0] == PAUSE_TAG, "Not pause message");
        (needWait, ) = ZeroCopySource.NextBool(rawData, 1);
    }


    function encodeUnpauseMessage(bool needWait) pure public returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            UNPAUSE_TAG,
            ZeroCopySink.WriteBool(needWait)
            );
        return buff;
    }
    function decodeUnpauseMessage(bytes memory rawData) pure public returns(bool needWait) {
        require(rawData[0] == UNPAUSE_TAG, "Not unpause message");
        (needWait, ) = ZeroCopySource.NextBool(rawData, 1);
    }

}