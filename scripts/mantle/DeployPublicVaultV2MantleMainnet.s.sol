pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "@rivera/vaults/RiveraAutoCompoundingVaultV2Public.sol";
// import "@rivera/factories/staking/vault/RiveraConcLiqStakingWhiLisVaultFactory.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
// import '@rivera/factories/staking/RiveraLpStakingVaultCreationStruct.sol';

struct RiveraVaultParams {
    address asset;
    uint256 totalTvlCap;
    uint256 approvalDelay;
    string tokenName;
    string tokenSymbol;
    int24 tickLower;
    int24 tickUpper;
    address stake;
    // address[] rewardToLp0AddressPath;
    // uint24[] rewardToLp0FeePath;
    // address[] rewardToLp1AddressPath;
    // uint24[] rewardToLp1FeePath;
    // address  rewardtoNativeFeed;
    address  assettoNativeFeed;
    address tickMathLib;
    address sqrtPriceMathLib;
    address liquidityMathLib;
    address safeCastLib;
    address liquidityAmountsLib;
    address fullMathLib;
    // string pendingReward;
}

struct FeeParams {
    uint256 withdrawFeeDecimals;//100
    uint256 withdrawFee;//0

    uint256 feeDecimals;//100
    uint256 protocolFee;//15
    uint256 fundManagerFee;//0
    uint256 partnerFee;//0
    address partner;//
}


enum VaultType {
        PRIVATE ,
        PUBLIC,
        WHITELISTED
    }

interface IRiveraVaultFactoryV2
 {
    event VaultCreated(address indexed user, address indexed stake, address vault);

    function allVaults(uint) external view returns (address vault);
    function listAllVaults() external view returns (address[] memory);
    function createVault(RiveraVaultParams memory createVaultParams,FeeParams memory feePArams) external returns (address vault);

}




