import chai from 'chai'
import { solidity } from 'ethereum-waffle'
import { BigNumberish, Signer } from 'ethers'
import hre from 'hardhat'
import moment from 'moment'

import { getMarkets, getNFT } from '../../config'
import { claimNFT } from '../../tasks'
import { Market } from '../../types/custom/config-types'
import {
  ERC20,
  ITellerDiamond,
  ITellerNFT,
  ITToken,
  TellerNFT,
} from '../../types/typechain'
import { CacheType, LoanStatus } from '../../utils/consts'
import { fundedMarket } from '../fixtures'
import { getFunds } from '../helpers/get-funds'
import {
  createLoan,
  CreateLoanReturn,
  loanHelpers,
  LoanHelpersReturn,
  LoanType,
} from '../helpers/loans'

chai.should()
chai.use(solidity)

const { getNamedSigner, getNamedAccounts, contracts, ethers, evm, toBN } = hre

describe('Loans', () => {
  getMarkets(hre.network).forEach(testLoans)

  function testLoans(market: Market): void {
    let deployer: Signer
    let diamond: ITellerDiamond
    let lendingToken: ERC20
    let prevHelpers: LoanHelpersReturn

    before(async () => {
      // Get a fresh market
      await hre.deployments.fixture(['markets', 'nft'])

      deployer = await getNamedSigner('deployer')
      diamond = await contracts.get<ITellerDiamond>('TellerDiamond')
      lendingToken = await hre.tokens.get(market.lendingToken)

      // Fund the market
      await fundedMarket({ assetSym: market.lendingToken })
    })

    interface CreateArgs {
      amount: BigNumberish
      borrower: string
      loanType: LoanType
    }
    const create = async (args: CreateArgs): Promise<CreateLoanReturn> => {
      const { amount, borrower, loanType } = args
      return await createLoan({
        lendTokenSym: market.lendingToken,
        collTokenSym: market.collateralTokens[0],
        amount,
        borrower,
        loanType,
      })
    }

    it('should be able to take out a loan with collateral', async () => {
      const revert = await evm.snapshot()

      const { borrower } = await getNamedAccounts()
      const amount = toBN(100, await lendingToken.decimals())

      // Create loan
      const { getHelpers } = await create({
        amount,
        borrower,
        loanType: LoanType.OVER_COLLATERALIZED,
      })
      const helpers = await getHelpers()

      // Deposit collateral needed
      await helpers.collateral.deposit()
      // .should.emit(diamond, 'CollateralDeposited')
      // .withArgs(loanID, borrowerAddress, collateralNeeded)

      // Advance time
      await evm.advanceTime(moment.duration(5, 'minutes'))

      // Take out loan
      await helpers
        .takeOut()
        .should.emit(helpers.diamond, 'LoanTakenOut')
        .withArgs(helpers.details.loan.id, borrower, amount)

      const { loan: updatedLoan } = await helpers.details.refresh()
      updatedLoan.status.should.eq(LoanStatus.Active)

      await revert()
    })

    it('should not be able to take out a loan without collateral', async () => {
      // Skip ahead a day to avoid request rate limit
      await evm.advanceTime(moment.duration(1, 'day'))

      const { borrower } = await getNamedAccounts()
      const amount = toBN(100, await lendingToken.decimals())

      // Create loan with terms without depositing collateral
      const { getHelpers } = await create({
        amount,
        borrower,
        loanType: LoanType.OVER_COLLATERALIZED,
      })
      const helpers = await getHelpers()
      prevHelpers = helpers

      // Try to take out loan which should fail
      await helpers
        .takeOut()
        .should.be.revertedWith('Teller: more collateral required')

      const { loan: updatedLoan } = await helpers.details.refresh()
      updatedLoan.status.should.eq(LoanStatus.TermsSet)
    })

    it('should be able to deposit collateral, takeout and repay previous loan', async () => {
      const { diamond, details, takeOut, repay, collateral } = prevHelpers

      // Deposit collateral
      await collateral.deposit()

      // Advance time
      await evm.advanceTime(moment.duration(5, 'minutes'))

      // Take out loan
      await takeOut()
        .should.emit(diamond, 'LoanTakenOut')
        .withArgs(
          details.loan.id,
          details.loan.loanTerms.borrower,
          details.loan.loanTerms.maxLoanAmount
        )

      // Get updated loan details after loan is taken out
      const { loan: updatedLoan } = await details.refresh()
      updatedLoan.status.should.eq(LoanStatus.Active)

      // Repay full amount
      const amountToRepay = updatedLoan.principalOwed.add(
        updatedLoan.interestOwed
      )

      // Get the funds to pay back the interest
      await getFunds({
        tokenSym: market.lendingToken,
        to: details.borrower.address,
        amount: updatedLoan.interestOwed,
      })

      // Approve loan repayment
      await lendingToken
        .connect(details.borrower.signer)
        .approve(diamond.address, amountToRepay)

      // Repay loan
      await repay(amountToRepay, details.borrower.signer)
        .should.emit(diamond, 'LoanRepaid')
        .withArgs(
          details.loan.id,
          details.borrower.address,
          amountToRepay,
          details.borrower.address,
          '0'
        )

      const { loan: repaidLoan } = await details.refresh()
      repaidLoan.status.should.eq(LoanStatus.Closed)
    })

    it('should be able to take out a loan with an NFT', async () => {
      const revert = await evm.snapshot()

      // Setup for NFT user
      const { merkleTrees } = getNFT(hre.network)
      const merkleIndex = 0
      const borrower = ethers.utils.getAddress(
        merkleTrees[merkleIndex].balances[0].address
      )
      const imp = await evm.impersonate(borrower)
      await diamond.connect(deployer).addAuthorizedAddress(borrower)

      // Claim user's NFTs
      await claimNFT({ address: borrower, merkleIndex }, hre)

      // Get the sum of loan amount to take out
      const nft = await contracts.get<TellerNFT>('TellerNFT')
      const ownedNFTs = await nft.getOwnedTokens(borrower)
      let amount = toBN(0)
      for (const nftID of ownedNFTs) {
        const { tier_ } = await nft.getTokenTier(nftID)
        amount = amount.add(
          toBN(tier_.baseLoanSize, await lendingToken.decimals())
        )
      }
      console.log('nft total amount', amount.toString())

      await nft
        .connect(imp.signer)
        .setApprovalForAll(diamond.address, true)
        .then(({ wait }) => wait())
      await diamond
        .connect(imp.signer)
        .stakeNFTs(ownedNFTs)
        .then(({ wait }) => wait())

      // Create loan
      const { getHelpers } = await create({
        amount,
        borrower,
        loanType: LoanType.ZERO_COLLATERAL,
      })
      const { details } = await getHelpers()

      // Take out loan
      await diamond
        .connect(imp.signer)
        .takeOutLoanWithNFTs(details.loan.id, amount, ownedNFTs)
        .should.emit(diamond, 'LoanTakenOut')
        .withArgs(details.loan.id, borrower, amount)

      const { loan: updatedLoan } = await details.refresh()
      updatedLoan.status.should.eq(LoanStatus.Active)

      await imp.stop()
      await revert()
    })

    it('should not be able to take out with invalid debt ratio', async () => {
      // Skip ahead a day to avoid request rate limit
      await evm.advanceTime(moment.duration(1, 'day'))

      const revert = await evm.snapshot()

      // Update debt ratio as deployer
      await diamond.connect(deployer).updateAssetSetting(lendingToken.address, {
        key: ethers.utils.id('MaxDebtRatio'),
        value: ethers.utils.hexZeroPad(ethers.utils.hexlify(0), 32),
        cacheType: CacheType.Uint,
      })

      const amount = toBN(100000, await lendingToken.decimals())
      const { borrower } = await getNamedAccounts()

      // Try to take out another loan which should fail
      const { tx, getHelpers } = await create({
        amount,
        borrower,
        loanType: LoanType.OVER_COLLATERALIZED,
      })
      const helpers = await getHelpers()

      await helpers
        .takeOut()
        .should.be.revertedWith('Teller: max supply-to-debt ratio exceeded')

      await revert()
    })

    it('should be able to withdraw collateral before takeOutLoan', async () => {
      // Skip ahead a day to avoid request rate limit
      await evm.advanceTime(moment.duration(1, 'day'))

      const revert = await evm.snapshot()

      // Create loan terms
      const { borrower } = await getNamedAccounts()
      const amount = toBN(100, await lendingToken.decimals())

      // Create loan with terms without depositing collateral
      const { getHelpers } = await create({
        amount,
        borrower,
        loanType: LoanType.OVER_COLLATERALIZED,
      })
      const helpers = await getHelpers()

      // Deposit collateral
      await helpers.collateral.deposit()

      // Verify collateral has been added
      await helpers.details
        .refresh()
        .then(({ loan }) =>
          loan.collateral.should.eq(helpers.collateral.needed)
        )

      // Withdraw collateral without taking out the loan
      await helpers.collateral.withdraw(helpers.collateral.needed)

      // Verify collateral has been removed
      await helpers.details
        .refresh()
        .then(({ loan }) => loan.collateral.should.eq(toBN(0)))

      await revert()
    })
  }
})