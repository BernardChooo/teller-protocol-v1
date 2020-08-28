// JS Libraries
const withData = require('leche').withData;
const { t, NULL_ADDRESS } = require('../utils/consts');
const { lendingPool } = require('../utils/events');
const SettingsInterfaceEncoder = require('../utils/encoders/SettingsInterfaceEncoder');

// Mock contracts
const Mock = artifacts.require("./mock/util/Mock.sol");

// Smart contracts
const LendingPool = artifacts.require("./base/LendingPool.sol");

contract('LendingPoolSetInterestValidatorTest', function (accounts) {
    const settingsInterfaceEncoder = new SettingsInterfaceEncoder(web3);
    let instance;
    let settingsInstance;
    let interestValidatorInstance;

    beforeEach('Setup for each test', async () => {
        const loansInstance = await Mock.new();
        settingsInstance = await Mock.new();
        const tTokenInstance = await Mock.new();
        const lendingTokenInstance = await Mock.new();
        const cTokenInstance = await Mock.new()
        const lendersInstance = await Mock.new();
        const marketsInstance = await Mock.new();
        interestValidatorInstance = await Mock.new();
        
        instance = await LendingPool.new();
        await instance.initialize(
            tTokenInstance.address,
            lendingTokenInstance.address,
            lendersInstance.address,
            loansInstance.address,
            cTokenInstance.address,
            settingsInstance.address,
            marketsInstance.address,
            interestValidatorInstance.address,
        );
    });

    const getNewInterestValidator = async (newPriceOracleIndex, Mock) => {
        if (newPriceOracleIndex === -1) {
            return NULL_ADDRESS;
        }
        if (newPriceOracleIndex === 0) {
            return interestValidatorInstance.address;
        }
        if (newPriceOracleIndex === 99) {
            return (await Mock.new()).address;
        }
        return accounts[newPriceOracleIndex];
    };

    withData({
        _1_basic: [1, true, 99, undefined, false],
        _2_sender_not_allowed: [1, false, 99, 'ADDRESS_ISNT_ALLOWED', true],
        _3_same_address: [1, true, 0, 'NEW_VALIDATOR_MUST_BE_PROVIDED', true],
        _4_not_contract: [1, true, 2, 'VALIDATOR_MUST_CONTRACT_NT_EMPTY', true],
    }, function(senderIndex, hasPauserRole, newInterestValidatorIndex, expectedErrorMessage, mustFail) {
        it(t('user', 'setInterestValidator', 'Should be able (or not) to set a new interest validator instance.', mustFail), async function() {
            // Setup
            const sender = senderIndex === -1 ? NULL_ADDRESS : accounts[senderIndex];
            /*
                If index = -1 => empty address (0x0)
                If index = 99 => a new contract address
                If index = 0 => current validator address.
                Otherwise accounts[index]
            */
            const newInterestValidator = await getNewInterestValidator(newInterestValidatorIndex, Mock);

            await settingsInstance.givenMethodReturnBool(
                settingsInterfaceEncoder.encodeHasPauserRole(),
                hasPauserRole
            );

            try {
                // Invocation
                const result = await instance.setInterestValidator(
                    newInterestValidator,
                    {
                        from: sender,
                    }
                );

                // Assertions
                assert(!mustFail, 'It should have failed because data is invalid.');
                assert(result);

                lendingPool
                    .interestValidatorUpdated(result)
                    .emitted(sender, interestValidatorInstance.address, newInterestValidator);
                
            } catch (error) {
                // Assertions
                assert(mustFail);
                assert(error);
                assert.equal(error.reason, expectedErrorMessage);
            }
        })
    })
})