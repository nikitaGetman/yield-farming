import { expect } from "chai";
import { ethers } from "hardhat";
import { BearToken, BearToken__factory } from "../typechain";

describe("BearToken", () => {
  let owner: any, other: any, otherSpender: any;
  let token: BearToken;

  beforeEach(async function () {
    [owner, other, otherSpender] = await ethers.getSigners();

    token = await new BearToken__factory(owner).deploy();
    await token.deployed();
  });

  async function mintTokens(sender: any, amount: number = 100) {
    const tx = await token.connect(owner).mint(sender.address, amount);
    await tx.wait();
    return [tx, amount];
  }

  it("initial balance should be zero", async () => {
    expect(await token.balanceOf(owner.address)).to.equal(0);
  });

  it("should mint by owner", async () => {
    const [_, mintAmount] = await mintTokens(owner);
    expect(await token.balanceOf(owner.address)).to.equal(mintAmount);
    expect(await token.balanceOf(other.address)).to.equal(0);
  });

  it("should not be minted by other", async () => {
    const mintAmount = 100;
    const tx = token.connect(other).mint(other.address, mintAmount);
    await expect(tx).to.be.reverted;
  });

  it("should adds amount to destination account on transfer", async () => {
    await mintTokens(owner);

    await token.transfer(other.address, 10);
    expect(await token.balanceOf(other.address)).to.equal(10);
  });

  it("should emits event on Transfer", async () => {
    await mintTokens(owner);

    await expect(token.transfer(other.address, 10))
      .to.emit(token, "Transfer")
      .withArgs(owner.address, other.address, 10);
  });

  it("Can not transfer above the amount", async () => {
    await expect(token.transfer(owner.address, 1)).to.be.reverted;

    await mintTokens(owner, 10);
    await expect(token.transfer(owner.address, 11)).to.be.reverted;
  });

  it("should not transfer from empty account", async () => {
    await expect(token.connect(other).transfer(owner.address, 1)).to.be
      .reverted;
  });

  it("should increase totalSupply on mint", async () => {
    const totalSupply = await token.totalSupply();
    expect(totalSupply).to.be.equal(0);

    const mintAmount = 100;
    await mintTokens(owner, mintAmount);
    const newTotalSupply = await token.totalSupply();
    expect(newTotalSupply).to.be.equal(mintAmount);
  });

  it("should be able to transfer approved tokens", async () => {
    await mintTokens(owner);

    await expect(await token.approve(otherSpender.address, 10)).to.be.ok;
    await expect(
      await token
        .connect(otherSpender)
        .transferFrom(owner.address, other.address, 10)
    ).to.be.ok;
    expect(await token.balanceOf(other.address)).to.equal(10);
  });

  it("should not be able to transfer more than approved", async () => {
    await mintTokens(owner);

    await expect(token.approve(otherSpender.address, 10)).to.be.ok;
    await expect(
      token.connect(otherSpender).transferFrom(owner.address, other.address, 11)
    ).to.be.reverted;
    expect(await token.balanceOf(other.address)).to.equal(0);
  });
});
