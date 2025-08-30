// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AssetRelease} from "./AssetRelease.sol";
import {test} from "./LucyAI.sol";


/*
    Mainnet info:
    Vault proxy: 0xf1433b9c5e8146903F67c1c9ab15e883c7A0B5A6
    Vault implementation: 0xA7fF2d0F8006Bc5ccE03e42F3FfacD728C28CC5c
    Tokens being staked: 0xe102f20347D601C08E9f998475b7c9998b498deE
    Yield contract: 0x965c947D7B5EE16B8ba539C7F6Ed7121CD25F61F

*/
/*
    new and final:
    Vault proxy: 0x48676E9d531A05E11397DA4e369243c512A0C97c
    Vault implementation: 0xBbc7eadADf1E0A42369FFFe00eE4603D227947dC
    Tokens being staked: 0xC5fA473F2AD03A9271a3F33c42971F0B3FBDeAe0
    Yield contract: 0xe64923fC24cc5B7BfcB81d57f3826ff0d461a1A0

    Zetachain Testnet:
    Vault proxy: 0xdfBBf99CFF88c6beF8336124B5ed3A2f69e52fef
    Vault implementation: 0x7B4b8Ce8c678719F84A9DAC7285a30B24966aF96
    New Implementation: 0x86744d993b49F6CeAB6B0B340793300b2532b3D1
    new implementation: 0x52D45Bf16383dA37BcDB864B6A813832B542CAE0

    Tokens being staked: 0x908b0B487EfA3153b29817Ea2A4ef1e6bdeD3bDf
    Yield contract: 0x5a6F827f3a2AFf50f4FabA528461115ca6cb6E4b
    new Yield contract: 0xD692cad397017AdE05e49dCc673C97c703F0a0d3

    basic function: Vault is the contract where you put and extract tokens from and you get a proportional
    of it by the amount you have put. Yield contract is the one sending tokens to the vault in order to
    increase the value of the vault.

    The proxy has the state variables, the implementation has the logic in order to upset upgrades later
    by changing the implementation. You will need to interact with the proxy but using the ABI of the
    implementation because of that.

    the functions to stake are:
    with approval:
        deposit and mint. One is in terms of the assets, the other of the shares.
    with permit:
        permitAndDeposit and permitAndMint. One in terms of assets, the other of shares.

    For permit you will have to sign first the permit function you can finde the data in the token being
    stacked. Then send that signature when calling any of the permit functions above.

    This will do that we only do one transaction to one smart contract instead of approving first the
    token and then sending the deposit to the vault.

    Assets: Tokens being staked
    Shares: (the vault is a token) Tokens received when staking to know how much of the vault is yours.

    All the contracts are verified and you can get the ABI and test them in blockscout explorer.

    Please do the integration for testing.
*/

