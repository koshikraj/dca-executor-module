// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {
    ERC20Integration, ERC4626Integration
} from "modulekit/Integrations.sol";
import { UniswapV3Integration } from "../integrations/Uniswap.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { ERC7579ValidatorBase } from "../module-bases/ERC7579ValidatorBase.sol";
import "../safe7579/interfaces/IERC7579Account.sol";

import { PackedUserOperation } from
    "@account-abstraction/contracts/core/UserOperationLib.sol";

import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { ExecutionLib } from "../safe7579/lib/ExecutionLib.sol";
import   "../safe7579/lib/ModeLib.sol";


import { ERC7579ExecutorBase } from "../module-bases/ERC7579ExecutorBase.sol";


contract SessionValidator is ERC7579ValidatorBase, ERC7579ExecutorBase {
    using SignatureCheckerLib for address;
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;
    

    event SessionKeyAdded(address indexed sessionKey, address indexed account);
    event SessionKeyDisabled(address indexed sessionKey, address indexed account);
    event SessionKeyActive(address indexed sessionKey, address indexed account);
    event SessionKeyInactive(address indexed sessionKey, address indexed account);


    error ExecutionFailed();
    error SessionKeyDoesNotExist(address session);

    // account => sessionKeys
    mapping(address => address[]) public sessionKeyList;

    // sessionKey => account=> SessionData
    mapping(address =>  mapping(address => SessionData)) public sessionKeyData;

    
    struct SessionData {

        address target;
        bytes4 funcSelector; 

        uint48 validAfter;
        uint48 validUntil;
        bool active;
    }


    function onInstall(bytes calldata data) external override {
    }

    function onUninstall(bytes calldata) external override {

        // delete the Safe account sessions
    }


    // @inheritdoc IERC20SessionKeyValidator
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external override returns (ValidationData) {
        address sessionKeySigner = ECDSA.recover(
            ECDSA.toEthSignedMessageHash(userOpHash),
            userOp.signature
        );
        if (!validateSessionKeyParams(sessionKeySigner, userOp))
            return VALIDATION_FAILED;
        SessionData memory sd = sessionKeyData[sessionKeySigner][msg.sender];
        return _packValidationData(false, sd.validUntil, sd.validAfter);
    }


    function toggleSessionKeyActive(address _sessionKey) external {
        SessionData storage sd = sessionKeyData[_sessionKey][msg.sender];
        if (sd.validUntil == 0)
            revert SessionKeyDoesNotExist(_sessionKey);
        if (sd.active) {
            sd.active = false;
            emit SessionKeyActive(_sessionKey, msg.sender);
        } else {
            sd.active = true;
            emit SessionKeyInactive(_sessionKey, msg.sender);
        }
    }

    function isSessionKeyActive(address _sessionKey) public view returns (bool) {
        return sessionKeyData[_sessionKey][msg.sender].active;
    }

    // @inheritdoc IERC20SessionKeyValidator
    function validateSessionKeyParams(
        address _sessionKey,
        PackedUserOperation calldata userOp
    ) public view returns (bool) {
        SessionData memory sd = sessionKeyData[_sessionKey][msg.sender];
        if (isSessionKeyActive(_sessionKey) == false) {
            return false;
        }
        address target;
        bytes calldata callData = userOp.callData;
        bytes4 sel = bytes4(callData[:4]);
        if (sel == IERC7579Account.execute.selector) {
            ModeCode mode = ModeCode.wrap(bytes32(callData[4:36]));
            (CallType calltype, , , ) = ModeLib.decode(mode);
            if (calltype == CALLTYPE_SINGLE) {
                bytes calldata execData;
                // 0x00 ~ 0x04 : selector
                // 0x04 ~ 0x24 : mode code
                // 0x24 ~ 0x44 : execution target
                // 0x44 ~0x64 : execution value
                // 0x64 ~ : execution calldata
                (target, , execData) = ExecutionLib.decodeSingle(
                    callData[100:]
                );
                
                bytes4 selector = bytes4(execData[0:4]);

                if (target != sd.target) return false;
                if (selector != sd.funcSelector) return false;
                return true;

            }
            if (calltype == CALLTYPE_BATCH) {
                Execution[] calldata execs = ExecutionLib.decodeBatch(
                    callData[100:]
                );
                for (uint256 i; i < execs.length; i++) {
                    target = execs[i].target;
                    bytes4 selector = bytes4(execs[i].callData[0:4]);

                    if (target != sd.target) return false;
                    if (selector != sd.funcSelector) return false;
                }
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }


    function isValidSignatureWithSender(
        address,
        bytes32 hash,
        bytes calldata data
    )
        external
        view
        override
        returns (bytes4)
    {

        //Implement the session key sig validation

        // return SignatureCheckerLib.isValidSignatureNowCalldata(owner, hash, data)
        //     ? EIP1271_SUCCESS
        //     : EIP1271_FAILED;
    }


    /**
     * @dev Adds a session key to the mapping.
     */
    // Add a session key to the mapping
    function enableSessionKey(address sessionKey, SessionData memory sessionData) public {

        sessionKeyData[sessionKey][msg.sender] = sessionData;
        emit SessionKeyAdded(sessionKey, msg.sender);
    }

    function disableSessionKey(address _session) public {
        if (sessionKeyData[_session][msg.sender].validUntil == 0)
            revert SessionKeyDoesNotExist(_session);
        delete sessionKeyData[_session][msg.sender];
        emit SessionKeyDisabled(_session, msg.sender);
    }



    // Function to get the array of SessionData for a specific address
    function getSessionData(address sessionKey) public view returns (SessionData memory) {
        return sessionKeyData[sessionKey][msg.sender];
    }


    function name() external pure returns (string memory) {
        return "AutoDCASessionModule";
    }

    function version() external pure returns (string memory) {
        return "0.0.1";
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_VALIDATOR || typeID == TYPE_EXECUTOR;
    }

    function isInitialized(address smartAccount) external view returns (bool) { }
}