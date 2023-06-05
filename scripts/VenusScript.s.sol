// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@rivera/strategies/venus/interfaces/IVenusDistribution.sol";
import "@rivera/strategies/venus/interfaces/IVToken.sol";
import "@rivera/strategies/common/interfaces/IChainlinkPriceFeed.sol";

contract VenusScript is Script {
    uint256 public number;
    IVenusDistribution VenusDistribution =
        IVenusDistribution(0xfD36E2c2a6789Db23113685031d7F16329158384);

    address _wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address stabelcoinWhale = 0xc686D5a4A1017BC1B751F25eF882A16AB1A81B63;
    address _usdt = 0x55d398326f99059fF775485246999027B3197955;
    address _whaleUsdt = 0xc686D5a4A1017BC1B751F25eF882A16AB1A81B63;
    address _user = 0xbA79a22A4b8018caFDC24201ab934c9AdF6903d7;
    address vUSDT = 0xfD5840Cd36d94D7229439859C0112a4185BC0255;
    address vWBNB = 0xA07c5b74C9B40447a954e1466938b865b6BBea36;
    address vCAKE = 0x86aC3974e2BD0d60825230fa6F355fF11409df5c;
    address _cake = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address chainllinkBnb = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
    address chainlinkCake = 0xB6064eD41d4f67e353768aA239cA86f4F73665a1;

    function run() external {
        vm.startPrank(_whaleUsdt);
        IERC20(_usdt).transfer(_user, 42e18);
        //usdt balance before
        console.log("usdt balance before", IERC20(_usdt).balanceOf(_user));
        vm.stopPrank();
        vm.startPrank(_user);
        address[] memory markets = new address[](2);
        markets[0] = vUSDT;
        markets[1] = vCAKE;
        VenusDistribution.enterMarkets(markets);

        console.log("=====================Supply=====================");

        //mint
        IERC20(_usdt).approve(vUSDT, 10e18);
        IVToken(vUSDT).mint(10e18);

        //balance of underlying
        console.log(
            "balance of underlying",
            IVToken(vUSDT).balanceOfUnderlying(_user)
        );

        //call markets function
        (, uint256 collateralFactorMantissa, ) = VenusDistribution.markets(
            vUSDT
        );
        console.log("collateralFactorMantissa", collateralFactorMantissa);

        console.log("=====================Borrow=====================");

        (, uint256 borrowAble, ) = VenusDistribution.getAccountLiquidity(_user);

        console.log("borrowAble", borrowAble);

        //get bnb price
        (, int256 price, , , ) = IChainlinkPriceFeed(chainlinkCake)
            .latestRoundData();

        //get borrow amount
        uint256 borrowAmount = (borrowAble / uint256(price)) * 1e8;
        console.log("borrowAmount", borrowAmount);

        //borrow     20000000000000000 0.02 bnb
        console.log("=====================Borrow half=====================");

        uint result = IVToken(vCAKE).borrow(borrowAmount / 2);
        assert(result == 0);
        //balance of cake of user
        console.log("balance of cake of user", IERC20(_cake).balanceOf(_user));

        //borrow balance stored
        uint256 borrowBalanceStored = IVToken(vCAKE).borrowBalanceStored(_user);
        console.log("borrow balance stored", borrowBalanceStored);

        //borrow balance current
        uint256 borrowBalanceCurrent = IVToken(vCAKE).borrowBalanceCurrent(
            _user
        );
        console.log("borrow balance current", borrowBalanceCurrent);

        //borrow able after half borrow

        (, borrowAble, ) = VenusDistribution.getAccountLiquidity(_user);
        console.log("borrowAble after half borrow", borrowAble);

        console.log(
            "=====================Borrow half again====================="
        );
        result = IVToken(vCAKE).borrow(borrowAmount / 2);
        assert(result == 0);

        //borrow balance stored
        borrowBalanceStored = IVToken(vCAKE).borrowBalanceStored(_user);
        console.log("borrow balance stored", borrowBalanceStored);

        //borrow balance current
        borrowBalanceCurrent = IVToken(vCAKE).borrowBalanceCurrent(_user);
        console.log("borrow balance current", borrowBalanceCurrent);

        //borrow able after full borrow

        (, borrowAble, ) = VenusDistribution.getAccountLiquidity(_user);
        console.log("borrowAble after full borrow", borrowAble);

        //=====================Repay=====================
        //repay
        IERC20(_cake).approve(vCAKE, borrowBalanceStored);

        console.log("=====================Repay half=====================");
        IVToken(vCAKE).repayBorrow(borrowBalanceStored / 2);

        //borrow balance stored after repay
        uint256 borrowBalanceStoredAfterRepay = IVToken(vCAKE)
            .borrowBalanceStored(_user);
        console.log(
            "borrow balance stored after repay",
            borrowBalanceStoredAfterRepay
        );

        console.log("=====================Repay full=====================");

        IVToken(vCAKE).repayBorrow((2 ** 256) - 1);

        //borrow balance stored after repay
        borrowBalanceStoredAfterRepay = IVToken(vCAKE).borrowBalanceStored(
            _user
        );
        console.log(
            "borrow balance stored after repay",
            borrowBalanceStoredAfterRepay
        );

        console.log(
            "=====================Redeem/Withdraw full====================="
        );
        //balance of underlying
        uint balanceOfUnderlying = IVToken(vUSDT).balanceOfUnderlying(_user);
        console.log("balance of underlying", balanceOfUnderlying);
        //redeem underlying
        IVToken(vUSDT).redeemUnderlying(balanceOfUnderlying);

        //balance of user
        console.log("balance of user", IERC20(_usdt).balanceOf(_user));
    }
}
