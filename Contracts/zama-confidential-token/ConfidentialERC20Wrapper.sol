// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

// interfaces
import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';

// modules
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {ERC7984} from '@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol';
import {ERC7984ERC20Wrapper} from '@openzeppelin/confidential-contracts/token/ERC7984/extensions/ERC7984ERC20Wrapper.sol';
import {ZamaEthereumConfig} from '@fhevm/solidity/config/ZamaConfig.sol';

// libs
import {FHE, ebool, euint64, externalEuint64} from '@fhevm/solidity/lib/FHE.sol';

/// @title ConfidentialERC20Wrapper
/// @author Jean Cavallera (CJ42)
/// @notice Wraps a public ERC-20 into an ERC-7984 confidential token on Zama's FHEVM,
/// with an optional encrypted per-holder transfer limit set by the owner.
///
/// @dev Inherits {ERC7984ERC20Wrapper} from OpenZeppelin Confidential Contracts for the
/// wrap / unwrap / finalizeUnwrap flow, and {ZamaEthereumConfig} to point FHE operations
/// at Zama's coprocessor on Ethereum mainnet and Sepolia.
///
/// Neither the balances, the transferred amounts nor the transfer limits are ever revealed
/// on-chain. Following ERC-7984 semantics, a transfer above the sender's limit does not
/// revert (which would leak information) but silently transfers an encrypted zero.
///
/// Wrapping (mint) and unwrapping (burn) are never limited, so holders can always
/// exit to the underlying ERC-20.
contract ConfidentialERC20Wrapper is
  ERC7984ERC20Wrapper,
  ZamaEthereumConfig,
  Ownable2Step
{
  /// @dev Encrypted maximum amount each holder can send per confidential transfer.
  /// An uninitialized handle means the holder is unrestricted.
  mapping(address holder => euint64 limit) private _transferLimits;

  /// @notice Emitted when the owner sets or updates the encrypted transfer limit of `holder`.
  event TransferLimitSet(address indexed holder, euint64 limit);

  /// @notice Emitted when the owner removes the transfer limit of `holder`.
  event TransferLimitRemoved(address indexed holder);

  /// @param underlying_ The public ERC-20 token being wrapped.
  /// @param owner_ The account allowed to manage transfer limits.
  /// @param name_ Name of the confidential token.
  /// @param symbol_ Symbol of the confidential token.
  /// @param contractURI_ ERC-7572 contract-level metadata URI.
  constructor(
    IERC20 underlying_,
    address owner_,
    string memory name_,
    string memory symbol_,
    string memory contractURI_
  )
    ERC7984(name_, symbol_, contractURI_)
    ERC7984ERC20Wrapper(underlying_)
    Ownable(owner_)
  {}

  /// @notice Set an encrypted per-transfer limit for `holder`.
  ///
  /// @dev The limit is encrypted client-side (e.g. with the Zama Relayer SDK) against this
  /// contract and the owner address, then verified on-chain via `inputProof`.
  /// Both the owner and `holder` are granted ACL permission to decrypt it.
  ///
  /// @param holder The account to restrict.
  /// @param encryptedLimit Handle of the encrypted limit.
  /// @param inputProof Zero-knowledge proof of plaintext knowledge for `encryptedLimit`.
  function setTransferLimit(
    address holder,
    externalEuint64 encryptedLimit,
    bytes calldata inputProof
  ) external onlyOwner {
    euint64 limit = FHE.fromExternal(encryptedLimit, inputProof);

    FHE.allowThis(limit);
    FHE.allow(limit, owner());
    FHE.allow(limit, holder);

    _transferLimits[holder] = limit;
    emit TransferLimitSet(holder, limit);
  }

  /// @notice Remove the transfer limit of `holder`, making their transfers unrestricted.
  function removeTransferLimit(address holder) external onlyOwner {
    _transferLimits[holder] = euint64.wrap(0);
    emit TransferLimitRemoved(holder);
  }

  /// @notice Returns the handle of the encrypted transfer limit of `holder`.
  /// @dev Only accounts granted ACL access (owner and `holder`) can decrypt it.
  function transferLimitOf(address holder) external view returns (euint64) {
    return _transferLimits[holder];
  }

  /// @dev Caps holder-to-holder transfers at the sender's encrypted limit.
  /// The comparison and selection run homomorphically: `amount` is replaced by an encrypted
  /// zero when it exceeds the limit, without revealing which branch was taken.
  function _update(
    address from,
    address to,
    euint64 amount
  ) internal override returns (euint64) {
    euint64 limit = _transferLimits[from];

    if (from != address(0) && to != address(0) && FHE.isInitialized(limit)) {
      ebool withinLimit = FHE.le(amount, limit);
      amount = FHE.select(withinLimit, amount, FHE.asEuint64(0));
    }

    return super._update(from, to, amount);
  }
}
