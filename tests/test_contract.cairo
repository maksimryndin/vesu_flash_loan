use snforge_std::{declare, ContractClassTrait, test_address, start_cheat_caller_address};
use vesu_flash_loan::{
    arbitrage, IArbitrageurDispatcher, IArbitrageurDispatcherTrait,
    erc20::{IERC20Dispatcher, IERC20DispatcherTrait}
};
use starknet::{ContractAddress, contract_address_const};

// https://github.com/vesuxyz/changelog/blob/main/deployments/deployment_sn_main.json
// https://voyager.online/contract/0x02545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef
const VESU_SINGLETON_ADDRESS: felt252 =
    0x2545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef;
// https://docs.jediswap.xyz/for-developers/jediswap-v2/contract-addresses
// https://voyager.online/contract/0x0359550b990167afd6635fa574f3bdadd83cb51850e1d00061fe693158c23f80
const JEDISWAP_ROUTER_ADDRESS: felt252 =
    0x0359550b990167afd6635fa574f3bdadd83cb51850e1d00061fe693158c23f80;

fn declare_and_deploy() -> IArbitrageurDispatcher {
    // First declare and deploy a contract
    // (the name of the contract is the contract module name)
    let contract = declare("arbitrage").unwrap();
    // deploy function accepts a snap of an array of contract arguments serialized as felt252
    let (contract_address, _) = contract
        .deploy(@array![test_address().into(), VESU_SINGLETON_ADDRESS, JEDISWAP_ROUTER_ADDRESS])
        .unwrap();

    // Create a Dispatcher object that will allow interacting with the deployed contract
    IArbitrageurDispatcher { contract_address }
}

fn setup() -> (IArbitrageurDispatcher, IERC20Dispatcher, u256) {
    // we take one of the tokens supported by Vesu on Sepolia
    // https://github.com/vesuxyz/changelog/blob/main/deployments/deployment_sn_main.json
    let token_address = contract_address_const::<
        0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 // ETH
    >();

    let token = IERC20Dispatcher { contract_address: token_address };
    // We test a flash loan so the trader shouldn't have enough funds
    let balance_before = token.balanceOf(test_address());
    assert_eq!(balance_before, 0);

    let dispatcher = declare_and_deploy();
    assert_eq!(dispatcher.get_owner(), test_address());

    let amount: u256 = 1000;
    // We can check the balance of Vesu in the explorer
    // https://voyager.online/contract/0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7#readContract
    let balance = token.balanceOf(contract_address_const::<VESU_SINGLETON_ADDRESS>());
    assert(balance > amount.into(), 'amount fits');
    (dispatcher, token, amount)
}

#[should_panic(expected: ('unauthorized',))]
#[test]
#[fork("MAINNET_FORK")]
fn test_access_swap() {
    let (dispatcher, token, amount) = setup();
    let other_address = contract_address_const::<
        0x0576a87b1d9034d5d34a534c6151497dd1da44b986b1d94d0f42de317e1eef2c
    >();

    start_cheat_caller_address(dispatcher.contract_address, other_address);
    assert_ne!(other_address, test_address());
    assert_eq!(dispatcher.get_owner(), test_address());
    dispatcher.multihop_swap(array![token.contract_address.into()], amount);
}

#[should_panic(expected: ('unauthorized',))]
#[test]
#[fork("MAINNET_FORK")]
fn test_access_callback() {
    let (dispatcher, token, amount) = setup();
    let other_address = contract_address_const::<
        0x0576a87b1d9034d5d34a534c6151497dd1da44b986b1d94d0f42de317e1eef2c
    >();

    start_cheat_caller_address(dispatcher.contract_address, other_address);
    assert_ne!(other_address, test_address());
    assert_eq!(dispatcher.get_owner(), test_address());
    dispatcher.on_flash_loan(test_address(), token.contract_address, amount, array![].span());
}

#[should_panic(expected: ('Too little received',))]
#[test]
#[fork("MAINNET_FORK")]
fn test_arbitrage() {
    // we take one of the tokens supported by Vesu on Sepolia
    // https://github.com/vesuxyz/changelog/blob/main/deployments/deployment_sn_sepolia.json
    let (dispatcher, token, amount) = setup();
    // it is important to choose the first token among those supported by Vesu for flash loans
    // Swap via STRK
    dispatcher
        .multihop_swap(
            array![
                token.contract_address.into(),
                0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
                3000,
                0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
                token.contract_address.into(),
                3000
            ],
            amount
        );
    let balance_after = token.balanceOf(test_address());
    assert_eq!(balance_after, 0);
}
