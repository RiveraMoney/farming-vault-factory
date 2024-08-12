pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../src/strategies/staking/RiveraConcLpStaking.sol";
import "../../../src/strategies/common/interfaces/IStrategy.sol";
import "../../../src/vaults/RiveraAutoCompoundingVaultV2Public.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

import "@rivera/router/ERC4626Router.sol";
import "@rivera/strategies/staking/interfaces/INonfungiblePositionManager.sol";
import "@pancakeswap-v3-core/interfaces/IPancakeV3Pool.sol";
import "@pancakeswap-v3-core/interfaces/IPancakeV3Factory.sol";
import "@rivera/strategies/staking/interfaces/libraries/ITickMathLib.sol";
import "@openzeppelin/utils/math/Math.sol";

import "@rivera/libs/DexV3Calculations.sol";
import "@rivera/libs/DexV3CalculationStruct.sol";
import {WETH} from "solmate/tokens/WETH.sol";

///@dev
///As there is dependency on Cake swap protocol. Replicating the protocol deployment on separately is difficult. Hence we would test on main net fork of BSC.
///The addresses used below must also be mainnet addresses.


interface DSIERC20 is IERC20 {
    function DOMAIN_SEPARATOR() external returns (bytes32);
}

contract RiveraConcLpStakingTest is Test {
    RiveraConcLpStaking strategy;
    RiveraAutoCompoundingVaultV2Public vault;
    ERC4626Router erc4626Router;
    IWETH9 weth;

    //Events
    event StratHarvest(
        address indexed harvester,
        uint256 stakeHarvested,
        uint256 tvl
    );
    event Deposit(uint256 tvl, uint256 amount);
    event Withdraw(uint256 tvl, uint256 amount);

    ///@dev Required addresses from mainnet
    ///@notice Currrent addresses are for the BUSD-WOM pool
    //TODO: move these address configurations to an external file and keep it editable and configurable
    address _stake = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;  //Mainnet address of the CAKE-USDT LP Pool you're deploying funds to. It is also the ERC20 token contract of the LP token.
    address _chef = 0x556B9306565093C855AEA9AE92A594704c2Cd59e;   //Address of the pancake master chef v2 contract on BSC mainnet
    address _factory = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address _router = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4; //Address of Pancake Swap router
    address _nonFungiblePositionManager = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address _wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;   //Adress of the CAKE ERC20 token on mainnet
    address _usdt = 0x55d398326f99059fF775485246999027B3197955;

    //cakepool params
    bool _isTokenZeroDeposit = true;
    int24 currentTick = -60524;     //Taken from explorer
    int24 tickSpacing = 10;
    int24 _tickLower = ((currentTick - 6932) / tickSpacing) * tickSpacing;      //Tick for price that is half of current price
    int24 _tickUpper = ((currentTick + 6932) / tickSpacing) * tickSpacing;      //Tick for price that is double of current price
    address _cakeReward = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    //libraries
    address _tickMathLib = 0x21071Cd83f468856dC269053e84284c5485917E1;
    address _sqrtPriceMathLib = 0xA9C3e24d94ef6003fB6064D3a7cdd40F87bA44de;
    address _liquidityMathLib = 0xA7B88e482d3C9d17A1b83bc3FbeB4DF72cB20478;
    address _safeCastLib = 0x3dbfDf42AEbb9aDfFDe4D8592D61b1de7bd7c26a;
    address _liquidityAmountsLib = 0x672058B73396C78556fdddEc090202f066B98D71;
    address _fullMathLib = 0x46ECf770a99d5d81056243deA22ecaB7271a43C7;
    address  _rewardtoNativeFeed=0xcB23da9EA243f53194CBc2380A6d4d9bC046161f;
    address  _assettoNativeFeed=0xD5c40f5144848Bd4EF08a9605d860e727b991513;

    address[] _rewardToLp0AddressPath = [_cakeReward, _usdt];
    uint24[] _rewardToLp0FeePath = [2500];
    address[] _rewardToLp1AddressPath = [_cakeReward, _wbnb];
    uint24[] _rewardToLp1FeePath = [2500];

    ///@dev Vault Params
    ///@notice Can be configured according to preference
    string rivTokenName = "Riv CakeV2 WBNB-USDT";
    string rivTokenSymbol = "rivCakeV2WBNB-USDT";
    uint256 stratUpdateDelay = 21600;
    uint256 vaultTvlCap = 10000e18;

    ///@dev Users Setup
    address _manager = 0xA638177B9c3D96A30B75E6F9e35Baedf3f1954d2;
    address _user1;
    address _user2 = 0x2fa6a4D2061AD9FED3E0a1A7046dcc9692dA6Da8;
    address _whale = 0xD183F2BBF8b28d9fec8367cb06FE72B88778C86B;        //35 Mil whale 35e24
    uint256 _maxUserBal = 15e24;
    uint256 _user1PrivateKey;

    uint256 PERCENT_POOL_TVL_OF_CAPITAL = 5;
    uint256 minCapital = 1e18;      //One dollar of denomination asset

    uint256 withdrawFeeDecimals = 10000;
    uint256 withdrawFee = 10;

    uint256 feeDecimals = 1000;
    uint256 protocolFee = 15;
    uint256 fundManagerFee = 15;
    uint256 partnerFee = 15;
    address partner = 0xA638177B9c3D96A30B75E6F9e35Baedf3f1954d2;

    bytes32 public PERMIT_TYPEHASH = keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            );

    function setUp() public {
        
        string memory seedPhrase = vm.readFile(".secret");
        _user1PrivateKey = vm.deriveKey(seedPhrase, 0);
        _user1=vm.addr(_user1PrivateKey);

        ///@dev all deployments will be made by the user
        vm.startPrank(_manager);

        ///@dev Initializing the vault with invalid strategy
        vault = new RiveraAutoCompoundingVaultV2Public(_usdt, rivTokenName, rivTokenSymbol, stratUpdateDelay, vaultTvlCap);

        ///@dev Initializing the strategy
        CommonAddresses memory _commonAddresses = CommonAddresses(address(vault), _router, _nonFungiblePositionManager, withdrawFeeDecimals, 
        withdrawFee, feeDecimals, protocolFee, fundManagerFee, partnerFee, partner,_manager,_manager);
        RiveraLpStakingParams memory riveraLpStakingParams = RiveraLpStakingParams(
            _tickLower,
            _tickUpper,
            _stake,
            _chef,
            _cakeReward,
            _tickMathLib,
            _sqrtPriceMathLib,
            _liquidityMathLib,
            _safeCastLib,
            _liquidityAmountsLib,
            _fullMathLib,
            _rewardToLp0AddressPath,
            _rewardToLp0FeePath,
            _rewardToLp1AddressPath,
            _rewardToLp1FeePath,
            _rewardtoNativeFeed,
            _assettoNativeFeed,
            "pendingCake"
            );
        strategy = new RiveraConcLpStaking();
        strategy.init(riveraLpStakingParams, _commonAddresses);
        vault.init(IStrategy(address(strategy)));
        weth = IWETH9(address(new WETH()));
        erc4626Router = new ERC4626Router("", weth);
        //INstantiating ERC4626 router contraCT
        // erc4626Router=new ERC4626Router()

        vm.stopPrank();

        ///@dev Transfering LP tokens from a whale to my accounts
        vm.startPrank(_whale);
        IERC20(_usdt).transfer(_user1, _maxUserBal);
        IERC20(_usdt).transfer(_user2, _maxUserBal);
        vm.stopPrank();
    }


    function test_DepositWithRouter() public {
        vm.startPrank(_user1);
        assertEq(strategy.tokenID(), 0);
        uint depositAmount=IERC20(_usdt).balanceOf(_user1)/10000;
        console.log("deposit amount",depositAmount);
        IERC20(_usdt).approve(address(erc4626Router), depositAmount);
        erc4626Router.approve(ERC20(_usdt), address(vault), depositAmount);
        erc4626Router.depositToVault(IERC4626(address(vault)), _user1, depositAmount, depositAmount);
        console.log("vault token balance user1",vault.balanceOf(_user1));
        vm.stopPrank();
        vm.startPrank(_user2);
        IERC20(_usdt).approve(address(erc4626Router), depositAmount);
        erc4626Router.approve(ERC20(_usdt), address(vault), depositAmount);
        erc4626Router.depositToVault(IERC4626(address(vault)), _user2, depositAmount, depositAmount);
        console.log("vault token balance user2",vault.balanceOf(_user2));
        console.log("deposit balance user2",vault.convertToAssets(vault.balanceOf(_user2)));
        console.log("deposit balance user1",vault.convertToAssets(vault.balanceOf(_user1)));
    }

    function test_DepositWithMulticallRouter() public {
        vm.startPrank(_user1);
        uint depositAmount=IERC20(_usdt).balanceOf(_user1)/10000;
        // IERC20(_usdt).approve(address(erc4626Router), depositAmount);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _user1PrivateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _computeDomainSeparator(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, _user1, address(erc4626Router), depositAmount, 0, block.timestamp))
                )
            )
        );

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(SelfPermit.selfPermit.selector, IERC20(_usdt), depositAmount, block.timestamp, v, r, s);
        data[1] = abi.encodeWithSelector(PeripheryPayments.approve.selector, IERC20(_usdt), address(vault), depositAmount);
        data[2] = abi.encodeWithSelector(IERC4626Router.depositToVault.selector, vault, _user1, depositAmount, depositAmount);

        erc4626Router.multicall(data);
    }

    function test_GetDepositToken() public {
        address depositTokenAddress = strategy.depositToken();
        assertEq(depositTokenAddress, _usdt);
    }

    //@notice tests for deposit function

    function test_DepositWhenNotPausedAndCalledByVaultForFirstTime(uint256 depositAmount) public {
        uint256 poolTvl = IERC20(_usdt).balanceOf(_stake) + DexV3Calculations.convertAmount0ToAmount1(IERC20(_wbnb).balanceOf(_stake), _stake, _fullMathLib);
        emit log_named_uint("Total Pool TVL", poolTvl);
        vm.assume(depositAmount < PERCENT_POOL_TVL_OF_CAPITAL * poolTvl / 100 && depositAmount > minCapital);
        vm.prank(_user1);
        IERC20(_usdt).transfer(address(strategy), depositAmount);
        emit log_named_uint("strategy token id", strategy.tokenID());
        assertEq(strategy.tokenID(), 0);
        vm.prank(address(vault));
        strategy.deposit();
        assertTrue(strategy.tokenID()!=0);

        (uint128 liquidity, , int24 tickLower, int24 tickUpper, , , address user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
        assertTrue(liquidity!=0);
        assertEq(strategy.tickLower(), tickLower);
        assertEq(strategy.tickUpper(), tickUpper);
        emit log_named_address("user from position", user);
        assertEq(address(strategy), user);

        uint256 point5PercentOfDeposit = 3 * depositAmount / 1000;
        uint256 usdtBal = IERC20(_usdt).balanceOf(address(vault));
        emit log_named_uint("After vault USDT balance", usdtBal);
        assertLt(usdtBal, point5PercentOfDeposit);

        emit log_named_uint("After strat USDT balance", IERC20(_usdt).balanceOf(address(strategy)));
        assertEq(IERC20(_usdt).balanceOf(address(strategy)), 0);

        // uint256 point5PercentOfDepositInBnb = DexV3Calculations.convertAmount0ToAmount1(1 * depositAmount / 1000, _stake, _fullMathLib);
        uint256 wbnbBal = IERC20(_wbnb).balanceOf(address(strategy));
        emit log_named_uint("After strat WBNB balance", wbnbBal);
        assertEq(wbnbBal, 0);

        uint256 stratStakeBalanceAfter = strategy.balanceOf();
        emit log_named_uint("Total assets of strat", stratStakeBalanceAfter);
        assertApproxEqRel(stratStakeBalanceAfter, depositAmount, 1e15);     //Checks if the percentage difference between them is less than 0.5
    }

    function test_DepositWhenPaused() public {
        vm.prank(_manager);
        strategy.pause();
        vm.prank(address(vault));
        vm.expectRevert("Pausable: paused");
        strategy.deposit();
    }

    function test_DepositWhenNotVault() public {
        vm.expectRevert("!vault");
        strategy.deposit();
    }

    function _depositDenominationAsset(uint256 depositAmount) internal {        //Function to call in other tests that brings the vault to an already deposited state
        uint256 poolTvl = IERC20(_usdt).balanceOf(_stake) + DexV3Calculations.convertAmount0ToAmount1(IERC20(_wbnb).balanceOf(_stake), _stake, _fullMathLib);
        vm.assume(depositAmount < PERCENT_POOL_TVL_OF_CAPITAL * poolTvl / 100 && depositAmount > minCapital);
        vm.prank(_user1);
        IERC20(_usdt).transfer(address(strategy), depositAmount);
        vm.prank(address(vault));
        strategy.deposit();
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("Tether USD")),
                    keccak256("0"),
                    block.chainid,
                    _usdt
                )
            );
    }

    function _performSwapInBothDirections(uint256 swapAmount) internal {
        uint256 poolTvl = IERC20(_usdt).balanceOf(_stake) + DexV3Calculations.convertAmount0ToAmount1(IERC20(_wbnb).balanceOf(_stake), _stake, _fullMathLib);
        vm.assume(swapAmount < PERCENT_POOL_TVL_OF_CAPITAL * poolTvl / 100 && swapAmount > minCapital);
        vm.startPrank(_user2);
        IERC20(_usdt).approve(_router, type(uint256).max);
        IERC20(_wbnb).approve(_router, type(uint256).max);
        uint256 _wbnbReceived = IV3SwapRouter(_router).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams(
                _usdt,
                _wbnb,
                strategy.poolFee(),
                _user2,
                swapAmount,
                0,
                0
            )
        );

        IV3SwapRouter(_router).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams(
                _wbnb,
                _usdt,
                strategy.poolFee(),
                _user2,
                _wbnbReceived,
                0,
                0
            )
        );
        vm.stopPrank();
    }

    

}

/*
anvil -f https://bsc-mainnet.nodereal.io/v1/563771091a104763859e6c6737707005

forge test --match-path test/strategies/staking/RiveraConcLpStakingRouter.t.sol --fork-url http://127.0.0.1:8545/ -vvv

forge test --match-path test/strategies/staking/RiveraConcLpStakingRouter.t.sol --fork-url http://127.0.0.1:8545/ -vvv
*/