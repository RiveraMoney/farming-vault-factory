pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/security/Pausable.sol";
import "@openzeppelin/security/ReentrancyGuard.sol";
import "@openzeppelin/proxy/utils/Initializable.sol";

import "../common/FeeManager.sol";

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router.sol";

struct CommonAddresses {
    address vault;
    address router;
    uint256 withdrawFeeDecimals;
    uint256 withdrawFee;
    uint256 feeDecimals;
    uint256 protocolFee;
    uint256 fundManagerFee;
    uint256 partnerFee;
    address partner;
    address manager;
    address owner;
}


struct RiveraLpStakingParams {
    address  depositToken;
    address  tokenB;
    address stake;
    address factory;
}

contract RiveraUniV2 is FeeManager ,ReentrancyGuard ,Initializable {
    using SafeERC20 for IERC20;

    address public depositToken;
    address public tokenB;

    address public stake;
    address public factory;



    function init(RiveraLpStakingParams memory _rivera_param ,CommonAddresses memory _commonAddresses ) public virtual initializer{
        depositToken = _rivera_param.depositToken;
        tokenB = _rivera_param.tokenB;
        stake = _rivera_param.stake;
        factory = _rivera_param.factory;

        
        vault = _commonAddresses.vault;
        router = _commonAddresses.router;

        withdrawFeeDecimals = _commonAddresses.withdrawFeeDecimals;
        withdrawFee = _commonAddresses.withdrawFee;
        feeDecimals = _commonAddresses.feeDecimals;
        protocolFee = _commonAddresses.protocolFee;
        fundManagerFee = _commonAddresses.fundManagerFee;
        partnerFee = _commonAddresses.partnerFee;
        partner = _commonAddresses.partner;

        _transferManagership(_commonAddresses.manager);
        _transferOwnership(_commonAddresses.owner);

        _giveAllowances();
    }


  function deposit() public whenNotPaused{
    onlyVault();
    _deposit();
  }
   
   function _deposit() internal {
    uint256 deposit_balance = IERC20(depositToken).balanceOf(address(this));
    _swapTokens(deposit_balance/2 ,depositToken , tokenB);
    _addLiquidity();
   }


  function withdraw(uint256 _amount) external nonReentrant {
        uint256 amountInLp = tokenToLpTokenConversion( depositToken,_amount);
        _removeLiquidity(amountInLp);
        uint256 amountinB = IERC20(tokenB).balanceOf(address(this));
        _swapTokens(amountinB,tokenB,depositToken);
        uint256 feeCharged = _chargeFees(depositToken);
        IERC20(depositToken).transfer(vault,_amount -feeCharged);
  }


   function balanceOf() public view returns(uint256) {
    uint256 tokenBinA = tokenAToTokenBConversion(tokenB , depositToken ,balanceOfB());
    return balanceOfA() + balanceOfLPinA()+ tokenBinA;
   }

   function balanceOfA() public view returns(uint256){
    return IERC20(depositToken).balanceOf(address(this));
   }

   function balanceOfB() public view returns(uint256){
    return IERC20(tokenB).balanceOf(address(this));
   }

   function balanceOfLP() public view returns(uint256){
    return IERC20(stake).balanceOf(address(this));
   }

   function balanceOfLPinA() public view returns(uint256){
    uint256 lpBalance = balanceOfLP();
    address token0 = IUniswapV2Pair(stake).token0();
    address token1 = IUniswapV2Pair(stake).token1();
    (uint256 balA , uint256 balB) = calculateAmounts(lpBalance);
    uint256 token0inA = tokenAToTokenBConversion(token0,depositToken,balA);
    uint256 token1inA = tokenAToTokenBConversion(token1,depositToken,balB);
    return token0inA + token1inA;
   }


   function _addLiquidity() internal {
        uint256 lp0Bal = IERC20(depositToken).balanceOf(address(this));
        uint256 lp1Bal = IERC20(tokenB).balanceOf(address(this));
        IUniswapV2Router(router).addLiquidity(
            depositToken,
            tokenB,
            lp0Bal,
            lp1Bal,
            1,
            1,
            address(this),
            block.timestamp
        );
    }


     function _removeLiquidity(uint256  _amount) internal {
        IUniswapV2Router(router).removeLiquidity(
            depositToken,
            tokenB,
            _amount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function arrangeTokens(
        address tokenX,
        address tokenY
    ) public pure returns (address, address) {
        return tokenX < tokenY ? (tokenX, tokenY) : (tokenY, tokenX);
    }

    function tokenAToTokenBConversion(
        address tokenX,
        address tokenY,
        uint256 amount
    ) public view returns (uint256) {
        if (tokenX == tokenY) {
            return amount;
        }
        address lpAddress = IUniswapV2Factory(factory).getPair(tokenX, tokenY);
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(lpAddress)
            .getReserves();
        (address token0, address token1) = arrangeTokens(tokenX, tokenY);
        return
            token0 == tokenX
                ? ((amount * _reserve1) / _reserve0)
                : ((amount * _reserve0) / _reserve1);
    }

    function calculateAmounts(uint256 liquidity) public view returns (uint256 amount0, uint256 amount1) {
        IUniswapV2Pair pair = IUniswapV2Pair(stake);

        // Get the reserves
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // Get the total supply of liquidity tokens
        uint256 totalSupply = pair.totalSupply();

        // Calculate the amounts to receive
        amount0 = liquidity * uint256(reserve0) / totalSupply;
        amount1 = liquidity * uint256(reserve1) / totalSupply;
    }


    function tokenToLpTokenConversion(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        uint256 amountInBase = tokenAToTokenBConversion(
            token,
            depositToken,
            amount
        );
        return baseTokenToLpTokenConversion(stake, amountInBase);
    }

    function baseTokenToLpTokenConversion(
        address lpToken,
        uint256 amount
    ) public view returns (uint256 lpTokenAmount) {
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(lpToken)
            .getReserves();
        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();
        uint256 reserve0InBaseToken = tokenAToTokenBConversion(
            token0,
            depositToken,
            _reserve0
        );
        uint256 reserve1InBaseToken = tokenAToTokenBConversion(
            token1,
            depositToken,
            _reserve1
        );

        uint256 lpTotalSuppy = IUniswapV2Pair(lpToken).totalSupply();
        return ((lpTotalSuppy * amount) /
            (reserve0InBaseToken + reserve1InBaseToken));
    }




   function _swapTokens(uint256 amountIn, address _tokenA , address _tokenB) internal {
        address[] memory path  = new address[](2);
        path[0] = _tokenA;
        path[1] = _tokenB;
        IUniswapV2Router(router).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

      function _chargeFees(address _token) internal returns(uint256 wFee) {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));

        uint256 protocolFeeAmount = (tokenBal * protocolFee) / feeDecimals;
        IERC20(_token).safeTransfer(manager, protocolFeeAmount);

        uint256 fundManagerFeeAmount = (tokenBal * fundManagerFee) /
            feeDecimals;
        IERC20(_token).safeTransfer(owner(), fundManagerFeeAmount);

        uint256 partnerFeeAmount = (tokenBal * partnerFee) / feeDecimals;
        IERC20(_token).safeTransfer(partner, partnerFeeAmount);

         wFee = (tokenBal * withdrawFee) / withdrawFeeDecimals;
        IERC20(_token).transfer(owner(), wFee);
    }

    function panic() public  {
        onlyManager();
        pause();
        _removeAllowances();
    }

    function pause() public {
        onlyManager();
        _pause();
        _removeAllowances();
    }

    function unpause() public {
        onlyManager();
        _giveAllowances();
    }


    function retireStrat() public {
        onlyVault();
        _removeAllowances();
    }


    function _giveAllowances() internal {
        IERC20(depositToken).approve(router , type(uint256).max);
        IERC20(tokenB).approve(router , type(uint256).max);
        IERC20(stake).approve(router , type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(depositToken).approve(router , 0);
        IERC20(tokenB).approve(router , 0);
        IERC20(stake).approve(router , 0);
    }


}