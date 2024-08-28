pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/strategies/staking/RiveraConcNoStaking.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";


import "@rivera/strategies/staking/interfaces/INonfungiblePositionManager.sol";
import "@pancakeswap-v3-core/interfaces/IPancakeV3Pool.sol";
import "@pancakeswap-v3-core/interfaces/IPancakeV3Factory.sol";
import "@rivera/strategies/staking/interfaces/libraries/ITickMathLib.sol";
import "@openzeppelin/utils/math/Math.sol";

import "@rivera/libs/DexV3Calculations.sol";
import "@rivera/libs/DexV3CalculationStruct.sol";

interface IToken is IERC20 {
    function decimals() external view returns(uint);
}

///The pool used in this testing is fusionx's USDT / WETH 0.05%  https://fusionx.finance/info/v3/pairs/0xa125af1a4704044501fe12ca9567ef1550e430e8?chain=mantle

///@dev

contract SlippageTest is Test {

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
    int24 currentTick =202248;     //Taken from explorer
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

    ///@dev Users Setup
    address _manager = 0xA638177B9c3D96A30B75E6F9e35Baedf3f1954d2;
    address _user1 = 0x0A0e42Cb6FA85e78848aC241fACd8fCCbAc4962A;
    address _user2 = 0x2fa6a4D2061AD9FED3E0a1A7046dcc9692dA6Da8;
    address _whale = 0xf89d7b9c864f589bbF53a82105107622B35EaA40;        //35 Mil whale 35e24
    uint256 _maxUserBal = IERC20(_lp0Token).balanceOf(_whale)/4;

 
    function setUp() public {

        ///@dev Transfering LP tokens from a whale to my accounts
        vm.startPrank(_whale);
        IERC20(_lp0Token).transfer(_user1, _maxUserBal);
        IERC20(_lp0Token).transfer(_user2, _maxUserBal);
        vm.stopPrank();
        // emit log_named_uint("lp0Token balance of user1", IERC20(_lp0Token).balanceOf(_user1));
    }



    // function test_performSwapInBothDirections() public {
    //     uint256 swapAmount=_maxUserBal/4;
    //     (uint160 sqrtPriceX96, int24 tick, , , , , ) = IPancakeV3Pool(_stake).slot0();
    //     console.log("sqrtPriceX96 before",sqrtPriceX96);
    //     console2.logInt(tick);
    //     vm.startPrank(_user2);
    //     IERC20(_lp0Token).approve(_router, type(uint256).max);
    //     IERC20(_lp1Token).approve(_router, type(uint256).max);
    //     uint256 _lp1TokenReceived = IV3SwapRouter(_router).exactInputSingle(
    //         IV3SwapRouter.ExactInputSingleParams(
    //             _lp0Token,
    //             _lp1Token,
    //             500,
    //             _user2,
    //             swapAmount,
    //             0,
    //             0
    //         )
    //     );
    //     // IV3SwapRouter(_router).exactInputSingle(
    //     //     IV3SwapRouter.ExactInputSingleParams(
    //     //         _lp1Token,
    //     //         _lp0Token,
    //     //         500,
    //     //         _user2,
    //     //         _lp1TokenReceived,
    //     //         0,
    //     //         0
    //     //     )
    //     // );
    //     ( sqrtPriceX96,  tick, , , , , ) = IPancakeV3Pool(_stake).slot0();
    //     console.log("sqrtPriceX96 ",sqrtPriceX96);
    //     console2.logInt(tick);
    //     vm.stopPrank();
    // }


    function test_slippage() public {
        // uint256 swapAmount=_maxUserBal/4;
        uint256 swapAmount=2730e6;
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IPancakeV3Pool(_stake).slot0();
        console.log("swapAmount lp0",swapAmount);
        uint256 amountOutMinimum = getOutAmount(_stake, _lp0Token, _lp1Token, swapAmount, 0);//100=1%

        vm.startPrank(_user2);
        IERC20(_lp0Token).approve(_router, type(uint256).max);
        IERC20(_lp1Token).approve(_router, type(uint256).max);
        // uint256 _lp1TokenReceived = IV3SwapRouter(_router).exactInputSingle(
        //     IV3SwapRouter.ExactInputSingleParams(
        //         _lp0Token,
        //         _lp1Token,
        //         500,
        //         _user2,
        //         swapAmount,
        //         0,
        //         0
        //     )
        // );

        // console.log("_lp1TokenReceived   ",_lp1TokenReceived);
        
        // console.log("==check random for 2 eth in ==");
        // amountOutMinimum = getOutAmount(_stake, _lp1Token, _lp0Token, 1e18, 0);//100=1%

    }


    function test_AmountOut()public{
        // Create a local fork using vm
        string memory rpcUrl = "https://rpc.degen.tips";
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);
        IPancakeV3Pool pool=IPancakeV3Pool(0x342B19546cD25716E9D709DF87049ea5885d298F);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        address token0=IPancakeV3Pool(pool).token0();
        address token1=IPancakeV3Pool(pool).token1();
        uint token0inAmount=540e18;
        uint token1inAmount=25e18;
        uint256 amountOutMinimum = getOutAmount(address(pool), token0, token1, token0inAmount, 100);//100=1%
        console.log("token0 in",token0inAmount);
        console.log("token1 out",amountOutMinimum);
        console.log("opposite direction");
        amountOutMinimum = getOutAmount(address(pool), token1, token0, token1inAmount, 100);//100=1%
        console.log("token1 in",token1inAmount);
        console.log("token0 out",amountOutMinimum);
        
    }



    // Slippage tolerance in basis points (e.g., 100 = 1%)
    function getOutAmount(address pool, address tokenIn,address tokenOut,uint256 amountIn, uint256 slippageTolerance) internal view returns (uint256 amountOutMinimum) {
        (uint160 sqrtPriceX96, , , , , , ) = IPancakeV3Pool(pool).slot0();
        address token0=IPancakeV3Pool(pool).token0();
        address token1=IPancakeV3Pool(pool).token1();
        uint256 decimals0 = IToken(token0).decimals();
        uint256 decimals1 = IToken(token1).decimals();
        (uint256 buyOneOfToken0,uint256 buyOneOfToken1)=GetPrice(sqrtPriceX96,decimals0,decimals1);
        console.log("price of token0 in value of token1 in lowest decimal : ",buyOneOfToken0);
	    console.log("price of token1 in value of token0 in lowest decimal : ",buyOneOfToken1);
        if(tokenIn==token0){
            // amountOutMinimum=(amountIn*buyOneOfToken0)/10**decimals0;
            amountOutMinimum=(amountIn*buyOneOfToken0  * (10000 - slippageTolerance))/(10000*(10**decimals0));
        }else{
            // amountOutMinimum=(amountIn*buyOneOfToken1)/10**decimals1;
            amountOutMinimum=(amountIn*buyOneOfToken1 * (10000 - slippageTolerance))/(10000*(10**decimals1));
        }
    }

    

    function GetPrice(uint160 sqrtPriceX96,uint256 Decimal0,uint256 Decimal1) internal view returns(uint256 buyOneOfToken0,uint256 buyOneOfToken1)  {
        uint256 sqrtPriceX96Squared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 factor0 = sqrtPriceX96Squared*(10**Decimal0 );
        uint256 factor1 = 2**192*(10**Decimal1 );
        // uint256 power192 = 2**192;
        // buyOneOfToken0 = factor0/ power192;
        buyOneOfToken0 = factor0/  2**192;
        buyOneOfToken1 = factor1 / sqrtPriceX96Squared; 
    }
}


/*
forge test --match-path test/SlippageTest/SlippageTest.t.sol --fork-url http://127.0.0.1:8545/ -vvv
*/