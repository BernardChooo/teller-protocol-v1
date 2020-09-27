const _1_escrow_repay_loan_in_full = require('./1_escrow_repay_loan_in_full');

const _1_uniswap_secured_swap_token_for_weth = require('./dapps/uniswap/1_uniswap_secured_swap_token_for_weth')
const _2_uniswap_secured_swap_token_for_token = require('./dapps/uniswap/2_uniswap_secured_swap_token_for_token')
const _3_uniswap_secured_swap_weth_for_token = require('./dapps/uniswap/3_uniswap_secured_swap_weth_for_token')
const _4_uniswap_secured_swap_token_for_token_gt_balance = require('./dapps/uniswap/4_uniswap_secured_swap_token_for_token_gt_balance')
const _5_uniswap_unsecured_swap = require('./dapps/uniswap/5_uniswap_unsecured_swap')

const escrow = {
  _1_escrow_repay_loan_in_full,
}

const uniswap = {
  _1_uniswap_secured_swap_token_for_weth,
  _2_uniswap_secured_swap_token_for_token,
  _3_uniswap_secured_swap_weth_for_token,
  _4_uniswap_secured_swap_token_for_token_gt_balance,
  _5_uniswap_unsecured_swap,
}

const dapps = {
  ...uniswap
}

module.exports = {
  ...escrow,
  ...dapps
}