contract DeployPublicVaultV2MantleMainnet is Script {

    //factoru
    IRiveraVaultFactoryV2 _factory=IRiveraVaultFactoryV2(0x19F51834817708F2da9Ac7D0cc3eAFF0b6Ed17D7);
    address _stake = 0xA125AF1A4704044501Fe12Ca9567eF1550E430e8;//mainnet
    address _lpToken0=0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE;//mainnnet
    address _lpToken1=0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111;//mainnnet
    int24 _tickLower = 50940;
    int24 _tickUpper = 97020;
    uint256 _withdrawFeeDecimals=100;
    uint256 _withdrawFee=0;
    uint256 _feeDecimals=100;
    uint256 _protocolFee=15;
    uint256 _fundManagerFee=0;
    uint256 _partnerFee=0;
    address _partner=0x961Ef0b358048D6E34BDD1acE00D72b37B9123D7 ;
    address  assettoNativeFeed=address(0);
    address _user1;
    address _user2;
    address _user3;  
    address _user4;
    address _user5;
    address _user6;
    address _user7;
    address _user8;
    address _user9;
    address _user10;
    uint256 _privateKey1;
    uint256 _privateKey2;
    uint256 _privateKey3;
    uint256 _privateKey4;

    // string pendingReward="pendingFusionX";
    // address _reward = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    // //libraries
     address _tickMathLib =0x74C5E75798b33D38abeE64f7EC63698B7e0a10f1;
    address _sqrtPriceMathLib = 0xA38Bf51645D77bd0ec5072Ae5eCA7c0e67CFc081;
    address _liquidityMathLib = 0xe6d2bD39aEFCDCFC989B03AE45A5aBEfe9BF1F51;
    address _safeCastLib = 0x55FD5B67B115767036f9e8af569B281A8A544a12;
    address _liquidityAmountsLib =0xE344B76f1Dec90E8a2e68fa7c1cfEBB329aFB332;
    address _fullMathLib = 0xAa5Fd782B03Bfb2f25F13B6ae4e254F5149B9575;

    //usdt bnb pool



    uint256 stratUpdateDelay = 172800;
    uint256 vaultTvlCap = 100000e6;
    VaultType _vaultType;

    function setUp() public {
        string memory seedPhrase = vm.readFile(".secret");
        uint256 privateKey1 = vm.deriveKey(seedPhrase, 0);      //[key1, key2, ...] = vm.deriveKeys(seedPhrase, 0, 10); 
        _privateKey1=privateKey1;
        ///user1 will be
        _user1 = vm.addr(privateKey1);
        uint256 privateKey2 = vm.deriveKey(seedPhrase, 1);
        _privateKey2=privateKey2;
        ///user2 will be
        _user2 = vm.addr(privateKey2);

        uint256 privateKey3 = vm.deriveKey(seedPhrase, 2);
        _privateKey3=privateKey3;
        ///user3 will be
        _user3 = vm.addr(privateKey3);

        uint256 privateKey4 = vm.deriveKey(seedPhrase,3);
        _privateKey4=privateKey4;
        _user4 =vm.addr(privateKey4);

        uint256 privateKey5 = vm.deriveKey(seedPhrase,4);
        _user5 =vm.addr(privateKey5);

        uint256 privateKey6 = vm.deriveKey(seedPhrase,5);
        _user6 =vm.addr(privateKey6);

        uint256 privateKey7 = vm.deriveKey(seedPhrase,6);
        _user7 =vm.addr(privateKey7);

        uint256 privateKey8 = vm.deriveKey(seedPhrase,7);
        _user8 =vm.addr(privateKey8);

        uint256 privateKey9 = vm.deriveKey(seedPhrase,8);
        _user9 =vm.addr(privateKey9);

        uint256 privateKey10 = vm.deriveKey(seedPhrase,9);
        _user10 =vm.addr(privateKey10);

        console.log("user1",_user1);
        console.log("user2",_user2);
        console.log("user3",_user3);
        console.log("user4",_user4);

    }

    function run() public {

        vm.startBroadcast(_privateKey2);
        console.log("Vault Factory",address(_factory));
        console.log("======================Deploy Vaults====================");
        console.log("create vault");
        RiveraVaultParams memory createVaultParamsFsxPool= RiveraVaultParams(
            _lpToken0,
            vaultTvlCap,
            stratUpdateDelay,
            "RIV-01-01-Y",
            "RIV-01-01-Y",
            _tickLower,
            _tickUpper,
            _stake,
            // rewardToLp0AddressPath,
            // rewardToLp0FeePath,
            // rewardToLp1AddressPath,
            // rewardToLp1FeePath,
            // rewardtoNativeFeed,
            assettoNativeFeed,
            _tickMathLib,
            _sqrtPriceMathLib,
            _liquidityMathLib,
            _safeCastLib,
            _liquidityAmountsLib,
            _fullMathLib
            // pendingReward

        );
        FeeParams memory feeParams = FeeParams(
            _withdrawFeeDecimals,
            _withdrawFee,
            _feeDecimals,
            _protocolFee,
            _fundManagerFee,
            _partnerFee,
            _partner
        );
        address vaultFsxPool = _createVault(_factory,createVaultParamsFsxPool,feeParams);
        console.log("Vault RIV-01-01-Y ",vaultFsxPool);
        console.log("======================"); 
        vm.stopBroadcast(); 
        address[] memory vault=_factory.listAllVaults();
        console.log("all vaults",vault.length);
        console.log("======================Deposit in Vault====================");
        uint256 depositAmount1=IERC20(_lpToken0).balanceOf(_user3)/2;///vault 1 deposit amount
        vm.startBroadcast(_privateKey3);
        IERC20(_lpToken0).approve(vaultFsxPool, depositAmount1);
        RiveraAutoCompoundingVaultV2Public(vaultFsxPool).deposit(depositAmount1, _user3);
        console.log("deposited");
        vm.stopBroadcast();
        // vm.startBroadcast(_privateKey4);
        // IERC20(l_lpToken0).approve(vaultFsxPool, depositAmount1);
        // RiveraAutoCompoundingVaultV2Public(vaultFsxPool).deposit(depositAmount1, _user4);
        // vm.stopBroadcast();
    }

    function _createVault(IRiveraVaultFactoryV2 factory,RiveraVaultParams memory createVaultParams,FeeParams memory feeParams) internal returns (address vaultAddress){
        
        vaultAddress =factory.createVault(createVaultParams,feeParams); 
    }
}

