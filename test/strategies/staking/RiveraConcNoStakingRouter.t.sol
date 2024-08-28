pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../src/strategies/staking/RiveraConcNoStaking.sol";
import "../../../src/strategies/common/interfaces/IStrategy.sol";
import "../../../src/vaults/RiveraAutoCompoundingVaultV2Public.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

import "@rivera/strategies/staking/interfaces/INonfungiblePositionManager.sol";
import "@pancakeswap-v3-core/interfaces/IPancakeV3Pool.sol";
import "@pancakeswap-v3-core/interfaces/IPancakeV3Factory.sol";
import "@rivera/strategies/staking/interfaces/libraries/ITickMathLib.sol";
import "@openzeppelin/utils/math/Math.sol";

import "@rivera/libs/DexV3Calculations.sol";
import "@rivera/libs/DexV3CalculationStruct.sol";
import "@rivera/router/ERC4626Router.sol";
import {WETH} from "solmate/tokens/WETH.sol";

///@dev
///The pool used in this testing is fusionx's USDT / WETH 0.05%  https://fusionx.finance/info/v3/pairs/0xa125af1a4704044501fe12ca9567ef1550e430e8?chain=mantle

contract RiveraConcNoStakingTest is Test {
    RiveraConcNoStaking strategy;
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
    address _stake = 0xA125AF1A4704044501Fe12Ca9567eF1550E430e8;  //Mainnet address of the Mantle UST/MNT
    address _chef = address(0);   //Address of
    // address _chef = 0x556B9306565093C855AEA9AE92A594704c2Cd59e;   //
    address _factory = 0x530d2766D1988CC1c000C8b7d00334c14B69AD71;
    address _router = 0x4bf659cA398A73AaF73818F0c64c838B9e229c08; //Address of Pancake Swap router
    address _nonFungiblePositionManager = 0x5752F085206AB87d8a5EF6166779658ADD455774;
    address _lp1Token = 0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111; //weth
    address _lp0Token = 0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE; //usdt    
    // address depositToken=_lp0Token;

    //cakepool params
    bool _isTokenZeroDeposit = true;
    int24 currentTick =197404;     //Taken from explorer
    int24 tickSpacing = 10;
    int24 _tickLower = ((currentTick - 6932) / tickSpacing) * tickSpacing;      //Tick for price that is half of current price
    int24 _tickUpper = ((currentTick + 6932) / tickSpacing) * tickSpacing;      //Tick for price that is double of current price
    address _rewardToken = address(0);
    //libraries
    address _tickMathLib = 0x74C5E75798b33D38abeE64f7EC63698B7e0a10f1;
    address _sqrtPriceMathLib = 0xA38Bf51645D77bd0ec5072Ae5eCA7c0e67CFc081;
    address _liquidityMathLib = 0xe6d2bD39aEFCDCFC989B03AE45A5aBEfe9BF1F51;
    address _safeCastLib = 0x55FD5B67B115767036f9e8af569B281A8A544a12;
    address _liquidityAmountsLib = 0xE344B76f1Dec90E8a2e68fa7c1cfEBB329aFB332;
    address _fullMathLib = 0xAa5Fd782B03Bfb2f25F13B6ae4e254F5149B9575;
    address  _rewardtoNativeFeed=address(0);
    address  _assettoNativeFeed=address(0);

    address[] _rewardToLp0AddressPath = [_rewardToken, _lp0Token];
    uint24[] _rewardToLp0FeePath = [2500];
    address[] _rewardToLp1AddressPath = [_rewardToken, _lp1Token];
    uint24[] _rewardToLp1FeePath = [2500];

    ///@dev Vault Params
    ///@notice Can be configured according to preference
    string rivTokenName = "Rivlp1Token-lp0Token";
    string rivTokenSymbol = "rivV2lp1Token-lp0Token";
    uint256 stratUpdateDelay = 21600;
    uint256 vaultTvlCap = 1000e6;

    ///@dev Users Setup
    address _manager = 0xA638177B9c3D96A30B75E6F9e35Baedf3f1954d2;
    address _user1 ;
    address _user2 = 0x2fa6a4D2061AD9FED3E0a1A7046dcc9692dA6Da8;
    uint256 _user1PrivateKey;
    address _whale = 0xf89d7b9c864f589bbF53a82105107622B35EaA40;        //35 Mil whale 35e24
    uint256 _maxUserBal = IERC20(_lp0Token).balanceOf(_whale)/4;

    uint256 PERCENT_POOL_TVL_OF_CAPITAL = 5;
    uint256 minCapital = 1e6;      //One dollar of denomination asset

    uint256 withdrawFeeDecimals = 100;
    uint256 withdrawFee = 1;

    uint256 feeDecimals = 100;
    uint256 protocolFee = 15;
    uint256 fundManagerFee = 0;
    uint256 partnerFee = 0;
    address partner = 0x961Ef0b358048D6E34BDD1acE00D72b37B9123D7;
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
        vault = new RiveraAutoCompoundingVaultV2Public(_lp0Token, rivTokenName, rivTokenSymbol, stratUpdateDelay, vaultTvlCap);

        ///@dev Initializing the strategy
        CommonAddresses memory _commonAddresses = CommonAddresses(address(vault), _router, _nonFungiblePositionManager, withdrawFeeDecimals, 
        withdrawFee, feeDecimals, protocolFee, fundManagerFee, partnerFee, partner,_manager,_manager);
        RiveraLpStakingParams memory riveraLpStakingParams = RiveraLpStakingParams(
            _tickLower,
            _tickUpper,
            _stake,
            // _chef,
            // _rewardToken,
            _tickMathLib,
            _sqrtPriceMathLib,
            _liquidityMathLib,
            _safeCastLib,
            _liquidityAmountsLib,
            _fullMathLib,
            // _rewardToLp0AddressPath,
            // _rewardToLp0FeePath,
            // _rewardToLp1AddressPath,
            // _rewardToLp1FeePath,
            // _rewardtoNativeFeed,
            _assettoNativeFeed
            // "pendingCake"
            );
        strategy = new RiveraConcNoStaking();
        strategy.init(riveraLpStakingParams, _commonAddresses);
        vault.init(IStrategy(address(strategy)));
        weth = IWETH9(address(new WETH()));
        erc4626Router = new ERC4626Router("", weth);
        vm.stopPrank();
        

        ///@dev Transfering LP tokens from a whale to my accounts
        vm.startPrank(_whale);
        IERC20(_lp0Token).transfer(_user1, _maxUserBal);
        IERC20(_lp0Token).transfer(_user2, _maxUserBal);
        vm.stopPrank();
        // emit log_named_uint("lp0Token balance of user1", IERC20(_lp0Token).balanceOf(_user1));
    }

    function test_DepositWithRouter() public {
        vm.startPrank(_user1);
        assertEq(strategy.tokenID(), 0);
        uint depositAmount=IERC20(_lp0Token).balanceOf(_user1)/10000;
        console.log("deposit amount",depositAmount);
        IERC20(_lp0Token).approve(address(erc4626Router), depositAmount);
        erc4626Router.approve(ERC20(_lp0Token), address(vault), depositAmount);
        erc4626Router.depositToVault(IERC4626(address(vault)), _user1, depositAmount, depositAmount);
        console.log("vault token balance user1",vault.balanceOf(_user1));
        vm.stopPrank();
        vm.startPrank(_user2);
        IERC20(_lp0Token).approve(address(erc4626Router), depositAmount);
        erc4626Router.approve(ERC20(_lp0Token), address(vault), depositAmount);
        erc4626Router.depositToVault(IERC4626(address(vault)), _user2, depositAmount, depositAmount);
        console.log("vault token balance user2",vault.balanceOf(_user2));
        console.log("deposit balance user2",vault.convertToAssets(vault.balanceOf(_user2)));
        console.log("deposit balance user1",vault.convertToAssets(vault.balanceOf(_user1)));
    }

    function test_DepositSlippage() public {
        vm.startPrank(_user1);
        assertEq(strategy.tokenID(), 0);
        uint depositAmount=IERC20(_lp0Token).balanceOf(_user1)/1000;
        console.log("deposit amount",depositAmount);
        // get previewDeposit from vault
        uint previewDeposit=vault.previewDeposit(depositAmount);
        console.log("previewDeposit",previewDeposit); 
        IERC20(_lp0Token).approve(address(erc4626Router), depositAmount);
        erc4626Router.approve(ERC20(_lp0Token), address(vault), depositAmount);
        erc4626Router.depositToVault(IERC4626(address(vault)), _user1, depositAmount, depositAmount);
        console.log("vault token balance user1",vault.balanceOf(_user1));
        vm.stopPrank();

        vm.startPrank(_user2);
        IERC20(_lp0Token).approve(address(erc4626Router), depositAmount);
        erc4626Router.approve(ERC20(_lp0Token), address(vault), depositAmount);
        previewDeposit=vault.previewDeposit(depositAmount);
        console.log("previewDeposit",previewDeposit); 
        erc4626Router.depositToVault(IERC4626(address(vault)), _user2, depositAmount, depositAmount);
        console.log("vault token balance user2",vault.balanceOf(_user2));
        console.log("deposit balance user2",vault.convertToAssets(vault.balanceOf(_user2)));
        console.log("deposit balance user1",vault.convertToAssets(vault.balanceOf(_user1)));


        previewDeposit=vault.previewDeposit(depositAmount);
        console.log("previewDeposit",previewDeposit); 

    }

    function test_DepositWithMulticallRouter() public {
        vm.startPrank(_user1);
        uint depositAmount=IERC20(_lp0Token).balanceOf(_user1)/10000;
        IERC20(_lp0Token).approve(address(erc4626Router), depositAmount);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(PeripheryPayments.approve.selector, IERC20(_lp0Token), address(vault), depositAmount);
        data[1] = abi.encodeWithSelector(IERC4626Router.depositToVault.selector, vault, _user1, depositAmount, depositAmount);
        console.log("vault token balance user1 before",vault.balanceOf(_user1));
        erc4626Router.multicall(data);
        console.log("vault token balance user1 after",vault.balanceOf(_user1));

        vm.stopPrank();
    }

    function test_GetDepositToken() public {
        address depositTokenAddress = strategy.depositToken();
        assertEq(depositTokenAddress, _lp0Token);
    }

    ///@notice tests for deposit function

    function test_DepositWhenNotPausedAndCalledByVaultForFirstTime(uint256 depositAmount) public {
        uint256 poolTvl = IERC20(_lp0Token).balanceOf(_stake) + DexV3Calculations.convertAmount0ToAmount1(IERC20(_lp1Token).balanceOf(_stake), _stake, _fullMathLib);
        emit log_named_uint("Total Pool TVL", poolTvl);
        vm.assume(depositAmount < PERCENT_POOL_TVL_OF_CAPITAL * poolTvl / 100 && depositAmount > minCapital);
        depositAmount=2e6;
        vm.prank(_user1);
        IERC20(_lp0Token).transfer(address(strategy), depositAmount);
        emit log_named_uint("strategy token id", strategy.tokenID());
        assertEq(strategy.tokenID(), 0);
        vm.prank(address(vault));
        strategy.deposit();
        assertTrue(strategy.tokenID()!=0);
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
        address user;
        if(_chef!=address(0)){
            ( liquidity, ,  tickLower,  tickUpper, , ,  user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
        }else{
            (, , ,, ,  tickLower,  tickUpper,  liquidity,,, ,  ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(strategy.tokenID());
            user= INonfungiblePositionManager(_nonFungiblePositionManager).ownerOf(strategy.tokenID());
        }
        assertTrue(liquidity!=0);
        assertEq(strategy.tickLower(), tickLower);
        assertEq(strategy.tickUpper(), tickUpper);
        emit log_named_address("user from position", user);
        assertEq(address(strategy), user);

        uint256 point5PercentOfDeposit = 3 * depositAmount / 1000;
        uint256 lp0TokenBal = IERC20(_lp0Token).balanceOf(address(vault));
        emit log_named_uint("After vault lp0Token balance", lp0TokenBal);
        assertLt(lp0TokenBal, point5PercentOfDeposit);

        emit log_named_uint("After strat lp0Token balance", IERC20(_lp0Token).balanceOf(address(strategy)));
        assertEq(IERC20(_lp0Token).balanceOf(address(strategy)), 0);

        // uint256 point5PercentOfDepositInBnb = DexV3Calculations.convertAmount0ToAmount1(1 * depositAmount / 1000, _stake, _fullMathLib);
        uint256 lp1TokenBal = IERC20(_lp1Token).balanceOf(address(strategy));
        emit log_named_uint("After strat lp1Token balance", lp1TokenBal);
        assertEq(lp1TokenBal, 0);

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
        uint256 poolTvl = IERC20(_lp0Token).balanceOf(_stake) + DexV3Calculations.convertAmount0ToAmount1(IERC20(_lp1Token).balanceOf(_stake), _stake, _fullMathLib);
        vm.assume(depositAmount < PERCENT_POOL_TVL_OF_CAPITAL * poolTvl / 100 && depositAmount > minCapital);
        vm.prank(_user1);
        IERC20(_lp0Token).transfer(address(strategy), depositAmount);
        vm.prank(address(vault));
        strategy.deposit();
    }

    function _performSwapInBothDirections(uint256 swapAmount) internal {
        uint256 poolTvl = IERC20(_lp0Token).balanceOf(_stake) + DexV3Calculations.convertAmount0ToAmount1(IERC20(_lp1Token).balanceOf(_stake), _stake, _fullMathLib);
        vm.assume(swapAmount < PERCENT_POOL_TVL_OF_CAPITAL * poolTvl / 100 && swapAmount > minCapital);
        vm.startPrank(_user2);
        IERC20(_lp0Token).approve(_router, type(uint256).max);
        IERC20(_lp1Token).approve(_router, type(uint256).max);
        uint256 _lp1TokenReceived = IV3SwapRouter(_router).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams(
                _lp0Token,
                _lp1Token,
                strategy.poolFee(),
                _user2,
                swapAmount,
                0,
                0
            )
        );

        IV3SwapRouter(_router).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams(
                _lp1Token,
                _lp0Token,
                strategy.poolFee(),
                _user2,
                _lp1TokenReceived,
                0,
                0
            )
        );
        vm.stopPrank();
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("Tether USD")),
                    keccak256("0"),
                    block.chainid,
                    _lp0Token
                )
            );
    }


}

/*

forge test --match-path test/strategies/staking/RiveraConcNoStaking.t.sol --fork-url http://127.0.0.1:8545/ -vvv

*/