const AirdropCentral = artifacts.require("./AirdropCentral.sol");
const ERC20Basic = artifacts.require("./ERC20Basic.sol");
const Web3 = require('web3')

//The following line is required to use timeTravel with web3 v1.x.x
Web3.providers.HttpProvider.prototype.sendAsync = Web3.providers.HttpProvider.prototype.send;

const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545")) // Hardcoded development port

const timeTravel = function (time) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync({
      jsonrpc: "2.0",
      method: "evm_increaseTime",
      params: [time], // 86400 is num seconds in day
      id: new Date().getTime()
    }, (err, result) => {
      if(err){ return reject(err) }
      return resolve(result)
    });
  })
}

const mineBlock = function () {
  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync({
      jsonrpc: "2.0",
      method: "evm_mine"
    }, (err, result) => {
      if(err){ return reject(err) }
      return resolve(result)
    });
  })
}

const logTitle = function (title) {
  console.log("*****************************************");
  console.log(title);
  console.log("*****************************************");
}

const logError = function (err) {
  console.log("-----------------------------------------");
  console.log(err);
  console.log("-----------------------------------------");
}

contract('AirdropCentral', function(accounts) {
  let airdropcentral;
  let token;
  let token2;

  // STEP 1: Create Token Central with accounts[0]
  it("should create the Airdrop Central", async function () {
    airdropcentral = await AirdropCentral.new({from:accounts[0]});
    assert.notEqual(airdropcentral.valueOf(), "0x0000000000000000000000000000000000000000", "Airdrop Central was not initialized");
  });

  // STEP 2: Create 2 tokens with accounts[1] and [2]
  it("should create two token contracts", async function () {
    token = await ERC20Basic.new("Token1","TKN",{from:accounts[1]});
    assert.notEqual(token.valueOf(), "0x0000000000000000000000000000000000000000", "Token was not initialized");

    token2 = await ERC20Basic.new("Other Token","OTH",{from:accounts[2]});
    assert.notEqual(token2.valueOf(), "0x0000000000000000000000000000000000000000", "Token was not initialized");

  });

  // STEP 3: Accept submission
  it("should accept a token and airdropper", async function () {
    await airdropcentral.revokeSubmission(accounts[1],token.address,{from:accounts[0]});
    let airdropperBlacklist = await airdropcentral.airdropperBlacklist(accounts[1]);
    //console.log("blacklisted?",airdropperBlacklist);

    await airdropcentral.removeFromBlacklist(accounts[1],token.address,{from:accounts[0]});
    await airdropcentral.approveSubmission(accounts[1],token.address,{from:accounts[0]});

    let tokenWhitelisted = await airdropcentral.tokenWhitelist(token.address);
    assert.isTrue(tokenWhitelisted, "submission was not accepted");
  });

  // STEP 4: Sign up user accounts[3], [4]
  it("should sign user up", async function () {
    await airdropcentral.signUpForAirdrops({from:accounts[3]});
    await airdropcentral.signUpForAirdrops({from:accounts[4]});
    let users = await airdropcentral.userSignupCount();
    //console.log("Users:",users.toString());
    let userData3 = await airdropcentral.signups(accounts[3]);
    let userData4 = await airdropcentral.signups(accounts[4]);
    //console.log("User data:",userData);
    assert.equal(userData3[0], accounts[3], "User 3 was not signed up");
    assert.equal(userData4[0], accounts[4], "User 4 was not signed up");

  });

  // STEP 5: Airdrop token 1
  it("should perform airdrop for token 1", async function () {
    await token.approve(airdropcentral.address,10000 * 10 ** 18,{from:accounts[1]});
    await airdropcentral.airdropTokens(token.address, 100, 10000,{from:accounts[1]});
    let airdrop1 = await airdropcentral.airdroppedTokens(token.address,0);
    console.log("Airdrop 1a data:",airdrop1);

    await airdropcentral.airdropTokens(token.address, 150, 1000,{from:accounts[1]});
    airdrop1 = await airdropcentral.airdroppedTokens(token.address,1);
    console.log("Airdrop 1b data:",airdrop1);

    await airdropcentral.airdropTokens(token.address, 250, 1000,{from:accounts[1]});
    airdrop1 = await airdropcentral.airdroppedTokens(token.address,2);
    console.log("Airdrop 1c data:",airdrop1);

  });

  // STEP 6: Withdraw tokens of airdrop 1
  it("user 3 should withdraw tokens of airdrop 1", async function () {
    await airdropcentral.withdrawTokens(token.address,{from:accounts[3]});
    let tokenBalance = await token.balanceOf(accounts[3]);
    console.log("User 3 new token balance:",tokenBalance);

  });

  // STEP 7: Withdraw tokens of airdrop 1 after expriation
  it("user 4 should not be able to withdraw tokens of airdrop 1 after expriation", async function () {
    logTitle("Will move forward in time");
    await timeTravel(1500) // Move forward 6 days in time so the crowdsale has ended
    await mineBlock() // workaround for https://github.com/ethereumjs/testrpc/issues/336


    await airdropcentral.withdrawTokens(token.address,{from:accounts[4]});
    let tokenBalance = await token.balanceOf(accounts[4]);
    console.log("User 4 new token balance:",tokenBalance);

  });

  // STEP 8: Withdraw expired tokens
  it("airdropper 1 should be able to get his tokens back", async function () {
    let tokenBalance = await token.balanceOf(accounts[1]);
    console.log("Airdropper 1 prev token balance:",tokenBalance);
    await airdropcentral.returnTokensToAirdropper(token.address,{from:accounts[1]});
    tokenBalance = await token.balanceOf(accounts[1]);
    console.log("Airdropper 1 new token balance:",tokenBalance);

  });

});
