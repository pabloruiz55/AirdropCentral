const Account = require("./account");
const Nat = require("./nat");
const Bytes = require("./bytes");
const RLP = require("./rlp");
const keccak256 = require("./hash").keccak256;

// EthereumRPC, IncompleteTransaction -> Promise Transaction
const addDefaults = (rpc, tx) => {
  var baseDefaults = [
    tx.chainId || rpc("net_version", []),
    tx.gasPrice || rpc("eth_gasPrice", []),
    tx.nonce || rpc("eth_getTransactionCount", [tx.from,"latest"]),
    tx.value || "0x0",
    tx.data || "0x"
  ];
  return Promise.all(baseDefaults).then(([chainIdNum, gasPrice, nonce, value, data]) => {
    var chainId = Nat.fromNumber(chainIdNum);
    var from = tx.from;
    var to = tx.to === "" || tx.to === "0x" ? null : tx.to;
    var gasEstimator = tx.gas
      ? Promise.resolve(null)
      : rpc("eth_estimateGas", [{
        from: tx.from,
        to: tx.to,
        value: tx.value,
        nonce: tx.nonce,
        data: tx.data
      }]);
    return gasEstimator.then(gasEstimate => {
      return {
        chainId: chainId,
        from: from ? from.toLowerCase() : null,
        to: to ? to.toLowerCase() : null,
        gasPrice: gasPrice,
        gas: tx.gas ? tx.gas : Nat.div(Nat.mul(gasEstimate, "0x6"), "0x5"),
        nonce: nonce,
        value: value,
        data: data ? data.toLowerCase() : null
      }
    });
  });
};

// Transaction -> Bytes
const signingData = tx => {
  return RLP.encode([
    Bytes.fromNat(tx.nonce),
    Bytes.fromNat(tx.gasPrice),
    Bytes.fromNat(tx.gas),
    tx.to ? tx.to.toLowerCase() : "0x",
    Bytes.fromNat(tx.value),
    tx.data,
    Bytes.fromNat(tx.chainId || "0x1"),
    "0x",
    "0x"
  ]);
};

// Transaction, Account -> Bytes
const sign = (tx, account) => {
  const data = signingData(tx);
  const signature = Account.makeSigner(Nat.toNumber(tx.chainId || "0x1") * 2 + 35)(keccak256(data), account.privateKey);
  const rawTransaction = RLP.decode(data).slice(0,6).concat(Account.decodeSignature(signature));
  return RLP.encode(rawTransaction);
};

// Bytes -> Address
const recover = (rawTransaction) => {
  const values = RLP.decode(rawTransaction);
  const signature = Account.encodeSignature(values.slice(6,9));
  const recovery = Bytes.toNumber(values[6]);
  const extraData = recovery < 35 ? [] : [Bytes.fromNumber((recovery - 35) >> 1), "0x", "0x"]
  const data = values.slice(0,6).concat(extraData);
  const dataHex = RLP.encode(data);
  return Account.recover(keccak256(dataHex), signature);
};

module.exports = {
  addDefaults,
  signingData,
  sign,
  recover
};
