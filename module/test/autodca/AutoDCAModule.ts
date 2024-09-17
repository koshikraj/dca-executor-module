import { expect } from 'chai'
import { deployments, ethers } from 'hardhat'
import { impersonateAccount } from "@nomicfoundation/hardhat-network-helpers"
import { getTestSafe, getEntryPoint, getTestToken, getSafe7579, getAutoDCAExecutor, getSessionValidator, getTestVault } from '../utils/setup'
import { logGas } from '../../src/utils/execution'
import {
  buildUnsignedUserOpTransaction,
} from '../../src/utils/userOp'
import execSafeTransaction from '../utils/execSafeTransaction';
import { ZeroAddress } from 'ethers';
import { Hex, pad } from 'viem'

describe('Spendlimit session key - Basic tests', () => {
  const setupTests = deployments.createFixture(async ({ deployments }) => {
    await deployments.fixture()

    const [ user1, user2, relayer] = await ethers.getSigners()

    await impersonateAccount("0x958543756A4c7AC6fB361f0efBfeCD98E4D297Db");

    const mockAccount = await ethers.getImpersonatedSigner("0x958543756A4c7AC6fB361f0efBfeCD98E4D297Db");


    let entryPoint = await getEntryPoint()

    entryPoint = entryPoint.connect(relayer)
    const autoDCAExecutor = await getAutoDCAExecutor()
       
    const sessionValidator =  await getSessionValidator()
    const safe7579 = await getSafe7579()
    const testToken = await getTestToken("0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359") // USDC
    const testToken2 = await getTestToken("0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270") // WMATIC
    const testVault = await getTestVault("0x28F53bA70E5c8ce8D03b1FaD41E9dF11Bb646c36"); // WMATCI Vault


    const safe = await getTestSafe(user1, await safe7579.getAddress(), await safe7579.getAddress())

    return {
      testToken,
      testToken2,
      testVault,
      user1,
      user2,  
      safe,
      relayer,
      autoDCAExecutor,
      sessionValidator,
      safe7579,
      entryPoint,
      mockAccount
    }
  })


    it('should add a validator and execute DCA job', async () => {
      const { testVault, testToken, testToken2, user1, relayer, safe, autoDCAExecutor, sessionValidator, safe7579, entryPoint, mockAccount } = await setupTests()

      await entryPoint.depositTo(await safe.getAddress(), { value: ethers.parseEther('1.0') })

      const mockLimit = await testToken.balanceOf(await mockAccount.getAddress())
   
      await  testToken.connect(mockAccount).transfer(await safe.getAddress(), mockLimit)

      const abi = [
        'function executeJob(uint256 jobId) external',
      ]

     
      const execCallData = new ethers.Interface(abi).encodeFunctionData('executeJob', [0])
      const newCall = {target: await autoDCAExecutor.getAddress() as Hex, value: 0, callData: execCallData as Hex}


      const currentTime = Math.floor(Date.now()/1000)
      const sessionKeyData = { target: await autoDCAExecutor.getAddress(), funcSelector: execCallData.slice(0, 10), validAfter: 0, validUntil: currentTime + 100, active: true }
      const jobData = { token: await testToken.getAddress(), targetToken: await testToken2.getAddress(),  vault: await testVault.getAddress(), limitAmount: mockLimit, limitUsed: 0, validAfter: 0, validUntil: currentTime + 100, lastUsed: 0, refreshInterval: 0 }

      await execSafeTransaction(safe, await safe7579.initializeAccount.populateTransaction([], [], [], [], {registry: ZeroAddress, attesters: [], threshold: 0}));

      await execSafeTransaction(safe, {to: await safe.getAddress(), data:  ((await safe7579.installModule.populateTransaction(1, await sessionValidator.getAddress(), '0x')).data as string), value: 0})
      await execSafeTransaction(safe, {to: await safe.getAddress(), data:  ((await safe7579.installModule.populateTransaction(2, await autoDCAExecutor.getAddress(), '0x')).data as string), value: 0})
      await execSafeTransaction(safe, await autoDCAExecutor.createJob.populateTransaction(jobData))
      await execSafeTransaction(safe, await sessionValidator.enableSessionKey.populateTransaction(user1.address, sessionKeyData))

      

      const key = BigInt(pad(await sessionValidator.getAddress() as Hex, {
          dir: "right",
          size: 24,
        }) || 0
      )
      const currentNonce = await entryPoint.getNonce(await safe.getAddress(), key);

      let userOp = buildUnsignedUserOpTransaction(await safe.getAddress(), currentNonce, newCall)

      const typedDataHash = ethers.getBytes(await entryPoint.getUserOpHash(userOp))
      userOp.signature = await user1.signMessage(typedDataHash)
      
      await logGas('Execute UserOp without a prefund payment', entryPoint.handleOps([userOp], relayer))

      expect(await testToken.balanceOf(await safe.getAddress())).to.be.eq(ethers.parseEther('0'))
      expect(await testVault.balanceOf(await safe.getAddress())).to.be.not.eq(ethers.parseEther('0'))



    })

    // it('should execute multiple session key transaction within limit and after refresh interval', async () => {
    //   const { user1, user2, safe, spendLimitModule, safe7579, entryPoint, relayer } = await setupTests()

    //   await entryPoint.depositTo(await safe.getAddress(), { value: ethers.parseEther('1.0') })

    //   await user1.sendTransaction({ to: await safe.getAddress(), value: ethers.parseEther('1') })

    //   const abi = [
    //     'function execute(address sessionKey, uint256 sessionId, address to, uint256 value, bytes calldata data) external',
    //   ]

    //   const execCallData = new ethers.Interface(abi).encodeFunctionData('execute', [user1.address, 0, user1.address, ethers.parseEther('0.5'), '0x' as Hex])

    //   const newCall = {target: await spendLimitModule.getAddress() as Hex, value: 0, callData: execCallData as Hex}
     
    //   const currentTime = Math.floor(Date.now()/1000)
    //   const sessionData = {account: await safe.getAddress(), token: ZeroAddress,  validAfter: currentTime, validUntil: currentTime + 30, limitAmount: ethers.parseEther('0.5'), limitUsed: 0, lastUsed: 0, refreshInterval: 5 }


    //   await execSafeTransaction(safe, await safe7579.initializeAccount.populateTransaction([], [], [], [], {registry: ZeroAddress, attesters: [], threshold: 0}));

    //   await execSafeTransaction(safe, {to: await safe.getAddress(), data:  ((await safe7579.installModule.populateTransaction(1, await spendLimitModule.getAddress(), '0x')).data as string), value: 0})
    //   await execSafeTransaction(safe, {to: await safe.getAddress(), data:  ((await safe7579.installModule.populateTransaction(2, await spendLimitModule.getAddress(), '0x')).data as string), value: 0})
    //    await execSafeTransaction(safe, await spendLimitModule.addSessionKey.populateTransaction(user1.address, sessionData))
      

    //   const key = BigInt(pad(await spendLimitModule.getAddress() as Hex, {
    //       dir: "right",
    //       size: 24,
    //     }) || 0
    //   )
    //   let currentNonce = await entryPoint.getNonce(await safe.getAddress(), key);


    //   let userOp = buildUnsignedUserOpTransaction(await safe.getAddress(), currentNonce, newCall)

    //   let typedDataHash = ethers.getBytes(await entryPoint.getUserOpHash(userOp))
    //   userOp.signature = await user1.signMessage(typedDataHash)
      
    //   await logGas('Execute UserOp without a prefund payment', entryPoint.handleOps([userOp], relayer))
    //   expect(await ethers.provider.getBalance(await safe.getAddress())).to.be.eq(ethers.parseEther('0.5'))


    //     // Wait for 5 seconds for the next subscription interval
    //     await delay(5000);

    //   currentNonce = await entryPoint.getNonce(await safe.getAddress(), key);
    //   userOp = buildUnsignedUserOpTransaction(await safe.getAddress(), currentNonce, newCall)

    //   typedDataHash = ethers.getBytes(await entryPoint.getUserOpHash(userOp))
    //   userOp.signature = await user1.signMessage(typedDataHash)
      
    //   await logGas('Execute UserOp without a prefund payment', entryPoint.handleOps([userOp], relayer))
    //   expect(await ethers.provider.getBalance(await safe.getAddress())).to.be.eq(ethers.parseEther('0'))

    // })
  
})

function delay(timeout = 10000): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, timeout));
}