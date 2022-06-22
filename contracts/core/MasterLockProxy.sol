pragma solidity ^0.8.12;

import "../libs/common/ZeroCopySink.sol";
import "../libs/common/ZeroCopySource.sol";
import "../libs/access/Ownable.sol";
import "./CrossChainGovernance.sol";
import "./Codec.sol";
import "./MessageFilter.sol";

contract MasterLockProxy is Ownable, Core {

    struct Token {
        uint64 chainId;
        bytes tokenAddress;
    }

    uint public newGroupIndex = 1;
    address public messageFilter;
    mapping(uint64 => mapping(bytes => uint)) public tokenGroupMap; // tokenGroupMap[tokenChainId][tokenAddress] = groupId
    mapping(uint => mapping(uint64 => bytes)) public groupTokenMap; // groupTokenMap[groupId][tokenChainId] = tokenAddress
    mapping(uint => bytes) public groupInfoMap; // groupInfoMap[groupId] = info 
    mapping(uint64 => mapping(bytes => mapping(uint => uint))) public liquidityOf; // liquidityOf[ownerChainId][ownerAddress][groupId] = amount
    mapping(uint => mapping(uint64 => uint)) public chainLiquidityMap; // chainLiquidityMap[groupId][chainId] = amount

    event BindBranchEvent(uint64 branchChainId, bytes branchAddress);
    event DeleteTokensEvent(uint groupId, uint64[] tokenChainIds);
    event DeleteGroupEvent(uint groupId);
    event CreateNewGroupEvent(uint groupId, Token[] tokens);
    event AddTokensToGrounpEvent(uint groupId, Token[] newTokens);
    
    event Pause(uint64[] chainIds, bool needWait);
    event Unpause(uint64[] chainIds, bool needWait);

    event RollBackEvent(bytes fromAsset, uint64 fromChainId, bytes refundAddress, uint amount, string err);
    event LockEvent(bytes fromAsset, uint64 fromChainId, bytes toAddress, uint64 toChainId, uint256 amount);
    event UnlockEvent(bytes toAsset, uint64 toChainId, bytes toAddress, uint amount);
    event AddLiquidityEvent(uint groupId, uint64 fromChainId, bytes beneficiary, uint64 beneficiaryChainId, uint amount);
    event RemoveLiquidityEvent(uint groupId, bytes provider, uint64 providerChainId, bytes toAddress, uint64 toChainId, uint amount);
    event RevertEvent(string err);
    
    function setMessageFilter(address messageFilterAddress) onlyOwner public {
        messageFilter = messageFilterAddress;
    }

    function bindBranch(uint64 branchChainId, bytes memory branchAddress) onlyOwner public {
        branchMap[branchChainId] = branchAddress;
        emit BindBranchEvent(branchChainId, branchAddress); 
    }

    function bindBranchBatch(uint64[] memory branchChainIds, bytes[] memory branchAddrs) onlyOwner public {
        require(branchChainIds.length == branchAddrs.length, "input lists length do not match");
        for (uint i = 0; i < branchChainIds.length; i++) {
            uint64 branchChainId = branchChainIds[i];
            bytes memory branchAddress = branchAddrs[i];
            branchMap[branchChainId] = branchAddress;
            emit BindBranchEvent(branchChainId, branchAddress); 
        }
    }

    function pauseBranch(uint64[] memory chainIds, bool needWait) onlyOwner public {
        bytes memory message = Codec.encodePauseMessage(needWait);
        for (uint i = 0; i < chainIds.length; i++) {
            sendMessageToBranch(chainIds[i], message);
        }
        emit Pause(chainIds, needWait);
    }

    function unpauseBranch(uint64[] memory chainIds, bool needWait) onlyOwner public {
        bytes memory message = Codec.encodeUnpauseMessage(needWait);
        for (uint i = 0; i < chainIds.length; i++) {
            sendMessageToBranch(chainIds[i], message);
        }
        emit Unpause(chainIds, needWait);
    }

    function addNewGroup(Token[] memory tokens) onlyOwner public {
        uint groupId = newGroupIndex;
        newGroupIndex++;
        bytes memory info = ZeroCopySink.WriteUint255(tokens.length);
        uint64 lastChainId = 0;
        for (uint i = 0; i < tokens.length; i++) {
            uint64 chainId = tokens[i].chainId;
            require(chainId > lastChainId, "chainIds not asc or has zero chainId");
            lastChainId = chainId;
            bytes memory token = tokens[i].tokenAddress;
            tokenGroupMap[chainId][token] = groupId;
            groupTokenMap[groupId][chainId] = token;
            info = abi.encodePacked(
                info,
                ZeroCopySink.WriteUint64(chainId),
                ZeroCopySink.WriteVarBytes(token)
            );
        }
        groupInfoMap[groupId] = info;
        emit CreateNewGroupEvent(groupId, tokens);
    }

    function addTokensToGroup(uint groupId, Token[] memory newTokens) onlyOwner public {
        require(groupId < newGroupIndex, "group does not exisit");
        Token[] memory oldTokens = getGroupTokens(groupId);
        uint len = oldTokens.length + newTokens.length;
        uint newTokenIndex = 0;
        uint lastNewTokenChainId = 0;
        uint oldTokenIndex = 0;
        bytes memory info = ZeroCopySink.WriteUint255(len);
        for (uint i = 0; i < len; i++) {
            if (oldTokenIndex == oldTokens.length) {
                uint64 chainId = newTokens[newTokenIndex].chainId;
                bytes memory token = newTokens[newTokenIndex].tokenAddress;
                require(chainId > lastNewTokenChainId, "new token chainIds not asc or has zero chainId");
                lastNewTokenChainId = chainId;
                info = abi.encodePacked(
                    info,
                    ZeroCopySink.WriteUint64(chainId),
                    ZeroCopySink.WriteVarBytes(token)
                );
                newTokenIndex++;
                tokenGroupMap[chainId][token] = groupId;
                groupTokenMap[groupId][chainId] = token;
            } else if (newTokenIndex == newTokens.length) {
                uint64 chainId = oldTokens[oldTokenIndex].chainId;
                bytes memory token = oldTokens[oldTokenIndex].tokenAddress;
                info = abi.encodePacked(
                    info,
                    ZeroCopySink.WriteUint64(chainId),
                    ZeroCopySink.WriteVarBytes(token)
                );
                oldTokenIndex++;
            }
            uint64 oc = oldTokens[oldTokenIndex].chainId;
            uint64 nc = newTokens[newTokenIndex].chainId;
            if (oc == nc) {
                revert("duplicate chainId");
            } else if (oc > nc) {
                require(nc > lastNewTokenChainId, "new token chainIds not asc or has zero chainId");
                lastNewTokenChainId = nc;
                bytes memory token = newTokens[newTokenIndex].tokenAddress;
                info = abi.encodePacked(
                    info,
                    ZeroCopySink.WriteUint64(nc),
                    ZeroCopySink.WriteVarBytes(token)
                );
                newTokenIndex++;
                tokenGroupMap[nc][token] = groupId;
                groupTokenMap[groupId][nc] = token;
            } else {
                info = abi.encodePacked(
                    info,
                    ZeroCopySink.WriteUint64(oc),
                    ZeroCopySink.WriteVarBytes(oldTokens[oldTokenIndex].tokenAddress)
                );
                oldTokenIndex++;
            }
        }
        groupInfoMap[groupId] = info;
        emit AddTokensToGrounpEvent(groupId, newTokens);
    }

    function deleteGroup(uint groupId) onlyOwner public {
        Token[] memory tokens = getGroupTokens(groupId);
        for (uint i = 0; i < tokens.length; i++) {
            uint64 chainId = tokens[i].chainId;
            bytes memory token = tokens[i].tokenAddress;
            delete tokenGroupMap[chainId][token];
            delete groupTokenMap[groupId][chainId];
        }
        delete groupInfoMap[groupId];
        emit DeleteGroupEvent(groupId);
    }

    function removeTokensFromGroup(uint groupId, uint64[] memory tokenChainIds) onlyOwner public {
        Token[] memory currentTokens = getGroupTokens(groupId);
        require(currentTokens.length >= tokenChainIds.length, "no that much token in group");
        bytes memory info = ZeroCopySink.WriteUint255(currentTokens.length - tokenChainIds.length);
        uint64 lastDeleteTokenChainId = 0;
        uint64 currentDeleteTokenIndex = 0;
        for (uint i = 0; i < currentTokens.length; i++) {
            uint64 chainId = currentTokens[i].chainId;
            bytes memory token = currentTokens[i].tokenAddress;
            if (chainId == tokenChainIds[currentDeleteTokenIndex]) {
                require(chainId > lastDeleteTokenChainId, "delete token chainIds not asc or has zero chainId");
                delete tokenGroupMap[chainId][token];
                delete groupTokenMap[groupId][chainId];
                lastDeleteTokenChainId = chainId;
                currentDeleteTokenIndex++;
            } else {
                info = abi.encodePacked(
                    info,
                    ZeroCopySink.WriteUint64(chainId),
                    ZeroCopySink.WriteVarBytes(token)
                );
            }
        }
        groupInfoMap[groupId] = info;
        emit DeleteTokensEvent(groupId, tokenChainIds);
    }

    function getGroupTokens(uint groupId) public view returns(Token[] memory) {
        bytes memory info = groupInfoMap[groupId];
        if (info.length == 0) {
            return new Token[](0);
        }
        (uint len, uint off) = ZeroCopySource.NextUint255(info, 0);
        Token[] memory tokens = new Token[](len);
        uint64 chainId;
        bytes memory tokenAddress;
        for (uint i = 0; i < len; i++) {
            (chainId, off) = ZeroCopySource.NextUint64(info, off);
            (tokenAddress, off) = ZeroCopySource.NextVarBytes(info, off);
            tokens[i] = Token(chainId, tokenAddress);
        }
        return tokens;
    }

    function handleBranchMessage(uint64 branchChainId, bytes memory message) override internal {
        bytes1 tag = Codec.getTag(message);
        if (tag == Codec.LOCK_TAG) {
            handleLock(branchChainId, message);
        } else if (tag == Codec.ADD_LIQUIDITY_TAG) {
            handleAddLiquidity(branchChainId, message);
        } else if (tag == Codec.REMOVE_LIQUIDITY_TAG) {
            handleRemoveLiquidity(branchChainId, message);
        } else {
            revert("Unknown tag");
        }
    }

    function checkMessage(uint64 fromChainId, bytes memory message) internal returns(bool isValid, string memory err) {
        if (messageFilter != address(0)) {
            return IMessageFilter(messageFilter).handleMessage(fromChainId, message);
        }
        return (true, "");
    }

    function sendRollBackToBranch(uint64 branchChainId, bytes memory fromAsset, bytes memory refundAddress, uint amount, string memory err) internal {
        bytes memory rollBackData = Codec.encodeRollBackMessage(fromAsset, refundAddress, amount);
        sendMessageToBranch(branchChainId, rollBackData);
        emit RollBackEvent(fromAsset, branchChainId, refundAddress, amount, err);
    }

    function sendUnlockToBranch(uint64 toChainId, bytes memory toAsset, bytes memory toAddress, uint amount) internal {
        bytes memory unlockData = Codec.encodeUnlockMessage(toAsset, toAddress, amount);
        sendMessageToBranch(toChainId, unlockData);
        emit UnlockEvent(toAsset, toChainId, toAddress, amount);
    }

    function handleLock(uint64 fromChainId, bytes memory message) internal {
        (bytes memory fromAsset, bytes memory toAddress, bytes memory refundAddress, uint64 toChainId, uint amount) = Codec.decodeLockMessage(message);
        (bool isValidMessage, string memory err) = checkMessage(fromChainId, message);
        if (!isValidMessage) {
            sendRollBackToBranch(fromChainId, fromAsset, refundAddress, amount, string.concat("lock error: ", err));
            return;
        }
        uint groupId = tokenGroupMap[fromChainId][fromAsset];
        if (groupId == 0) {
            sendRollBackToBranch(fromChainId, fromAsset, refundAddress, amount, "lock error: invalid fromAsset");
            return;
        }
        bytes memory toBranch = branchMap[toChainId];
        if (toBranch.length == 0) {
            sendRollBackToBranch(fromChainId, fromAsset, refundAddress, amount, "lock error: invalid toBranch");
            return;
        }
        bytes memory toAsset = groupTokenMap[groupId][toChainId];
        if (toAsset.length == 0) {
            sendRollBackToBranch(fromChainId, fromAsset, refundAddress, amount, "lock error: invalid toAsset");
            return;
        }
        if (chainLiquidityMap[groupId][toChainId] < amount) {
            sendRollBackToBranch(fromChainId, fromAsset, refundAddress, amount, "lock error: target chain do not have enough liquidity");
            return;
        }
        chainLiquidityMap[groupId][fromChainId] += amount;
        chainLiquidityMap[groupId][toChainId] -= amount;
        sendUnlockToBranch(toChainId, toAsset, toAddress, amount);
        emit LockEvent(fromAsset, fromChainId, toAddress, toChainId, amount);
    }

    function handleAddLiquidity(uint64 fromChainId, bytes memory message) internal {
        (bytes memory fromAsset, bytes memory beneficiary, bytes memory refundAddress, uint64 beneficiaryChainId, uint amount) = Codec.decodeAddLiquidityMessage(message);
        (bool isValidMessage, string memory err) = checkMessage(fromChainId, message);
        if (!isValidMessage) {
            sendRollBackToBranch(fromChainId, fromAsset, refundAddress, amount, string.concat("add_liquidity error: ", err));
            return;
        }
        uint groupId = tokenGroupMap[fromChainId][fromAsset];
        if (groupId == 0) {
            sendRollBackToBranch(fromChainId, fromAsset, refundAddress, amount, "add_liquidity error: invalid fromAsset");
            return;
        }
        chainLiquidityMap[groupId][fromChainId] += amount;
        liquidityOf[beneficiaryChainId][beneficiary][groupId] += amount;
        emit AddLiquidityEvent(groupId, fromChainId, beneficiary, beneficiaryChainId, amount);
    }

    function handleRemoveLiquidity(uint64 fromChainId, bytes memory message) internal {
        (bytes memory toAsset, bytes memory provider, bytes memory toAddress, uint64 toChainId, uint amount) = Codec.decodeRemoveLiquidityMessage(message);
        (bool isValidMessage, string memory err) = checkMessage(fromChainId, message);
        if (!isValidMessage) {
            emit RevertEvent(string.concat("remove_liquidity error: ", err));
            return;
        }
        uint groupId = tokenGroupMap[fromChainId][toAsset];
        if (groupId == 0) {
            emit RevertEvent("remove_liquidity error: invalid toAsset");
            return;
        }
        bytes memory toBranch = branchMap[toChainId];
        if (toBranch.length == 0) {
            emit RevertEvent("remove_liquidity error: invalid toBranch");
            return;
        }
        if (liquidityOf[fromChainId][provider][groupId] < amount) {
            emit RevertEvent("remove_liquidity error: provider do not have enough liquidity");
            return;
        }
        if (chainLiquidityMap[groupId][toChainId] < amount) {
            emit RevertEvent("remove_liquidity error: target chain do not have enough liquidity");
            return;
        }
        liquidityOf[fromChainId][provider][groupId] -= amount;
        chainLiquidityMap[groupId][toChainId] -= amount;
        sendUnlockToBranch(toChainId, toAsset, toAddress, amount);
        emit RemoveLiquidityEvent(groupId, provider, fromChainId, toAddress, toChainId, amount);
    }
}