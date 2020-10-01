const BigNumber = require("bignumber.js");
const platformSettingsNames = require("../../../test/utils/platformSettingsNames");
const {
  NULL_ADDRESS,
  ONE_DAY,
  toBytes32,
} = require("../../../test/utils/consts");
const {
  createMultipleSignedLoanTermsResponses,
  createLoanTermsRequest,
} = require("../../../test/utils/loan-terms-helper");
const { printLoanDetails, printPairAggregator } = require("../../../test/utils/printer");
const {
  lendingPool: lendingPoolEvents,
  loans: loansEvents,
} = require("../../../test/utils/events");
const errorActions = require("./errors");

/**
 * Gets an amount of tokens requested based on the current network.
 */
const getFunds = async (
  {token},
  {testContext},
  {amount, to}
) => {
  switch (testContext.network) {
    case 'ganache':
      await token.mint(to, amount);
      break
    case 'ganache-mainnet':
      const { swapper } = testContext;
      await swapper.swapForExact(to, token.address, amount)
      break
  }
}

const depositFunds = async (
  {token, lendingPool},
  {txConfig, testContext},
  {amount}
) => {
  console.log("Depositing funds on pool...");
  await getFunds({ token }, { testContext }, { amount, to: txConfig.from })
  await token.approve(lendingPool.address, amount, txConfig);
  const depositResult = await lendingPool.deposit(amount, txConfig);
  lendingPoolEvents
    .tokenDeposited(depositResult)
    .emitted(txConfig.from, amount);
  return depositResult;
};

const requestLoanTerms = async (
  {loans, loanTermsConsensus, settings},
  {txConfig, testContext},
  {loanTermsRequestTemplate, loanResponseTemplate}
) => {
  console.log("Requesting loan terms...");
  const {web3, timer, nonces, chainId} = testContext;
  const currentTimestamp = parseInt(await timer.getCurrentTimestamp());
  const {
    amount,
    durationInDays,
    borrower,
    recipient = NULL_ADDRESS,
  } = loanTermsRequestTemplate;
  const {
    interestRate,
    collateralRatio,
    maxLoanAmount,
    signers,
    responseTime,
  } = loanResponseTemplate;

  const loanTermsRequestInfo = {
    borrower,
    recipient,
    requestNonce: nonces.newNonce(borrower),
    amount: amount.toFixed(0),
    duration: durationInDays * ONE_DAY,
    requestTime: currentTimestamp,
    caller: loans.address,
    consensusAddress: loanTermsConsensus.address,
  };
  const loanResponseInfoTemplate = {
    //        responseTime: currentTimestamp - 10,
    responseTime: currentTimestamp - 10,
    interestRate,
    collateralRatio,
    maxLoanAmount: maxLoanAmount.toFixed(0),
    consensusAddress: loanTermsConsensus.address,
  };
  const loanTermsRequest = createLoanTermsRequest(
    loanTermsRequestInfo,
    chainId
  );
  const signedResponses = await createMultipleSignedLoanTermsResponses(
    web3,
    loanTermsRequest,
    signers,
    loanResponseInfoTemplate,
    nonces,
    chainId
  );

  const createLoanWithTermsResult = await loans.createLoanWithTerms(
    loanTermsRequest.loanTermsRequest,
    signedResponses,
    txConfig.value,
    txConfig
  );

  const termsExpiryTime = await settings.getPlatformSettingValue(
    toBytes32(web3, platformSettingsNames.TermsExpiryTime)
  );
  const expiryTermsExpected = await timer.getCurrentTimestampInSecondsAndSum(
    termsExpiryTime
  );
  const loanIDs = await loans.getBorrowerLoans(borrower);
  const lastLoanID = loanIDs[loanIDs.length - 1];
  loansEvents
    .loanTermsSet(createLoanWithTermsResult)
    .emitted(
      lastLoanID,
      txConfig.from,
      recipient,
      loanResponseInfoTemplate.interestRate,
      loanResponseInfoTemplate.collateralRatio,
      loanResponseInfoTemplate.maxLoanAmount,
      loanTermsRequestInfo.duration,
      expiryTermsExpected
    );
  console.log(`Loan id requested: ${lastLoanID}`);
  const loansInfo = await loans.loans(lastLoanID);
  return loansInfo;
};

/**
 * Deposits collateral into the Loans contract for a specific loan.
 * If the token parameter is not defined, use ETH as collateral.
 */
const depositCollateral = async (
  {collateralToken, loans},
  {txConfig, testContext},
  {loanId, amount}
) => {
  const collateralTokenSymbol = await collateralToken.symbol();
  console.log(`Depositing collateral ${amount} ${collateralTokenSymbol} in loan id ${loanId}.`);
  if (collateralTokenSymbol.toUpperCase() !== 'ETH') {
    await getFunds({ token: collateralToken }, { txConfig, testContext }, { amount, to: txConfig.from })
    await collateralToken.approve(loans.address, amount, txConfig);
  } else {
    // Don't overwrite the config object
    txConfig = Object.assign({}, txConfig);
    txConfig.value = amount;
  }
  const depositResult = await loans.depositCollateral(
    txConfig.from,
    loanId,
    amount,
    txConfig
  );
  loansEvents
    .collateralDeposited(depositResult)
    .emitted(loanId, txConfig.from, amount);
  return depositResult;
};

