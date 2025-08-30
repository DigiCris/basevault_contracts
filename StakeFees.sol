// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Usar deposit y redeem

/// @dev ERC-4626 vault with entry/exit fees expressed in https://en.wikipedia.org/wiki/Basis_point[basis point (bp)].
///
/// NOTE: The contract charges fees in terms of assets, not shares. This means that the fees are calculated based on the
/// amount of assets that are being deposited or withdrawn, and not based on the amount of shares that are being minted or
/// redeemed. This is an opinionated design decision that should be taken into account when integrating this contract.
///
/// WARNING: This contract has not been audited and shouldn't be considered production ready. Consider using it with caution.
contract StakeFees is ERC4626 {
    using Math for uint256;

    struct User {
        uint256 vesting;
        uint256 amount;
    }

    uint256 private constant _BASIS_POINT_SCALE = 1e4;
    address public immutable protocolAddr;
    uint256 public minStakingTime;
    uint256 public fee_;

    mapping(address => User) public user;// contiene siempre el minimo que el usuario puede sacar pero nunca se puede achicar sin previamente withdraw todo

    constructor(IERC20 asset_) ERC4626(asset_) {
        protocolAddr = msg.sender;
        minStakingTime = 60;
        fee_ = 50; // 0.5% al salir
    }

    // === Overrides ===

    /// @dev Preview taking an entry fee on deposit. See {IERC4626-previewDeposit}.
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return super.previewDeposit(assets);
    }

    /// @dev Preview taking an exit fee on redeem. See {IERC4626-previewRedeem}.
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        User storage _user = user[msg.sender];
        uint256 _vesting = _user.vesting;
        uint256 _amount = _user.amount;
        uint256 assets = super.previewRedeem(shares);
        if(_vesting < block.timestamp) {
            if(assets > _amount) {
                assets = _amount;
            }
        }
        return assets - _feeOnTotal(assets, _exitFeeBasisPoints());
    }

    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 3;
    }

    function deposit(uint256 assets, address receiver, uint256 target) public virtual returns (uint256) {
        User storage _user = user[receiver];
        uint256 _vesting = _user.vesting;
        if(_vesting < target) { // solo aumento el tiempo si el target es superior.
            if(receiver == msg.sender) {
                _user.vesting = target; // si el usuario se aumenta el tiempo a si mismo lo dejo.
            } else {
                if(_vesting == 0) {
                    _user.vesting = target; // acá lo incremento porque sería un primer deposito.
                } /*
                else {
                    Aca no incremento el tiempo porque alguien podría incrementarle el tiempo de otro
                }*/
            }
        }
        _user.amount += assets;
        if (_vesting < (block.timestamp + minStakingTime)) revert(); // No dejamos que nadie deposite por menos de 60 segundos (la idea es que sea en días, pero para testear.
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    // shares no sirve para nada porque lo saca todo.
    function redeem(address receiver, address owner) public virtual returns (uint256) {
        uint256 shares = balanceOf(owner);

        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares); //assets reducidos por el fee

        User storage _user = user[receiver];
        _user.vesting = 0;
        _user.amount = 0;

        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    /// @dev Send exit fee to {_exitFeeRecipient}. See {IERC4626-_deposit}.
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        uint256 fee = _feeOnRaw(assets, _exitFeeBasisPoints());
        address recipient = _exitFeeRecipient();

        super._withdraw(caller, receiver, owner, assets, shares);

        if (fee > 0 && recipient != address(this)) {
            SafeERC20.safeTransfer(IERC20(asset()), recipient, fee);
        }
    }

    // === Fee configuration ===

    function _exitFeeBasisPoints() internal view virtual returns (uint256) {
        return fee_; // replace with e.g. 100 for 1%
    }

    function _entryFeeRecipient() internal view virtual returns (address) {
        return address(protocolAddr); // replace with e.g. a treasury address
    }

    function _exitFeeRecipient() internal view virtual returns (address) {
        return address(protocolAddr); // replace with e.g. a treasury address
    }

    // === Fee operations ===

    /// @dev Calculates the fees that should be added to an amount `assets` that does not already include fees.
    /// Used in {IERC4626-mint} and {IERC4626-withdraw} operations.
    function _feeOnRaw(uint256 assets, uint256 feeBasisPoints) private pure returns (uint256) {
        return assets.mulDiv(feeBasisPoints, _BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    /// @dev Calculates the fee part of an amount `assets` that already includes fees.
    /// Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
    function _feeOnTotal(uint256 assets, uint256 feeBasisPoints) private pure returns (uint256) {
        return assets.mulDiv(feeBasisPoints, feeBasisPoints + _BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }
}