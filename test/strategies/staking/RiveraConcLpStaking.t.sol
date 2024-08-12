pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../src/strategies/staking/RiveraConcLpStaking.sol";
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


///@dev
///As there is dependency on Cake swap protocol. Replicating the protocol deployment on separately is difficult. Hence we would test on main net fork of BSC.
///The addresses used below must also be mainnet addresses.

contract RiveraConcLpStakingTest is Test {
    RiveraConcLpStaking strategy;
    RiveraAutoCompoundingVaultV2Public vault;

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
    address _user1 = 0x0A0e42Cb6FA85e78848aC241fACd8fCCbAc4962A;
    address _user2 = 0x2fa6a4D2061AD9FED3E0a1A7046dcc9692dA6Da8;
    address _whale = 0xD183F2BBF8b28d9fec8367cb06FE72B88778C86B;        //35 Mil whale 35e24
    uint256 _maxUserBal = 15e24;

    uint256 PERCENT_POOL_TVL_OF_CAPITAL = 5;
    uint256 minCapital = 1e18;      //One dollar of denomination asset

    uint256 withdrawFeeDecimals = 10000;
    uint256 withdrawFee = 10;

    uint256 feeDecimals = 1000;
    uint256 protocolFee = 15;
    uint256 fundManagerFee = 15;
    uint256 partnerFee = 15;
    address partner = 0xA638177B9c3D96A30B75E6F9e35Baedf3f1954d2;

    function setUp() public {

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
        vm.stopPrank();

        ///@dev Transfering LP tokens from a whale to my accounts
        vm.startPrank(_whale);
        IERC20(_usdt).transfer(_user1, _maxUserBal);
        IERC20(_usdt).transfer(_user2, _maxUserBal);
        vm.stopPrank();
    }

    function test_GetDepositToken() public {
        address depositTokenAddress = strategy.depositToken();
        assertEq(depositTokenAddress, _usdt);
    }

    ///@notice tests for deposit function

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

    // function test_BurnAndCollectV3(uint256 depositAmount, uint256 swapAmount) public {
    //     _depositDenominationAsset(depositAmount);
    //     vm.warp(block.timestamp + 7*24*60*60);
    //     _performSwapInBothDirections(swapAmount);

    //     (uint128 liquidity, , int24 tickLower, int24 tickUpper, , , address user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
    //     assertTrue(liquidity!=0);
    //     assertEq(strategy.tickLower(), tickLower);
    //     assertEq(strategy.tickUpper(), tickUpper);
    //     assertEq(address(strategy), user);

    //     uint256 tokenId = strategy.tokenID();
    //     ( , , , , , tickLower, tickUpper, liquidity, , , , ) = INonfungiblePositionManager(strategy.NonfungiblePositionManager()).positions(tokenId);
    //     assertTrue(liquidity!=0);
    //     assertEq(strategy.tickLower(), tickLower);
    //     assertEq(strategy.tickUpper(), tickUpper);

    //     assertTrue(strategy.rewardsAvailable()!=0);

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
    //     uint256 token0BalBef = IERC20(_usdt).balanceOf(address(strategy));
    //     uint256 token1BalBef = IERC20(_wbnb).balanceOf(address(strategy));

    //     assertEq(INonfungiblePositionManager(_nonFungiblePositionManager).ownerOf(tokenId), _chef);

    //     strategy._burnAndCollectV3(true);

    //     (liquidity, , tickLower, tickUpper, , , user, , ) = IMasterChefV3(_chef).userPositionInfos(tokenId);
    //     assertEq(0, liquidity);
    //     assertEq(0, tickLower);
    //     assertEq(0, tickUpper);
    //     assertEq(address(0), user);

    //     vm.expectRevert("Invalid token ID");
    //     ( , , , , , tickLower, tickUpper, liquidity, , , , ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(tokenId);

    //     assertEq(0, strategy.rewardsAvailable());

    //     assertGt(IERC20(_usdt).balanceOf(address(strategy)), token0BalBef);
    //     assertGt(IERC20(_wbnb).balanceOf(address(strategy)), token1BalBef);     //Verifies that fees has been collected as that is the only way token0 and token balance could increase

    //     vm.expectRevert("ERC721: owner query for nonexistent token");
    //     INonfungiblePositionManager(_nonFungiblePositionManager).ownerOf(tokenId);
    // }

    function test_ConvertAmount0ToAmount1(uint256 amount) public {
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
        _depositDenominationAsset(depositAmount);
        uint256 withdrawAmount = 996 * depositAmount / 1000;

        uint256 vaultDenominaionbal = IERC20(_usdt).balanceOf(address(vault));
        uint256 point5PercentOfDeposit = 5 * depositAmount / 1000;
        emit log_named_uint("Vault USDT balance", vaultDenominaionbal);
        assertLt(vaultDenominaionbal, point5PercentOfDeposit);

        uint256 liquidityBalBefore = strategy.liquidityBalance();

        vm.prank(address(vault));
        strategy.withdraw(withdrawAmount);

        vaultDenominaionbal = IERC20(_usdt).balanceOf(address(vault));
        assertApproxEqRel(vaultDenominaionbal, withdrawAmount, 25e15);

        uint256 liquidityBalAfter = strategy.liquidityBalance();
        uint256 liqDelta = DexV3Calculations.calculateLiquidityDeltaForAssetAmount(LiquidityToAmountCalcParams(_tickLower, _tickUpper, 1e28, _safeCastLib, _sqrtPriceMathLib, _tickMathLib, _stake), 
        LiquidityDeltaForAssetAmountParams(_isTokenZeroDeposit, strategy.poolFee(), withdrawAmount, _fullMathLib, _liquidityAmountsLib));
        assertApproxEqRel(liquidityBalBefore - liquidityBalAfter, liqDelta, 25e15);

        uint256 wbnbBal = IERC20(_wbnb).balanceOf(address(strategy));
        emit log_named_uint("After strat WBNB balance", wbnbBal);
        assertEq(wbnbBal, 0);

        uint256 usdtBal = IERC20(_usdt).balanceOf(address(strategy));
        emit log_named_uint("After strat USDT balance", usdtBal);
        assertLt(usdtBal, withdrawAmount * withdrawFee / withdrawFeeDecimals);

    }

 

    function test_WithdrawWhenNotCalledByVault(uint256 depositAmount, address randomAddress) public {
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
        int24 tickSpacing = IPancakeV3Pool(_stake).tickSpacing();
        // vm.assume(tickLower < tickUpper);
        // vm.assume(tickLower >= ITickMathLib(_tickMathLib).MIN_TICK());
        // vm.assume(tickUpper <= ITickMathLib(_tickMathLib).MAX_TICK());
        // vm.assume(tickLower % tickSpacing == 0 && tickUpper % tickSpacing == 0);
        // vm.assume(!((tickLower == _tickLower) && (tickUpper == _tickUpper)));
        int24 tickLower = -53740; 
        int24 tickUpper = -53460; 
        _depositDenominationAsset(depositAmount);

        (uint128 liquidity, , int24 tickLower_, int24 tickUpper_, , , address user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
        assertEq(_tickLower, tickLower_);
        assertEq(_tickUpper, tickUpper_);

        uint256 tokenIdBef = strategy.tokenID();

        vm.startPrank(_manager);
        strategy.changeRange(tickLower, tickUpper);

        assertEq(tickLower, strategy.tickLower());
        assertEq(tickUpper, strategy.tickUpper());

        (liquidity, , tickLower_, tickUpper_, , , user, , ) = IMasterChefV3(_chef).userPositionInfos(strategy.tokenID());
        assertEq(tickLower, tickLower_);
        assertEq(tickUpper, tickUpper_);

        assertTrue(tokenIdBef != strategy.tokenID());
        
        uint256 point5PercentOfDeposit = 3 * depositAmount / 1000;
        uint256 usdtBal = IERC20(_usdt).balanceOf(address(strategy));
        emit log_named_uint("After USDT balance", usdtBal);
        assertLt(usdtBal, point5PercentOfDeposit);

        uint256 point5PercentOfDepositInBnb = DexV3Calculations.convertAmount0ToAmount1(point5PercentOfDeposit, _stake, _fullMathLib);
        uint256 wbnbBal = IERC20(_wbnb).balanceOf(address(strategy));
        emit log_named_uint("After WBNB balance", wbnbBal);
        assertLt(wbnbBal, point5PercentOfDepositInBnb);
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

    function test_HarvestWhenNotPaused(uint256 depositAmount, uint256 swapAmount) public {
        _depositDenominationAsset(depositAmount);

        uint256 stratPoolBalanceBefore = strategy.balanceOf();
        emit log_named_uint("Total assets of strat before", stratPoolBalanceBefore);

        vm.warp(block.timestamp + 7*24*60*60);

        _performSwapInBothDirections(swapAmount);
        _performSwapInBothDirections(swapAmount);

        // uint256[] memory pids = new uint256[](1);
        // pids[0] = IMasterChefV3(_chef).v3PoolAddressPid(_stake);
        // vm.prank(0xeCc90d54B10ADd1ab746ABE7E83abe178B72aa9E);
        // IMasterChefV3(_chef).updatePools(pids);

        uint256 rewardsAvblBef = IMasterChefV3(_chef).pendingCake(strategy.tokenID());
        emit log_named_uint("Cake rewards available before", rewardsAvblBef);
        assertTrue(rewardsAvblBef!=0);

        // ( , , , , , , , , , ,
        //     uint128 tokensOwed0,
        //     uint128 tokensOwed1
        // ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(strategy.tokenID());
        // assertTrue(tokensOwed0!=0);
        // assertTrue(tokensOwed1!=0);

        uint256 liquidityBef = strategy.liquidityBalance();

        uint256 usdtBalBef = IERC20(_usdt).balanceOf(address(strategy));
        uint256 wbnbBalBef = IERC20(_wbnb).balanceOf(address(strategy));
        uint256 cakeBalBef = IERC20(_cakeReward).balanceOf(address(strategy));

        vm.expectEmit(true, false, false, false);
        emit StratHarvest(address(this), 0, 0); //We don't try to match the second and third parameter of the event. They're result of Pancake swap contracts, we trust the protocol to be correct.
        strategy.harvest();
        
        emit log_named_uint("Total assets of strat after", strategy.balanceOf());
        assertGt(strategy.balanceOf(), stratPoolBalanceBefore);

        emit log_named_uint("Cake rewards available after", IMasterChefV3(_chef).pendingCake(strategy.tokenID()));
        assertEq(0, IMasterChefV3(_chef).pendingCake(strategy.tokenID()));

        ( , , , , , , , , , ,
            uint256 tokensOwed0,
            uint256 tokensOwed1
        ) = INonfungiblePositionManager(_nonFungiblePositionManager).positions(strategy.tokenID());
        assertLt(tokensOwed0, 1 * depositAmount / 1e6);       //Fees is non-zero because of the swap after harvest
        assertLt(tokensOwed1, DexV3Calculations.convertAmount0ToAmount1(1 * depositAmount / 1e6, _stake, _fullMathLib));

        uint256 liquidityAft = strategy.liquidityBalance();
        assertGt(liquidityAft, liquidityBef);

        if(IERC20(_usdt).balanceOf(address(strategy)) > usdtBalBef) {
            assertLe(IERC20(_usdt).balanceOf(address(strategy)) - usdtBalBef, 5 * _convertRewardToToken0(rewardsAvblBef) / 1000);
        } else {
            assertLe(IERC20(_usdt).balanceOf(address(strategy)), 5 * _convertRewardToToken0(rewardsAvblBef) / 1000);
        }
        if (IERC20(_wbnb).balanceOf(address(strategy)) > wbnbBalBef) {
            assertLe(IERC20(_wbnb).balanceOf(address(strategy)) - wbnbBalBef, 5 * _convertRewardToToken1(rewardsAvblBef) / 1000);
        } else {
            assertLe(IERC20(_wbnb).balanceOf(address(strategy)), 5 * _convertRewardToToken1(rewardsAvblBef) / 1000);
        }
        if (IERC20(_cakeReward).balanceOf(address(strategy)) > cakeBalBef) {
            assertLe(IERC20(_cakeReward).balanceOf(address(strategy)) - cakeBalBef, 5 * rewardsAvblBef / 1000);        //less than 0.5 percent of the cake rewards available is left uninvested
        } else {
            assertLe(IERC20(_cakeReward).balanceOf(address(strategy)), 5 * rewardsAvblBef / 1000);
        }
    }

    function test_HarvestWhenPaused() public {
        vm.prank(_manager);
        strategy.pause();
        vm.expectRevert("Pausable: paused");
        strategy.harvest();
    }
    function test_TokenStuck(uint256 depositAmount) public {
        address _whaleWbnb=0x0eD7e52944161450477ee417DE9Cd3a859b14fD0;
        uint256 bal=IERC20(_wbnb).balanceOf(_whaleWbnb);
        vm.assume(depositAmount<bal);
        vm.prank(_whaleWbnb);
        IERC20(_wbnb).transfer(address(strategy), depositAmount);
        vm.prank(_manager);
        strategy.inCaseTokensGetStuck(_wbnb);
    }

    function test_setRewardToLp0Path(uint256 depositAmount) public {
        _depositDenominationAsset(depositAmount);
        vm.startPrank(_manager);
        uint24 rewardToLp0FeePath0=strategy.rewardToLp0FeePath(0);
        address rewardToLp0AddressPath0=strategy.rewardToLp0AddressPath(0);
        address rewardToLp0AddressPath1=strategy.rewardToLp0AddressPath(1);
        emit log_named_uint("rewardToLp0FeePath0",rewardToLp0FeePath0);
        emit log_named_address("rewardToLp0AddressPath0",rewardToLp0AddressPath0);
        emit log_named_address("rewardToLp0AddressPath1",rewardToLp0AddressPath1);
        strategy.setRewardToLp0Path(_rewardToLp0AddressPath, _rewardToLp0FeePath);
        rewardToLp0FeePath0=strategy.rewardToLp0FeePath(0);
        rewardToLp0AddressPath0=strategy.rewardToLp0AddressPath(0);
        rewardToLp0AddressPath1=strategy.rewardToLp0AddressPath(1);
        emit log_named_uint("rewardToLp0FeePath0",rewardToLp0FeePath0);
        emit log_named_address("rewardToLp0AddressPath0",rewardToLp0AddressPath0);
        emit log_named_address("rewardToLp0AddressPath1",rewardToLp0AddressPath1);
    }

    function test_setRewardToLp1Path(uint256 depositAmount) public {
        _depositDenominationAsset(depositAmount);
        vm.startPrank(_manager);
        uint24 rewardToLp1FeePath0=strategy.rewardToLp0FeePath(0);
        address rewardToLp1AddressPath0=strategy.rewardToLp1AddressPath(0);
        address rewardToLp1AddressPath1=strategy.rewardToLp1AddressPath(1);
        emit log_named_uint("rewardToLp1FeePath0",rewardToLp1FeePath0);
        emit log_named_address("rewardToLp1AddressPath0",rewardToLp1AddressPath0);
        emit log_named_address("rewardToLp1AddressPath1",rewardToLp1AddressPath1);
        strategy.setRewardToLp0Path(_rewardToLp1AddressPath, _rewardToLp1FeePath);
        rewardToLp1FeePath0=strategy.rewardToLp0FeePath(0);
        rewardToLp1AddressPath0=strategy.rewardToLp1AddressPath(0);
        rewardToLp1AddressPath1=strategy.rewardToLp1AddressPath(1);
        emit log_named_uint("rewardToLp1FeePath0",rewardToLp1FeePath0);
        emit log_named_address("rewardToLp1AddressPath0",rewardToLp1AddressPath0);
        emit log_named_address("rewardToLp1AddressPath1",rewardToLp1AddressPath1);
    }
    function test_Panic(uint256 depositAmount) public {
        _depositDenominationAsset(depositAmount);
        vm.startPrank(_manager);
        strategy.panic();
       
    }

    function test_Unpause(uint256 depositAmount) public {
        // =2e18;
        _depositDenominationAsset(depositAmount);
        vm.startPrank(_manager);
        uint256 balanceOfBefore=strategy.balanceOf();
        console.log("balance Before pause",balanceOfBefore);
        strategy.panic();
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

    function test_retireStrat(uint256 depositAmount) public {
        _depositDenominationAsset(depositAmount);
        vm.prank(address(vault));
        strategy.retireStrat();       
    }

    function test_transferOwnership(uint256 depositAmount) public {
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
        _depositDenominationAsset(depositAmount);
        address manager=strategy.manager();
        vm.expectRevert();
        vm.prank(address(_manager));
        strategy.setManager(address(0));
    }

}

/*
forge test --match-path test/strategies/staking/RiveraConcLpStaking.t.sol --fork-url http://127.0.0.1:8545/ -vvv
*/