/**
 * Withdraws collateral from the loans contract for a specific loan.
 */
const withdrawCollateral = async (
  {loans},
  {txConfig, testContext},
  {loanId, amount}
) => {
  console.log(`Withdrawing collateral ${amount} in loan id ${loanId}.`);
  const depositResult = await loans.withdrawCollateral(
    amount,
    loanId,
    txConfig
  );
  loansEvents
    .collateralWithdrawn(depositResult)
    .emitted(loanId, txConfig.from, amount);
  return depositResult;
}

const takeOutLoan = async (
  {loans},
  {txConfig, testContext},
  {loanId, amount, expectedErrorMessage = undefined}
) => {
  console.log(`Taking out loan id ${loanId}...`);
  const takeOutLoanResultPromise = async () => await loans.takeOutLoan(loanId, amount, txConfig);

  const {
    failed,
    tx: takeOutLoanResult,
  } = await errorActions.handleContractError(
    'TakeOutLoan',
    { testContext },
    {
      fnPromise: takeOutLoanResultPromise,
      expectedErrorMessage,
    }
  );
  if(!failed) {
    const loanInfo = await loans.loans(loanId);
    const { escrow } = loanInfo;
    loansEvents
      .loanTakenOut(takeOutLoanResult)
      .emitted(loanId, txConfig.from, escrow, amount);
    return loanInfo;
  }
};

/**
 * Repays an amount of the borrowed token for a loan.
 */
const repay = async ({loans, lendingPool, token}, {txConfig}, {loanId, amount}) => {
  console.log(`Repaying ${amount} for loan id ${loanId}`);
  const loan = await loans.loans(loanId);
  const totalOwed = await loans.getTotalOwed(loanId);
  const totalOwedBigNumber = BigNumber(totalOwed.toString());
  
  await token.approve(lendingPool.address, amount, txConfig);
  const repayResult = await loans.repay(amount, loanId, txConfig);

  const totalPaid = totalOwedBigNumber.gt(amount) ? amount : totalOwedBigNumber;
  const totalOwedAfterRepayment = totalOwedBigNumber.gt(amount) ? totalOwedBigNumber.minus(amount) : '0';
  loansEvents
    .loanRepaid(repayResult)
    .emitted(loanId, loan.loanTerms.borrower, totalPaid, txConfig.from, totalOwedAfterRepayment);
  return repayResult;
};

const liquidateLoan = async (
  {token, loans, settings, lendingPool},
  {txConfig, testContext},
  {loanId, amount}
) => {
  console.log(`Liquidating loan id ${loanId}...`);
  const {web3} = testContext;

  const initialTotalCollateral = await loans.totalCollateral();
  const liquidateEthPrice = await settings.getPlatformSettingValue(
    toBytes32(web3, platformSettingsNames.LiquidateEthPrice)
  );
  const getCollateralInfo = await loans.getCollateralInfo(loanId);
  const {neededInLendingTokens} = getCollateralInfo;
  const transferAmountToLiquidate = BigNumber(neededInLendingTokens.toString())
    .times(liquidateEthPrice)
    .div(10000);

  // TODO Review it.
  await token.mint(txConfig.from, transferAmountToLiquidate.toFixed(0));

  const initialLiquidatorTokenBalance = await token.balanceOf(txConfig.from);

  await token.approve(
    lendingPool.address,
    transferAmountToLiquidate.toFixed(0),
    txConfig
  );
  // TODO Add validations
  const liquidateLoanResult = await loans.liquidateLoan(loanId, txConfig);
};

const printLoanInfo = async (
  allContracts,
  {testContext},
  {
    tokenInfo,
    collateralTokenInfo,
    loanId,
  }
) => {
  const { verbose } = testContext;
  if (!verbose) {
    return;
  }
  const escrow = await getEscrow(allContracts, { testContext }, {loanId});
  await printLoanDetails(allContracts, {testContext}, {tokenInfo, collateralTokenInfo, loanId, escrow});
};

const printPairAggregatorInfo = async (
  allContracts,
  { testContext },
  {
    tokenInfo,
    collateralTokenInfo,
  }
) => {
  const { verbose } = testContext;
  if (!verbose) {
    return;
  }
  await printPairAggregator(allContracts, {tokenInfo, collateralTokenInfo});
};

const getEscrow = async (
    {loans},
    {testContext},
    {
      loanId,
    }
  ) => {
    const { artifacts } = testContext;
    const Escrow = artifacts.require("./base/Escrow.sol");
    const loanInfo = await loans.loans(loanId);
    if(loanInfo.escrow ===  NULL_ADDRESS) {
      return undefined;
    }
    const escrow = await Escrow.at(loanInfo.escrow);
    return escrow;
  };

module.exports = {
  getFunds,
  depositFunds,
  requestLoanTerms,
  depositCollateral,
  withdrawCollateral,
  takeOutLoan,
  repay,
  liquidateLoan,
  printLoanInfo,
  printPairAggregatorInfo,
  getEscrow,
};