// SPDX-License-Identifier: GPL

pragma solidity ^0.8.16;

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * This test is non-exhaustive, and there may be false-negatives: during the
     * execution of a contract's constructor, its address will be reported as
     * not containing a contract.
     *
     * > It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }
}

library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _setOwner(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface ICallistoNFT {

    event NewBid       (uint256 indexed tokenID, uint256 indexed bidAmount, bytes bidData);
    event TokenTrade   (uint256 indexed tokenID, address indexed new_owner, address indexed previous_owner, uint256 priceInWEI);
    event Transfer     (address indexed from, address indexed to, uint256 indexed tokenId);
    event TransferData (bytes data);
    
    struct Properties {
        
        // In this example properties of the given NFT are stored
        // in a dynamically sized array of strings
        // properties can be re-defined for any specific info
        // that a particular NFT is intended to store.
        
        /* Properties could look like this:
        bytes   property1;
        bytes   property2;
        address property3;
        */
        
        string[] properties;
    }
    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function standard() external view returns (string memory);
    function balanceOf(address _who) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function transfer(address _to, uint256 _tokenId, bytes calldata _data) external returns (bool);
    function silentTransfer(address _to, uint256 _tokenId) external returns (bool);
    
    function priceOf(uint256 _tokenId) external view returns (uint256);
    function bidOf(uint256 _tokenId) external view returns (uint256 price, address payable bidder, uint256 timestamp);
    function getTokenProperties(uint256 _tokenId) external view returns (Properties memory);
    function getTokenProperty(uint256 _tokenId, uint256 _propertyId) external view returns (string memory);
    
    function setBid(uint256 _tokenId, bytes calldata _data) payable external; // bid amount is defined by msg.value
    function setPrice(uint256 _tokenId, uint256 _amountInWEI) external;
    function withdrawBid(uint256 _tokenId) external returns (bool);

    function getUserContent(uint256 _tokenId) external view returns (string memory _content, bool _all);
    function setUserContent(uint256 _tokenId, string calldata _content) external returns (bool);
}

abstract contract NFTReceiver {
    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) external virtual returns(bytes4);
}

