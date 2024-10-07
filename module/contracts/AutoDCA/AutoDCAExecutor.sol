// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { Execution } from "modulekit/Accounts.sol";
import {
    ERC20Integration, ERC4626Integration
} from "modulekit/Integrations.sol";
import { UniswapV3Integration } from "../integrations/Uniswap.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { ERC7579ValidatorBase } from "../module-bases/ERC7579ValidatorBase.sol";
import { PackedUserOperation } from
    "@account-abstraction/contracts/core/UserOperationLib.sol";

import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { ExecutionLib } from "../safe7579/lib/ExecutionLib.sol";

import { ERC7579ExecutorBase } from "../module-bases/ERC7579ExecutorBase.sol";


contract AutoDCAExecutor is ERC7579ExecutorBase {
    using SignatureCheckerLib for address;
    using ExecutionLib for bytes;


    mapping(address =>  JobData[]) public jobDetails;

    
    struct JobData {

        address token;
        address targetToken;
        address vault;

        uint48 validAfter;
        uint48 validUntil;
        uint256 limitAmount;
        uint256 limitUsed;

        uint48 lastUsed;
        uint48 refreshInterval;
    }

            
    event JobAdded(address indexed account, uint256 indexed id);

    error ExecutionFailed();

    function onInstall(bytes calldata data) external override {

    if (data.length == 0) return;

    (JobData memory jobData) = abi.decode(data, (JobData));

    createJob(jobData);
    
    }

    function onUninstall(bytes calldata) external override {

        // delete the Safe account jobs
    }



    function createJob(JobData memory jobData) public  returns (uint256) {

        jobDetails[msg.sender].push(jobData);
        emit JobAdded(msg.sender, jobDetails[msg.sender].length - 1);

        return jobDetails[msg.sender].length - 1;

    }



    function executeJob(uint256 jobId) public returns (bytes memory) {


            JobData storage jobData = jobDetails[msg.sender][jobId];
            
            if(!updateSpendLimitUsage(jobData.limitAmount, msg.sender, jobId, jobData.token))  {
            revert ExecutionFailed();
            }

            Execution[] memory swap = UniswapV3Integration.approveAndSwap({
                smartAccount: msg.sender,
                tokenIn: IERC20(jobData.token),
                tokenOut: IERC20(jobData.targetToken),
                amountIn: jobData.limitAmount,
                sqrtPriceLimitX96: 0
            });



            bytes[] memory results = _execute(swap);
            uint256 amountIn = abi.decode(results[2], (uint256));



        // approve and deposit to vault
        Execution[] memory approveAndDeposit = new Execution[](3);
        (approveAndDeposit[0], approveAndDeposit[1]) =
            ERC20Integration.safeApprove(IERC20(jobData.targetToken), jobData.vault, amountIn);
        approveAndDeposit[2] = ERC4626Integration.deposit(IERC4626(jobData.vault), amountIn, msg.sender);

        // execute deposit to vault on account
        _execute(approveAndDeposit);

        }



        function _getTokenSpendAmount(bytes memory callData) internal pure returns (uint256) {

        // Expected length: 68 bytes (4 selector + 32 address + 32 amount)
        if (callData.length < 68) {
            return 0;
        }

        // Load the amount being sent/approved.
        // Solidity doesn't support access a whole word from a bytes memory at once, only a single byte, and
        // trying to use abi.decode would require copying the data to remove the selector, which is expensive.
        // Instead, we use inline assembly to load the amount directly. This is safe because we've checked the
        // length of the call data.
        uint256 amount;
        assembly ("memory-safe") {
            // Jump 68 words forward: 32 for the length field, 4 for the selector, and 32 for the to address.
            amount := mload(add(callData, 68))
        }
        return amount;
        
        // Unrecognized function selector
        return 0;
    }

    function updateSpendLimitUsage(
        uint256 newUsage,
        address account,
        uint256 jobId,
        address token
    ) internal returns (bool) {


        JobData storage jobData = jobDetails[account][jobId];

        if(token != jobData.token) {
            return false;
        }

            uint48 refreshInterval =  jobData.refreshInterval;
            uint48 lastUsed = jobData.lastUsed;
            uint256 spendLimit = jobData.limitAmount;
            uint256 currentUsage = jobData.limitUsed;

        if(block.timestamp < jobData.validAfter || block.timestamp > jobData.validUntil) {
            return false;
        }
        

        if (refreshInterval == 0 || lastUsed + refreshInterval > block.timestamp) {
            // We either don't have a refresh interval, or the current one is still active.

            // Must re-check the limits to handle changes due to other user ops.
            // We manually check for overflows here to give a more informative error message.
            uint256 newTotalUsage;
            unchecked {
                newTotalUsage = newUsage + currentUsage;
            }
            if (newTotalUsage < newUsage || newTotalUsage > spendLimit) {
                // If we overflow, or if the limit is exceeded, fail here and revert in the parent context.
                return false;
            }

            // We won't update the refresh interval last used variable now, so just update the spend limit.
            jobData.limitUsed = newTotalUsage;
        } else {
            // We have a interval active that is currently resetting.
            // Must re-check the amount to handle changes due to other user ops.
            // It only needs to fit within the new refresh interval, since the old one has passed.
            if (newUsage > spendLimit) {
                return false;
            }

            // The refresh interval has passed, so we can reset the spend limit to the new usage.
            jobData.limitUsed = newUsage;
            jobData.lastUsed = uint48(block.timestamp);
        }

        return true;
    }


    function getJobData(address account) public view returns (JobData[] memory) {
        return jobDetails[account];
    }


    function name() external pure returns (string memory) {
        return "AutoDCAExecutor";
    }

    function version() external pure returns (string memory) {
        return "0.0.1";
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }

    function isInitialized(address smartAccount) external view returns (bool) { }
}