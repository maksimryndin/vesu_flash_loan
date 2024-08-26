use starknet::ContractAddress;

#[starknet::interface]
pub trait IJediSwapV2SwapRouter<TContractState> {
    fn exact_input(ref self: TContractState, params: ExactInputParams) -> u256;
}

// the order of arguments in path can be looked up at
// https://github.com/jediswaplabs/JediSwap-v2-periphery/blob/main/src/jediswap_v2_swap_router.cairo
// as slices of length 3 are deserialized into PathData struct
// in `_exact_input_internal` method
#[derive(Drop, Serde)]
pub struct ExactInputParams {
    pub path: Array<felt252>, //[token1, token2, fee1, token2, token3, fee2]
    pub recipient: ContractAddress,
    pub deadline: u64,
    pub amount_in: u256,
    pub amount_out_minimum: u256
}