/// @title Basevault
/// @dev A vault contract for managing ERC20 tokens.
/// @notice minimum investment 0.01Lucy, Maximum Investment 300000000 Lucy
/// @notice minimum investment needs to get at least 1000 shares. Maximum lost this way is 0.1%
contract Basevault is Initializable, ERC4626Upgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    /// @notice Custom error for insufficient balance
    error InsufficientBalance();

    /// @notice Custom error for transfer failure
    error TransferFailed();

    /// @notice Custom error for invalid address
    error InvalidAddress();

    /// @notice Custom error for invalid value
    error InvalidValue();

    /// @notice Custom error for invalid deadline
    error InvalidDeadline();

    /// @notice Event emitted when tokens are withdrawn
    /// @param token The address of the ERC20 token that was withdrawn
    /// @param owner The address of the owner who initiated the withdrawal
    /// @param amount The amount of tokens withdrawn
    event TokensWithdrawn(address indexed token, address indexed owner, uint256 amount);

    /// @notice Event emitted when Ether is withdrawn
    /// @param owner The address of the owner who initiated the withdrawal
    /// @param amount The amount of Ether withdrawn
    event EtherWithdrawn(address indexed owner, uint256 amount);

    /// @notice Event emitted when the AssetRelease contract address is updated
    /// @param oldAssetRelease The address of the previous AssetRelease contract
    /// @param newAssetRelease The address of the new AssetRelease contract
    event AssetReleaseUpdated(address indexed oldAssetRelease, address indexed newAssetRelease);

    /// @notice The AssetRelease contract associated with this vault
    AssetRelease public assetRelease;

    /// @dev Constructor to disable initializers
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract.
    /// @param asset_ The address of the ERC20 asset.
    /// @param _production Indicates if the contract is in production mode.
    function initialize(IERC20 asset_, bool _production) public initializer nonReentrant {

        if (!_production) {
            asset_ = new test();
        }
        
        if (address(asset_) == address(0) || !isContract(address(asset_))) revert InvalidAddress();

        __ERC20_init("Lucy vault", "vLucy");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ERC4626_init(asset_);
       
        AssetRelease _assetRelease = new AssetRelease(IERC20(asset()), msg.sender, address(this), 4);
        
        if (address(_assetRelease) == address(0) || !isContract(address(_assetRelease))) revert InvalidAddress();
        assetRelease = _assetRelease;

        if (!_production) {
            test(address(asset())).mint(address(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4), 100);
            test(address(asset())).mint(address(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2), 100);
            test(address(asset())).mint(address(0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db), 100);
            test(address(asset())).mint(address(0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB), 100);
            test(address(asset())).mint(msg.sender, 100*10**decimals());
            test(address(asset())).mint(address(assetRelease), 20000000*10**decimals());
            
            //test(address(asset())).mint(address(this), 20000000*10**decimals());
        }
        //min granularidad a stackear totalAssets/totalSupply
        _mint(msg.sender, 30000000000000);
        //////////////////44999965753 4559-44999965753 6058
        //320000017.757482258564020981
    }

    /// @dev Authorizes the upgrade of the contract.
    /// @param newImplementation The address of the new implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @dev Sets the AssetRelease contract address.
    /// @param _assetRelease The address of the AssetRelease contract.
    /// Emits an AssetReleaseUpdated event.
    function setAssetRelease(AssetRelease _assetRelease) external onlyOwner {
        if (address(_assetRelease) == address(0) || !isContract(address(_assetRelease))) revert InvalidAddress();

        address oldAssetRelease = address(assetRelease);
        assetRelease = _assetRelease;

        emit AssetReleaseUpdated(oldAssetRelease, address(_assetRelease));
    }

    // === Public/External Functions ===

    /// @dev Withdraws a specified amount of ERC20 tokens.
    /// @param token The address of the ERC20 token to withdraw.
    /// @param amount The amount of tokens to withdraw.
    /// Emits a TokensWithdrawn event.
    function withdrawToken(IERC20 token, uint256 amount) external onlyOwner nonReentrant {
        if (address(token) == address(0) || !isContract(address(token))) revert InvalidAddress();
        if (token.balanceOf(address(this)) < amount) revert InsufficientBalance();
        if (isContract(msg.sender) || msg.sender == address(0)) revert InvalidAddress();
        SafeERC20.safeTransfer(token, msg.sender, amount);
        emit TokensWithdrawn(address(token), msg.sender, amount);
    }

    /// @dev Withdraws a specified amount of Ether.
    /// @param amount The amount of Ether to withdraw.
    /// Emits an EtherWithdrawn event.
    function withdrawEther(uint256 amount) external onlyOwner nonReentrant {
        if (address(this).balance < amount) revert InsufficientBalance();
        if (isContract(msg.sender) || msg.sender == address(0)) revert InvalidAddress();
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        
        emit EtherWithdrawn(msg.sender, amount);
    }

    // === Overrides ===

    /// @dev See {IERC4626-deposit}. Using Permit
    /// @param assets The amount of assets to deposit.
    /// @param receiver The address to receive the deposited assets.
    /// @param deadline The time by which the permit must be executed.
    /// @param v The recovery byte of the signature.
    /// @param r The R value of the signature.
    /// @param s The S value of the signature.
    /// @return The amount of shares received for the deposited assets.
    function permitAndDeposit(uint256 assets, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public nonReentrant returns (uint256) {
        address _assetContract = asset();
        if (_assetContract == address(0) || !isContract(_assetContract)) revert InvalidAddress();
        if (receiver == address(0) || deadline == 0) revert InvalidValue();
        ERC20Permit(_assetContract).permit(msg.sender, address(this), assets, deadline, v, r, s);  
        return super.deposit(assets, receiver);
    }

    /// @dev See {IERC4626-mint}. Using permit
    /// @dev The use of timestamp is acceptable here as permit is evaluating it too.
    /// @param shares The number of shares to mint.
    /// @param receiver The address to receive the minted shares.
    /// @param deadline The time by which the permit must be executed.
    /// @param v The recovery byte of the signature.
    /// @param r The R value of the signature.
    /// @param s The S value of the signature.
    /// @return The amount of assets corresponding to the minted shares.
    function permitAndMint(uint256 shares, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public nonReentrant returns (uint256) {
        if (receiver == address(0)) revert InvalidAddress();
        if (deadline < block.timestamp) revert InvalidDeadline();
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        address _assetContract = asset();
        if (_assetContract == address(0) || !isContract(_assetContract)) revert InvalidAddress();
        uint256 assets = previewMint(shares);
        ERC20Permit(_assetContract).permit(msg.sender, address(this), assets, deadline, v, r, s);  
        _deposit(_msgSender(), receiver, assets, shares);
        return assets;
    }

    // === Internal Functions ===

    /// @dev Internal function to handle withdrawals.
    /// @param caller The address initiating the withdrawal.
    /// @param receiver The address to receive the withdrawn tokens.
    /// @param ownerAddress The address of the owner of the shares being withdrawn. Change from owner to ownerAddress so we don't shadow Ownable smart contract
    /// @param assets The amount of assets to withdraw.
    /// @param shares The amount of shares to burn.
    function _withdraw(
        address caller,
        address receiver,
        address ownerAddress,
        uint256 assets,
        uint256 shares
    ) internal nonReentrant virtual override {
        AssetRelease _assetRelease = assetRelease;
        if (address(_assetRelease) == address(0) || !isContract(address(_assetRelease))) revert InvalidAddress();
        if (caller == address(0) || receiver == address(0) || ownerAddress == address(0)) revert InvalidAddress();      
        if (assets < 1 && shares < 1) revert InvalidValue();
        bool callAfterRedeem = _assetRelease.beforeRedeem();
        super._withdraw(caller, receiver, ownerAddress, assets, shares);
        if (callAfterRedeem) {
            _assetRelease.afterRedeem();
        }
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override  {
        if (assets < 10000000000000000) revert InvalidValue(); // < 0.01 (in maximum a few hours you must get your money back)
        if (shares < 1000) revert InvalidValue();  // Not accepting deposits that are receiving less than 1000 shares in order to accept a max loss while deposit of 0.1% (30hours recover with 50% of yield)
        super._deposit(caller, receiver, assets, shares);
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

    /// @dev Returns the total assets held by the contract.
    /// @return The total assets.
    function totalAssets() public view override returns (uint256) {
        address _asset = asset();
        if (_asset == address(0) || !isContract(_asset)) return 0;
        AssetRelease _assetRelease = assetRelease;
        if (address(_assetRelease) == address(0) || !isContract(address(_assetRelease))) return IERC20(_asset).balanceOf(address(this));
        return IERC20(_asset).balanceOf(address(this)) + _assetRelease.incLucySinceLastTime();
    }
}

/*
    Depositos Symbiosis
    contexto:
    msg.sender = 0x7e2Bf2537086d1A22791CE00015BbE34Ed2D301c
    amount = 300_000; //493e0

    variables
    USDBC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    META_ROUTER_GATEWAY = 0X41ae964d0f61bb5f5e253141a462ad6f3b625b92;
    META_ROUTER = 0x691df9c4561d95a4a726313089c8536dd682b946
    PORTAL = 0xEE981B2459331AD268cc63CE6167b446AF4161f8;

    Prepare
    address[] approvedTokens= [USDBC,USDBC];
    otherSideCalldata =
    0xce654c17
    0000000000000000000000000000000000000000000000000000000000000020
    000000000000000000000000000000000000000000000000000000000003d090
    00000000000000000000000000000000000000000000000000000000000493e0 => amount
    000000000000000000000000d9aaec86b65d86f6a7b5b1b0c42ffa531710b6ca => USDB
    0000000000000000000000007e2bf2537086d1a22791ce00015bbe34ed2d301c => msg.sender
    00000000000000000000000045cfd6fb7999328f189aad2739fba4be6c45e5bf ==> C
    0000000000000000000000001a039ce63ae35a67bf0e9f6dbfae969639d59ec8 ==> D
    0000000000000000000000007e2bf2537086d1a22791ce00015bbe34ed2d301c => msg.sender
    0000000000000000000000000000000000000000000000000000000000d38bb4
    0000000000000000000000000000000000000000000000000000000000000200
    000000000000000000000000bbad2fe9558e55ebfa04b3b5bff0b6c4e2ffdd2c ==> b
    0000000000000000000000000000000000000000000000000000000000000260
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000540
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000007e2bf2537086d1a22791ce00015bbe34ed2d301c => msg.sender
    73796d62696f7369732d61707000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000002
    000000000000000000000000fbe80e8c3fbff0bc314b33d1c6185230ac319309 ==> a
    000000000000000000000000fbe80e8c3fbff0bc314b33d1c6185230ac319309 ==> a
    00000000000000000000000000000000000000000000000000000000000002a4
    1e859a0500000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    000000c000000000000000000000000000000000000000000000000000000000
    000001e000000000000000000000000000000000000000000000000000000000
    0000022000000000000000000000000000000000000000000000000000000000
    000002600000000000000000000000007e2bf2537086d1a22791ce00015bbe34 => msg.sender
    ed2d301c00000000000000000000000000000000000000000000000000000000
    0000000100000000000000000000000000000000000000000000000000000000
    0000002000000000000000000000000000000000000000000000000000000000
    000000a45f4b9bde000000000000000000000000000000000000000000000000
    000000000000000f000000000000000000000000000000000000000000000000
    000000000000c350000000000000000000000000000000000000000000000000
    00901757a0020d030000000000000000000000007e2bf2537086d1a22791ce00 => msg.sender
    015bbe34ed2d301c000000000000000000000000000000000000000000000000
    0000000068bb6e3a000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    00000001000000000000000000000000c3255e317481b95a3e61844c274de8ba ==> E
    f8edf39700000000000000000000000000000000000000000000000000000000
    00000001000000000000000000000000fbe80e8c3fbff0bc314b33d1c6185230ac319309 ==> a
    ac31930900000000000000000000000000000000000000000000000000000000
    0000000100000000000000000000000000000000000000000000000000000000
    0000004400000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000


    Function:
    USDBC.approve(META_ROUTER_GATEWAY,amount);
    META_ROUTER.metaRoute((0x,0x,approvedTokens,0x0,0x0,amount,false,PORTAL,otherSideCalldata))



*/