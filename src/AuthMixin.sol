pragma solidity 0.8.17;

interface IRegistry {
    function authorize(
        uint256 deadline,
        address signer,
        address userAddress,
        bytes4 selector,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool);

    function register(address _recipient) external;
}

contract AuthMixin {
    address immutable registryContract;
    error NotAuthorized();

    struct Signature {
        uint256 deadline;
        address signer;
        bytes4 selector;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    constructor(address _registryContract, address _recipient) {
        registryContract = _registryContract;
        IRegistry(registryContract).register(_recipient);
    }

    function _isAuthorized(
        Signature calldata _signature
    ) internal returns (bool) {
        return
            IRegistry(registryContract).authorize(
                _signature.deadline,
                _signature.signer,
                msg.sender,
                _signature.selector,
                _signature.v,
                _signature.r,
                _signature.s
            );
    }

    modifier isAuthorized(Signature calldata _signature) {
        if (_isAuthorized(_signature)) {
            _;
        } else {
            revert NotAuthorized();
        }
    }
}
