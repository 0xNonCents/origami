#[starknet::contract]
mod ERC20 {
    use token::erc20::models::{ERC20Allowance, ERC20Balance, ERC20Meta};
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use token::erc20::interface;
    use integer::BoundedInt;
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address};
    use zeroable::Zeroable;


    #[storage]
    struct Storage {
        _world: ContractAddress,
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256
    }

    mod Errors {
        const APPROVE_FROM_ZERO: felt252 = 'ERC20: approve from 0';
        const APPROVE_TO_ZERO: felt252 = 'ERC20: approve to 0';
        const TRANSFER_FROM_ZERO: felt252 = 'ERC20: transfer from 0';
        const TRANSFER_TO_ZERO: felt252 = 'ERC20: transfer to 0';
        const BURN_FROM_ZERO: felt252 = 'ERC20: burn from 0';
        const MINT_TO_ZERO: felt252 = 'ERC20: mint to 0';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        world: ContractAddress,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        recipient: ContractAddress
    ) {
        self._world.write(world);
        self.initializer(name, symbol);
        self._mint(recipient, initial_supply);
    }

    //
    // External
    //

    #[abi(embed_v0)]
    impl ERC20MetadataImpl of interface::IERC20Metadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.get_meta().name
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.get_meta().symbol
        }

        fn decimals(self: @ContractState) -> u8 {
            18
        }
    }

    #[abi(embed_v0)]
    impl ERC20Impl of interface::IERC20<ContractState> {
        fn total_supply(self: @ContractState) -> u256 {
            self.get_meta().total_supply
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.get_balance(account).amount
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.get_allowance(owner, spender).amount
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            self._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let owner = get_caller_address();
            self
                .set_allowance(
                    ERC20Allowance { token: get_contract_address(), owner, spender, amount }
                );
            true
        }
    }

    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl of interface::IERC20CamelOnly<ContractState> {
        fn totalSupply(self: @ContractState) -> u256 {
            ERC20Impl::total_supply(self)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            ERC20Impl::balance_of(self, account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            ERC20Impl::transfer_from(ref self, sender, recipient, amount)
        }
    }

    #[abi(embed_v0)]
    fn increase_allowance(
        ref self: ContractState, spender: ContractAddress, added_value: u256
    ) -> bool {
        self.update_allowance(get_caller_address(), spender, 0, added_value);
        true
    }

    #[abi(embed_v0)]
    fn increaseAllowance(
        ref self: ContractState, spender: ContractAddress, addedValue: u256
    ) -> bool {
        increase_allowance(ref self, spender, addedValue)
    }

    #[abi(embed_v0)]
    fn decrease_allowance(
        ref self: ContractState, spender: ContractAddress, subtracted_value: u256
    ) -> bool {
        self.update_allowance(get_caller_address(), spender, subtracted_value, 0);
        true
    }

    #[abi(embed_v0)]
    fn decreaseAllowance(
        ref self: ContractState, spender: ContractAddress, subtractedValue: u256
    ) -> bool {
        decrease_allowance(ref self, spender, subtractedValue)
    }

    //
    // Internal
    //

    #[generate_trait]
    impl WorldInteractionsImpl of WorldInteractionsTrait {
        fn world(self: @ContractState) -> IWorldDispatcher {
            IWorldDispatcher { contract_address: self._world.read() }
        }

        fn get_meta(self: @ContractState) -> ERC20Meta {
            get!(self.world(), get_contract_address(), ERC20Meta)
        }

        // Helper function to update total_supply model
        fn update_total_supply(ref self: ContractState, subtract: u256, add: u256) {
            let mut meta = self.get_meta();
            // adding and subtracting is fewer steps than if
            meta.total_supply = meta.total_supply - subtract;
            meta.total_supply = meta.total_supply + add;
            set!(self.world(), (meta));
        }

        // Helper function for balance model
        fn get_balance(self: @ContractState, account: ContractAddress) -> ERC20Balance {
            get!(self.world(), (get_contract_address(), account), ERC20Balance)
        }

        fn update_balance(
            ref self: ContractState, account: ContractAddress, subtract: u256, add: u256
        ) {
            let mut balance: ERC20Balance = self.get_balance(account);
            // adding and subtracting is fewer steps than if
            balance.amount = balance.amount - subtract;
            balance.amount = balance.amount + add;
            set!(self.world(), (balance));
        }

        // Helper function for allowance model
        fn get_allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> ERC20Allowance {
            get!(self.world(), (get_contract_address(), owner, spender), ERC20Allowance)
        }

        fn update_allowance(
            ref self: ContractState,
            owner: ContractAddress,
            spender: ContractAddress,
            subtract: u256,
            add: u256
        ) {
            let mut allowance = self.get_allowance(owner, spender);
            // adding and subtracting is fewer steps than if
            allowance.amount = allowance.amount - subtract;
            allowance.amount = allowance.amount + add;
            self.set_allowance(allowance);
        }

        fn set_allowance(ref self: ContractState, allowance: ERC20Allowance) {
            assert(!allowance.owner.is_zero(), Errors::APPROVE_FROM_ZERO);
            assert(!allowance.spender.is_zero(), Errors::APPROVE_TO_ZERO);
            set!(self.world(), (allowance));
            self
                .emit_event(
                    Approval {
                        owner: allowance.owner, spender: allowance.spender, value: allowance.amount
                    }
                );
        }

        fn emit_event<
            S, impl IntoImp: traits::Into<S, Event>, impl SDrop: Drop<S>, impl SCopy: Copy<S>
        >(
            ref self: ContractState, event: S
        ) {
            self.emit(event);
            emit!(self.world(), event);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn initializer(ref self: ContractState, name: felt252, symbol: felt252) {
            let meta = ERC20Meta { token: get_contract_address(), name, symbol, total_supply: 0 };
            set!(self.world(), (meta));
        }

        fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            assert(!recipient.is_zero(), Errors::MINT_TO_ZERO);
            self.update_total_supply(0, amount);
            self.update_balance(recipient, 0, amount);
            self.emit_event(Transfer { from: Zeroable::zero(), to: recipient, value: amount });
        }

        fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), Errors::BURN_FROM_ZERO);
            self.update_total_supply(amount, 0);
            self.update_balance(account, amount, 0);
            self.emit_event(Transfer { from: account, to: Zeroable::zero(), value: amount });
        }

        fn _approve(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            self
                .set_allowance(
                    ERC20Allowance { token: get_contract_address(), owner, spender, amount }
                );
        }

        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), Errors::TRANSFER_FROM_ZERO);
            assert(!recipient.is_zero(), Errors::TRANSFER_TO_ZERO);
            self.update_balance(sender, amount, 0);
            self.update_balance(recipient, 0, amount);
            self.emit_event(Transfer { from: sender, to: recipient, value: amount });
        }

        fn _spend_allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            let current_allowance = self.get_allowance(owner, spender).amount;
            if current_allowance != BoundedInt::max() {
                self.update_allowance(owner, spender, amount, 0);
            }
        }
    }
}
