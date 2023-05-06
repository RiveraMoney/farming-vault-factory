pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";
import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakePair.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IMasterChefV3.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "../common/AbstractStrategy.sol";
import "../utils/StringUtils.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

struct CakePoolParams {
    address stake;
    address chef;
    address[] rewardToLp0Route;
    address[] rewardToLp1Route;
    address depositToken;
    int24 tickLower;
    int24 tickUpper;
}
struct Range {
    int24 tickLower;
    int24 tickUpper;
}

contract CakeLpStakingV2 is AbstractStrategy, ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    // Tokens used
    address public reward;
    address public stake;
    address public lpToken0;
    address public lpToken1;
    address depositToken;
    address NonfungiblePositionManager =
        0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    uint256 public lastHarvest;
    string public pendingRewardsFunctionName;
    uint256 public tokenID;
    uint128 public Liquidity;
    uint256 rangeId;
    mapping(uint256 => Range) private ranges;

    // Routes
    address[] public rewardToLp0Route;
    address[] public rewardToLp1Route;

    //Events
    event StratHarvest(
        address indexed harvester,
        uint256 stakeHarvested,
        uint256 tvl
    );
    event Deposit(uint256 tvl, uint256 amount);
    event Withdraw(uint256 tvl, uint256 amount);

    ///@dev
    ///@param _cakePoolParams: Has the cake pool specific params
    ///@param _commonAddresses: Has addresses common to all vaults, check Rivera Fee manager for more info
    constructor(
        CakePoolParams memory _cakePoolParams, //["0x133B3D95bAD5405d14d53473671200e9342896BF","0x556B9306565093C855AEA9AE92A594704c2Cd59e",["0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82","0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"],["0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82","0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"],"0x55d398326f99059fF775485246999027B3197955",-54450,-41650]
        CommonAddresses memory _commonAddresses //["vault","0x10ED43C718714eb63d5aA57B78B54704E256024E"]
    ) AbstractStrategy(_commonAddresses) {
        stake = _cakePoolParams.stake;
        chef = _cakePoolParams.chef;
        depositToken = _cakePoolParams.depositToken;
        ranges[rangeId++] = Range(
            _cakePoolParams.tickLower,
            _cakePoolParams.tickUpper
        );

        address[] memory _rewardToLp0Route = _cakePoolParams.rewardToLp0Route;
        address[] memory _rewardToLp1Route = _cakePoolParams.rewardToLp1Route;

        reward = _rewardToLp0Route[0];

        // setup lp routing
        lpToken0 = IPancakePair(stake).token0();
        require(_rewardToLp0Route[0] == reward, "!rewardToLp0Route");
        // require(
        //     _rewardToLp0Route[_rewardToLp0Route.length - 1] == lpToken0,
        //     "!rewardToLp0Route"
        // );
        rewardToLp0Route = _rewardToLp0Route;

        lpToken1 = IPancakePair(stake).token1();
        require(_rewardToLp1Route[0] == reward, "!rewardToLp1Route");
        // require(
        //     _rewardToLp1Route[_rewardToLp1Route.length - 1] == lpToken1,
        //     "!rewardToLp1Route"
        // );
        rewardToLp1Route = _rewardToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public {
        onlyVault();
        userDepositSwap();
        _deposit();
    }

    //user stablecoin deposit swap
    function userDepositSwap() internal {
        uint256 stableCoinHalf = IERC20(depositToken).balanceOf(address(this)) /
            2;

        //Using Uniswap to convert half of the CAKE tokens into Liquidity Pair token 0
        if (depositToken != lpToken0) {
            address[] memory dTtolp0 = new address[](2);
            dTtolp0[0] = depositToken;
            dTtolp0[1] = lpToken0;

            IPancakeRouter02(router).swapExactTokensForTokens(
                stableCoinHalf,
                0,
                dTtolp0,
                address(this),
                block.timestamp
            );
        }

        if (depositToken != lpToken1) {
            //Using Uniswap to convert half of the CAKE tokens into Liquidity Pair token 1
            address[] memory dTtolp1 = new address[](2);
            dTtolp1[0] = depositToken;
            dTtolp1[1] = lpToken1;

            IPancakeRouter02(router).swapExactTokensForTokens(
                stableCoinHalf,
                0,
                dTtolp1,
                address(this),
                block.timestamp
            );
        }

        _mintAndAddLiquidityV3();
    }

    function _deposit() internal whenNotPaused nonReentrant {
        //Entire LP balance of the strategy contract address is deployed to the farm to earn CAKE
        INonfungiblePositionManager(NonfungiblePositionManager)
            .safeTransferFrom(address(this), chef, tokenID);
    }

    function burnAndCollectV3() internal nonReentrant {
        (uint256 liquidity, , , , , , , , ) = IMasterChefV3(chef)
            .userPositionInfos(tokenID);
        require(liquidity > 0, "No Liquidity available");
        IMasterChefV3(chef).withdraw(tokenID, address(this));

        (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(
            NonfungiblePositionManager
        ).decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams(
                    tokenID,
                    uint128(liquidity),
                    1,
                    1,
                    block.timestamp
                )
            );

        INonfungiblePositionManager(NonfungiblePositionManager).collect(
            INonfungiblePositionManager.CollectParams(
                tokenID,
                address(this),
                uint128(amount0),
                uint128(amount1)
            )
        );
        INonfungiblePositionManager(NonfungiblePositionManager).burn(tokenID);
    }

    //{-52050,-42800}
    function ChangeRange(int24 tickLower, int24 tickUpper) external {
        onlyManager();
        require(
            ranges[rangeId - 1].tickLower != tickLower &&
                ranges[rangeId - 1].tickUpper != tickUpper,
            "Range cannot be same"
        );
        burnAndCollectV3();
        ranges[rangeId++] = Range(tickLower, tickUpper);
        _mintAndAddLiquidityV3();
        _deposit();
    }

    //here _amount is liquidity amount and not deposited token amount
    function withdraw(uint256 _amount) external nonReentrant {
        onlyVault();
        //Pretty Straight forward almost same as AAVE strategy
        require(_amount <= Liquidity, "Amount is too large");

        (uint256 amount0, uint256 amount1) = IMasterChefV3(chef)
            .decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams(
                    tokenID,
                    uint128(_amount),
                    1,
                    1,
                    block.timestamp
                )
            );
        IMasterChefV3(chef).collect(
            INonfungiblePositionManager.CollectParams(
                tokenID,
                address(this),
                uint128(amount0),
                uint128(amount1)
            )
        );
        _lptoDepositTokenSwap();
        uint256 depositTokenBal = IERC20(depositToken).balanceOf(address(this));
        IERC20(depositToken).safeTransfer(vault, depositTokenBal);
        Liquidity = Liquidity - uint128(_amount);
        emit Withdraw(balanceOf(), _amount);
    }

    function beforeDeposit() external virtual {}

    function harvest() external virtual {
        _harvest();
    }

    function managerHarvest() external {
        onlyManager();
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        IMasterChefV3(chef).harvest(tokenID, address(this)); //it will transfer the CAKE rewards owed to the strategy.
        //This essentially harvests the yeild from CAKE.
        uint256 rewardBal = IERC20(reward).balanceOf(address(this)); //reward tokens will be CAKE. Cake balance of this strategy address will be zero before harvest.
        if (rewardBal > 0) {
            uint128 increasedLiquidity = addLiquidity(); //add liquidity to nfmanager and update liquidity at masterchef

            lastHarvest = block.timestamp;
            emit StratHarvest(
                msg.sender,
                uint256(increasedLiquidity),
                balanceOf()
            );
        }
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal returns (uint128) {
        //Should convert the CAKE tokens harvested into WOM and BUSD tokens and depost it in the liquidity pool. Get the LP tokens and stake it back to earn more CAKE.
        uint256 rewardHalf = IERC20(reward).balanceOf(address(this)) / 2; //It says IUniswap here which might be inaccurate. If the address is that of pancake swap and method signatures match then the call should be made correctly.
        if (lpToken0 != reward) {
            //Using Uniswap to convert half of the CAKE tokens into Liquidity Pair token 0
            IPancakeRouter02(router).swapExactTokensForTokens(
                rewardHalf,
                0,
                rewardToLp0Route,
                address(this),
                block.timestamp
            );
        }

        if (lpToken1 != reward) {
            //Using Uniswap to convert half of the CAKE tokens into Liquidity Pair token 1
            IPancakeRouter02(router).swapExactTokensForTokens(
                rewardHalf,
                0,
                rewardToLp1Route,
                address(this),
                block.timestamp
            );
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        (uint128 liquidity, , ) = INonfungiblePositionManager(
            NonfungiblePositionManager
        ).increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    tokenID,
                    lp0Bal,
                    lp1Bal,
                    1,
                    1,
                    block.timestamp
                )
            );
        IMasterChefV3(chef).updateLiquidity(tokenID);
        Liquidity = uint128(balanceOf());
        return liquidity;
    }

    function _mintAndAddLiquidityV3() internal {
        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        (uint256 tokenId, uint128 liquidity, , ) = INonfungiblePositionManager(
            NonfungiblePositionManager
        ).mint(
                INonfungiblePositionManager.MintParams(
                    lpToken0,
                    lpToken1,
                    2500,
                    ranges[rangeId - 1].tickLower, //
                    // -55600,//calxculated
                    ranges[rangeId - 1].tickUpper, //
                    // -41649,//calculated
                    lp0Bal,
                    lp1Bal,
                    1,
                    1,
                    address(this),
                    block.timestamp
                )
            );
        tokenID = tokenId;
        Liquidity = liquidity;
    }

    function _lptoDepositTokenSwap() internal {
        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        if (depositToken != lpToken0) {
            address[] memory lp0toDt = new address[](2);
            lp0toDt[0] = lpToken0;
            lp0toDt[1] = depositToken;

            IPancakeRouter02(router).swapExactTokensForTokens(
                lp0Bal,
                0,
                lp0toDt,
                address(this),
                block.timestamp
            );
        }

        if (depositToken != lpToken1) {
            //Using Uniswap to convert half of the CAKE tokens into Liquidity Pair token 1
            address[] memory lp1toDt = new address[](2);
            lp1toDt[0] = lpToken1;
            lp1toDt[1] = depositToken;

            IPancakeRouter02(router).swapExactTokensForTokens(
                lp1Bal,
                0,
                lp1toDt,
                address(this),
                block.timestamp
            );
        }
    }

    // calculate the total underlaying 'stake' held by the strat.
    function balanceOf() public view returns (uint256) {
        // return balanceOfStake() + balanceOfPool();
        return balanceOfPool();
    }

    // // it calculates how much 'stake' this contract holds.
    // function balanceOfStake() public view returns (uint256) {
    //     return IERC20(stake).balanceOf(address(this));
    // }

    // it calculates how much 'stake' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        //_amount is the LP token amount the user has provided to stake
        (uint256 liquidity, , , , , , , , ) = IMasterChefV3(chef)
            .userPositionInfos(tokenID);
        return liquidity;
    }

    // function setPendingRewardsFunctionName(
    //     string calldata _pendingRewardsFunctionName
    // ) external {
    //     onlyManager();
    //     //Interesting! function name that has to be used itself can be treated as an arguement
    //     pendingRewardsFunctionName = _pendingRewardsFunctionName;
    // }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        //Returns the rewards available to the strategy contract from the pool
        uint256 rewardsAvbl = IMasterChefV3(chef).pendingCake(tokenID);
        return rewardsAvbl;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        onlyVault();
        // IMasterChef(chef).emergencyWithdraw(poolId);
        burnAndCollectV3();
        _lptoDepositTokenSwap();
        uint256 depositTokenBal = IERC20(depositToken).balanceOf(address(this));
        IERC20(depositToken).safeTransfer(vault, depositTokenBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public {
        onlyManager();
        pause();
        burnAndCollectV3();
        _lptoDepositTokenSwap();
        uint256 depositTokenBal = IERC20(depositToken).balanceOf(address(this));
        IERC20(depositToken).safeTransfer(vault, depositTokenBal);
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

        // _deposit();
    }

    function _giveAllowances() internal {
        // IERC20(stake).safeApprove(chef, type(uint256).max);
        IERC20(reward).safeApprove(router, type(uint256).max);

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

        IERC20(depositToken).safeApprove(router, 0);
        IERC20(depositToken).safeApprove(router, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(stake).safeApprove(chef, 0);
        IERC20(reward).safeApprove(router, 0);
        IERC20(lpToken0).safeApprove(router, 0);
        IERC20(lpToken1).safeApprove(router, 0);
    }

    function rewardToLp0() external view returns (address[] memory) {
        return rewardToLp0Route;
    }

    function rewardToLp1() external view returns (address[] memory) {
        return rewardToLp1Route;
    }
}
