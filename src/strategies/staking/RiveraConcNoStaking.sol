pragma solidity ^0.8.0;
// import "hardhat/console.sol"; 
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/security/Pausable.sol";
import "@openzeppelin/security/ReentrancyGuard.sol";

import "@pancakeswap-v3-core/interfaces/IPancakeV3Pool.sol";

import "./interfaces/IMasterChefV3.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "../common/FeeManager.sol";
import "../utils/StringUtils.sol";
import "@openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/proxy/utils/Initializable.sol";
import "./interfaces/IV3SwapRouter.sol";

import "@rivera/libs/DexV3Calculations.sol";
import "@rivera/libs/DexV3CalculationStruct.sol";

struct RiveraLpStakingParams {
    int24 tickLower;
    int24 tickUpper;
    address stake;
    address tickMathLib;
    address sqrtPriceMathLib;
    address liquidityMathLib;
    address safeCastLib;
    address liquidityAmountsLib;
    address fullMathLib;
    address  assettoNativeFeed;
}

struct CommonAddresses {
    address vault;
    address router;
    address NonfungiblePositionManager;
    uint256 withdrawFeeDecimals;
    uint256 withdrawFee;
    uint256 slippage;
    uint256 slippageDecimals;////If wee put decimals  10000 then 100 will be 1 %
    address manager;
    address owner;
}

