// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MonadPay — tap-to-pay settlement on Monad
/// @notice Forwards MON to a merchant and emits an indexed receipt that
///         terminals watch via `monadLogs` (speculative, ~ms after proposal).
contract MonadPay {
    event Paid(
        address indexed merchant,
        bytes32 indexed invoiceId,
        address indexed payer,
        uint256 amount,
        string memo
    );

    error ZeroAmount();
    error TransferFailed();

    function pay(address payable merchant, bytes32 invoiceId, string calldata memo) external payable {
        if (msg.value == 0) revert ZeroAmount();
        (bool ok,) = merchant.call{value: msg.value}("");
        if (!ok) revert TransferFailed();
        emit Paid(merchant, invoiceId, msg.sender, msg.value, memo);
    }
}
