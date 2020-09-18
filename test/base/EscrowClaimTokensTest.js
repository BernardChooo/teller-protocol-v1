// JS Libraries
const LoansBaseInterfaceEncoder = require("../utils/encoders/LoansBaseInterfaceEncoder");
const loanStatus = require("../utils/loanStatus");
const { encodeLoanParameter } = require("../utils/loans");
const { escrow } = require("../utils/events");
const { withData } = require("leche");
const { t } = require("../utils/consts");

// Mock contracts
const Mock = artifacts.require("./mock/util/Mock.sol");
const DAI = artifacts.require("./mock/token/DAIMock.sol");

// Smart contracts
const Escrow = artifacts.require("./mock/base/EscrowMock.sol");

contract("EscrowClaimTokensTest", function(accounts) {
  const loansEncoder = new LoansBaseInterfaceEncoder(web3);

  let loans;
  let instance;

  beforeEach(async () => {
    loans = await Mock.new();

    instance = await Escrow.new();
    await instance.mockLoans(loans.address);
  });

  withData({
    _1_loan_active: [ loanStatus.Active, accounts[1], accounts[1], false, 0, 0, true, "LOAN_ACTIVE" ],
    _2_loan_not_liquidated_recipient_not_borrower: [ loanStatus.Closed, accounts[1], accounts[2], false, 0, 0, true, "LOAN_NOT_LIQUIDATED" ],
    _3_loan_not_liquidated_recipient_is_borrower: [ loanStatus.Closed, accounts[1], accounts[1], false, 2, 1000, false, null ],
    _4_loan_liquidated_recipient_not_borrower: [ loanStatus.Closed, accounts[1], accounts[2], true, 2, 1000, false, null ],
  }, function(
    status,
    recipient,
    borrower,
    liquidated,
    tokensCount,
    tokenBalance,
    mustFail,
    expectedErrorMessage
  ) {
    it(t("user", "claimTokens", "Should be able to claim tokens after the loan is closed.", mustFail), async function() {
      // Setup
      await loans.givenMethodReturn(
        loansEncoder.encodeLoans(),
        encodeLoanParameter(web3, { status, liquidated, loanTerms: { borrower } })
      );

      const tokens = [];
      for (let i = 0; i < tokensCount; i++) {
        const token = await DAI.new();
        await token.mint(instance.address, tokenBalance);
        tokens.push(token.address);
      }
      await instance.externalSetTokens(tokens)

      try {
        // Invocation
        const result = await instance.claimTokens(recipient);

        // Assertions
        for (let i = 0; i < tokensCount; i++) {
          const token = await DAI.at(tokens[i]);
          const escrowBalance = await token.balanceOf(instance.address)
          const recipientBalance = await token.balanceOf(recipient)

          assert.equal(escrowBalance.toString(), '0', 'Token balance left in Escrow')
          assert.equal(recipientBalance.toString(), tokenBalance.toString(), 'Recipient did not receive tokens')
        }

        escrow
          .tokensClaimed(result)
          .emitted(recipient);
      } catch (error) {
        assert(mustFail, error.message);
        assert.equal(error.reason, expectedErrorMessage);
      }
    });
  });
});
