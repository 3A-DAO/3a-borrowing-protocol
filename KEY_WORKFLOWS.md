## Key Workflows

This guide explains two essential processes for interacting with the 3A Borrowing Protocol using blockchain scanners:

1. **For Borrowers**: Find your vault, repay debt, and withdraw collateral
2. **For Redeemers**: Find redeemable vaults and redeem your EURO3 for collateral

## For Borrowers: Repaying Debt and Withdrawing Collateral

If you have borrowed EURO3 against your collateral and want to repay your debt to retrieve your collateral, follow these steps:

### 1. Connect to the correct network in your wallet

The 3A Borrowing Protocol is deployed on:

- Linea Mainnet
- Polygon

Choose the appropriate network in your wallet where your vault exists.

### 2. Find your vault

1. Open the blockchain explorer for your network:

   - Linea: [Lineascan](https://lineascan.build/)
   - Polygon: [Polygonscan](https://polygonscan.com/)

2. Navigate to the VaultFactory contract:

   - Linea Mainnet: `0x65c6FD9B3a2A892096881e28f07c732ed128893E`
   - Polygon: `0x4760847023fa0833221ae76E01Db1E483A5D20e0`

3. Go to the "Read Contract" tab

4. Find the function `getVaultsByOwner` and enter your wallet address

5. Click "Query" to see your vaults listed

### 3. Check your vault's debt and collateral

1. Click on your vault address from the previous step

2. Go to the "Read Contract" tab for your vault

3. Check your current position:
   - Use `debt()` to see how much EURO3 you've borrowed
   - Use `collaterals()` to see the list of collateral tokens
   - For each collateral address, use `collateral(address)` to check the amount

### 4. Repay your debt

1. Get EURO3 tokens if you don't already have them

   - You can acquire them from DEXs or other sources

2. Approve the VaultFactory to spend your EURO3:

   - Go to the EURO3 token contract in the blockchain explorer
   - Navigate to the "Write Contract" tab
   - Connect your wallet
   - Find the `approve` function
   - Enter the VaultFactory address and the amount to approve (you can enter a large number for unlimited approval)
   - Click "Write" and confirm the transaction

3. Repay your debt:
   - Go back to the VaultFactory contract's "Write Contract" tab
   - Find the `repay` function
   - Enter your vault address and the debt amount to repay
   - Click "Write" and confirm the transaction

### 5. Withdraw your collateral

Once your debt is fully repaid:

1. Go to the VaultFactory contract's "Write Contract" tab

2. For standard ERC20 tokens:

   - Find the `removeCollateral` function
   - Enter your vault address, collateral token address, amount, and your wallet address
   - Click "Write" and confirm the transaction

3. For native tokens (ETH on Linea, MATIC on Polygon):
   - Find the `removeCollateralNative` function
   - Enter your vault address, amount, and your wallet address
   - Click "Write" and confirm the transaction

### 6. Close your vault (optional)

If you've repaid all debt and withdrawn all collateral:

1. Go to the VaultFactory contract's "Write Contract" tab
2. Find the `closeVault` function
3. Enter your vault address
4. Click "Write" and confirm the transaction

## For Redeemers: Finding and Redeeming Vaults with EURO3

If you hold EURO3 and want to redeem it for collateral at a discount, follow these steps:

### 1. Connect to the correct network in your wallet

Choose Linea Mainnet or Polygon, where you wish to perform redemptions.

### 2. Find redeemable vaults

1. Open the blockchain explorer for your network:

   - Linea: [Lineascan](https://lineascan.build/)
   - Polygon: [Polygonscan](https://polygonscan.com/)

2. Navigate to the VaultFactoryHelperV2 contract:

   - Linea Mainnet: `0xf4ed6867eb3080fff0c7f44ca57b3e48aca66295`
   - Polygon: `0x05c5cdd1e21f7879cc77044150902c0a99940d60`

3. Go to the "Read Contract" tab

4. Use the `getAllVaults` function with the VaultFactory address as parameter to get a list of all vaults

### 3. Check which vaults are redeemable

For each vault address from the previous step:

1. Go to the vault's contract page in the blockchain explorer

2. Check the vault's health factor:

   - Navigate to the "Read Contract" tab
   - Use the `healthFactor(true)` function
   - The vault is potentially redeemable if the health factor is below the redemption limit (100%)

3. Check if the vault has debt:

   - Use the `debt()` function
   - The vault needs to have debt greater than 0 to be redeemable

4. Check available collateral:

   - Use the `collaterals()` function to see what collateral tokens are in the vault

5. Verify if collateral is redeemable:
   - Go to the VaultFactory contract
   - Use the `isReedemable(address vault, address collateral)` function
   - Enter the vault address and collateral token address
   - If this returns true, the collateral can be redeemed

### 4. Calculate redemption amounts

For each redeemable vault and collateral:

1. Go to the vault's "Read Contract" tab

2. Find the `calcRedeem` function

3. Enter the collateral address and amount you want to redeem

4. This will return two values:
   - The amount of EURO3 needed for the redemption
   - The redemption fee amount

### 5. Execute the redemption

1. Make sure you have enough EURO3 tokens

2. Approve the VaultFactory to spend your EURO3:

   - Go to the EURO3 token contract
   - Find the `approve` function in the "Write Contract" tab
   - Enter the VaultFactory address and the amount (EURO3 needed + fee)
   - Click "Write" and confirm the transaction

3. Execute the redemption:
   - Go to the VaultFactory contract's "Write Contract" tab
   - Find the `redeem` function
   - Enter:
     - Vault address
     - Collateral token address
     - Collateral amount
     - Your wallet address (where to receive the collateral)
   - Click "Write" and confirm the transaction

## Understanding Redemption Eligibility

For a vault to be eligible for redemption:

- Its health factor must be below 100% (the redemption limit)
- It must have outstanding debt
- It must have collateral that can be redeemed

The system prioritizes redeeming collateral with the lowest minimum collateralization ratio (MCR) first.

## Notes and Considerations

- Redemptions are processed on a first-come, first-served basis
- The redemption mechanism is designed to maintain system solvency
- When redeeming, you're effectively paying off someone else's debt in exchange for their collateral at a discount
- Always verify gas costs before confirming transactions
- Consider using advanced tools from the 3A DAO if you plan to perform frequent redemptions
