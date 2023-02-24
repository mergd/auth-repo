// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.17;

// import "openzeppelin/access/Ownable.sol";
// import "openzeppelin/token/ERC721/extensions/ERC721Enumerable.sol";
// import "openzeppelin/utils/Counters.sol";

/// @notice Implementation of CIP-001 https://github.com/Canto-Improvement-Proposals/CIPs/blob/main/CIP-001.md
/// @dev Every contract is responsible to register itself in the constructor by calling `register(address)`.
///      If contract is using proxy pattern, it's possible to register retroactively, however past fees will be lost.
///      Recipient withdraws fees by calling `withdraw(uint256,address,uint256)`.
contract Turnstile is Ownable, ERC721Enumerable {
    using Counters for Counters.Counter;

    struct NftData {
        uint256 tokenId;
        bool registered;
        bytes4[] selectors;
        mapping(address => bytes32) signers;
    }

    Counters.Counter private _tokenIdTracker;

    /// @notice maps smart contract address to tokenId
    mapping(address => NftData) public feeRecipient;

    /// @notice maps tokenId to fees earned
    mapping(uint256 => uint256) public balances;

    event Register(address smartContract, address recipient, uint256 tokenId);
    event Assign(address smartContract, uint256 tokenId);
    event Withdraw(uint256 tokenId, address recipient, uint256 feeAmount);
    event Authorize(
        address signer,
        address user,
        bytes4 func,
        address smartContract
    );
    // event DistributeFees(uint256 tokenId, uint256 feeAmount);

    // error NotAnOwner();
    error AlreadyRegistered();
    error Unregistered();
    error NotAnOwner();
    error NotAnSigner();
    error DeadlineExpired();
    error InvalidRecipient();
    error InvalidTokenId();
    error NothingToWithdraw();
    error NothingToDistribute();

    /// @dev only owner of _tokenId can call this function
    modifier onlyNftOwner(uint256 _tokenId) {
        if (ownerOf(_tokenId) != msg.sender) revert NotAnOwner();

        _;
    }

    /// @dev only smart contract that is unregistered can call this function
    modifier onlyUnregistered() {
        address smartContract = msg.sender;
        if (isRegistered(smartContract)) revert AlreadyRegistered();

        _;
    }

    constructor() ERC721("Turnstile", "Turnstile") {}

    /// @notice Returns current value of counter used to tokenId of new minted NFTs
    /// @return current counter value
    function currentCounterId() external view returns (uint256) {
        return _tokenIdTracker.current();
    }

    /// @notice Returns tokenId that collects fees generated by the smart contract
    /// @param _smartContract address of the smart contract
    /// @return tokenId that collects fees generated by the smart contract
    function getTokenId(
        address _smartContract
    ) external view returns (uint256) {
        if (!isRegistered(_smartContract)) revert Unregistered();

        return feeRecipient[_smartContract].tokenId;
    }

    /// @notice Returns true if smart contract is registered to collect fees
    /// @param _smartContract address of the smart contract
    /// @return true if smart contract is registered to collect fees, false otherwise
    function isRegistered(address _smartContract) public view returns (bool) {
        return feeRecipient[_smartContract].registered;
    }

    /// @notice Mints ownership NFT that allows the owner to collect fees earned by the smart contract.
    ///         `msg.sender` is assumed to be a smart contract that earns fees. Only smart contract itself
    ///         can register a fee receipient.
    /// @param _recipient recipient of the ownership NFT
    /// @return tokenId of the ownership NFT that collects fees
    function register(
        address _recipient
    ) public onlyUnregistered returns (uint256 tokenId) {
        address smartContract = msg.sender;

        if (_recipient == address(0)) revert InvalidRecipient();

        tokenId = _tokenIdTracker.current();
        _mint(_recipient, tokenId);
        _tokenIdTracker.increment();

        emit Register(smartContract, _recipient, tokenId);

        feeRecipient[smartContract] = NftData({
            tokenId: tokenId,
            registered: true,
            selectors: []
        });
    }

    function registerFunction(bytes4[] memory _functions) public {
        for (uint256 i = 0; i < _functions.length; i++) {
            _registerInterface(_functions[i]);
        }
    }

    /// @notice Assigns smart contract to existing NFT. That NFT will collect fees generated by the smart contract.
    ///         Callable only by smart contract itself.
    /// @param _tokenId tokenId which will collect fees
    /// @return tokenId of the ownership NFT that collects fees
    function assign(
        uint256 _tokenId
    ) public onlyUnregistered returns (uint256) {
        address smartContract = msg.sender;

        if (!_exists(_tokenId)) revert InvalidTokenId();

        emit Assign(smartContract, _tokenId);

        feeRecipient[smartContract] = NftData({
            tokenId: _tokenId,
            registered: true
        });

        return _tokenId;
    }

    function addSigner(address Signer, uint256 _tokenId) public {
        if (!_exists(_tokenId)) revert InvalidTokenId();
    }

    function setSigner(address _signer, uint256 _tokenId) public {
        if (!_exists(_tokenId)) revert InvalidTokenId();
        if (ownerOf(_tokenId) != msg.sender) revert NotAnOwner();

        feeRecipient[msg.sender].signer = bytes32(address(1));
    }

    function removeSigner(address _signer, uint256 _tokenId) public {
        if (!_exists(_tokenId)) revert InvalidTokenId();
        if (ownerOf(_tokenId) != msg.sender) revert NotAnOwner();
    }

    function authorize(
        uint256 deadline,
        address signer,
        address userAddress_,
        bytes4 selector,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (uint256) {
        NftData memory nftData = feeRecipient[msg.sender];
        bytes32 prevHash = feeRecipient[msg.sender][signer];
        require(prevHash != 0, "not signer");

        bytes32 currentHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n111",
                selector,
                deadline,
                block.chainid,
                userAddress_
            )
        );
        require(currentHash != prevHash, "already used");

        checkAuth(signer, deadline, currentHash, v, r, s);
        // user can reuse the same signature for multiple transactions
        emit Authorize(signer, userAddress_, selector, msg.sender);
        return nonce;
    }

    function checkAuth(
        address signer_,
        uint256 deadline,
        bytes32 currentHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        require(block.timestamp < deadline, DeadlineExpired());
        require(ecrecover(currentHash, v, r, s) == signer_, NotAnSigner());
    }
}