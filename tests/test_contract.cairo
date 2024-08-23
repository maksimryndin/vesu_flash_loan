use snforge_std::{declare, ContractClassTrait, test_address};
use vesu_flash_loan::{arbitrage, IArbitrageurDispatcher, IArbitrageurDispatcherTrait};
use starknet::{ContractAddress, contract_address_const};
use ekubo::router_lite::{RouteNode, TokenAmount, Swap};
use ekubo::types::i129::i129;
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

// https://github.com/vesuxyz/changelog/blob/main/deployments/deployment_sn_sepolia.json
const VESU_SINGLETON_ADDRESS: felt252 =
    0x69d0eca40cb01eda7f3d76281ef524cecf8c35f4ca5acc862ff128e7432964b;

fn declare_and_deploy() -> IArbitrageurDispatcher {
    // First declare and deploy a contract
    // (the name of the contract is the contract module name)
    let contract = declare("arbitrage").unwrap();
    // deploy function accepts a snap of an array of contract arguments serialized as felt252
    let (contract_address, _) = contract
        .deploy(@array![test_address().into(), VESU_SINGLETON_ADDRESS])
        .unwrap();

    // Create a Dispatcher object that will allow interacting with the deployed contract
    IArbitrageurDispatcher { contract_address }
}

#[test]
#[fork("SEPOLIA_FORK")]
fn test_flash_loan() {
    // we take one of the tokens supported by Vesu on Sepolia
    // https://github.com/vesuxyz/changelog/blob/main/deployments/deployment_sn_sepolia.json
    let token_address = contract_address_const::<
        0x063d32a3fa6074e72e7a1e06fe78c46a0c8473217773e19f11d8c8cbfc4ff8ca
    >();

    let token = IERC20Dispatcher { contract_address: token_address };
    // We test a flash loan so the trader shouldn't have enough funds
    let balance_before = token.balanceOf(test_address());
    assert_eq!(balance_before, 0);

    let dispatcher = declare_and_deploy();
    assert_eq!(dispatcher.get_owner(), test_address());

    let route = array![];
    let amount: u128 = 1000;
    // We can check the balance of Vesu in the explorer
    // https://sepolia.voyager.online/contract/0x063d32a3fa6074e72e7a1e06fe78c46a0c8473217773e19f11d8c8cbfc4ff8ca#readContract
    let balance = token.balanceOf(contract_address_const::<VESU_SINGLETON_ADDRESS>());
    assert(balance > amount.into(), 'amount fits');
    let token_amount = TokenAmount {
        token: token_address, amount: i129 { mag: amount, sign: false }
    };
    dispatcher.multihop_swap(route, token_amount);
    let balance_after = token.balanceOf(test_address());
    assert_eq!(balance_after, 0);
}
