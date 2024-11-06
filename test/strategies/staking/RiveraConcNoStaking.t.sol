pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../src/strategies/staking/RiveraConcNoStaking.sol";
import "../../../src/strategies/staking/Test/RiveraConcNoStakingTestHelper.sol";
import "../../../src/strategies/common/interfaces/IStrategy.sol";
import "../../../src/vaults/RiveraAutoCompoundingVaultV2Public.sol";
import "./interfaces/IAggregatorV3Interface.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

import "@rivera/strategies/staking/interfaces/INonfungiblePositionManager.sol";
import "@pancakeswap-v3-core/interfaces/IPancakeV3Pool.sol";
import "@pancakeswap-v3-core/interfaces/IPancakeV3Factory.sol";
import "@rivera/strategies/staking/interfaces/libraries/ITickMathLib.sol";
import "@openzeppelin/utils/math/Math.sol";

import "@rivera/libs/DexV3Calculations.sol";
import "@rivera/libs/DexV3CalculationStruct.sol";


///@dev
///The pool used in this testing is fusionx's USDT / WETH 0.05%  https://fusionx.finance/info/v3/pairs/0xa125af1a4704044501fe12ca9567ef1550e430e8?chain=mantle


contract RiveraConcNoStakingTest is Test {
    RiveraConcNoStaking strategy;
    RiveraConcNoStakingTestHelper testStrategy;

    RiveraAutoCompoundingVaultV2Public vault;
    RiveraAutoCompoundingVaultV2Public testVault;

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

    //cakepool params
    bool _isTokenZeroDeposit = true;
    int24 currentTick =197968;     //Taken from explorer
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
    uint256 vaultTvlCap = 1000000e6;

    ///@dev Users Setup
    address _manager = 0xA638177B9c3D96A30B75E6F9e35Baedf3f1954d2;
    address _user1 = 0x0A0e42Cb6FA85e78848aC241fACd8fCCbAc4962A;
    address _user2 = 0x2fa6a4D2061AD9FED3E0a1A7046dcc9692dA6Da8;
    address _whale = 0x28190bC18bbdc3D340C9A8C80265096E3A7f7EdA;        //35 Mil whale 35e24
    uint256 _maxUserBal = IERC20(_lp0Token).balanceOf(_whale)/4;
    address _whalelp1Token=0x588846213A30fd36244e0ae0eBB2374516dA836C;
    uint256 _maxUserBallp1 = IERC20(_lp1Token).balanceOf(_whalelp1Token)/4;
    uint256 PERCENT_POOL_TVL_OF_CAPITAL = 5;
    uint256 minCapital = 1e6;      //One dollar of denomination asset

    uint256 withdrawFeeDecimals = 100;
    uint256 withdrawFee = 1;

    uint256 feeDecimals = 100;
    uint256 protocolFee = 15;
    uint256 fundManagerFee = 0;
    uint256 partnerFee = 0;
    address partner = 0x961Ef0b358048D6E34BDD1acE00D72b37B9123D7;

    function setUp() public {

        ///@dev all deployments will be made by the user
        vm.startPrank(_manager);

        ///@dev Initializing the vault with invalid strategy
        vault = new RiveraAutoCompoundingVaultV2Public(_lp0Token, rivTokenName, rivTokenSymbol, stratUpdateDelay, vaultTvlCap);
        testVault = new RiveraAutoCompoundingVaultV2Public(_lp0Token, rivTokenName, rivTokenSymbol, stratUpdateDelay, vaultTvlCap);

        ///@dev Initializing the strategy
        CommonAddresses memory _commonAddresses = CommonAddresses(address(vault), _router, _nonFungiblePositionManager, withdrawFeeDecimals, 
        withdrawFee,50,10000,_manager,_manager);
        CommonAddresses memory _commonAddressesTest = CommonAddresses(address(testVault), _router, _nonFungiblePositionManager, withdrawFeeDecimals, 
        withdrawFee,50,10000,_manager,_manager);

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
        testStrategy = new RiveraConcNoStakingTestHelper();
        strategy.init(riveraLpStakingParams, _commonAddresses);
        testStrategy.init(riveraLpStakingParams, _commonAddressesTest);
        vault.init(IStrategy(address(strategy)));
        testVault.init(IStrategy(address(testStrategy)));
        vm.stopPrank();

        ///@dev Transfering LP tokens from a whale to my accounts
        vm.startPrank(_whale);
        IERC20(_lp0Token).transfer(_user1, _maxUserBal);
        IERC20(_lp0Token).transfer(_user2, _maxUserBal);
        vm.stopPrank();

        ///@dev Transfering LP tokens from a whale to my accounts
        vm.startPrank(_whalelp1Token);
        IERC20(_lp1Token).transfer(_user1, _maxUserBallp1);
        IERC20(_lp1Token).transfer(_user2, _maxUserBallp1);
        vm.stopPrank();
        // emit log_named_uint("lp0Token balance of user1", IERC20(_lp0Token).balanceOf(_user1));
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

    // function test_BurnAndCollectV3(uint256 depositAmount, uint256 swapAmount) public {
    //     depositAmount=10e6;
    //     swapAmount=5e6;
    //     _depositDenominationAsset(depositAmount);
    //     vm.warp(block.timestamp + 7*24*60*60);
    //     _performSwapInBothDirections(swapAmount);

    //     // (uint128 liquidity, , int24 tickLower, int24 tickUpper, , , address user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
    //     uint128 liquidity;
    //     int24 tickLower;
    //     int24 tickUpper;
    //     address user;
    //     if(_chef!=address(0)){
    //         ( liquidity, ,  tickLower,  tickUpper, , ,  user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
    //     }else{
    //         (, , ,, ,  tickLower,  tickUpper,  liquidity,,, ,  ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(strategy.tokenID());
    //         user= INonfungiblePositionManager(_nonFungiblePositionManager).ownerOf(strategy.tokenID());
    //     }
    //     assertTrue(liquidity!=0);
    //     assertEq(strategy.tickLower(), tickLower);
    //     assertEq(strategy.tickUpper(), tickUpper);
    //     assertEq(address(strategy), user);

    //     uint256 tokenId = strategy.tokenID();
    //     ( , , , , , tickLower, tickUpper, liquidity, , , , ) = INonfungiblePositionManager(strategy.NonfungiblePositionManager()).positions(tokenId);
    //     assertTrue(liquidity!=0);
    //     assertEq(strategy.tickLower(), tickLower);
    //     assertEq(strategy.tickUpper(), tickUpper);

    //     // if(_chef!=address(0)){
    //     //     assertTrue(strategy.rewardsAvailable()!=0);
    //     // }

    //     // ( , , , , , , , , uint256 feeGrowthInsideLast0, uint256 feeGrowthInsideLast1,
    //     //     uint128 tokensOwed0,
    //     //     uint128 tokensOwed1
    //     // ) = INonfungiblePositionManager(strategy.NonfungiblePositionManager()).positions(tokenId);
    //     // emit log_named_uint("Token 0 fee", tokensOwed0);
    //     // emit log_named_uint("Token 1 fee", tokensOwed1);
    //     // emit log_named_uint("Token 0 fee growth inside", feeGrowthInsideLast0);
    //     // emit log_named_uint("Token 1 fee growth inside", feeGrowthInsideLast1);
    //     // assertTrue(tokensOwed0!=0);     //These two are coming as zero because the tokensOwed in NonFungiblePositionManager is not checkpointed
    //     // assertTrue(tokensOwed1!=0);
    //     uint256 token0BalBef = IERC20(_lp0Token).balanceOf(address(strategy));
    //     uint256 token1BalBef = IERC20(_lp1Token).balanceOf(address(strategy));

    //     if(_chef!=address(0)){
    //         assertEq(INonfungiblePositionManager(_nonFungiblePositionManager).ownerOf(tokenId), _chef);
    //     }

    //     strategy._burnAndCollectV3(true);
    //     if(_chef!=address(0)){
    //     (liquidity, , tickLower, tickUpper, , , user, , ) = IMasterChefV3(_chef).userPositionInfos(tokenId);
    //         assertEq(0, liquidity);
    //         assertEq(0, tickLower);
    //         assertEq(0, tickUpper);
    //         assertEq(address(0), user);
    //     }

    //     vm.expectRevert("Invalid token ID");
    //     ( , , , , , tickLower, tickUpper, liquidity, , , , ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(tokenId);

    //     // assertEq(0, strategy.rewardsAvailable());
    //     //  if(_chef!=address(0)){
    //     //     assertTrue(strategy.rewardsAvailable()!=0);
    //     // }

    //     assertGt(IERC20(_lp0Token).balanceOf(address(strategy)), token0BalBef);
    //     assertGt(IERC20(_lp1Token).balanceOf(address(strategy)), token1BalBef);     //Verifies that fees has been collected as that is the only way token0 and token balance could increase

    //     vm.expectRevert("ERC721: owner query for nonexistent token");
    //     INonfungiblePositionManager(_nonFungiblePositionManager).ownerOf(tokenId);
    // }

    function test_ConvertAmount0ToAmount1(uint256 amount) public {
        vm.assume(amount < _maxUserBal);
        uint256 convertedAmount = DexV3Calculations.convertAmount0ToAmount1(amount, _stake, _fullMathLib);
        IPancakeV3Pool pool = IPancakeV3Pool(_stake);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 calculatedAmount = IFullMathLib(_fullMathLib).mulDiv(IFullMathLib(_fullMathLib).mulDiv(amount, sqrtPriceX96, FixedPoint96.Q96), sqrtPriceX96, FixedPoint96.Q96);
        assertEq(convertedAmount, calculatedAmount);
    }

    function test_ConvertAmount1ToAmount0(uint256 amount) public {
        vm.assume(Math.log2(amount) < 248);         //There is overflow in either amount0 or amount1 based on whether sqrtPriceX96 is greater than or less than 2^6. It will overflow at a particular power of two based on the difference in 2^96 and sqrtPriceX96
        uint256 convertedAmount = DexV3Calculations.convertAmount1ToAmount0(amount, _stake, _fullMathLib);
        emit log_named_uint("input amount", amount);
        emit log_named_uint("converted amount", convertedAmount);
        IPancakeV3Pool pool = IPancakeV3Pool(_stake);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        emit log_named_uint("sqrtPriceX96", sqrtPriceX96);
        uint256 intermediate = Math.mulDiv(amount, FixedPoint96.Q96, sqrtPriceX96);
        emit log_named_uint("intermediate amount", intermediate);
        uint256 calculatedAmount = Math.mulDiv(intermediate, FixedPoint96.Q96, uint256(sqrtPriceX96));
        assertEq(convertedAmount, calculatedAmount);
    }

    ///@notice tests for withdraw function

    function test_WithdrawWhenCalledByVault(uint256 depositAmount) public {
        depositAmount=10e6;
        _depositDenominationAsset(depositAmount);
        uint256 withdrawAmount = 996 * depositAmount / 1000;

        uint256 vaultDenominaionbal = IERC20(_lp0Token).balanceOf(address(vault));
        uint256 point5PercentOfDeposit = 3 * depositAmount / 1000;
        emit log_named_uint("Vault lp0Token balance", vaultDenominaionbal);
        assertLt(vaultDenominaionbal, point5PercentOfDeposit);

        uint256 liquidityBalBefore = strategy.liquidityBalance();

        vm.prank(address(vault));
        strategy.withdraw(withdrawAmount);

        vaultDenominaionbal = IERC20(_lp0Token).balanceOf(address(vault));
        assertApproxEqRel(vaultDenominaionbal, withdrawAmount, 25e15);

        uint256 liquidityBalAfter = strategy.liquidityBalance();
        uint256 liqDelta = DexV3Calculations.calculateLiquidityDeltaForAssetAmount(LiquidityToAmountCalcParams(_tickLower, _tickUpper, 1e28, _safeCastLib, _sqrtPriceMathLib, _tickMathLib, _stake), 
        LiquidityDeltaForAssetAmountParams(_isTokenZeroDeposit, strategy.poolFee(), withdrawAmount, _fullMathLib, _liquidityAmountsLib));
        assertApproxEqRel(liquidityBalBefore - liquidityBalAfter, liqDelta, 25e15);

        uint256 lp1TokenBal = IERC20(_lp1Token).balanceOf(address(strategy));
        emit log_named_uint("After strat lp1Token balance", lp1TokenBal);
        assertEq(lp1TokenBal, 0);
        address dToken=strategy.depositToken();

        uint256 lp0TokenBal = IERC20(_lp0Token).balanceOf(address(strategy));
        // emit log_named_uint("After strat lp0Token balance", lp0TokenBal);
        // assertEq(IERC20(dToken).balanceOf(_manager), withdrawAmount * withdrawFee / withdrawFeeDecimals);

    }

 

    function test_WithdrawWhenNotCalledByVault(uint256 depositAmount, address randomAddress) public {
        depositAmount=10e6;
        randomAddress=0xA93681479E5Cc9fD605516fba5C39E73aAA3bfeb;
        // vm.assume(_isEoa(randomAddress) && randomAddress!=address(vault));
        _depositDenominationAsset(depositAmount);
        uint256 withdrawAmount = depositAmount - strategy.poolFee() * depositAmount / 1e6;

        vm.expectRevert("!vault");
        vm.prank(randomAddress);
        strategy.withdraw(withdrawAmount);

    }

    function _isEoa(address account) internal view returns (bool) {
        return account.code.length == 0;
    }

    // function test_ChangeRangeWhenNotCalledByOwner(int24 tickLower, int24 tickUpper, address randomAddress, uint256 depositAmount) public {
    //     vm.assume(_isEoa(randomAddress) && randomAddress!=_manager);
    //     _depositDenominationAsset(depositAmount);

    //     vm.expectRevert("Ownable: caller is not the owner");
    //     vm.startPrank(randomAddress);
    //     strategy.changeRange(tickLower, tickUpper);
    // }

    function test_ChangeRangeWithSameTicks(uint256 depositAmount) public {
        depositAmount=10e6;
        _depositDenominationAsset(depositAmount);
        vm.expectRevert();
        vm.startPrank(_manager);
        strategy.changeRange(_tickLower, _tickLower);
    }

    // function test_ChangeRangeWithLowerTickNotLessThanUpperTick(int24 tickLower, int24 tickUpper, uint256 depositAmount) public {
    //     vm.assume(!(tickLower < tickUpper));
    //     _depositDenominationAsset(depositAmount);

    //     vm.expectRevert("Tick order incorrect");
    //     vm.startPrank(_manager);
    //     strategy.changeRange(tickLower, tickUpper);
    // }

    // function test_ChangeRangeWithLowerTickNotGreaterThanMinTick(int24 tickLower, int24 tickUpper, uint256 depositAmount) public {
    //     vm.assume(tickLower!=_tickLower && tickUpper!=_tickUpper);
    //     vm.assume(tickLower < tickUpper);
    //     vm.assume(!(tickLower >= ITickMathLib(_tickMathLib).MIN_TICK()));
    //     _depositDenominationAsset(depositAmount);

    //     vm.expectRevert("Lower tick too low");
    //     vm.startPrank(_manager);
    //     strategy.changeRange(tickLower, tickUpper);
    // }

    // function test_ChangeRangeWithUpperTickNotLessThanOrEqualMaxTick(int24 tickLower, int24 tickUpper, uint256 depositAmount) public {
    //     vm.assume(tickLower!=_tickLower && tickUpper!=_tickUpper);
    //     vm.assume(tickLower < tickUpper);
    //     vm.assume(tickLower >= ITickMathLib(_tickMathLib).MIN_TICK());
    //     vm.assume(!(tickUpper <= ITickMathLib(_tickMathLib).MAX_TICK()));
    //     _depositDenominationAsset(depositAmount);

    //     vm.expectRevert("Upper tick too high");
    //     vm.startPrank(_manager);
    //     strategy.changeRange(tickLower, tickUpper);
    // }

    // function test_ChangeRangeWithTickNotMultipleOfTickSpacing(int24 tickLower, int24 tickUpper, uint256 depositAmount) public {
    //     vm.assume(tickLower!=_tickLower && tickUpper!=_tickUpper);
    //     vm.assume(tickLower < tickUpper);
    //     vm.assume(tickLower >= ITickMathLib(_tickMathLib).MIN_TICK());
    //     vm.assume(tickUpper <= ITickMathLib(_tickMathLib).MAX_TICK());
    //     int24 tickSpacing = IPancakeV3Pool(_stake).tickSpacing();
    //     vm.assume(!(tickLower % tickSpacing == 0 && tickUpper % tickSpacing == 0));
    //     _depositDenominationAsset(depositAmount);

    //     vm.expectRevert("Invalid Ticks");
    //     vm.startPrank(_manager);
    //     strategy.changeRange(tickLower, tickUpper);
    // }

    function test_ChangeRangeWhenCalledByOwner( uint256 depositAmount) public {
        depositAmount=10e6;
        int24 tickSpacing = IPancakeV3Pool(_stake).tickSpacing();
        // vm.assume(tickLower < tickUpper);
        // vm.assume(tickLower >= ITickMathLib(_tickMathLib).MIN_TICK());
        // vm.assume(tickUpper <= ITickMathLib(_tickMathLib).MAX_TICK());
        // vm.assume(tickLower % tickSpacing == 0 && tickUpper % tickSpacing == 0);
        // vm.assume(!((tickLower == _tickLower) && (tickUpper == _tickUpper)));
        int24 tickLower = -53740; 
        int24 tickUpper = -53460; 
        _depositDenominationAsset(depositAmount);
        uint128 liquidity;
        int24 tickLower_;
        int24 tickUpper_;
        address user;
        // (uint128 liquidity, , int24 tickLower_, int24 tickUpper_, , , address user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
         if(_chef!=address(0)){
            ( liquidity, ,  tickLower_,  tickUpper_, , ,  user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
        }else{
            (, , ,, ,  tickLower_,  tickUpper_,  liquidity,,, ,  ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(strategy.tokenID());
            user= INonfungiblePositionManager(_nonFungiblePositionManager).ownerOf(strategy.tokenID());
        }
        assertEq(_tickLower, tickLower_);
        assertEq(_tickUpper, tickUpper_);

        uint256 tokenIdBef = strategy.tokenID();

        vm.startPrank(_manager);
        strategy.changeRange(tickLower, tickUpper);

        assertEq(tickLower, strategy.tickLower());
        assertEq(tickUpper, strategy.tickUpper());

        if(_chef!=address(0)){
            ( liquidity, ,  tickLower_,  tickUpper_, , ,  user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
        }else{
            (, , ,, ,  tickLower_,  tickUpper_,  liquidity,,, ,  ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(strategy.tokenID());
            user= INonfungiblePositionManager(_nonFungiblePositionManager).ownerOf(strategy.tokenID());
        }
        assertEq(tickLower, tickLower_);
        assertEq(tickUpper, tickUpper_);

        assertTrue(tokenIdBef != strategy.tokenID());
        
        uint256 point5PercentOfDeposit = 3 * depositAmount / 1000;
        uint256 lp0TokenBal = IERC20(_lp0Token).balanceOf(address(strategy));
        emit log_named_uint("After lp0Token balance", lp0TokenBal);
        assertLt(lp0TokenBal, point5PercentOfDeposit);

        uint256 point5PercentOfDepositInBnb = DexV3Calculations.convertAmount0ToAmount1(point5PercentOfDeposit, _stake, _fullMathLib);
        uint256 lp1TokenBal = IERC20(_lp1Token).balanceOf(address(strategy));
        emit log_named_uint("After lp1Token balance", lp1TokenBal);
        assertLt(lp1TokenBal, point5PercentOfDepositInBnb);
    }

    function _convertRewardToToken0(uint256 reward) internal view returns (uint256 amount0) {
        // (address[] memory rewardToLp0AddressPath, uint24[] memory rewardToLp0FeePath) = strategy.getRewardToLp0Path();
        amount0 = reward;
        // for (uint256 i = 0; i < rewardToLp0FeePath.length; i++) {
        //     uint24 fee = rewardToLp0FeePath[i];
        //     address token0 = rewardToLp0AddressPath[i];
        //     address token1 = rewardToLp0AddressPath[i+1];
        //     address pool = IPancakeV3Factory(_factory).getPool(token0, token1, fee);
        //     (uint160 sqrtPriceX96, , , , , , ) = IPancakeV3Pool(pool).slot0();
        //     if (token0 != IPancakeV3Pool(pool).token0()) {
        //         amount0 = IFullMathLib(_fullMathLib).mulDiv(IFullMathLib(_fullMathLib).mulDiv(amount0, FixedPoint96.Q96, sqrtPriceX96), FixedPoint96.Q96, sqrtPriceX96);
        //     } else {
        //         amount0 = IFullMathLib(_fullMathLib).mulDiv(IFullMathLib(_fullMathLib).mulDiv(amount0, sqrtPriceX96, FixedPoint96.Q96), sqrtPriceX96, FixedPoint96.Q96);
        //     }
        // }
    }

    function _convertRewardToToken1(uint256 reward) internal view returns (uint256 amount1) {
        // (address[] memory rewardToLp1AddressPath, uint24[] memory rewardToLp1FeePath) = strategy.getRewardToLp0Path();
        amount1 = reward;
        // for (uint256 i = 0; i < rewardToLp1FeePath.length; i++) {
        //     uint24 fee = rewardToLp1FeePath[i];
        //     address token0 = rewardToLp1AddressPath[i];
        //     address token1 = rewardToLp1AddressPath[i+1];
        //     address pool = IPancakeV3Factory(_factory).getPool(token0, token1, fee);
        //     (uint160 sqrtPriceX96, , , , , , ) = IPancakeV3Pool(pool).slot0();
        //     if (token0 != IPancakeV3Pool(pool).token0()) {
        //         amount1 = IFullMathLib(_fullMathLib).mulDiv(IFullMathLib(_fullMathLib).mulDiv(amount1, FixedPoint96.Q96, sqrtPriceX96), FixedPoint96.Q96, sqrtPriceX96);
        //     } else {
        //         amount1 = IFullMathLib(_fullMathLib).mulDiv(IFullMathLib(_fullMathLib).mulDiv(amount1, sqrtPriceX96, FixedPoint96.Q96), sqrtPriceX96, FixedPoint96.Q96);
        //     }
        // }
    }

    ///@notice tests for harvest functions

    function test_HarvestWhenNotPaused() public {
        uint256 depositAmount=10e6;
        uint256 swapAmount=100e6;
        _depositDenominationAsset(depositAmount);

        uint256 stratPoolBalanceBefore = strategy.balanceOf();
        emit log_named_uint("Total assets of strat before", stratPoolBalanceBefore);

        vm.warp(block.timestamp + 7*24*60*60);
         uint256 tvlBefore=strategy.balanceOf();
        emit log_named_uint("tvlBefore", tvlBefore);

        _performSwapInBothDirections(swapAmount);
        _performSwapInBothDirections(swapAmount);

        // uint256 lprewardsAvailabe=strategy.lpRewardsAvailable();
        // emit log_named_uint("lprewardsAvailabe", lprewardsAvailabe);

        vm.prank(_user1);
        IERC20(_lp0Token).transfer(address(strategy), 1e6);


        // uint256[] memory pids = new uint256[](1);
        // pids[0] = IMasterChefV3(_chef).v3PoolAddressPid(_stake);
        // vm.prank(0xeCc90d54B10ADd1ab746ABE7E83abe178B72aa9E);
        // IMasterChefV3(_chef).updatePools(pids);

        // uint256 rewardsAvblBef = IMasterChefV3(_chef).pendingCake(strategy.tokenID());
        // emit log_named_uint("Cake rewards available before", rewardsAvblBef);
        // assertTrue(rewardsAvblBef!=0);

        // ( , , , , , , , , , ,
        //     uint128 tokensOwed0,
        //     uint128 tokensOwed1
        // ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(strategy.tokenID());
        // assertTrue(tokensOwed0!=0);
        // assertTrue(tokensOwed1!=0);

        // uint256 liquidityBef = strategy.liquidityBalance();

        // uint256 lp0TokenBalBef = IERC20(_lp0Token).balanceOf(address(strategy));
        // uint256 lp1TokenBalBef = IERC20(_lp1Token).balanceOf(address(strategy));
        // uint256 cakeBalBef = IERC20(_rewardToken).balanceOf(address(strategy));

        // vm.expectEmit(true, false, false, false);
        // emit StratHarvest(address(this), 0, 0); //We don't try to match the second and third parameter of the event. They're result of Pancake swap contracts, we trust the protocol to be correct.
        strategy.harvest();

        uint256 tvlAfter=strategy.balanceOf();
        emit log_named_uint("tvlAfter", tvlAfter);
        
        // emit log_named_uint("Total assets of strat after", strategy.balanceOf());
        // assertGt(strategy.balanceOf(), stratPoolBalanceBefore);

        // emit log_named_uint("Cake rewards available after", IMasterChefV3(_chef).pendingCake(strategy.tokenID()));
        // assertEq(0, IMasterChefV3(_chef).pendingCake(strategy.tokenID()));

        // ( , , , , , , , , , ,
        //     uint256 tokensOwed0,
        //     uint256 tokensOwed1
        // ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(strategy.tokenID());
        // assertLt(tokensOwed0, 1 * depositAmount / 1e6);       //Fees is non-zero because of the swap after harvest
        // assertLt(tokensOwed1, DexV3Calculations.convertAmount0ToAmount1(1 * depositAmount / 1e6, _stake, _fullMathLib));

        // uint256 liquidityAft = strategy.liquidityBalance();
        // assertGt(liquidityAft, liquidityBef);

        // if(IERC20(_lp0Token).balanceOf(address(strategy)) > lp0TokenBalBef) {
        //     assertLe(IERC20(_lp0Token).balanceOf(address(strategy)) - lp0TokenBalBef, 5 * _convertRewardToToken0(rewardsAvblBef) / 1000);
        // } else {
        //     assertLe(IERC20(_lp0Token).balanceOf(address(strategy)), 5 * _convertRewardToToken0(rewardsAvblBef) / 1000);
        // }
        // if (IERC20(_lp1Token).balanceOf(address(strategy)) > lp1TokenBalBef) {
        //     assertLe(IERC20(_lp1Token).balanceOf(address(strategy)) - lp1TokenBalBef, 5 * _convertRewardToToken1(rewardsAvblBef) / 1000);
        // } else {
        //     assertLe(IERC20(_lp1Token).balanceOf(address(strategy)), 5 * _convertRewardToToken1(rewardsAvblBef) / 1000);
        // }
        // if (IERC20(_rewardToken).balanceOf(address(strategy)) > cakeBalBef) {
        //     assertLe(IERC20(_rewardToken).balanceOf(address(strategy)) - cakeBalBef, 5 * rewardsAvblBef / 1000);        //less than 0.5 percent of the cake rewards available is left uninvested
        // } else {
        //     assertLe(IERC20(_rewardToken).balanceOf(address(strategy)), 5 * rewardsAvblBef / 1000);
        // }
    }

    function test_HarvestWhenPaused() public {
        vm.prank(_manager);
        strategy.pause();
        vm.expectRevert("Pausable: paused");
        strategy.harvest();
    }
    function test_TokenStuck(uint256 depositAmount) public {
        depositAmount=10e6;
        uint256 bal=IERC20(_lp1Token).balanceOf(_whalelp1Token);
        vm.assume(depositAmount<bal);
        vm.prank(_whalelp1Token);
        IERC20(_lp1Token).transfer(address(strategy), depositAmount);
        vm.prank(_manager);
        strategy.inCaseTokensGetStuck(_lp1Token);
    }

    // function test_setRewardToLp0Path(uint256 depositAmount) public {
    //     _depositDenominationAsset(depositAmount);
    //     vm.startPrank(_manager);
    //     uint24 rewardToLp0FeePath0=strategy.rewardToLp0FeePath(0);
    //     address rewardToLp0AddressPath0=strategy.rewardToLp0AddressPath(0);
    //     address rewardToLp0AddressPath1=strategy.rewardToLp0AddressPath(1);
    //     emit log_named_uint("rewardToLp0FeePath0",rewardToLp0FeePath0);
    //     emit log_named_address("rewardToLp0AddressPath0",rewardToLp0AddressPath0);
    //     emit log_named_address("rewardToLp0AddressPath1",rewardToLp0AddressPath1);
    //     strategy.setRewardToLp0Path(_rewardToLp0AddressPath, _rewardToLp0FeePath);
    //     rewardToLp0FeePath0=strategy.rewardToLp0FeePath(0);
    //     rewardToLp0AddressPath0=strategy.rewardToLp0AddressPath(0);
    //     rewardToLp0AddressPath1=strategy.rewardToLp0AddressPath(1);
    //     emit log_named_uint("rewardToLp0FeePath0",rewardToLp0FeePath0);
    //     emit log_named_address("rewardToLp0AddressPath0",rewardToLp0AddressPath0);
    //     emit log_named_address("rewardToLp0AddressPath1",rewardToLp0AddressPath1);
    // }

    // function test_setRewardToLp1Path(uint256 depositAmount) public {
    //     _depositDenominationAsset(depositAmount);
    //     vm.startPrank(_manager);
    //     uint24 rewardToLp1FeePath0=strategy.rewardToLp0FeePath(0);
    //     address rewardToLp1AddressPath0=strategy.rewardToLp1AddressPath(0);
    //     address rewardToLp1AddressPath1=strategy.rewardToLp1AddressPath(1);
    //     emit log_named_uint("rewardToLp1FeePath0",rewardToLp1FeePath0);
    //     emit log_named_address("rewardToLp1AddressPath0",rewardToLp1AddressPath0);
    //     emit log_named_address("rewardToLp1AddressPath1",rewardToLp1AddressPath1);
    //     strategy.setRewardToLp0Path(_rewardToLp1AddressPath, _rewardToLp1FeePath);
    //     rewardToLp1FeePath0=strategy.rewardToLp0FeePath(0);
    //     rewardToLp1AddressPath0=strategy.rewardToLp1AddressPath(0);
    //     rewardToLp1AddressPath1=strategy.rewardToLp1AddressPath(1);
    //     emit log_named_uint("rewardToLp1FeePath0",rewardToLp1FeePath0);
    //     emit log_named_address("rewardToLp1AddressPath0",rewardToLp1AddressPath0);
    //     emit log_named_address("rewardToLp1AddressPath1",rewardToLp1AddressPath1);
    // }
    function test_Panic(uint256 depositAmount) public {
        depositAmount=10e6;
        _depositDenominationAsset(depositAmount);
        vm.startPrank(_manager);
        strategy.panic();
       
    }
    function test_retireStrat(uint256 depositAmount) public {
        depositAmount=10e6;
        _depositDenominationAsset(depositAmount);
        vm.prank(address(vault));
        strategy.retireStrat();       
    }

    function test_transferOwnership(uint256 depositAmount) public {
        depositAmount=10e6;
        _depositDenominationAsset(depositAmount);
        address owner=strategy.owner();
        emit log_named_address("owner before",owner);
        vm.prank(address(_manager));
        strategy.transferOwnership(_user2);
        vm.prank(address(_user2));
        strategy.acceptOwnership();
        owner=strategy.owner();
        emit log_named_address("owner after",owner);
    }

    function test_setManager(uint256 depositAmount,address newManager) public {
        depositAmount=10e6;
        // uint256 depositAmount=2e18;
        // address newManager=address(0);
        vm.assume(newManager!=address(0));
        _depositDenominationAsset(depositAmount);
        address manager=strategy.manager();
        emit log_named_address("manager before",manager);
        vm.prank(address(_manager));
        strategy.setManager(newManager);
        vm.prank(newManager);
        strategy.acceptManagership();
        manager=strategy.manager();
        emit log_named_address("manager after",manager);
    }

    function test_setManagerWithAddress0(uint256 depositAmount) public {
        depositAmount=10e6;
        _depositDenominationAsset(depositAmount);
        address manager=strategy.manager();
        vm.expectRevert();
        vm.prank(address(_manager));
        strategy.setManager(address(0));
    }

    function test_Unpause() public {
        uint256 depositAmount=2e6;
        _depositDenominationAsset(depositAmount);
        vm.startPrank(_manager);
        uint256 balanceOfBefore=strategy.balanceOf();
        console.log("balance Before pause",balanceOfBefore);
        strategy.pause();
        uint256 balanceOfAfter=strategy.balanceOf();
        console.log("balance After pause",balanceOfAfter);
        uint256  tokenId=strategy.tokenID();
        console.log("tokenId after pause",tokenId);
        strategy.unpause();   
        vm.stopPrank();
        _depositDenominationAsset(depositAmount);
        balanceOfAfter=strategy.balanceOf();
        console.log("balance After deposit",balanceOfAfter);
        tokenId=strategy.tokenID();
        console.log("tokenId after deposit",tokenId);

    }


    function test_SetSlippage() public {
        uint256 newSlippage = 50; // 0.5% slippage
        uint256 oldSlippage = strategy.slippage();
        console.log("oldSlippage",oldSlippage);
        // console.logInt(((42928 - 6932) / 60) * 60);
        // console.logInt(((42928 + 6932) / 60) * 60);
        
        // Only manager can set slippage
        vm.expectRevert();
        vm.prank(_user1);
        strategy.setSlippage(newSlippage);

        // Slippage must be > 0
        // vm.expectRevert();
        vm.prank(_manager); 
        strategy.setSlippage(0);

        // Slippage must be <= slippageDecimals
        vm.expectRevert();
        vm.prank(_manager);
        strategy.setSlippage(10001);

        // Valid slippage update
        vm.prank(_manager);
        strategy.setSlippage(newSlippage);
        console.log("newSlippage",strategy.slippage());

        assertEq(strategy.slippage(), newSlippage);
    }

    function test_PanicAndWithdraw() public {
        uint256 depositAmount=2e6;
        // _depositDenominationAsset(depositAmount);
        console.log("balance before",IERC20(_lp0Token).balanceOf(_user1));
        vm.startPrank(_user1);
        IERC20(_lp0Token).approve(address(vault), depositAmount);
        vault.deposit(depositAmount,_user1);
        vm.stopPrank();
        vm.startPrank(_manager);
        uint256 balanceOfBefore=strategy.balanceOf();
        console.log("balanceOfBefore",balanceOfBefore);
        console.log("panic vault");
        strategy.panic();
        console.log("try withdraw from vault");
        vm.stopPrank();
        vm.startPrank(_user1);
        vault.withdraw(depositAmount/2, _user1, _user1);
        vm.stopPrank();
        vm.prank(_manager);
        strategy.unpause();   
        console.log("balance before",IERC20(_lp0Token).balanceOf(_user1));
        _depositDenominationAsset(depositAmount);
        // uint256 balanceOfAfter=strategy.balanceOf();
        // console.log("balance After deposit",balanceOfAfter);
        // // tokenId=strategy.tokenID();
        // // console.log("tokenId after deposit",tokenId);
    }


    // function test_GetOutAmountMantle() public {
    //     // Define test parameters
    //     // address tokenIn = _lp0Token;
    //     // address tokenOut = _lp1Token ;
    //     uint256 amountInToken0 = 2626e6; // 1 token with 18 decimals
    //     uint256 amountInToken1 = 1e18; // 1 token with 18 decimals
    //     // uint256 amountInToken0 = 1e5; // 1 token with 18 decimals
    //     // uint256 amountInToken1 = 1e15; // 1 token with 18 decimals
    //     uint256 slippageTolerance = 100; // 1% slippage
    //     // Get the expected amount out using the contract function
    //     uint256 amountOutMinimumlp1 = strategy.getOutAmount(_stake,_lp0Token, amountInToken0, slippageTolerance);
    //     // console.log("amountOutMinimumlp1",amountOutMinimumlp1);
    //     uint256 amountOutMinimumlp0 = strategy.getOutAmount(_stake,_lp1Token, amountInToken1, slippageTolerance);
    //     console.log("amountInToken1",amountInToken1);
    //     console.log("amountOutMinimumlp0",amountOutMinimumlp0);
    //     console.log("amountOutMinimumlp1",amountOutMinimumlp1);
    //     assertGt(amountOutMinimumlp1, 0, "amountOutMinimumlp1 should be greater than 0");
    //     assertGt(amountOutMinimumlp0, 0, "amountOutMinimumlp0 should be greater than 0");
    //     // // Calculate the expected amount out minimum
    //     uint256 expectedAmountOutMinimumlp0;
    //     // // Fetch the price from Chainlink Price Feed
    //     // // Use a local fork of Ethereum mainnet
    //     uint256 forkId = vm.createFork("https://eth.llamarpc.com");
    //     vm.selectFork(forkId);
    //     IAggregatorV3Interface priceFeed = IAggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);//eth/usd chainlink eth mainnet aggregatr as here our lp1 in weth
    //     (, int price, , , ) = priceFeed.latestRoundData();
    //     uint256 priceInWei = uint256(price);
    //     // console.log("priceInWei",priceInWei);
    //     // // Calculate the expected amount out minimum using Chainlink price
    //     expectedAmountOutMinimumlp0 = (amountInToken1 * priceInWei * ((10000 - slippageTolerance)) / (10000 * 10** (12+priceFeed.decimals())));
    //     // expectedAmountOutMinimumlp0 = (amountInToken1 * priceInWei  / ( 10** priceFeed.decimals()));
    //     console.log("expectedAmountOutMinimumlp0",expectedAmountOutMinimumlp0);

    //     // // Assert that the calculated amount out is as expected
    //     // assertApproxEqRel(1000, 999, 1e16, "Amount out minimum is not within 1% of expected value");
    //     assertApproxEqRel(amountOutMinimumlp0, expectedAmountOutMinimumlp0, 1e17, "Amount out minimum is not within 1% of expected value");
    // }

    //  function test_GetOutAmountPolygon() public {
    //     uint256 forkId = vm.createFork("https://polygon-mainnet.g.alchemy.com/v2/QMIfo1I9pWTw5QMkmRRBP0BCs2LEzZue");
    //     vm.selectFork(forkId);
    //     RiveraConcNoStaking strategyP=new RiveraConcNoStaking();
    //     testVault = new RiveraAutoCompoundingVaultV2Public(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, rivTokenName, rivTokenSymbol, stratUpdateDelay, 100000e18);
    //     CommonAddresses memory _commonAddressesTest = CommonAddresses(address(testVault), 0xE592427A0AEce92De3Edee1F18E0157C05861564, 0xC36442b4a4522E871399CD717aBDD847Ab11FE88, 1000, 
    //     3,100,10000,_manager,_manager);

    //     RiveraLpStakingParams memory riveraLpStakingParams = RiveraLpStakingParams(
    //         34140,
    //         48000,
    //         0x7A73f0E2bB9Cf2A8F27e792908D68F9f58fa7375,
    //         // _chef,
    //         // _rewardToken,
    //         0x6D4ABbF94A81F15dFA012a8479dEFBB5B0DED7ED,
    //         0x19F51834817708F2da9Ac7D0cc3eAFF0b6Ed17D7,
    //         0x98D98C50047c6bDD424aD799Fc25efd7f9A28E32,
    //         0x52F199Be0f15D69C86B3327acf24c85a5E31F516,
    //         0xF5B745923b1879830F37da07a420Ed425eae8588,
    //         0x1F0Ac8D2215e7C6fCf63a6C2cE61615F267048A7,
    //         // _rewardToLp0AddressPath,
    //         // _rewardToLp0FeePath,
    //         // _rewardToLp1AddressPath,
    //         // _rewardToLp1FeePath,
    //         // _rewardtoNativeFeed,
    //         address(0)
    //         // "pendingCake"
    //     );
    //     strategyP.init(riveraLpStakingParams, _commonAddressesTest);
    //     uint256 amountInToken0 = 100e18; // 1 token with 18 decimals
    //     uint256 amountInToken1 = 100e18; // 1 token with 18 decimals
    //     uint256 slippageTolerance = 0; // 1% slippage
    //     // // Get the expected amount out using the contract function
    //     uint256 amountOutMinimumlp1 = strategyP.getOutAmount(0x7A73f0E2bB9Cf2A8F27e792908D68F9f58fa7375,0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, amountInToken0, slippageTolerance);
    //     uint256 amountOutMinimumlp0 = strategyP.getOutAmount(0x7A73f0E2bB9Cf2A8F27e792908D68F9f58fa7375,0x3d2bD0e15829AA5C362a4144FdF4A1112fa29B5c, amountInToken1, slippageTolerance);
    //     console.log("amountInToken0",amountInToken0);
    //     console.log("amountInToken1",amountInToken1);
    //     console.log("amountOutMinimumlp0",amountOutMinimumlp0);
    //     console.log("amountOutMinimumlp1",amountOutMinimumlp1);
    //     // assertGt(amountOutMinimumlp1, 0, "amountOutMinimumlp1 should be greater than 0");
    //     // assertGt(amountOutMinimumlp0, 0, "amountOutMinimumlp0 should be greater than 0");
    //     // // // Calculate the expected amount out minimum
    //     // uint256 expectedAmountOutMinimumlp0;





    //     // // Fetch the price from Chainlink Price Feed
    //     // // // Use a local fork of Ethereum mainnet
    //     // uint256 forkId = vm.createFork("https://eth.llamarpc.com");
    //     // vm.selectFork(forkId);
    //     // IAggregatorV3Interface priceFeed = IAggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);//eth/usd chainlink eth mainnet aggregatr as here our lp1 in weth
    //     // (, int price, , , ) = priceFeed.latestRoundData();
    //     // uint256 priceInWei = uint256(price);
    //     // // console.log("priceInWei",priceInWei);
    //     // // // Calculate the expected amount out minimum using Chainlink price
    //     // expectedAmountOutMinimumlp0 = (amountInToken1 * priceInWei * ((10000 - slippageTolerance)) / (10000 * 10** (12+priceFeed.decimals())));
    //     // // expectedAmountOutMinimumlp0 = (amountInToken1 * priceInWei  / ( 10** priceFeed.decimals()));
    //     // console.log("expectedAmountOutMinimumlp0",expectedAmountOutMinimumlp0);
    //     // // // Assert that the calculated amount out is as expected
    //     // // assertApproxEqRel(1000, 999, 1e16, "Amount out minimum is not within 1% of expected value");
    //     // assertApproxEqRel(amountOutMinimumlp0, expectedAmountOutMinimumlp0, 1e17, "Amount out minimum is not within 1% of expected value");
    // }

    // function test_GetOutAmountMantleSix() public {
    //     RiveraConcNoStaking strategyM=new RiveraConcNoStaking();
    //     testVault = new RiveraAutoCompoundingVaultV2Public(0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111, rivTokenName, rivTokenSymbol, stratUpdateDelay, 100000e18);
    //     CommonAddresses memory _commonAddressesTest = CommonAddresses(address(testVault), _router, _nonFungiblePositionManager, withdrawFeeDecimals, 
    //     withdrawFee,100,10000,_manager,_manager);

    //     RiveraLpStakingParams memory riveraLpStakingParams = RiveraLpStakingParams(
    //         -106550,-60500,
    //         0xD3d3127D9654f806370da592eb292eA0a347f0e3,
    //         // _chef,
    //         // _rewardToken,
    //         _tickMathLib,
    //         _sqrtPriceMathLib,
    //         _liquidityMathLib,
    //         _safeCastLib,
    //         _liquidityAmountsLib,
    //         _fullMathLib,
    //         // _rewardToLp0AddressPath,
    //         // _rewardToLp0FeePath,
    //         // _rewardToLp1AddressPath,
    //         // _rewardToLp1FeePath,
    //         // _rewardtoNativeFeed,
    //         _assettoNativeFeed
    //         // "pendingCake"
    //         );
    //     strategyM.init(riveraLpStakingParams, _commonAddressesTest);
    //     uint256 amountInToken0 = 1e18; // 1 token with 18 decimals
    //     uint256 amountInToken1 = 1e18; // 1 token with 18 decimals
    //     uint256 slippageTolerance = 0; // 1% slippage
    //     // // Get the expected amount out using the contract function
    //     uint256 amountOutMinimumlp1 = strategyM.getOutAmount(0xD3d3127D9654f806370da592eb292eA0a347f0e3,0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111, amountInToken0, slippageTolerance);
    //     uint256 amountOutMinimumlp0 = strategyM.getOutAmount(0xD3d3127D9654f806370da592eb292eA0a347f0e3,0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8, amountInToken1, slippageTolerance);
    //     console.log("amountInToken0",amountInToken0);
    //     console.log("amountInToken1",amountInToken1);
    //     console.log("amountOutMinimumlp0",amountOutMinimumlp0);
    //     console.log("amountOutMinimumlp1",amountOutMinimumlp1);
    //     // assertGt(amountOutMinimumlp1, 0, "amountOutMinimumlp1 should be greater than 0");
    //     // assertGt(amountOutMinimumlp0, 0, "amountOutMinimumlp0 should be greater than 0");
    //     // // // Calculate the expected amount out minimum
    //     // uint256 expectedAmountOutMinimumlp0;





    //     // // Fetch the price from Chainlink Price Feed
    //     // // // Use a local fork of Ethereum mainnet
    //     // uint256 forkId = vm.createFork("https://eth.llamarpc.com");
    //     // vm.selectFork(forkId);
    //     // IAggregatorV3Interface priceFeed = IAggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);//eth/usd chainlink eth mainnet aggregatr as here our lp1 in weth
    //     // (, int price, , , ) = priceFeed.latestRoundData();
    //     // uint256 priceInWei = uint256(price);
    //     // // console.log("priceInWei",priceInWei);
    //     // // // Calculate the expected amount out minimum using Chainlink price
    //     // expectedAmountOutMinimumlp0 = (amountInToken1 * priceInWei * ((10000 - slippageTolerance)) / (10000 * 10** (12+priceFeed.decimals())));
    //     // // expectedAmountOutMinimumlp0 = (amountInToken1 * priceInWei  / ( 10** priceFeed.decimals()));
    //     // console.log("expectedAmountOutMinimumlp0",expectedAmountOutMinimumlp0);
    //     // // // Assert that the calculated amount out is as expected
    //     // // assertApproxEqRel(1000, 999, 1e16, "Amount out minimum is not within 1% of expected value");
    //     // assertApproxEqRel(amountOutMinimumlp0, expectedAmountOutMinimumlp0, 1e17, "Amount out minimum is not within 1% of expected value");
    // }


    function test_DepositWithNormal() public {
        uint depositAmount=150000e6;
        vm.startPrank(_user1);
        IERC20(_lp0Token).approve(address(vault), depositAmount);
        (uint160 sqrtPriceX96, , , , , , ) = IPancakeV3Pool(_stake).slot0();
        console.log("sqrtPriceX96 before deposit ",sqrtPriceX96);
        uint256 sqrtPriceLimitX96 = strategy.getSqrtPriceLimitX96(sqrtPriceX96,_lp0Token,100 , 10000);
        console.log("sqrtPriceLimitX96",sqrtPriceLimitX96);
        vault.deposit(depositAmount,_user1);
        ( sqrtPriceX96, , , , , , ) = IPancakeV3Pool(_stake).slot0();
        console.log("sqrtPriceX96 after",sqrtPriceX96);
        console.log("balance after",vault.convertToAssets(IERC20(address(vault)).balanceOf(_user1)));
        vm.stopPrank();
    }

    //Function to test the deposit transaction by frontrunning it by calling function fluctuatePrice and checking it should be reverted if pool price is too fluctuated
    function test_DepositWithFRPriceFluc() public {
        uint depositAmount=50e6;
        // ChangeInAmountsForNewRatioParams(strategy.poolFee(), depositAmount, 0, _fullMathLib));
        (uint160 sqrtPriceX96, , , , , , ) = IPancakeV3Pool(_stake).slot0();
        console.log("sqrtPriceX96 before deposit ",sqrtPriceX96);

        uint256 sqrtPriceLimitX96 = strategy.getSqrtPriceLimitX96(sqrtPriceX96,_lp0Token,100 , 10000);
        console.log("sqrtPriceLimitX96",sqrtPriceLimitX96);
        // console.log("amountOutMinimum",amountOutMinimum);
        testStrategy.setTestOutAmountSwap(sqrtPriceLimitX96);
        vm.startPrank(_user1);
        // bytes memory depositData = abi.encodeWithSignature("deposit(uint256,address)", depositAmount, _user1);
        IERC20(_lp0Token).approve(address(testVault), depositAmount);
        fluctuatePrice(true);
        ( sqrtPriceX96, , , , , , ) = IPancakeV3Pool(_stake).slot0();
        console.log("sqrtPriceX96 after",sqrtPriceX96);
        vm.expectRevert();
        testVault.deposit(depositAmount,_user1);
        // (bool success2, ) = address(testVault).call(depositData);
        console.log("balance after",testVault.convertToAssets(IERC20(address(testVault)).balanceOf(_user1)));
        vm.stopPrank();
    }


    function test_Swap() public {
        console.logInt(((currentTick - 6932) / tickSpacing) * tickSpacing);
        console.logInt(((currentTick + 6932) / tickSpacing) * tickSpacing);
        uint swapAmount=25000e6;
        vm.startPrank(_user1);
        IERC20(_lp0Token).approve(_router, swapAmount);
        uint160 sqLimit=getStPriceLimitX96(_stake,_lp0Token,10000,10000);
        IV3SwapRouter(_router).exactInputSingle(IV3SwapRouter.ExactInputSingleParams(
                _lp0Token,
                _lp1Token,
                500,
                _user1,
                swapAmount,
                0,
                sqLimit
        ));
        swapAmount=20e18;
        sqLimit=getStPriceLimitX96(_stake,_lp1Token,10000,10000);
        IERC20(_lp1Token).approve(_router, swapAmount);
        IV3SwapRouter(_router).exactInputSingle(IV3SwapRouter.ExactInputSingleParams(
                _lp1Token,
                _lp0Token,
                500,
                _user1,
                swapAmount, 
                0,
                sqLimit
        ));
    }


    // function test_Slippage() public {
    //     uint swapAmount=2600e6;
    //     uint256 amountOutMinimum = strategy.getOutAmount(_stake,_lp0Token,swapAmount , 100);
    //     console.log("amountOutMinimum", amountOutMinimum);

    //     vm.startPrank(_user1);
    //     IERC20(_lp0Token).transfer(address(testStrategy), swapAmount);
    //     fluctuatePrice(true);
    //     // fluctuatePrice(false);
    //     console.log("bal", IERC20(_lp1Token).balanceOf(address(testStrategy)));
    //     vm.expectRevert();
    //     testStrategy.testSwapV3In(_lp0Token, _lp1Token, swapAmount, 500, amountOutMinimum);
    //     console.log("bal", IERC20(_lp1Token).balanceOf(address(testStrategy)));
    // }


    function getStPriceLimitX96(address pool, address tokenIn, uint256 _slippageTolerance,uint256 _slippageDecimals) public virtual view returns(uint160){
        (uint160 sqrtPriceX96, , , , , , ) = IPancakeV3Pool(pool).slot0();
        uint256 priceLimit;
        // uint256 priceLimit = (uint256(sqrtPriceX96) * (_slippageDecimals - _slippageTolerance)) / _slippageDecimals;
        if(_slippageDecimals==_slippageTolerance){
            return 0;
        }
        if(tokenIn==_lp1Token){
            priceLimit =(sqrtPriceX96 * _slippageDecimals )/ (_slippageDecimals - _slippageTolerance);
        }else{
            priceLimit=(sqrtPriceX96 * (_slippageDecimals - _slippageTolerance)) / _slippageDecimals;
        }


        return(uint160(priceLimit)); 
    }

    function fluctuatePrice(bool increaselp1Price) public{
    //     uint256 amountOutMinimum = strategy.getOutAmount(_stake,_lp1Token,1e18 , 100);
    //     console.log("price before",amountOutMinimum/1e6);
        // console.log("bal", IERC20(_lp0Token).balanceOf(_user1)/1e6);

        if(increaselp1Price){
            uint swapAmount=25000e6;
            vm.startPrank(_user1);
            IERC20(_lp0Token).approve(_router, swapAmount);
            IV3SwapRouter(_router).exactInputSingle(IV3SwapRouter.ExactInputSingleParams(
                    _lp0Token,
                    _lp1Token,
                    500,
                    _user1,
                    swapAmount,
                    0,
                    0
            ));
        }else{
            uint swapAmount=20e18;
            vm.startPrank(_user1);
            // console.log("bal", IERC20(_lp1Token).balanceOf(_user1));
            IERC20(_lp1Token).approve(_router, swapAmount);
            IV3SwapRouter(_router).exactInputSingle(IV3SwapRouter.ExactInputSingleParams(
                    _lp1Token,
                    _lp0Token,
                    500,
                    _user1,
                    swapAmount, 
                    0,
                    0
            ));
        }
        
        // amountOutMinimum = strategy.getOutAmount(_stake,_lp1Token,1e18 , 100);
        // console.log("price after",amountOutMinimum/1e6);
    }

}

/*

forge test --match-path test/strategies/staking/RiveraConcNoStaking.t.sol --fork-url http://127.0.0.1:8545/ -vvv

*/