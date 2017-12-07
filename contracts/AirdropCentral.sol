pragma solidity 0.4.18;

import './ERC20Basic.sol';

/// @author Pablo Ruiz <me@pabloruiz.co>
/// @Title Airdrop Central - To submit your token follow the instructions at:
/// https://github.com/pabloruiz55/AirdropCentral

//////////////////

//
// Permissions
//                               Admin      Airdropper       User
// approve/ revoke submissions     x
// pause / unpause                 x
// signupUsersManually             x
// airdropTokens                                x
// returnTokensToAirdropper                     x
// signUpForAirdrops                                          x
// quitFromAirdrops                                           x
// getTokensAvailableToMe                                     x
// withdrawTokens                                             x

////////

contract AirdropCentral {
    using SafeMath for uint256;

    // The owner / admin of the Airdrop Central
    // In charge of accepting airdrop submissions
    address public owner;

    // How many tokens the owner keeps of each airdrop as transaction fee
    uint public ownersCut = 2; // 2% commision in tokens

    // Id of each airdrop (token address + id #)
    struct TokenAirdropID {
        address tokenAddress;
        uint airdropAddressID; // The id of the airdrop within a token address
    }

    struct TokenAirdrop {
        address tokenAddress;
        uint airdropAddressID; // The id of the airdrop within a token address
        address tokenOwner;
        uint airdropDate; // The airdrop creation date
        uint airdropExpirationDate; // When airdrop expires
        uint tokenBalance; // Current balance
        uint totalDropped; // Total to distribute
        uint usersAtDate; // How many users were signed at airdrop date
    }

    struct User {
        address userAddress;
        uint signupDate; // Determines which airdrops the user has access to
        // User -> Airdrop id# -> balance
        mapping (address => mapping (uint => uint)) withdrawnBalances;
    }

    // Maps the tokens available to airdrop central contract. Keyed by token address
    mapping (address => TokenAirdrop[]) public airdroppedTokens;
    TokenAirdropID[] public airdrops;

    // List of users that signed up
    mapping (address => User) public signups;
    uint public userSignupCount = 0;

    // Admins with permission to accept submissions
    mapping (address => bool) admins;

    // Whether or not the contract is paused (in case of a problem is detected)
    bool public paused = false;

    // List of approved/rejected token/sender addresses
    mapping (address => bool) public tokenWhitelist;
    mapping (address => bool) public tokenBlacklist;
    mapping (address => bool) public airdropperBlacklist;

    //
    // Modifiers
    //

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    modifier onlyAdmin {
        require(msg.sender == owner || admins[msg.sender]);
        _;
    }

    modifier ifNotPaused {
        require(!paused);
        _;
    }

    //
    // Events
    //

    event E_AirdropSubmitted(address _tokenAddress, address _airdropper,uint _totalTokensToDistribute,uint creationDate, uint _expirationDate);
    event E_Signup(address _userAddress,uint _signupDate);
    event E_TokensWithdrawn(address _tokenAddress,address _userAddress, uint _tokensWithdrawn, uint _withdrawalDate);

    function AirdropCentral() public {
        owner = msg.sender;
    }

    /////////////////////
    // Owner / Admin functions
    /////////////////////

    /**
     * @dev pause or unpause the contract in case a problem is detected
     */
    function setPaused(bool _isPaused) public onlyOwner{
        paused = _isPaused;
    }

    /**
     * @dev allows owner to grant/revoke admin privileges to other accounts
     * @param _admin is the account to be granted/revoked admin privileges
     * @param isAdmin is whether or not to grant or revoke privileges.
     */
    function setAdmin(address _admin, bool isAdmin) public onlyOwner{
        admins[_admin] = isAdmin;
    }

    /**
     * @dev removes a token and/or account from the blacklist to allow
     * them to submit a token again.
     * @param _airdropper is the account to remove from blacklist
     * @param _tokenAddress is the token address to remove from blacklist
     */
    function removeFromBlacklist(address _airdropper, address _tokenAddress) public onlyOwner {
        if(_airdropper != address(0))
            airdropperBlacklist[_airdropper] = false;

        if(_tokenAddress != address(0))
            tokenBlacklist[_tokenAddress] = false;
    }

    /**
     * @dev approves a given token and account address to make it available for airdrop
     * This is necessary to avoid malicious contracts to be added.
     * @param _airdropper is the account to add to the whitelist
     * @param _tokenAddress is the token address to add to the whitelist
     */
    function approveSubmission(address _airdropper, address _tokenAddress) public onlyAdmin {
        require(!airdropperBlacklist[_airdropper]);
        require(!tokenBlacklist[_tokenAddress]);

        tokenWhitelist[_tokenAddress] = true;
    }

    /**
     * @dev removes token and airdropper from whitelist.
     * Also adds them to a blacklist to prevent further submissions of any
     * To be used in case of an emgency where the owner failed to detect
     * a problem with the address submitted.
     * @param _airdropper is the account to add to the blacklist and remove from whitelist
     * @param _tokenAddress is the token address to add to the blacklist and remove from whitelist
     */
    function revokeSubmission(address _airdropper, address _tokenAddress) public onlyAdmin {
        if(_tokenAddress != address(0)){
            tokenWhitelist[_tokenAddress] = false;
            tokenBlacklist[_tokenAddress] = true;
        }

        if(_airdropper != address(0)){
            airdropperBlacklist[_airdropper] = true;
        }

    }

    /**
     * @dev allows admins to add users to the list manually
     * Use to add people who explicitely asked to be added...
     */
    function signupUsersManually(address _user) public onlyAdmin {
        require(signups[_user].userAddress == address(0));
        signups[_user] = User(_user,now);
        userSignupCount++;

        E_Signup(msg.sender,now);
    }


    /////////////////////
    // Airdropper functions
    /////////////////////

    /**
     * @dev Transfers tokens to contract and sets the Token Airdrop
     * @notice Before calling this function, you must have given the Airdrop Central
     * an allowance of the tokens to distribute.
     * Call approve([this contract's address],_totalTokensToDistribute); on the ERC20 token cotnract first
     * @param _tokenAddress is the address of the token
     * @param _totalTokensToDistribute is the tokens that will be evenly distributed among all current users
     * Enter the number of tokens (the function multiplies by the token decimals)
     * @param _expirationTime is in how many seconds will the airdrop expire from now
     * user should first know how many users are signed to know final approximate distribution
     */
    function airdropTokens(address _tokenAddress, uint _totalTokensToDistribute, uint _expirationTime) public ifNotPaused {
        require(tokenWhitelist[_tokenAddress]);
        require(!airdropperBlacklist[msg.sender]);

        ERC20Basic token = ERC20Basic(_tokenAddress);
        require(token.balanceOf(msg.sender) >= _totalTokensToDistribute);

        //Multiply number entered by token decimals.
        _totalTokensToDistribute = _totalTokensToDistribute.mul(10 ** uint256(token.decimals()));

        // Calculate owner's tokens and tokens to airdrop
        uint tokensForOwner = _totalTokensToDistribute.mul(ownersCut).div(100);
        _totalTokensToDistribute = _totalTokensToDistribute.sub(tokensForOwner);

        // Store the airdrop unique id in array (token address + id)
        TokenAirdropID memory taid = TokenAirdropID(_tokenAddress,airdroppedTokens[_tokenAddress].length);
        TokenAirdrop memory ta = TokenAirdrop(_tokenAddress,airdroppedTokens[_tokenAddress].length,msg.sender,now,now+_expirationTime,_totalTokensToDistribute,_totalTokensToDistribute,userSignupCount);
        airdroppedTokens[_tokenAddress].push(ta);
        airdrops.push(taid);

        // Transfer the tokens
        require(token.transferFrom(msg.sender,this,_totalTokensToDistribute));
        require(token.transferFrom(msg.sender,owner,tokensForOwner));

        E_AirdropSubmitted(_tokenAddress,ta.tokenOwner,ta.totalDropped,ta.airdropDate,ta.airdropExpirationDate);

    }

    /**
     * @dev returns unclaimed tokens to the airdropper after the airdrop expires
     * @param _tokenAddress is the address of the token
     */
    function returnTokensToAirdropper(address _tokenAddress) public ifNotPaused {
        require(tokenWhitelist[_tokenAddress]); // Token must be whitelisted first

        // Get the token
        ERC20Basic token = ERC20Basic(_tokenAddress);

        uint tokensToReturn = 0;

        for (uint i =0; i<airdroppedTokens[_tokenAddress].length; i++){
            TokenAirdrop storage ta = airdroppedTokens[_tokenAddress][i];
            if(msg.sender == ta.tokenOwner &&
                airdropHasExpired(_tokenAddress,i)){

                tokensToReturn = tokensToReturn.add(ta.tokenBalance);
                ta.tokenBalance = 0;
            }
        }
        require(token.transfer(msg.sender,tokensToReturn));
        E_TokensWithdrawn(_tokenAddress,msg.sender,tokensToReturn,now);

    }

    /////////////////////
    // User functions
    /////////////////////

    /**
     * @dev user can signup to the Airdrop Central to receive token airdrops
     * Airdrops made before the user registration won't be available to them.
     */
    function signUpForAirdrops() public ifNotPaused{
        require(signups[msg.sender].userAddress == address(0));
        signups[msg.sender] = User(msg.sender,now);
        userSignupCount++;

        E_Signup(msg.sender,now);
    }

    /**
     * @dev removes user from airdrop list.
     * Beware that token distribution for existing airdrops won't change.
     * For example: if 100 tokens were to be distributed to 10 people (10 each).
     * if one quitted from the list, the other 9 will still get 10 each.
     * @notice WARNING: Quiting from the airdrop central will make you lose
     * tokens not yet withdrawn. Make sure to withdraw all pending tokens before
     * removing yourself from this list. Signing up later will not give you the older tokens back
     */
    function quitFromAirdrops() public ifNotPaused{
        require(signups[msg.sender].userAddress == msg.sender);
        delete signups[msg.sender];
        userSignupCount--;
    }

    /**
     * @dev calculates the amount of tokens the user will be able to withdraw
     * Given a token address, the function checks all airdrops with the same address
     * @param _tokenAddress is the token the user wants to check his balance for
     * @return totalTokensAvailable is the tokens calculated
     */
    function getTokensAvailableToMe(address _tokenAddress) view public returns (uint){
        require(tokenWhitelist[_tokenAddress]); // Token must be whitelisted first

        // Get User instance, given the sender account
        User storage user = signups[msg.sender];
        require(user.userAddress != address(0));

        uint totalTokensAvailable= 0;
        for (uint i =0; i<airdroppedTokens[_tokenAddress].length; i++){
            TokenAirdrop storage ta = airdroppedTokens[_tokenAddress][i];

            uint _withdrawnBalance = user.withdrawnBalances[_tokenAddress][i];

            //Check that user signed up before the airdrop was done. If so, he is entitled to the tokens
            //And the airdrop must not have expired
            if(ta.airdropDate >= user.signupDate &&
                now <= ta.airdropExpirationDate){

                // The user will get a portion of the total tokens airdroped,
                // divided by the users at the moment the airdrop was created
                uint tokensAvailable = ta.totalDropped.div(ta.usersAtDate);

                // if the user has not alreay withdrawn the tokens, count them
                if(_withdrawnBalance < tokensAvailable){
                    totalTokensAvailable = totalTokensAvailable.add(tokensAvailable);

                }
            }
        }
        return totalTokensAvailable;
    }

    /**
     * @dev calculates and withdraws the amount of tokens the user has been awarded by airdrops
     * Given a token address, the function checks all airdrops with the same
     * address and withdraws the corresponding tokens for the user.
     * @param _tokenAddress is the token the user wants to check his balance for
     */
    function withdrawTokens(address _tokenAddress) ifNotPaused public {
        require(tokenWhitelist[_tokenAddress]); // Token must be whitelisted first

        // Get User instance, given the sender account
        User storage user = signups[msg.sender];
        require(user.userAddress != address(0));

        uint totalTokensToTransfer = 0;
        // For each airdrop made for this token (token owner may have done several airdrops at any given point)
        for (uint i =0; i<airdroppedTokens[_tokenAddress].length; i++){
            TokenAirdrop storage ta = airdroppedTokens[_tokenAddress][i];

            uint _withdrawnBalance = user.withdrawnBalances[_tokenAddress][i];

            //Check that user signed up before the airdrop was done. If so, he is entitled to the tokens
            //And the airdrop must not have expired
            if(ta.airdropDate >= user.signupDate &&
                now <= ta.airdropExpirationDate){

                // The user will get a portion of the total tokens airdroped,
                // divided by the users at the moment the airdrop was created
                uint tokensToTransfer = ta.totalDropped.div(ta.usersAtDate);

                // if the user has not alreay withdrawn the tokens
                if(_withdrawnBalance < tokensToTransfer){
                    // Register the tokens withdrawn by the user and total tokens withdrawn
                    user.withdrawnBalances[_tokenAddress][i] = tokensToTransfer;
                    ta.tokenBalance = ta.tokenBalance.sub(tokensToTransfer);
                    totalTokensToTransfer = totalTokensToTransfer.add(tokensToTransfer);

                }
            }
        }
        // Get the token
        ERC20Basic token = ERC20Basic(_tokenAddress);
        // Transfer tokens from all airdrops that correspond to this user
        require(token.transfer(msg.sender,totalTokensToTransfer));

        E_TokensWithdrawn(_tokenAddress,msg.sender,totalTokensToTransfer,now);
    }

    function airdropsCount() public view returns (uint){
        return airdrops.length;
    }

    function getAddress() public view returns (address){
      return address(this);
    }

    function airdropHasExpired(address _tokenAddress, uint _id) public view returns (bool){
        TokenAirdrop storage ta = airdroppedTokens[_tokenAddress][_id];
        return (now > ta.airdropExpirationDate);
    }
}
