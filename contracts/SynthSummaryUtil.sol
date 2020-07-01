pragma solidity ^0.5.16;

interface ISynth {
    function currencyKey() external view returns (bytes32);
    function balanceOf(address owner) external view returns (uint);
    function totalSupply() external view returns (uint);
}
interface ISynthetix {
    function availableSynths(uint index) external view returns (ISynth);
    function availableSynthCount() external view returns (uint);
    function availableCurrencyKeys() external view returns (bytes32[] memory);
}

interface IExchangeRates {
    function rateIsFrozen(bytes32 currencyKey) external view returns (bool);
    function ratesForCurrencies(bytes32[] calldata currencyKeys) external view returns (uint[] memory);
    function effectiveValue(bytes32 sourceCurrencyKey, uint sourceAmount, bytes32 destinationCurrencyKey)
    external
    view
    returns (uint);
}

interface IAddressResolver {
    function getAddress(bytes32 name) external view returns (address);
    function getSynth(bytes32 key) external view returns (address);
    function requireAndGetAddress(bytes32 name, string calldata reason) external view returns (address);
}


contract Owned {
    address public owner;
    address public nominatedOwner;

    constructor(address _owner) public {
        require(_owner != address(0), "Owner address cannot be 0");
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function nominateNewOwner(address _owner) external onlyOwner {
        nominatedOwner = _owner;
        emit OwnerNominated(_owner);
    }

    function acceptOwnership() external {
        require(msg.sender == nominatedOwner, "You must be nominated before you can accept ownership");
        emit OwnerChanged(owner, nominatedOwner);
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only the contract owner may perform this action");
        _;
    }

    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);
}


contract SynthSummaryUtil is Owned {

    IAddressResolver public addressResolver;

    bytes32 internal constant CONTRACT_SYNTHETIX = "Synthetix";
    bytes32 internal constant CONTRACT_EXRATES = "ExchangeRates";
    bytes32 internal constant SUSD = "sUSD";

    constructor(address resolver) public Owned(msg.sender) {
        addressResolver = IAddressResolver(resolver);
    }

    function _synthetix() internal view returns (ISynthetix) {
        return ISynthetix(addressResolver.requireAndGetAddress(CONTRACT_SYNTHETIX, "Missing Synthetix address"));
    }

    function _exchangeRates() internal view returns (IExchangeRates) {
        return IExchangeRates(addressResolver.requireAndGetAddress(CONTRACT_EXRATES, "Missing ExchangeRates address"));
    }

    function setAddressResolver(IAddressResolver resolver) external onlyOwner {
        addressResolver = resolver;
    }

    function totalSynthsInKey(address account, bytes32 currencyKey) external view returns (uint total) {
        ISynthetix synthetix = _synthetix();
        IExchangeRates exchangeRates = _exchangeRates();
        uint numSynths = synthetix.availableSynthCount();
        for (uint i = 0; i < numSynths; i++) {
            ISynth synth = synthetix.availableSynths(i);
            total += exchangeRates.effectiveValue(synth.currencyKey(), synth.balanceOf(account), currencyKey);
        }
        return total;
    }

    function synthsBalances(address account) external view returns (bytes32[] memory, uint[] memory,  uint[] memory) {
        ISynthetix synthetix = _synthetix();
        IExchangeRates exchangeRates = _exchangeRates();
        uint numSynths = synthetix.availableSynthCount();
        bytes32[] memory currencyKeys = new bytes32[](numSynths);
        uint[] memory balances = new uint[](numSynths);
        uint[] memory sUSDBalances = new uint[](numSynths);
        for (uint i = 0; i < numSynths; i++) {
            ISynth synth = synthetix.availableSynths(i);
            currencyKeys[i] = synth.currencyKey();
            balances[i] = synth.balanceOf(account);
            sUSDBalances[i] = exchangeRates.effectiveValue(currencyKeys[i], balances[i], SUSD);
        }
        return (currencyKeys, balances, sUSDBalances);
    }

    function frozenSynths() external view returns (bytes32[] memory) {
        ISynthetix synthetix = _synthetix();
        IExchangeRates exchangeRates = _exchangeRates();
        uint numSynths = synthetix.availableSynthCount();
        bytes32[] memory frozenSynthsKeys = new bytes32[](numSynths);
        for (uint i = 0; i < numSynths; i++) {
            ISynth synth = synthetix.availableSynths(i);
            if (exchangeRates.rateIsFrozen(synth.currencyKey())) {
                frozenSynthsKeys[i] = synth.currencyKey();
            }

        }
        return frozenSynthsKeys;
    }

    function synthsRates() external view returns (bytes32[] memory, uint[] memory) {
        bytes32[] memory currencyKeys = _synthetix().availableCurrencyKeys();
        return (currencyKeys, _exchangeRates().ratesForCurrencies(currencyKeys));
    }

    function synthsTotalSupplies()
        external
        view
        returns (bytes32[] memory, uint256[] memory, uint256[] memory)
    {
        ISynthetix synthetix = _synthetix();
        IExchangeRates exchangeRates = _exchangeRates();

        uint256 numSynths = synthetix.availableSynthCount();
        bytes32[] memory currencyKeys = new bytes32[](numSynths);
        uint256[] memory balances = new uint256[](numSynths);
        uint256[] memory sUSDBalances = new uint256[](numSynths);
        for (uint256 i = 0; i < numSynths; i++) {
            ISynth synth = synthetix.availableSynths(i);
            currencyKeys[i] = synth.currencyKey();
            balances[i] = synth.totalSupply();
            sUSDBalances[i] = exchangeRates.effectiveValue(
                currencyKeys[i],
                balances[i],
                SUSD
            );
        }
        return (currencyKeys, balances, sUSDBalances);
    }
}
