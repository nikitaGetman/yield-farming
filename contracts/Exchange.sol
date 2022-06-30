// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Exchange contract with constant Automated market maker
// x * y = K
// ETH <-> Token
contract Exchange is ERC20 {
    using SafeMath for uint256;

    address public tokenAddress;

    uint256 public constant FEE = 3; // 0.3%

    constructor(address _tokenAddress) ERC20("YoloSwap-1", "YOLO-V1") {
        require(_tokenAddress != address(0), "Incorrect token address");
        tokenAddress = _tokenAddress;
    }

    // Adding new liquidity in the pool
    // Returns the amount of share issued for locking given assets
    function provideLiquidity(
        uint256 _maxToken,
        uint256 _minLiquidity,
        uint256 _deadline
    )
        external
        payable
        deadlineCheck(_deadline)
        validBalanceAndAllowance(_maxToken)
        returns (uint256 share)
    {
        require(msg.value > 0, "Insufficient liquidity provided");

        uint256 amountToken = msg.value.div(getEthReserve()).mul(
            getTokenReserve()
        );

        if (totalSupply() == 0) {
            // Genesis liquidity
            share = msg.value;
        } else {
            share = totalSupply().mul(amountToken).div(getTokenReserve());
        }

        require(
            amountToken <= _maxToken &&
                amountToken > 0 &&
                share >= _minLiquidity &&
                share > 0,
            "Asset value less than threshold for contribution!"
        );

        IERC20(tokenAddress).transferFrom(
            msg.sender,
            payable(address(this)),
            amountToken
        );
        _mint(msg.sender, share);
    }

    // Returns the estimate of Eth & Token that will be released on burning given _share
    function getWithdrawEstimate(uint256 _share)
        public
        view
        activePool
        returns (uint256 amountEth, uint256 amountToken)
    {
        uint256 _totalShares = totalSupply();
        require(_share <= _totalShares, "Share should be less than totalShare");
        amountEth = _share.mul(getEthReserve()).div(_totalShares);
        amountToken = _share.mul(getTokenReserve()).div(_totalShares);
    }

    // Removes liquidity from the pool and releases corresponding Token1 & Token2 to the withdrawer
    function withdrawLiquidity(
        uint256 _share,
        uint256 _minEth,
        uint256 _minToken,
        uint256 _deadline
    )
        external
        activePool
        deadlineCheck(_deadline)
        validBalance(address(this), _share)
        returns (uint256 amountEth, uint256 amountToken)
    {
        (amountEth, amountToken) = getWithdrawEstimate(_share);

        require(
            amountEth >= _minEth && amountToken >= _minToken,
            "Asset value less than threshold for withdraw!"
        );

        _burn(msg.sender, _share);

        IERC20(tokenAddress).transfer(msg.sender, amountToken);
        payable(msg.sender).transfer(amountEth);
    }

    // Returns output token amount by input amount
    function getOutputAmount(
        uint256 _inputAmount,
        uint256 _inputReserve,
        uint256 _outputReserve
    ) private pure returns (uint256) {
        require(
            _inputReserve > 0 && _outputReserve > 0,
            "Insufficient pool balance"
        );

        uint256 inputAmountWithFee = (_inputAmount * (1000 - FEE)) / 1000;

        require(inputAmountWithFee > 0, "Too little amount");

        return
            (inputAmountWithFee * _outputReserve) /
            (_inputReserve + _inputAmount);
    }

    // Returns input token amount by output amount
    function getInputAmount(
        uint256 _outputAmount,
        uint256 _inputReserve,
        uint256 _outputReserve
    ) private pure returns (uint256) {
        require(
            _inputReserve > 0 &&
                _outputReserve > 0 &&
                _outputAmount < _outputReserve,
            "Insufficient pool balance"
        );

        uint256 inputAmount = (_outputAmount * _inputReserve) /
            (_outputReserve - _outputAmount);

        uint256 inputAmountWithFee = (inputAmount / (1000 - FEE)) * 1000;

        require(inputAmountWithFee > 0, "Too little amount");

        return inputAmountWithFee;
    }

    // Swaps given amount of Eth to Token using algorithmic price determination
    function ethToTokenSwap(uint256 _minToken, uint256 _deadline)
        external
        payable
        activePool
        deadlineCheck(_deadline)
        returns (uint256 amountToken)
    {
        amountToken = getOutputAmount(
            msg.value,
            getEthReserve() - msg.value,
            getTokenReserve()
        );
        require(amountToken >= _minToken, "Insufficient output amount");
        IERC20(tokenAddress).transfer(msg.sender, amountToken);
    }

    // Swaps given amount of Token2 to Token1 using algorithmic price determination
    function tokenToEthSwap(
        uint256 _amountToken,
        uint256 _minEth,
        uint256 _deadline
    ) external activePool deadlineCheck(_deadline) returns (uint256 amountEth) {
        amountEth = getOutputAmount(
            _amountToken,
            getTokenReserve(),
            getEthReserve()
        );

        require(amountEth >= _minEth, "Insufficient output amount");
        IERC20(tokenAddress).transferFrom(
            msg.sender,
            payable(address(this)),
            _amountToken
        );
        payable(msg.sender).transfer(amountEth);
    }

    // ##------------------- Utilities -------------------##
    function getEthReserve() public view returns (uint256) {
        return address(this).balance;
    }

    function getTokenReserve() public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    // Returns the amount of Token that the user will get when swapping a given amount of Eth for Token
    function getEthToTokenEstimate(uint256 _amountEth)
        public
        view
        activePool
        returns (uint256 amountToken)
    {
        amountToken = getOutputAmount(
            _amountEth,
            getEthReserve(),
            getTokenReserve()
        );
    }

    // Returns the amount of Eth that the user should swap to get _amountToken in return
    function getEthToTokenEstimateByToken(uint256 _amountToken)
        public
        view
        activePool
        returns (uint256 amountEth)
    {
        amountEth = getInputAmount(
            _amountToken,
            getEthReserve(),
            getTokenReserve()
        );
    }

    // Returns the amount of Eth that the user will get when swapping a given amount of Token for Eth
    function getTokenToEthEstimate(uint256 _amountToken)
        public
        view
        activePool
        returns (uint256 amountEth)
    {
        amountEth = getOutputAmount(
            _amountToken,
            getTokenReserve(),
            getEthReserve()
        );
    }

    // Returns the amount of Token that the user should swap to get _amountEth in return
    function getTokenToEthEstimateByEth(uint256 _amountEth)
        public
        view
        activePool
        returns (uint256 amountToken)
    {
        amountToken = getInputAmount(
            _amountEth,
            getTokenReserve(),
            getEthReserve()
        );
    }

    // Returns the balance of the user
    function getMyHoldings()
        external
        view
        returns (
            uint256 myShare,
            uint256 amountEth,
            uint256 amountToken
        )
    {
        myShare = balanceOf(msg.sender);
        (amountEth, amountToken) = getWithdrawEstimate(myShare);
    }

    // Returns amount of Token required when providing liquidity with _amountEth quantity of Eth
    function getEquivalentTokenEstimate(uint256 _amountEth)
        public
        view
        activePool
        returns (uint256)
    {
        return getTokenReserve().mul(_amountEth).div(getEthReserve());
    }

    // Returns amount of Eth required when providing liquidity with _amountToken quantity of Token
    function getEquivalentToken2Estimate(uint256 _amountToken)
        public
        view
        activePool
        returns (uint256)
    {
        return getEthReserve().mul(_amountToken).div(getTokenReserve());
    }

    // Ensures that the _amount is non-zero and the user has enough balance
    function _checkBalance(address _tokenAddress, uint256 _amount)
        internal
        view
    {
        uint256 userBalance = IERC20(_tokenAddress).balanceOf(msg.sender);
        require(_amount > 0 && _amount <= userBalance, "Insufficient amount");
    }

    // ##------------------- Modifiers -------------------##
    modifier validBalance(address _tokenAddress, uint256 _amount) {
        _checkBalance(_tokenAddress, _amount);
        _;
    }

    modifier validBalanceAndAllowance(uint256 _amount) {
        _checkBalance(tokenAddress, _amount);

        uint256 approved = IERC20(tokenAddress).allowance(
            msg.sender,
            address(this)
        );
        require(_amount <= approved, "Check token allowance");
        _;
    }

    // Pool is not active until liquidity is not added
    modifier activePool() {
        require(totalSupply() > 0, "Zero Liquidity");
        _;
    }

    modifier deadlineCheck(uint256 _deadline) {
        require(block.timestamp < _deadline, "Deadline expired");
        _;
    }
}
