// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";


// ERC4626 Vault Example
contract TestVault is ERC4626 {
    constructor(ERC20 asset)
        ERC20("Example Vault Token", "EVT")
        ERC4626(asset) // Initializes the ERC4626 Vault with the underlying token
    {}

    // Additional strategies or yield generation logic can be added here
}