contract RiveraConcNoStaking is FeeManager, ReentrancyGuard, ERC721Holder, Initializable {
    using SafeERC20 for IERC20;

    //To Farm or not
    // bool public hasFarm;

    // Tokens used
    address public stake;
    address public lpToken0;
    address public lpToken1;
    address public depositToken;

    // Third party contracts
    address public tickMathLib;
    address public sqrtPriceMathLib;
    address public liquidityMathLib;
    address public safeCastLib;
    address public liquidityAmountsLib;
    address public fullMathLib;

    uint256 public lastHarvest;
    uint256 public tokenID;
    int24 public tickLower;
    int24 public tickUpper;
    uint24 public poolFee;

    address public assettoNativeFeed;

    //Events
    event StratHarvest(
        address indexed harvester,
        uint256 tvl
    );
    event Deposit(uint256 tvl, uint256 amount);
    event Withdraw(uint256 tvl, uint256 amount);
    event RangeChange(int24 tickLower, int24 tickUpper);
    event AssetToNativeFeedChange(address oldFeed, address newFeed);
    event SlippageChange(uint256 oldSlippage,uint256 newSlippage);

    ///@dev
    ///@param _riveraLpStakingParams: Has the pool specific params
    ///@param _commonAddresses: Has addresses common to all vaults, check Rivera Fee manager for more info
    function init(RiveraLpStakingParams memory _riveraLpStakingParams, CommonAddresses memory _commonAddresses) public virtual initializer {
        tickMathLib = _riveraLpStakingParams.tickMathLib;
        sqrtPriceMathLib = _riveraLpStakingParams.sqrtPriceMathLib;
        liquidityMathLib = _riveraLpStakingParams.liquidityMathLib;
        safeCastLib = _riveraLpStakingParams.safeCastLib;
        liquidityAmountsLib = _riveraLpStakingParams.liquidityAmountsLib;
        fullMathLib = _riveraLpStakingParams.fullMathLib;
        stake = _riveraLpStakingParams.stake;
        DexV3Calculations.checkTicks(0, 0, _riveraLpStakingParams.tickLower, _riveraLpStakingParams.tickUpper, tickMathLib, stake);
        tickLower = _riveraLpStakingParams.tickLower;
        tickUpper = _riveraLpStakingParams.tickUpper;
        poolFee = IPancakeV3Pool(stake).fee();
        lpToken0 = IPancakeV3Pool(stake).token0();
        lpToken1 = IPancakeV3Pool(stake).token1();
        (bool success, bytes memory data) = _commonAddresses.vault.call(abi.encodeWithSelector(bytes4(keccak256(bytes('asset()')))));
        require(success, "AF");
        depositToken = abi.decode(data, (address));
        assettoNativeFeed = _riveraLpStakingParams.assettoNativeFeed;
        vault = _commonAddresses.vault;
        router = _commonAddresses.router;
        NonfungiblePositionManager = _commonAddresses.NonfungiblePositionManager;

        withdrawFeeDecimals = _commonAddresses.withdrawFeeDecimals;
        withdrawFee = _commonAddresses.withdrawFee;

        slippage = _commonAddresses.slippage;
        slippageDecimals = _commonAddresses.slippageDecimals;
        _transferManagership(_commonAddresses.manager);
        _transferOwnership(_commonAddresses.owner);
        _giveAllowances();
    }

    function deposit() public virtual whenNotPaused {
        onlyVault();
        _deposit();
    }

    function _deposit() internal virtual {
        _swapAssetsToNewRangeRatio();
        _depositV3();
        IERC20(depositToken).safeTransfer(vault, _lptoDepositTokenSwap(IERC20(lpToken0).balanceOf(address(this)), IERC20(lpToken1).balanceOf(address(this))));
    }

    // puts the funds to work
    function _depositV3() internal {
        if (tokenID == 0) {         //Strategy does not have an active non fungible liquidity position
            _mintAndAddLiquidityV3();
        } else {
            _increaseLiquidity();
        }
    }

    function _mintAndAddLiquidityV3() internal {
        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        (uint256 tokenId, , , ) = INonfungiblePositionManager(
            NonfungiblePositionManager
        ).mint(
                INonfungiblePositionManager.MintParams(
                    lpToken0,
                    lpToken1,
                    poolFee,
                    tickLower,
                    tickUpper,
                    lp0Bal,
                    lp1Bal,
                    0,
                    0,
                    address(this),
                    block.timestamp
                )
            );
        tokenID = tokenId;
    }


    function _increaseLiquidity() internal {
        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        INonfungiblePositionManager(
            NonfungiblePositionManager
        ).increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    tokenID,
                    lp0Bal,
                    lp1Bal,
                    0,
                    0,
                    block.timestamp
                )
            );
    }

    function _burnAndCollectV3() internal nonReentrant  {
        uint128 liquidity = liquidityBalance();
        require(liquidity > 0, "No Liquidity available");
        INonfungiblePositionManager(NonfungiblePositionManager).collect(
            INonfungiblePositionManager.CollectParams(
                tokenID,
                address(this),
                type(uint128).max,
                type(uint128).max
            )
        );
       
        INonfungiblePositionManager(NonfungiblePositionManager)
            .decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams(
                    tokenID,
                    liquidity,
                    0,
                    0,
                    block.timestamp
                )
            );

        INonfungiblePositionManager(NonfungiblePositionManager).collect(
            INonfungiblePositionManager.CollectParams(
                tokenID,
                address(this),
                type(uint128).max,
                type(uint128).max
            )
        );
        INonfungiblePositionManager(NonfungiblePositionManager).burn(tokenID);
        tokenID = 0;
    }

    /// @dev Function to change the asset holding of the strategy contract to new ratio that is the result of change range
    function _swapAssetsToNewRangeRatio() internal {      //lib
        uint256 currAmount0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 currAmount1Bal = IERC20(lpToken1).balanceOf(address(this));
        (uint256 x, uint256 y) = DexV3Calculations.changeInAmountsToNewRangeRatio(LiquidityToAmountCalcParams(tickLower, tickUpper, 1e28, safeCastLib, sqrtPriceMathLib, tickMathLib, stake), 
        ChangeInAmountsForNewRatioParams(poolFee, currAmount0Bal, currAmount1Bal, fullMathLib));
        if (x!=0) {
            _swapV3In(lpToken0, lpToken1, x, poolFee);
        }
        if (y!=0) {
            _swapV3In(lpToken1, lpToken0, y, poolFee);
        }
    }

    //{-52050,-42800}
    function changeRange(int24 _tickLower, int24 _tickUpper) external virtual {
        _checkOwner();
        DexV3Calculations.checkTicks(tickLower, tickUpper, _tickLower, _tickUpper, tickMathLib, stake);
        _burnAndCollectV3();        //This will return token0 and token1 in a ratio that is corresponding to the current range not the one we're setting it to
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        _deposit();
        emit RangeChange(tickLower, tickUpper);
    }

    function _withdrawV3(uint256 _amount) internal returns (uint256 userAmount0,  uint256 userAmount1) {
        uint128 liquidityDelta = DexV3Calculations.calculateLiquidityDeltaForAssetAmount(LiquidityToAmountCalcParams(tickLower, tickUpper, 1e28, safeCastLib, sqrtPriceMathLib, tickMathLib, stake), 
        LiquidityDeltaForAssetAmountParams(depositToken == lpToken0, poolFee, _amount, fullMathLib, liquidityAmountsLib));
        uint128 liquidityAvlbl = liquidityBalance();
        if (liquidityDelta > liquidityAvlbl) {
            liquidityDelta = liquidityAvlbl;
        }
        IMasterChefV3(NonfungiblePositionManager).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(
                tokenID,
                liquidityDelta,
                0,
                0,
                block.timestamp
            )
        );

        (userAmount0, userAmount1) = IMasterChefV3(NonfungiblePositionManager).collect(INonfungiblePositionManager.CollectParams(
                tokenID,
                address(this),
                type(uint128).max,
                type(uint128).max
            ));
        
    }

    //here _amount is liquidity amount and not deposited token amount
    function withdraw(uint256 _amount) external virtual nonReentrant {
        onlyVault();
        (uint256 userAmount0, uint256 userAmount1) = _withdrawV3(_amount);
        uint256 withdrawAmount = _lptoDepositTokenSwap(userAmount0, userAmount1);
        IERC20(depositToken).safeTransfer(vault, withdrawAmount - withdrawAmount * withdrawFee / withdrawFeeDecimals);
        // IERC20(depositToken).safeTransfer(owner(),IERC20(depositToken).balanceOf(address(this)));
        IERC20(depositToken).safeTransfer(owner(),withdrawAmount * withdrawFee / withdrawFeeDecimals);
        emit Withdraw(balanceOf(), _amount);
    }

    function harvest() external virtual {
        _requireNotPaused();
        IMasterChefV3(NonfungiblePositionManager).collect(
            INonfungiblePositionManager.CollectParams(
                tokenID,
                address(this),
                type(uint128).max,
                type(uint128).max
            )
        );
        lastHarvest = block.timestamp;
        _deposit();
        emit StratHarvest(
                msg.sender,
                balanceOf()
            );
    }

  

    function _lptoDepositTokenSwap(uint256 amount0, uint256 amount1) internal returns (uint256 totalDepositAsset) {
        uint256 amountOut;
        if (depositToken != lpToken0) {
            if (amount0 != 0) {amountOut = _swapV3In(lpToken0, depositToken, amount0, poolFee);}
            totalDepositAsset = amount1 + amountOut;
        }

        if (depositToken != lpToken1) {
            if (amount1 != 0) {amountOut = _swapV3In(lpToken1, depositToken, amount1, poolFee);}
            totalDepositAsset = amount0 + amountOut;
        }
    }
   

    function setAssettoNativeFeed(address assettoNativeFeed_) external {
        onlyManager();
        require(assettoNativeFeed_!=address(0), "IA");
        emit AssetToNativeFeedChange(assettoNativeFeed, assettoNativeFeed_);
        assettoNativeFeed = assettoNativeFeed_;
    }

    function _swapV3In(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee
    ) internal returns (uint256 amountOut) {
        (uint160 sq0, , , , , , ) = IPancakeV3Pool(stake).slot0();
        uint160 sqrtPriceLimitX96 = getSqrtPriceLimitX96(sq0,tokenIn,slippage,slippageDecimals);// 1% is 100 sq1
        amountOut = IV3SwapRouter(router).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams(
                tokenIn,
                tokenOut,
                fee,
                address(this),
                amountIn,
                0,
                sqrtPriceLimitX96
            )   
        );
    }

    function getSqrtPriceLimitX96(uint160 sqrtPriceX96,address tokenIn, uint256 _slippageTolerance,uint256 _slippageDecimals) public virtual view returns(uint160){
        // (uint160 sqrtPriceX96, , , , , , ) = IPancakeV3Pool(pool).slot0();
        uint256 priceLimit; 
        if(_slippageDecimals==_slippageTolerance){
            return 0;
        }

        if(tokenIn==lpToken1){
            priceLimit =(sqrtPriceX96 * _slippageDecimals )/ (_slippageDecimals - _slippageTolerance);
        }else{
            priceLimit=(sqrtPriceX96 * (_slippageDecimals - _slippageTolerance)) / _slippageDecimals;
        }
        return(uint160(priceLimit)); 
    }

    function balanceOf() public view returns (uint256) {
        uint128 totalLiquidityDelta = liquidityBalance();
        (uint256 amount0, uint256 amount1) = DexV3Calculations.liquidityToAmounts(LiquidityToAmountCalcParams(tickLower, tickUpper, totalLiquidityDelta, safeCastLib, sqrtPriceMathLib, tickMathLib, stake));
        uint256 vaultReserve = IERC20(depositToken).balanceOf(vault);
        if (depositToken == lpToken0) {
            return amount0 + DexV3Calculations.convertAmount1ToAmount0(amount1, stake, fullMathLib) + vaultReserve;
        } else {
            return DexV3Calculations.convertAmount0ToAmount1(amount0, stake, fullMathLib) + amount1 + vaultReserve;
        }
    }

    function liquidityBalance() public view returns (uint128 liquidity) {
        if(tokenID==0){
            return 0;
        }else{
            (, , ,, ,,,  liquidity,,, ,  ) = INonfungiblePositionManager(NonfungiblePositionManager).positions(tokenID);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        onlyVault();
        _burnAndCollectV3();
        IERC20(depositToken).safeTransfer(vault, _lptoDepositTokenSwap(IERC20(lpToken0).balanceOf(address(this)), IERC20(lpToken1).balanceOf(address(this))));
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public {
        onlyManager();
        _burnAndCollectV3();
        IERC20(depositToken).safeTransfer(vault, _lptoDepositTokenSwap(IERC20(lpToken0).balanceOf(address(this)), IERC20(lpToken1).balanceOf(address(this))));
        pause();
    }

    function pause() public {
        onlyManager();
        _pause();

        _removeAllowances();
    }

    function unpause() external {
        onlyManager();
        _unpause();

        _giveAllowances();

        // deposit();
    }

    function _giveAllowances() internal virtual {
        IERC20(lpToken0).safeApprove(router, 0);
        IERC20(lpToken0).safeApprove(router, type(uint256).max);

        IERC20(lpToken1).safeApprove(router, 0);
        IERC20(lpToken1).safeApprove(router, type(uint256).max);

        IERC20(lpToken0).safeApprove(NonfungiblePositionManager, 0);
        IERC20(lpToken0).safeApprove(
            NonfungiblePositionManager,
            type(uint256).max
        );

        IERC20(lpToken1).safeApprove(NonfungiblePositionManager, 0);
        IERC20(lpToken1).safeApprove(
            NonfungiblePositionManager,
            type(uint256).max
        );
    }

    function _removeAllowances() internal virtual {
        IERC20(lpToken0).safeApprove(router, 0);
        IERC20(lpToken1).safeApprove(router, 0);
        IERC20(lpToken0).safeApprove(NonfungiblePositionManager, 0);
        IERC20(lpToken1).safeApprove(NonfungiblePositionManager, 0);
    }


    function setSlippage(uint256 _slippage) external {
        onlyManager();
        require(_slippage >= 0 && _slippage <= slippageDecimals, "Invalid slippage");
        emit SlippageChange(slippage, _slippage);
        slippage = _slippage;
    }

    function inCaseTokensGetStuck(address _token) external {
        onlyManager();
        require(_token != depositToken, "NT"); //Token must not be equal to address of stake currency
        uint256 amount = IERC20(_token).balanceOf(address(this)); //Just finding the balance of this vault contract address in the the passed token and transfers
        IERC20(_token).transfer(msg.sender, amount);
    }

}