use starknet::ContractAddress;
use ekubo::router_lite::{RouteNode, TokenAmount, Swap};

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

    // Does a multihop swap, where the output/input of each hop is passed as input/output of the
    // next swap Note to do exact output swaps, the route must be given in reverse
    fn multihop_swap(ref self: TContractState, route: Array<RouteNode>, token_amount: TokenAmount);

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
    use core::num::traits::Zero;
    use ekubo::router_lite::{RouteNode, TokenAmount};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        vesu: IVesuDispatcher,
        owner: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, vesu: ContractAddress) {
        let vesu = IVesuDispatcher { contract_address: vesu };
        self.vesu.write(vesu);
        assert(!owner.is_zero(), 'owner is the zero address');
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl ArbitrageImpl of super::IArbitrageur<ContractState> {
        fn on_flash_loan(
            ref self: ContractState,
            sender: ContractAddress,
            asset: ContractAddress,
            amount: u256,
            data: Span<felt252>
        ) {
            let vesu = self.vesu.read();
            assert(get_caller_address() == vesu.contract_address, 'unauthorized');
            assert(get_contract_address() == sender, 'unauthorized');

            // for testing purposes only
            let token_address = starknet::contract_address_const::<
                0x063d32a3fa6074e72e7a1e06fe78c46a0c8473217773e19f11d8c8cbfc4ff8ca
            >();
            let token = IERC20Dispatcher { contract_address: token_address };
            let balance = token.balanceOf(get_contract_address());
            assert(balance == amount, 'loan received');
        }

        // https://book.cairo-lang.org/ch11-06-inlining-in-cairo.html
        #[inline(always)]
        fn multihop_swap(
            ref self: ContractState, route: Array<RouteNode>, token_amount: TokenAmount
        ) {
            let owner = self.owner.read();
            assert(owner == get_caller_address(), 'unauthorized');
            let token = IERC20Dispatcher { contract_address: token_amount.token };
            // the direction of a swap doesn't matter for a loan
            // either we borrow an exact input (positive): our investment
            // or an exact output (negative): investment + returns
            let amount: u256 = token_amount.amount.mag.into();
            let vesu = self.vesu.read();
            token.approve(vesu.contract_address, amount);
            vesu
                .flash_loan(
                    get_contract_address(), token.contract_address, amount, false, array![].span()
                );
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}