abstract contract CallistoNFT is ICallistoNFT {
    
    using Address for address;
    
    mapping (uint256 => Properties) internal _tokenProperties;
    mapping (uint32 => Fee)         public feeLevels; // level # => (fee receiver, fee percentage)
    
    uint256 public bidLock = 1 days; // Time required for a bid to become withdrawable.
    
    struct Bid {
        address payable bidder;
        uint256 amountInWEI;
        uint256 timestamp;
    }
    
    struct Fee {
        address payable feeReceiver;
        uint256 feePercentage; // Will be divided by 100000 during calculations
                               // feePercentage of 100 means 0.1% fee
                               // feePercentage of 2500 means 2.5% fee
    }
    
    mapping (uint256 => uint256) internal _asks; // tokenID => price of this token (in WEI)
    mapping (uint256 => Bid)     internal _bids; // tokenID => price of this token (in WEI)
    mapping (uint256 => uint32)  internal _tokenFeeLevels; // tokenID => level ID / 0 by default

    // Token name
    string internal _name;

    // Token symbol
    string internal _symbol;

    mapping(uint256 => string) internal _tokenURI;

    // Mapping from token ID to owner address
    mapping(uint256 => address) internal _owners;

    // Mapping owner address to token count
    mapping(address => uint256) internal _balances;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_, uint256 _defaultFee) {
        _name   = name_;
        _symbol = symbol_;
        feeLevels[0].feeReceiver   = payable(msg.sender);
        feeLevels[0].feePercentage = _defaultFee;
    }
    
    // Reward is always paid based on BID
    modifier checkTrade(uint256 _tokenId)
    {
        _;
        (uint256 _bid, address payable _bidder,) = bidOf(_tokenId);
        if(priceOf(_tokenId) > 0 && priceOf(_tokenId) <= _bid)
        {
            uint256 _reward = _bid - _claimFee(_bid, _tokenId);

            emit TokenTrade(_tokenId, _bidder, ownerOf(_tokenId), _reward);

            payable(ownerOf(_tokenId)).transfer(_reward);

            bytes memory _empty;
            delete _bids[_tokenId];
            delete _asks[_tokenId];
            _transfer(ownerOf(_tokenId), _bidder, _tokenId, _empty );
        }
    }
    
    function standard() public pure override returns (string memory)
    {
        return "CallistoNFT";
    }
    
    function priceOf(uint256 _tokenId) public view override returns (uint256)
    {
        address owner = _owners[_tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return _asks[_tokenId];
    }
    
    function bidOf(uint256 _tokenId) public view override returns (uint256 price, address payable bidder, uint256 timestamp)
    {
        address owner = _owners[_tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return (_bids[_tokenId].amountInWEI, _bids[_tokenId].bidder, _bids[_tokenId].timestamp);
    }
    
    function getTokenProperties(uint256 _tokenId) public view override returns (Properties memory)
    {
        return _tokenProperties[_tokenId];
    }
    
    function getTokenProperty(uint256 _tokenId, uint256 _propertyId) public view override returns (string memory)
    {
        return _tokenProperties[_tokenId].properties[_propertyId];
    }

    function getUserContent(uint256 _tokenId) public view override returns (string memory _content, bool _all)
    {
        return (_tokenProperties[_tokenId].properties[0], true);
    }

    function setUserContent(uint256 _tokenId, string calldata _content) public override returns (bool success)
    {
        require(msg.sender == ownerOf(_tokenId), "NFT: only owner can change NFT content");
        _tokenProperties[_tokenId].properties[0] = _content;
        return true;
    }
    
    function balanceOf(address owner) public view override returns (uint256) {
        require(owner != address(0), "NFT: balance query for the zero address");
        return _balances[owner];
    }
    
    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return owner;
    }
    
    function setPrice(uint256 _tokenId, uint256 _amountInWEI) checkTrade(_tokenId) public override {
        require(ownerOf(_tokenId) == msg.sender, "Setting asks is only allowed for owned NFTs!");
        _asks[_tokenId] = _amountInWEI;
    }
    
    function setBid(uint256 _tokenId, bytes calldata _data) payable checkTrade(_tokenId) public override
    {
        (uint256 _previousBid, address payable _previousBidder, ) = bidOf(_tokenId);
        require(msg.value > _previousBid, "New bid must exceed the existing one");

        uint256 _bid;
        
        // Return previous bid if the current one exceeds it.
        if(_previousBid != 0)
        {
            _previousBidder.transfer(_previousBid);
        }
        // Refund overpaid amount.
        if (priceOf(_tokenId) < msg.value)
        {
            _bid = priceOf(_tokenId);
        }
        else
        {
            _bid = msg.value;
        }
        _bids[_tokenId].amountInWEI = _bid;
        _bids[_tokenId].bidder      = payable(msg.sender);
        _bids[_tokenId].timestamp   = block.timestamp;

        emit NewBid(_tokenId, _bid, _data);
        
        // Send back overpaid amount.
        // WARHNING: Creates possibility for reentrancy.
        if (priceOf(_tokenId) < msg.value)
        {
            payable(msg.sender).transfer(msg.value - priceOf(_tokenId));
        }
    }
    
    function withdrawBid(uint256 _tokenId) public override returns (bool)
    {
        (uint256 _bid, address payable _bidder, uint256 _timestamp) = bidOf(_tokenId);
        require(msg.sender == _bidder, "Can not withdraw someone elses bid");
        require(block.timestamp > _timestamp + bidLock, "Bid is time-locked");
        
        _bidder.transfer(_bid);
        delete _bids[_tokenId];
        return true;
    }
    
    function name() public view override returns (string memory) {
        return _name;
    }
    
    function symbol() public view override returns (string memory) {
        return _symbol;
    }
    
    function transfer(address _to, uint256 _tokenId, bytes memory _data) public override returns (bool)
    {
        _transfer(msg.sender, _to, _tokenId, _data);
        emit TransferData(_data);
        return true;
    }
    
    function silentTransfer(address _to, uint256 _tokenId) public override returns (bool)
    {
        require(CallistoNFT.ownerOf(_tokenId) == msg.sender, "NFT: transfer of token that is not own");
        require(_to != address(0), "NFT: transfer to the zero address");
        
        _asks[_tokenId] = 0; // Zero out price on transfer
        
        // When a user transfers the NFT to another user
        // it does not automatically mean that the new owner
        // would like to sell this NFT at a price
        // specified by the previous owner.
        
        // However bids persist regardless of token transfers
        // because we assume that the bidder still wants to buy the NFT
        // no matter from whom.

        _beforeTokenTransfer(msg.sender, _to, _tokenId);

        _balances[msg.sender] -= 1;
        _balances[_to] += 1;
        _owners[_tokenId] = _to;

        emit Transfer(msg.sender, _to, _tokenId);
        return true;
    }
    
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }
    
    function _claimFee(uint256 _amountFrom, uint256 _tokenId) internal returns (uint256)
    {
        uint32 _level          = _tokenFeeLevels[_tokenId];
        address _feeReceiver   = feeLevels[_level].feeReceiver;
        uint256 _feePercentage = feeLevels[_level].feePercentage;
        
        uint256 _feeAmount = _amountFrom * _feePercentage / 100000;
        payable(_feeReceiver).transfer(_feeAmount);
        return _feeAmount;        
    }
    
    function _safeMint(
        address to,
        uint256 tokenId,
        string memory tURI
    ) internal virtual {
        _mint(to, tokenId, tURI);
    }

    function configureNFT(uint256 tokenId) internal
    {
        if(_tokenProperties[tokenId].properties.length == 0)
        {
            _tokenProperties[tokenId].properties.push("");
        }
    }
    
    function _mint(address to, uint256 tokenId, string memory tURI) internal {
        require(to != address(0), "NFT: mint to the zero address");
        require(!_exists(tokenId), "NFT: token already minted");

        configureNFT(tokenId);

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;
        _tokenURI[tokenId] = tURI;

        emit Transfer(address(0), to, tokenId);
    }
    
    function _mint(address to, uint256 tokenId, string memory tURI, uint32 feeLevel) internal virtual {
        require(to != address(0), "NFT: mint to the zero address");
        require(!_exists(tokenId), "NFT: token already minted");

        configureNFT(tokenId);
        _tokenFeeLevels[tokenId] = feeLevel;

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;
        _tokenURI[tokenId] = tURI;

        emit Transfer(address(0), to, tokenId);
    }
    
    function _burn(uint256 tokenId) internal {
        address owner = CallistoNFT.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);
        

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }
    
    function _transfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal {
        require(CallistoNFT.ownerOf(tokenId) == from, "NFT: transfer of token that is not own");
        require(to != address(0), "NFT: transfer to the zero address");
        
        _asks[tokenId] = 0; // Zero out price on transfer
        
        // When a user transfers the NFT to another user
        // it does not automatically mean that the new owner
        // would like to sell this NFT at a price
        // specified by the previous owner.
        
        // However bids persist regardless of token transfers
        // because we assume that the bidder still wants to buy the NFT
        // no matter from whom.

        _beforeTokenTransfer(from, to, tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        if(to.isContract())
        {
            NFTReceiver(to).onERC721Received(msg.sender, from, tokenId, data);
        }

        emit Transfer(from, to, tokenId);
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}
}

interface IEnumerableNFT is ICallistoNFT {
    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

abstract contract EnumerableNFT is CallistoNFT, IEnumerableNFT {
    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        require(index < CallistoNFT.balanceOf(owner), "NFT: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        require(index < EnumerableNFT.totalSupply(), "NFT: global index out of bounds");
        return _allTokens[index];
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = CallistoNFT.balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = CallistoNFT.balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}

contract NFT is EnumerableNFT, Ownable {
    using Strings for uint256;

    uint256 public cost = 0.05 ether;
    uint256 public maxSupply = 1000;
    uint256 public fees = 1000;
    bool public paused = false;

    constructor(
        string memory _name,
        string memory _symbol
    ) CallistoNFT(_name, _symbol, fees) {}


    // public
    function mint(string memory tURI) public payable onlyOwner {
        uint256 supply = totalSupply();
        require(!paused, "Mint NFT is paused");
        require(supply <= maxSupply);

        //require(msg.sender == owner(), "Mint NFT only owner");

        _safeMint(msg.sender, supply + 1, tURI);

    }

    function tokenURI(uint256 tURI) public view returns (string memory){
        return _tokenURI[tURI];
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
        tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    //only owner

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }
    
    function withdraw() public payable onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }
}
