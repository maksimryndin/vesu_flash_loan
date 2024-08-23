use snforge_std::{declare, ContractClassTrait, test_address};
use vesu_flash_loan::{
    arbitrage, IArbitrageurDispatcher, IArbitrageurDispatcherTrait,
    erc20::{IERC20Dispatcher, IERC20DispatcherTrait}
};
use starknet::{ContractAddress, contract_address_const};

// https://github.com/vesuxyz/changelog/blob/main/deployments/deployment_sn_sepolia.json
const VESU_SINGLETON_ADDRESS: felt252 =
    0x69d0eca40cb01eda7f3d76281ef524cecf8c35f4ca5acc862ff128e7432964b;
// https://docs.jediswap.xyz/for-developers/jediswap-v2/contract-addresses
const JEDISWAP_ROUTER_ADDRESS: felt252 =
    0x03c8e56d7f6afccb775160f1ae3b69e3db31b443e544e56bd845d8b3b3a87a21;

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

    let amount: u256 = 1000;
    // We can check the balance of Vesu in the explorer
    // https://sepolia.voyager.online/contract/0x063d32a3fa6074e72e7a1e06fe78c46a0c8473217773e19f11d8c8cbfc4ff8ca#readContract
    let balance = token.balanceOf(contract_address_const::<VESU_SINGLETON_ADDRESS>());
    assert(balance > amount.into(), 'amount fits');
    dispatcher.multihop_swap(array![token.contract_address.into()], token.contract_address, amount);
    let balance_after = token.balanceOf(test_address());
    assert_eq!(balance_after, 0);
}
// test_access (both methods)
// test_arbitrage

