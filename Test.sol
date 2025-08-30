// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "StakeFees.sol";

contract Test is ERC20, ERC20Burnable, ERC20Permit {

    StakeFees public immutable stakeFees;

    constructor()
        ERC20("test Token", "test")
        ERC20Permit("test Token")
    {
        stakeFees = StakeFees(new StakeFees(IERC20(address(this))));
        //_mint(msg.sender, 5_000_000_000 * 10 ** decimals());
    }

    function test() public {
        mint(address(this), 1000);
        mint(msg.sender, 2000);
        mint(address(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2),3000);
        this.approve(address(stakeFees),1000*decimals());
        stakeFees.deposit(1000,address(this));
    }

////////////////// For testing Purposes ////////////////////////////////
    function mint(address who, uint256 amount) public {
        _mint(who, amount);
    }

}