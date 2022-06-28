import { expect } from "chai";
import { ethers } from "hardhat";
import { DEX, DEX__factory, BearToken, BearToken__factory } from "../typechain";

describe("DEX", function () {
  let owner: any;
  let token: BearToken, dex: DEX;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();

    token = await new BearToken__factory(owner).deploy();
    await token.deployed();

    dex = await new DEX__factory(owner).deploy(token.address, { value: 10 });
    await dex.deployed();
  });

  async function mintTokens(sender: any, amount: number = 100) {
    const tx = await token.connect(owner).mint(sender.address, amount);
    await tx.wait();
    return [tx, amount];
  }

  it("should not be deployed with zero funds", async () => {
    await expect(
      new DEX__factory(owner).deploy(token.address)
    ).to.be.revertedWith(
      "You have to at least deposit something to start a DEX"
    );
    await expect(
      new DEX__factory(owner).deploy(token.address, { value: 0 })
    ).to.be.revertedWith(
      "You have to at least deposit something to start a DEX"
    );
  });

  it("should deploy with correct token address and value", async () => {
    expect(await dex.tokenAddress()).to.be.equal(token.address);
    // expect(dex.getBalance).to.be.equal(token.address);
  });

  it("should swap ether to tokens", async () => {
    const minted = 100;
    const spent = 10;
    await mintTokens(dex, minted);
    await dex.buy({ value: spent });

    expect(await token.balanceOf(dex.address)).to.be.equal(minted - spent);
    expect(await token.balanceOf(owner.address)).to.be.equal(spent);
  });

  it("should not swap zero ether to tokens", async () => {
    await expect(dex.buy({ value: 0 })).to.be.revertedWith(
      "You need to send some Ether"
    );
  });

  it("should not swap more ether than have", async () => {
    await expect(dex.buy({ value: 100 })).to.be.revertedWith(
      "Not enough tokens in the reserve"
    );
  });

  it("should swap tokens to ether", async () => {
    const minted = 100;
    const spent = 10;
    await mintTokens(owner, minted);
    await token.approve(dex.address, minted);
    await dex.sell(spent);

    expect(await token.balanceOf(owner.address)).to.be.equal(minted - spent);
    expect(await token.balanceOf(dex.address)).to.be.equal(spent);
  });

  it("should not swap ether to zero tokens", async () => {
    const minted = 100;
    const spent = 0;
    await mintTokens(owner, minted);

    await expect(dex.sell(spent)).to.be.revertedWith(
      "You need to sell at least some tokens"
    );
  });

  it("should not swap ether to tokens if tokens not approved", async () => {
    const minted = 100;
    const spent = 10;
    await mintTokens(owner, minted);

    await expect(dex.sell(spent)).to.be.revertedWith(
      "Check the token allowance"
    );
  });
});
