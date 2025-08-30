// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SimpleVault
 * @dev A vault contract for managing ERC20 tokens with entry and exit fees.
 */
contract AssetRelease is Ownable, ReentrancyGuard, Pausable {
    
    // Custom errors

    /// @notice Custom error for unauthorized access to the vault
    error NotTheVault();

    /// @notice Custom error for insufficient balance
    error InsufficientBalance();

    /// @notice Custom error for invalid address
    error InvalidAddress();

    /// @notice Custom error for invalid block time
    error InvalidBlockTime();

    /// @notice Custom error for transfer failure
    error TransferFailed();

    // Events

    /// @notice Emitted when tokens are withdrawn from the contract.
    /// @param token The address of the ERC20 token that was withdrawn.
    /// @param owner The address of the owner who initiated the withdrawal.
    /// @param amount The amount of tokens withdrawn.
    event TokensWithdrawn(address indexed token, address indexed owner, uint256 amount);

    /// @notice Emitted when Ether is withdrawn from the contract.
    /// @param owner The address of the owner who initiated the withdrawal.
    /// @param amount The amount of Ether withdrawn.
    event EtherWithdrawn(address indexed owner, uint256 amount);

    /// @notice Emitted when the vault address is updated.
    /// @param oldVault The address of the previous vault.
    /// @param newVault The address of the new vault.
    event VaultUpdated(address indexed oldVault, address indexed newVault);

    /// @notice Emitted when the Lucy token address is updated.
    /// @param oldLucyToken The address of the previous Lucy token.
    /// @param newLucyToken The address of the new Lucy token.
    event LucyTokenUpdated(address indexed oldLucyToken, address indexed newLucyToken);

    /// @notice Emitted when the block time is updated.
    /// @param oldBlockTime The previous block time.
    /// @param newBlockTime The new block time.
    /// @param timestamp The current block timestamp.
    /// @param blockNumber The current block number.
    event BlockTimeUpdated(uint256 oldBlockTime, uint256 newBlockTime, uint256 timestamp, uint256 blockNumber);

    /// @notice Emitted when a redeem operation fails.
    /// @param token The address of the token involved in the redeem operation.
    /// @param reason The reason for the failure.
    event RedeemFailed(address indexed token, string reason);

    // Variables

    /// @notice The ERC20 token managed by the vault.
    IERC20 public lucyToken; 
    /// @notice The address of the vault contract.
    address public vault; 
    
    /// @notice Block of the last call to a withdraw or redeem function
    uint256 public lastBlockDistribution;
    /// @notice Time between blocks. Updated from while to while.
    uint256 public blockTime;
    /// @notice Timestamp when blockTime was updated for the last time
    uint256 public blockTimeUpdateTime;
    /// @notice Block when blockTime was updated for the last time
    uint256 public blockTimeUpdateBlock;
    /// @notice Ending timestamp of the staking
    uint256 public endTime;

    // Modifiers

    /// @notice Amount of blocks remaining until the end
    uint256 public amountOfBlocks;


    // Modificadores

    /*
        0   0   =>  0 ( es vault        es contrato)        => continua
        0   1   =>  1 ( es vault        No es contrato)     => NotTheVault
        1   0   =>  1 ( no es vault     es contrato)        => NotTheVault
        1   1   =>  1 ( no es vault     No es contrato)     => NotTheVault
    */
    /// @notice Modifier to restrict access to the vault.
    modifier onlyVault() {
        address _vault = vault;
        if (msg.sender != _vault || !isContract(_vault)) revert NotTheVault();
        _;
    }

    // Constructor
    /// @param _lucyToken The address of the ERC20 token managed by the vault.
    /// @param initialOwner The initial owner of the contract.
    /// @param _vault The address of the vault contract.
    /// @param _blockTime The time between blocks.
    constructor(IERC20 _lucyToken, address initialOwner, address _vault, uint256 _blockTime) Ownable(initialOwner) {
        if (address(_vault) == address(0)) revert InvalidAddress();
        if (address(_lucyToken) == address(0) || !isContract(address(_lucyToken))) revert InvalidAddress();        
        lucyToken = _lucyToken;
        vault = _vault;
        _start(_blockTime);
        emit VaultUpdated(address(0), _vault);
        emit LucyTokenUpdated(address(0), address(_lucyToken));
    }

    /// @notice Sets a new vault address.
    /// @param _vault The new vault address.
    /// @dev Reverts with InvalidAddress if the provided address is zero.
    function setVault(address _vault) external onlyOwner {
        if (address(_vault) == address(0) || !isContract(_vault)) revert InvalidAddress();
        address oldVault = vault;
        vault = _vault;
        emit VaultUpdated(oldVault, _vault);
    }

    /// @notice Sets a new Lucy token address.
    /// @param _lucyToken The new Lucy token address.
    /// @dev Reverts with InvalidAddress if the provided address is zero.
    function setLucyToken(IERC20 _lucyToken) external onlyOwner {
        if (address(_lucyToken) == address(0) || !isContract(address(_lucyToken))) revert InvalidAddress();
        address oldLucyToken = address(lucyToken);
        lucyToken = _lucyToken;
        emit LucyTokenUpdated(oldLucyToken, address(_lucyToken));
    }

    /// @notice Starts the distribution process with a specific block time.
    /// @param _blockTime The time between blocks.
    function start(uint256 _blockTime) public onlyOwner {
        _start(_blockTime);
    }

    /// @notice Calculates the amount of Lucy tokens generated since the last distribution.
    /// @return The amount of Lucy tokens generated since the last distribution.
    function incLucySinceLastTime() public view returns(uint256) {
        uint256 _lastBlockDistribution = lastBlockDistribution;
        if (_lastBlockDistribution > block.number) return 0;
        return (block.number - _lastBlockDistribution) * lucyPerBlock();
    }

    /// @notice Calculates the amount of Lucy tokens generated per block.
    /// @dev The use of timestamp for comparisons is considered acceptable
    /// in this context since calculations are approximate, spanning over a time
    /// frame of 365-days
    /// @return The amount of Lucy tokens generated per block.
    function lucyPerBlock() public view returns(uint256) {
        uint256 _amountOfBlocks = amountOfBlocks;
        if (_amountOfBlocks < 1 || endTime < block.timestamp) return 0; // Check if no blocks are available or if the end time has passed
        IERC20 _lucyToken = lucyToken;
        if (address(_lucyToken) == address(0) || !isContract(address(_lucyToken))) return 0;
        // minimum of 1 wei lucy per block
        return _lucyToken.balanceOf(address(this)) / _amountOfBlocks;
    }

    /// @notice Prepares for redeeming by transferring tokens to the vault.
    /// @dev The use of timestamp for comparisons is considered acceptable
    /// in this context since calculations are approximate, spanning over a time
    /// frame of more than one day, and are intended to check if the 365-day
    /// duration of the contract has passed. Minor manipulations of timestamp
    /// are not critical for the logic of this function.
    /// @return True if the block time has been updated recently.
    function beforeRedeem() external onlyVault nonReentrant whenNotPaused returns(bool) {
        uint256 _amountToSendToTheVault = incLucySinceLastTime();
        if (_amountToSendToTheVault > 0 && endTime > block.timestamp) {
            IERC20 _lucyToken = lucyToken;
            // If there is a problem with the token setting here, we inhabilitate the beforeRedeem and afterRedeem function by rturning false here.
            if (address(_lucyToken) == address(0) || !isContract(address(_lucyToken))) {
                emit RedeemFailed(address(_lucyToken), "Invalid _lucyToken");
                return false;
            }
            lastBlockDistribution = block.number;
            SafeERC20.safeTransfer(_lucyToken, vault, _amountToSendToTheVault);    
        } else {
            emit RedeemFailed(address(lucyToken), "Amount zero or finished");
        }
        return ((blockTimeUpdateTime + 1 days) < block.timestamp);
    }

    /// @notice Updates the block time and recalibrates the remaining blocks after redeeming.
    /// @dev The use of timestamp for comparisons is considered acceptable
    /// in this context since calculations are approximate, spanning over a time
    /// frame of more than one day, and are intended to check if the 365-day
    /// duration of the contract has passed. Minor manipulations of timestamp
    /// are not critical for the logic of this function.
    function afterRedeem() external onlyVault {
        uint256 _blockTimeUpdateTime = blockTimeUpdateTime;
        uint256 _endTime = endTime;
        uint256 _blockTimeUpdateBlock = blockTimeUpdateBlock;
        if ((_blockTimeUpdateTime + 1 days) < block.timestamp  && _endTime > block.timestamp  && block.number > _blockTimeUpdateBlock) {
            uint256 _oldBlockTime = blockTime;
            if (_oldBlockTime == 0) revert InvalidBlockTime();
            uint256 blocksExpected = (block.timestamp - _blockTimeUpdateTime) / _oldBlockTime; //(t1-t0)/dTb
            uint256 passedBlock = block.number - _blockTimeUpdateBlock; //b1 - b0
            uint256 _blockTime = _oldBlockTime;
            if (blocksExpected < passedBlock) {
                if (_oldBlockTime > 1) {
                    --_blockTime; // we decrement the blocktime if the previous time was greater
                    blockTime = _blockTime;
                }
            } else {
                ++_blockTime; // we increment the blockTime if the previous time was less than expected.
                blockTime = _blockTime;
            }
            if (_blockTime == 0) revert InvalidBlockTime();
            // we set the timestamp and blocknumber for next update
            blockTimeUpdateTime = block.timestamp;
            blockTimeUpdateBlock = block.number;
            amountOfBlocks = (_endTime - block.timestamp) / _blockTime;
            ++amountOfBlocks; // So this is never 0 + rounding up.
            emit BlockTimeUpdated(_oldBlockTime, _blockTime, block.timestamp, block.number);
        }
    }

    /// @dev Withdraws a specified amount of ERC20 tokens.
    /// @param token The address of the ERC20 token to withdraw.
    /// @param amount The amount of tokens to withdraw.
    /// Emits a TokensWithdrawn event.
    function withdrawToken(IERC20 token, uint256 amount) external onlyOwner nonReentrant {
        if (address(token) == address(0) || !isContract(address(token))) revert InvalidAddress();
        if (isContract(msg.sender)) revert InvalidAddress();
        if (token.balanceOf(address(this)) < amount) revert InsufficientBalance();
        SafeERC20.safeTransfer(token, msg.sender, amount);
        emit TokensWithdrawn(address(token), msg.sender, amount);
    }

    /// @dev Withdraws a specified amount of Ether.
    /// @param amount The amount of Ether to withdraw.
    /// Emits an EtherWithdrawn event.
    function withdrawEther(uint256 amount) external onlyOwner nonReentrant {
        if (address(this).balance < amount) revert InsufficientBalance();
        if (isContract(msg.sender)) revert InvalidAddress();
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        emit EtherWithdrawn(msg.sender, amount);
    }

    // Funciones internas
    /// @notice Initializes the contract parameters and state.
    /// @dev The use of timestamp for comparisons is considered acceptable
    /// in this context since calculations are approximate, spanning over a time
    /// frame of 365-days
    /// @param _blockTime The time between blocks.
    function _start(uint256 _blockTime) internal {
        if (_blockTime == 0) revert InvalidBlockTime();

        uint256 _endTime = block.timestamp + 93 days;
        endTime = _endTime;
        lastBlockDistribution = block.number;
        uint256 oldBlockTime = blockTime;
        blockTime = _blockTime; // 4s
        blockTimeUpdateTime = block.timestamp;
        blockTimeUpdateBlock = block.number;
        amountOfBlocks = (_endTime - block.timestamp) / _blockTime;
        ++amountOfBlocks; // always round up and amountOfBlocks never be 0.

        emit BlockTimeUpdated(oldBlockTime, blockTime, block.timestamp, block.number);
    }

    /// @notice Checks if the given address is a contract.
    /// @param _addr The address to check.
    /// @return True if the address is a contract, false otherwise.
    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}