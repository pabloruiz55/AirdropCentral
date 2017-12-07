const Eth = require(".");
//const rpc = Eth.rpc("https://testnet.infura.io/sE0I5J1gO2jugs9LndHR");
const rpc = Eth.rpc("https://177.208.20.33");

//console.log("getPrice:", Eth.hash.keccak256s("getPrice()").slice(0,10));
//console.log("getAccountCount:", Eth.hash.keccak256s("getAccountCount()").slice(0,10));
//console.log("getTokenByAccountId:", Eth.hash.keccak256s("getTokenByAccountId(uint256)").slice(0,10));
//console.log("buy:", Eth.hash.keccak256s("buy()").slice(0,10));
//console.log("sell:", Eth.hash.keccak256s("sell()").slice(0,10));


//(async () => {
  //console.log(await rpc("eth_blockNumber"));
  ////const a = await rpc("eth_call", [{
    ////to: "0xbcdd3c90eaebb5f3815cc67cc64e6180861a43a1",
    ////data: "0x9eb5e6500000000000000000000000000000000000000000000000000000000000000000"
  ////}, "latest"]);
  ////console.log(a);
//})();



for (var i = 0; i < 16; ++i)
  console.log(Eth.account.create().address)
