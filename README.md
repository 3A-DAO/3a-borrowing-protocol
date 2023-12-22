<center><img src="3alogo.png" width="150" height="150" alt="" /></center>

# 3A Borrowing Protocol

> [!NOTE]
> This repository contains the core smart contracts for the 3A DAO Borrowing Protocol.

The 3A Borrowing Protocol is an open-source project of the 3A DAO.
It's a DeFi protocol aiming to provide an over-collateralized EUR pegged stablecoin across the Ethereum ecosystem.

---

## Smart contracts

### A3A

> [!NOTE]  
> `A3A` is the 3A DAO utility token bridge from Ethereum to Polygon with a max supply of 1 Million and it is deployed under the A3A contract.

<details>
  <summary>A3A.sol</summary>

The `A3A` contract is an ERC20 token called the 3A Utility Token with a total fixed supply of 1 billion tokens. Upon deployment, the constructor mints the total supply to the contract deployer's address, setting up the token for usage within the Ethereum ecosystem.

- [Polygonscan](https://polygonscan.com/address/0x58c7B2828e7F2B2CaA0cC7fEef242fA3196d03df)
- [Etherscan](https://etherscan.io/address/0x3F817b28Da4940F018C6b5c0A11C555ebB1264f9)
</details>

<details>
  <summary>A3AStaking.sol</summary>

Stake A3A to get EURO3 rewards for paying your debt back from your vault.

- [Polygonscan](https://polygonscan.com/address/0x9b5089A5a48A8F3A7f8F5CB4837249787533f85A)
</details>

---

### EURO3

> [!NOTE]  
> `EURO3` is deployed under the MintableToken contract.

<details>
  <summary>MintableToken.sol</summary>

The `MintableToken` contract extends ERC20, implementing minting and burning functionalities for the contract owner. It features functions to mint tokens to designated addresses and burn tokens held by the message sender. Ownership control is ensured for minting operations.

- [Polygonscan](https://polygonscan.com/address/0xA0e4c84693266a9d3BBef2f394B33712c76599Ab)
</details>

<details>
  <summary>StabilityPool.sol</summary>

The `StabilityPool` contract allows users to deposit EURO3, pay other vault´s debt back when liquidation and get the collateral from those users with more value than the debt they are paying back.

Meanwhile, the depositors will get rewarded with A3A based on the amount they have deposited.

- [Polygonscan](https://polygonscan.com/address/0xDFf76acD594101fB5e9FaE176aEDb21A7a1Fe39F)
</details>

<details>
  <summary>MintableTokenOwner.sol</summary>

The `MintableTokenOwner` contract will maintain the privileges of who can mint more EURO3 tokens and it will work as a middleware for allowing or refusing new EURO3 minted.

- [Polygonscan](https://polygonscan.com/address/0xB3857F86A95516902C953D530D3E5C29B1518a85)
</details>

---

### Vaults

> [!TIP]  
> You can check all the openned vaults in our open [API](https://api.3adao.org/vaults).

<details>
  <summary>VaultFactoryZapper.sol</summary>

The `VaultFactoryZapper` contract facilitates the creation of Vaults with collateral and borrowing capabilities. It integrates with VaultFactory to generate and manage custom-named Vaults based on user-defined prefixes. The contract supports collateral deposits, borrowing against collateral, and Ether-based collateral creation for Vaults.

- [Polygonscan](https://polygonscan.com/address/0x8e83CA66Ec901E16BdAf137aC9eD7553E4dD95D3)
</details>

<details>
  <summary>VaultFactory.sol</summary>

The `VaultFactory` contract facilitates the creation, management, and liquidation of Vaults. It enables users to create Vaults, add/remove collateral, borrow funds, and manage debt, with features including collateral redemption and liquidation checks based on health factors. Additionally, it incorporates native and custom tokens as collateral, offering functionality to transfer ownership and repay borrowed amounts.

- [Polygonscan](https://polygonscan.com/address/0x4760847023fa0833221ae76E01Db1E483A5D20e0)
</details>

<details>
  <summary>Vault.sol</summary>

The `Vault` contract manages collateral, debt, and borrowable amounts, allowing collateral addition/removal, borrowing, and redemption. It calculates health factors based on collateralization ratios and facilitates collateral liquidation for debt recovery.

</details>

<details>
  <summary>VaultBorrowRate.sol</summary>
The `VaultBorrowRate` contract calculates the overall borrow rate for a given Vault based on its collateral types and respective borrow rates. It fetches collateral details via interfaces, computes collateral values, and aggregates weighted fees to determine the final borrow rate returned as a percentage.

- [Polygonscan](https://polygonscan.com/address/0x1E7224703E1B289e06F0Ff12519685fCf8E9306c)
</details>

<details>
  <summary>VaultDeployer.sol</summary>

The `VaultDeployer` contract deploys new instances of the Vault contract, facilitating the creation of vaults with specified factory, owner, and name parameters. It includes a single function deployVault to create and return the address of the newly deployed Vault instance.

- [Polygonscan](https://polygonscan.com/address/0x244dce725005bfffdeee080d10ef40c75f8233f0)
</details>

<details>
  <summary>VaultFactoryHelper.sol</summary>

The `VaultFactoryHelper` contract aids in retrieving data about vaults within a factory, including TVL by collateral, liquidatable and redeemable vaults, and the protocol's total TVL. It provides functions to fetch collaterals held by vaults, assess TVL based on collateral, and identify vaults based on their liquidatable or redeemable status.

- [Polygonscan](https://polygonscan.com/address/0x905784CA5246f48e8DFAF1888f9b45DCD3F11d54)
</details>

<details>
  <summary>VaultFactoryConfig.sol</summary>

The `VaultFactoryConfig` contract defines the protocol parameters. Manages protocol parameters, setting rates, limits, and recipients, also modifying collateral capacities, debt limits, and protocol addresses while providing methods for setting rates, addresses, and ceiling values.

- [Polygonscan](https://polygonscan.com/address/0x2c2abDb364659091401a667a72dE7Fe36c540E71)
</details>

---

### Liquidation & Redemption Management

> [!NOTE]  
> This section will take care of the liquidation & Redemption flow. Every time a liquidation or redemption happens, the same value will be burnt in EURO3.

<details>
  <summary>LiquidationRouter.sol</summary>

The `LiquidationRouter` acts as a crucial gateway for the liquidation process. It coordinates between the Stability Pool and the vaults, initiating auctioning if the Stability Pool lacks EURO3 and executes liquidation when sufficient EURO3 exists in the Stability Pool.

- [Polygonscan](https://polygonscan.com/address/0x00ff66600b35428b8eb76dc622d404c7ac27a99f)

</details>

<details>
  <summary>AuctionManager.sol</summary>

The `AuctionManager` smart contract facilitates auctions to liquidate debt against collateral, managing auction creation, bids, and liquidation thresholds. It allows bids based on collateral value, and upon auction end or expiration, transfers bids to the `LastResortLiquidation` contract for debt settlement.

- [Polygonscan](https://polygonscan.com/address/0x7aFB2EBD975345DfAC950b924fb32B757da0Fc93)

</details>

<details>
  <summary>LastResortLiquidation.sol</summary>

The `LastResortLiquidation` contract serves as a control mechanism for collateral and debt handling in liquidation scenarios. It manages various functionalities including collateral addition and withdrawal, tracks and handles bad debt, and allows permission-based distribution to designated vaults, ensuring controlled access and management of assets during liquidation events.

- [Polygonscan](https://polygonscan.com/address/0x65c6fd9b3a2a892096881e28f07c732ed128893e)

</details>

---

### Bots

<details>
  <summary>VaultOptimizerBot.sol</summary>

The `VaultOptimizerBot` streamlines vault actions, enabling borrowing and depositing tokens into a Stability Pool, withdrawal and repayment from vaults, and secure token transfers to respective vault owners. It interfaces with multiple contracts to efficiently execute these operations while maintaining security and reliability.

- _Not deployed yet_

</details>

---

### Governance

<details>
  <summary>OwnerProxy.sol</summary>

The `OwnerProxy` contract facilitates the main owner's control over finely-grained permissions for specific callers to execute functions on designated addresses. Through permission management, it allows addition and removal of permissions, enabling authorized callers to execute functions on specified addresses, all while using cryptographic hashes for permission validation and emitting events for permission changes and function executions.

- _Not deployed yet_

</details>

---

### Oracles

> [!NOTE]  
> Oracle flow to retrieve price feeds for `EURO3` & whitelisted assets such as `USDC.e, WETH, WMATIC, QNT and more`.

<details>
  <summary>TokenToPriceFeed.sol</summary>

The `TokenToPriceFeed` contract manages token-to-price-feed mappings, enabling the owner to set/update price feed contracts for tokens. It provides functions to retrieve token prices, collateral ratios, and borrow rates while ensuring constraints on ratios and rates. The contract implements an interface (`ITokenPriceFeed`) to access token-related information. `TokenToPriceFeed can handle token prices such as USDC.e, WETH, WMATIC, QNT and more.`

- [Polygonscan](https://polygonscan.com/address/0xfBC5cfEb809c6352Bc4ef2FFe842f72a8769E45e)
</details>

<details>
  <summary>ChainlinkPriceFeed.sol</summary>

The `ChainlinkPriceFeed` contract integrates with Chainlink oracles to fetch and manage up-to-date token prices. It uses precision settings, monitors price updates, and emits signals when price changes occur for associated tokens. `It will track the price of EUR/USD`.

- [Polygonscan](https://polygonscan.com/address/0x2c2abDb364659091401a667a72dE7Fe36c540E71)
</details>

<details>
  <summary>ConvertedPriceFeed.sol</summary>

The `ConvertedPriceFeed` contract integrates two price feed contracts to convert prices and emits signals based on the converted price for a specific token. It allows retrieving the converted price to EURO3 and emits updates accordingly.

ConvertedPriceFeed contracts deployed for each token:

- USDC.e: [Polygonscan](https://polygonscan.com/address/0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174)
- DAI: [Polygonscan](https://polygonscan.com/address/0x045d6078DD0d2436B67bc4050AB8F2a7E7e9B03c)
- WETH: [Polygonscan](https://polygonscan.com/address/0xcFD9c639E84DCB9D8B9004840f12381E540d57Fb)
- WMATIC: [Polygonscan](https://polygonscan.com/address/0x99782c90eAA2B9aB311AAa7F928322F23FfAf71B)
- PAXG: [Polygonscan](https://polygonscan.com/address/0x0B1d4D9F953c4113A8784f5527cf63E347C3F876)
- QNT: [Polygonscan](https://polygonscan.com/address/0xD78fF234A0d5ddea664f4478D72B621715EF03E5)

</details>

---

### Utils

> [!NOTE]
> Utils are smart contracts & libraries used within the system to enhance functionality and provide reusable code for various operations.

<details>
  <summary>Constants.sol</summary>

The `Constants` contract encapsulates declarations for various constants used in precision, reserves, percentages, and rates without explicitly listing the constant values in this summary.

</details>

<details>
  <summary>LinkedAddressList.sol</summary>

The `LinkedAddressList` library implements a linked list structure for managing sorted Troves and provides functionality to add and remove elements within the list.

</details>

<details>
  <summary>PoolAddress.sol</summary>

The `PoolAddress` library contains functions to generate a pool address using the Uniswap V3 factory contract, tokens, and fee details. It includes logic to create a deterministic pool address based on the PoolKey structure and the factory contract's initialization code hash.

</details>

<details>
  <summary>BONQMath.sol</summary>

The `BONQMath` library offers essential mathematical functions with precise decimal calculations, including min, max, and an optimized exponentiation algorithm tailored for time in minutes.

</details>

## Environment Setup

1. **Node Version Manager (NVM)**

   - If you haven't installed NVM, please visit [NVM GitHub page](https://github.com/nvm-sh/nvm) and follow the instructions.
   - Set up the correct Node.js version by running `nvm use` command in the root of the project. Make sure the project's `.nvmrc` file specifies the correct Node.js version.

2. **Node Package Manager (NPM)**

   - Install project dependencies by running `npm install` command in the root of the project.

3. **Environment Variables**
   - Set up the environment variables as shown in the `.env.example` file. Copy the `.env.example` file and rename it to `.env`. Then, replace the placeholders with your actual values.

## Running Tests

Tests are an essential part of this project. They ensure that the current functionality works as expected and helps to prevent regressions when new features are developed.

To run the tests, execute the following command in the root of the project:

```shell
# compile solidity code and generate typings
npx hardhat compile
# normal tests
npx hardhat test
# tests with traces
npx hardhat test --traces
```

## License

This project is licensed under the [Business Source License 1.1](LICENSE.md) - see the [LICENSE.md](LICENSE.md) file for details.
