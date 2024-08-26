pub mod jediswap;
pub mod erc20;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IArbitrageur<TContractState> {
    // Flash loan callback
    fn on_flash_loan(
        ref self: TContractState,
        sender: ContractAddress,
        asset: ContractAddress,
        amount: u256,
        data: Span<felt252>
    );

    // Does a multihop swap, where the output of each hop is passed as input of the
    // next swap
    fn multihop_swap(ref self: TContractState, path: Array<felt252>, amount: u256);

    // Get the owner of the bot, read-only (view) function
    fn get_owner(self: @TContractState) -> ContractAddress;
}

// https://github.com/vesuxyz/vesu-v1/blob/main/src/singleton.cairo
#[starknet::interface]
pub trait IVesu<TContractState> {
    fn flash_loan(
        ref self: TContractState,
        receiver: ContractAddress,
        asset: ContractAddress,
        amount: u256,
        is_legacy: bool,
        data: Span<felt252>
    );
}


#[starknet::contract]
pub mod arbitrage {
    use super::{IVesuDispatcherTrait, IVesuDispatcher};
    use super::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use super::jediswap::{
        IJediSwapV2SwapRouterDispatcher, IJediSwapV2SwapRouterDispatcherTrait, ExactInputParams
    };
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        vesu: IVesuDispatcher,
        jediswap: IJediSwapV2SwapRouterDispatcher,
        owner: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        vesu: ContractAddress,
        jediswap: ContractAddress
    ) {
        assert(!owner.is_zero(), 'owner is the zero address');
        let vesu = IVesuDispatcher { contract_address: vesu };
        self.vesu.write(vesu);
        let jediswap = IJediSwapV2SwapRouterDispatcher { contract_address: jediswap };
        self.jediswap.write(jediswap);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl ArbitrageImpl of super::IArbitrageur<ContractState> {
        fn on_flash_loan(
            ref self: ContractState,
            sender: ContractAddress,
            asset: ContractAddress,
            amount: u256,
            mut data: Span<felt252>
        ) {
            assert(get_contract_address() == sender, 'unauthorized');
            let vesu = self.vesu.read();
            assert(get_caller_address() == vesu.contract_address, 'unauthorized');
            let jediswap = self.jediswap.read();

            let params: ExactInputParams = Serde::deserialize(ref data)
                .expect('deserialize swap params');
            // Approve the router to spend token.
            // https://docs.jediswap.xyz/for-developers/jediswap-v1/smart-contract-integration/implement-a-swap#id-2.-approve
            let token = IERC20Dispatcher { contract_address: asset };
            token.approve(jediswap.contract_address, amount);
            let swapped = jediswap.exact_input(params);

            assert(swapped > amount, 'unprofitable swap');
            let owner = self.owner.read();

            // take profit to the owner
            token.transfer(owner, swapped - amount);
        }

        // https://book.cairo-lang.org/ch11-06-inlining-in-cairo.html
        #[inline(always)]
        fn multihop_swap(ref self: ContractState, path: Array<felt252>, amount: u256) {
            let owner = self.owner.read();
            assert(owner == get_caller_address(), 'unauthorized');
            assert(*path.at(0) == *path.at(path.len() - 2), 'the same token');

            let token = IERC20Dispatcher {
                contract_address: (*path.at(0)).try_into().expect('first token')
            };
            let vesu = self.vesu.read();
            // Allow Vesu to take back the loan
            token.approve(vesu.contract_address, amount);

            let args = ExactInputParams {
                path,
                recipient: owner,
                deadline: get_block_timestamp(),
                amount_in: amount,
                amount_out_minimum: amount,
            };

            let mut serialized: Array<felt252> = array![];

            Serde::serialize(@args, ref serialized);

            vesu
                .flash_loan(
                    get_contract_address(), token.contract_address, amount, false, serialized.span()
                );
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}
