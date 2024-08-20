pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/vaults/RiveraAutoCompoundingVaultV2Public.sol";
import "../src/strategies/staking/RiveraUniV2.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "../src/strategies/common/interfaces/IStrategy.sol";


contract DeployV2 is Script {
    address public depositToken=0xC87De04e2EC1F4282dFF2933A2D58199f688fC3d;//wsvm
    address public tokenB =0xcc82bD85a3CaAdE271756FB24C831456Ff7c053F;//ice
    address public stake=0xb414290A00f384b71a61705668fD10ff143D9CAe;
    address public router =0xf8ac4BEB2F75d2cFFb588c63251347fdD629B92c;
    address public factory =0xE578184bC88EB48485Bba23a37B5509578d2aE38;
    address public vault =0xA8D248c1257d28D1B4e86AFcA6E2b16aDC729917;
    address public strat=0x0796F7c3A87409428C25Ce41ce468273376B07D6;


    uint256 _stratUpdateDelay = 172800;
    uint256 _vaultTvlCap = 10000e18;

function setUp() public {}

function run() public {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    address owner = vm.addr(privateKey);
    vm.startBroadcast(privateKey);

    RiveraAutoCompoundingVaultV2Public newVault = new RiveraAutoCompoundingVaultV2Public(
        depositToken,
        "RIV-01-01-Y",
        "RIV-01-01-Y",
        _stratUpdateDelay,
         _vaultTvlCap
    );
    vault = address(newVault);
    console.log("address vault is " , vault);

    RiveraUniV2 newStrat = new RiveraUniV2();


    RiveraLpStakingParams memory rivParam =  RiveraLpStakingParams (
        depositToken,
        tokenB,
        stake,
        factory
    );

    CommonAddresses memory common =  CommonAddresses(
        vault,
        router,
        1000,
        3,
        100,
        0,
        0,
        0,
        owner,
        owner,
        owner
    );

    newStrat.init(rivParam,common);
    strat = address(newStrat);
    newVault.init(IStrategy(strat));
    console.log("address strat is " , strat);
    console.log("before token balance is " , IERC20(depositToken).balanceOf(owner));
    IERC20(depositToken).approve(vault,1000e18);
    newVault.deposit(1e10,owner);
    console.log("User balance is " , IERC20(vault).balanceOf(owner));
    console.log("total  asset is " , newStrat.balanceOf());
    newVault.withdraw(
        5e9,
        owner,
        owner
    );

    console.log("After User balance is " , IERC20(vault).balanceOf(owner));
    console.log("After total  asset is " , newStrat.balanceOf());
    console.log("After token balance is " , IERC20(depositToken).balanceOf(owner));

}
}




//forge script scripts/DeployV2.s.sol:DeployV2 --rpc-url https://rpc.stratovm.io --broadcast -vvv --legacy --slow
//https://rpc.stratovm.io