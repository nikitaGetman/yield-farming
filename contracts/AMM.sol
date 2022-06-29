// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Automated market maker with constant function
// x * y = K
contract AMM is ERC20 {
    using SafeMath for uint256;

    IERC20Metadata token1;
    IERC20Metadata token2;

    address public token1Address;
    address public token2Address;

    uint256 public immutable FEE = 3; // 0.3%

    // Ensures that the _qty is non-zero and the user has enough balance
    function _checkAmount(IERC20 token, uint256 _qty) internal view {
        uint256 tokenBalance = token.balanceOf(msg.sender);
        require(_qty > 0, "Amount cannot be zero!");
        require(_qty <= tokenBalance, "Insufficient amount");
    }

    modifier validAmountCheck(IERC20 token, uint256 _qty) {
        _checkAmount(token, _qty);
        _;
    }

    modifier validAndApprovedAmountCheck(IERC20 token, uint256 _qty) {
        _checkAmount(token, _qty);

        uint256 approved = token.allowance(msg.sender, address(this));
        require(_qty <= approved, "Check token allowance");
        _;
    }

    // Pool is not active until liquidity is not added
    modifier activePool() {
        require(totalShares() > 0, "Zero Liquidity");
        _;
    }

    modifier deadlineCheck(uint256 _deadline) {
        require(block.timestamp < _deadline, "Deadline expired");
        _;
    }

    constructor(address _token1, address _token2)
        ERC20("YoloSwap-1", "YOLO-V1")
    {
        require(
            _token1 != address(0) && _token2 != address(0),
            "Incorrect token address"
        );
        token1Address = _token1;
        token2Address = _token2;
        token1 = IERC20Metadata(address(token1Address));
        token2 = IERC20Metadata(address(token2Address));
    }

    function totalShares() public view returns (uint256) {
        return totalSupply();
    }

    // Returns the balance of the user
    function getMyHoldings()
        external
        view
        returns (
            uint256 myShare,
            uint256 amountToken1,
            uint256 amountToken2
        )
    {
        myShare = balanceOf(msg.sender);
        (amountToken1, amountToken2) = getWithdrawEstimate(myShare);
    }

    function getReserveToken1() public view returns (uint256) {
        return token1.balanceOf(address(this));
    }

    function getReserveToken2() public view returns (uint256) {
        return token2.balanceOf(address(this));
    }

    // Returns the total amount of tokens locked in the pool and the total shares issued corresponding to it
    function getPoolDetails()
        external
        view
        returns (
            string memory,
            uint256,
            string memory,
            uint256,
            uint256
        )
    {
        return (
            token1.symbol(),
            getReserveToken1(),
            token2.symbol(),
            getReserveToken2(),
            totalShares()
        );
    }

    // Returns amount of Token1 required when providing liquidity with _amountToken2 quantity of Token2
    function getEquivalentToken1Estimate(uint256 _amountToken2)
        public
        view
        activePool
        returns (uint256)
    {
        return getReserveToken1().mul(_amountToken2).div(getReserveToken2());
    }

    // Returns amount of Token2 required when providing liquidity with _amountToken1 quantity of Token1
    function getEquivalentToken2Estimate(uint256 _amountToken1)
        public
        view
        activePool
        returns (uint256)
    {
        return getReserveToken2().mul(_amountToken1).div(getReserveToken1());
    }

    // Adding new liquidity in the pool
    // Returns the amount of share issued for locking given assets
    function provide(
        uint256 _maxToken1,
        uint256 _maxToken2,
        uint256 _minLiquidity,
        uint256 _deadline
    )
        external
        deadlineCheck(_deadline)
        validAndApprovedAmountCheck(token1, _maxToken1)
        validAndApprovedAmountCheck(token2, _maxToken2)
        returns (uint256 share)
    {
        uint256 amountToken1 = _maxToken1;
        uint256 amountToken2 = amountToken1.div(getReserveToken1()) *
            getReserveToken2();

        if (amountToken2 > _maxToken2) {
            amountToken2 = _maxToken2;
            amountToken1 =
                amountToken2.div(getReserveToken2()) *
                getReserveToken1();
        }

        require(
            amountToken1 <= _maxToken1 && amountToken2 <= _maxToken2,
            "Equivalent value of tokens not provided"
        );

        if (totalShares() == 0) {
            // Genesis liquidity is issued 100 Shares
            share = 100 * 10**decimals();
        } else {
            // TODO: убедиться что share по amountToken2 всегда равен share по amountToken1
            share = totalShares().mul(amountToken1).div(getReserveToken1());
        }

        require(
            share >= _minLiquidity,
            "Asset value less than threshold for contribution!"
        );

        token1.transferFrom(msg.sender, payable(address(this)), amountToken1);
        token2.transferFrom(msg.sender, payable(address(this)), amountToken2);

        _mint(msg.sender, share);
    }

    // Returns the estimate of Token1 & Token2 that will be released on burning given _share
    function getWithdrawEstimate(uint256 _share)
        public
        view
        activePool
        returns (uint256 amountToken1, uint256 amountToken2)
    {
        uint256 _totalShares = totalShares();
        require(_share <= _totalShares, "Share should be less than totalShare");
        amountToken1 = _share.mul(getReserveToken1()).div(_totalShares);
        amountToken2 = _share.mul(getReserveToken2()).div(_totalShares);
    }

    // Removes liquidity from the pool and releases corresponding Token1 & Token2 to the withdrawer
    function withdraw(
        uint256 _share,
        uint256 _minToken1,
        uint256 _minToken2,
        uint256 _deadline
    )
        external
        activePool
        deadlineCheck(_deadline)
        validAmountCheck(this, _share)
        returns (uint256 amountToken1, uint256 amountToken2)
    {
        (amountToken1, amountToken2) = getWithdrawEstimate(_share);

        // TODO: потестить, возможно, если amount != minAmount, то всегда будет падать, тогда оставить только deadline
        require(
            amountToken1 >= _minToken1 && amountToken2 >= _minToken2,
            "Asset value less than threshold for withdraw!"
        );

        _burn(msg.sender, _share);

        token1.transfer(msg.sender, amountToken1);
        token2.transfer(msg.sender, amountToken2);
    }

    // Returns output token amount by input amount
    function getOutputAmount(
        uint256 _inputAmount,
        uint256 _inputReserve,
        uint256 _outputReserve
    ) private pure returns (uint256) {
        require(_inputReserve > 0 && _outputReserve > 0, "Invalid reserves");

        uint256 inputAmountWithFee = _inputAmount.mul(1000 - FEE).div(1000);

        return
            inputAmountWithFee.mul(_outputReserve).div(
                _inputReserve.add(_inputAmount)
            );
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
            "Invalid reserves"
        );

        uint256 inputAmountWithoutFee = _outputAmount.mul(_inputReserve).div(
            _outputReserve.sub(_outputAmount)
        );

        return inputAmountWithoutFee.div(1000 - FEE).mul(1000);
    }

    // Returns the amount of Token2 that the user will get when swapping a given amount of Token1 for Token2
    function getSwapToken1Estimate(uint256 _amountToken1)
        public
        view
        activePool
        returns (uint256 amountToken2)
    {
        amountToken2 = getOutputAmount(
            _amountToken1,
            getReserveToken1(),
            getReserveToken2()
        );

        // To ensure that Token2's pool is not completely depleted leading to inf:0 ratio
        // TODO: вроде ненужная проверка
        if (amountToken2 == getReserveToken2()) amountToken2--;
    }

    // Returns the amount of Token1 that the user should swap to get _amountToken2 in return
    function getSwapToken1EstimateGivenToken2(uint256 _amountToken2)
        public
        view
        activePool
        returns (uint256 amountToken1)
    {
        require(
            _amountToken2 < getReserveToken2(),
            "Insufficient pool balance"
        );

        amountToken1 = getInputAmount(
            _amountToken2,
            getReserveToken1(),
            getReserveToken2()
        );
    }

    // Swaps given amount of Token1 to Token2 using algorithmic price determination
    function swapToken1(
        uint256 _amountToken1,
        uint256 _minToken2,
        uint256 _deadline
    )
        external
        activePool
        deadlineCheck(_deadline)
        validAndApprovedAmountCheck(token1, _amountToken1)
        returns (uint256 amountToken2)
    {
        amountToken2 = getSwapToken1Estimate(_amountToken1);
        require(amountToken2 >= _minToken2, "Insufficient output amount");
        token1.transferFrom(msg.sender, payable(address(this)), _amountToken1);
        token2.transfer(msg.sender, amountToken2);
    }

    // Returns the amount of Token2 that the user will get when swapping a given amount of Token1 for Token2
    function getSwapToken2Estimate(uint256 _amountToken2)
        public
        view
        activePool
        returns (uint256 amountToken1)
    {
        amountToken1 = getOutputAmount(
            _amountToken2,
            getReserveToken2(),
            getReserveToken1()
        );

        // To ensure that Token1's pool is not completely depleted leading to inf:0 ratio
        // TODO: вроде ненужная проверка
        if (amountToken1 == getReserveToken1()) amountToken1--;
    }

    // Returns the amount of Token2 that the user should swap to get _amountToken1 in return
    function getSwapToken2EstimateGivenToken1(uint256 _amountToken1)
        public
        view
        activePool
        returns (uint256 amountToken2)
    {
        require(
            _amountToken1 < getReserveToken1(),
            "Insufficient pool balance"
        );

        amountToken2 = getInputAmount(
            _amountToken1,
            getReserveToken2(),
            getReserveToken1()
        );
    }

    // Swaps given amount of Token2 to Token1 using algorithmic price determination
    function swapToken2(
        uint256 _amountToken2,
        uint256 _minToken1,
        uint256 _deadline
    )
        external
        activePool
        deadlineCheck(_deadline)
        validAndApprovedAmountCheck(token2, _amountToken2)
        returns (uint256 amountToken1)
    {
        amountToken1 = getSwapToken2Estimate(_amountToken2);
        require(_minToken1 <= amountToken1, "Insufficient output amount");
        token2.transferFrom(msg.sender, payable(address(this)), _amountToken2);
        token1.transfer(msg.sender, amountToken1);
    }
}
