pragma solidity ^0.8.8;

import "../interfaces/ICrossChainManager.sol";
import "../libs/token/ERC20/utils/SafeERC20.sol";
import "../libs/token/ERC20/IERC20.sol";
import "../libs/security/ReentrancyGuard.sol";
import "../libs/security/Pausable.sol";
import "../libs/utils/Utils.sol";
import "../interfaces/ICrossChainManager.sol";
import "./CrossChainGovernance.sol";
import "./Codec.sol";

contract LockProxy is Branch, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    constructor(address _managerContractAddress, bytes memory _coreAddress, uint64 _coreChainId) {
        managerContractAddress = _managerContractAddress;
        coreAddress = _coreAddress;
        coreChainId = _coreChainId;
    }

    event LockEvent(address fromAsset, address fromAddress, address refundAddress, bytes toAddress, uint64 toChainId, uint256 amount);
    event UnlockEvent(address toAsset, address toAddress, uint256 amount);
    event RollBackEvent(address fromAsset, address refundAddress, uint amount);
    event AddLiquidityEvent(address fromAsset, address fromAddress, address refundAddress, bytes beneficiary, uint amount);
    event RemoveLiquidityEvent(bytes toAsset, address provider, bytes toAddress, uint64 toChainId, uint amount);

    function lock(address fromAsset, address refundAddress, bytes memory toAddress, uint64 toChainId, uint256 amount) public payable nonReentrant whenNotPaused {
        require(amount != 0, "amount cannot be zero!");
        
        _transferToContract(fromAsset, amount);
        
        sendMessageToCore(Codec.encodeLockMessage(Utils.addressToBytes(fromAsset), toAddress, Utils.addressToBytes(refundAddress), toChainId, amount));

        emit LockEvent(fromAsset, msg.sender, refundAddress, toAddress, toChainId, amount);
    }

    function deposite(address fromAsset, address refundAddress, bytes memory beneficiary, uint64 beneficiaryChainId, uint256 amount) public payable nonReentrant whenNotPaused {
        require(amount != 0, "amount cannot be zero!");
        
        _transferToContract(fromAsset, amount);
        
        sendMessageToCore(Codec.encodeAddLiquidityMessage(Utils.addressToBytes(fromAsset), beneficiary, Utils.addressToBytes(refundAddress), beneficiaryChainId, amount));

        emit AddLiquidityEvent(fromAsset, msg.sender, refundAddress, beneficiary, amount);
    }

    function withdraw(bytes memory toAsset, bytes memory toAddress, uint64 toChainId, uint256 amount) public nonReentrant whenNotPaused {
        require(amount != 0, "amount cannot be zero!");

        sendMessageToCore(Codec.encodeRemoveLiquidityMessage(toAsset, Utils.addressToBytes(msg.sender), toAddress, toChainId, amount));

        emit RemoveLiquidityEvent(toAsset, msg.sender, toAddress, toChainId, amount);
    }

    function handleCoreMessage(bytes memory message) override internal {
        bytes1 tag = Codec.getTag(message);
        if (tag == Codec.UNLOCK_TAG) {
            (bytes memory toAssetBytes, bytes memory toAddressBytes, uint amount) = Codec.decodeUnlockMessage(message);
            address toAsset = Utils.bytesToAddress(toAssetBytes);
            address toAddress = Utils.bytesToAddress(toAddressBytes);
            _transferFromContract(toAsset, toAddress, amount);
            emit UnlockEvent(toAsset, toAddress, amount);
        } else if (tag == Codec.ROLLBACK_TAG) {
            (bytes memory fromAssetBytes, bytes memory refundAddressBytes, uint amount) = Codec.decodeRollBackMessage(message);
            address fromAsset = Utils.bytesToAddress(fromAssetBytes);
            address refundAddress = Utils.bytesToAddress(refundAddressBytes);
            _transferFromContract(fromAsset, refundAddress, amount);
            emit RollBackEvent(fromAsset, refundAddress, amount);
        } else if (tag == Codec.PAUSE_TAG) {
            bool needWait = Codec.decodePauseMessage(message);
            if (paused()) {
                require(!needWait, "lock_proxy is paused! wait until its not paused");
            } else {
                _pause();
            }
        } else if (tag == Codec.UNPAUSE_TAG) {
            bool needWait = Codec.decodeUnpauseMessage(message);
            if (!paused()) {
                require(!needWait, "lock_proxy is not paused! wait until its paused");
            } else {
                _unpause();
            }
        } else {
            revert("Unknown message tag");
        }
    }

    function _transferToContract(address fromAssetHash, uint256 amount) internal {
        if (fromAssetHash == address(0)) {
            require(msg.value != 0, "transferred ether cannot be zero!");
            require(msg.value == amount, "transferred ether is not equal to amount!");
        } else {
            require(msg.value == 0, "there should be no ether transfer!");
            IERC20 erc20Token = IERC20(fromAssetHash);
            erc20Token.safeTransferFrom(fromAssetHash, msg.sender, amount);
        }
    }

    function _transferFromContract(address toAssetHash, address toAddress, uint256 amount) internal {
        if (toAssetHash == address(0)) {
            payable(address(uint160(toAddress))).transfer(amount);
        } else {
            IERC20 erc20Token = IERC20(toAssetHash);
            erc20Token.safeTransfer(toAddress, amount);
        }
    }
}