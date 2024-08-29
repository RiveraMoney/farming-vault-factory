pragma solidity ^0.8.0;

import './RiveraLpStakingVaultCreationStruct.sol';
import '@rivera/strategies/staking/RiveraConcNoStaking.sol';

contract RiveraALMStrategyFactory {

    function createStrat(RiveraVaultParams memory createVaultParams, address vaultAddress, address user, address manager, address router, address nonfungiblePositionManager, /*address chef, */
    FeeParams memory feeParams) external returns (address) {
        RiveraConcNoStaking strategy = new RiveraConcNoStaking();
        // strategy.init(RiveraLpStakingParams(createVaultParams.tickLower, createVaultParams.tickUpper, createVaultParams.stake, chef, createVaultParams.rewardToLp0AddressPath[0], createVaultParams.tickMathLib, 
        // createVaultParams.sqrtPriceMathLib, createVaultParams.liquidityMathLib, createVaultParams.safeCastLib, createVaultParams.liquidityAmountsLib, createVaultParams.fullMathLib, 
        // createVaultParams.rewardToLp0AddressPath, createVaultParams.rewardToLp0FeePath, createVaultParams.rewardToLp1AddressPath, createVaultParams.rewardToLp1FeePath, 
        // createVaultParams.rewardtoNativeFeed, createVaultParams.assettoNativeFeed,createVaultParams.pendingReward), CommonAddresses(vaultAddress, router, nonfungiblePositionManager, feeParams.withdrawFeeDecimals, 
        // feeParams.withdrawFee, feeParams.feeDecimals, feeParams.protocolFee, feeParams.fundManagerFee, feeParams.partnerFee, feeParams.partner,manager,user));

        strategy.init(RiveraLpStakingParams(createVaultParams.tickLower, createVaultParams.tickUpper, createVaultParams.stake, createVaultParams.tickMathLib, 
        createVaultParams.sqrtPriceMathLib, createVaultParams.liquidityMathLib, createVaultParams.safeCastLib, createVaultParams.liquidityAmountsLib, createVaultParams.fullMathLib, createVaultParams.assettoNativeFeed), CommonAddresses(vaultAddress, router, nonfungiblePositionManager, feeParams.withdrawFeeDecimals, 
        feeParams.withdrawFee, feeParams.feeDecimals, feeParams.protocolFee, feeParams.fundManagerFee, feeParams.partnerFee, feeParams.partner,manager,user));
        return address(strategy);
    }

}
