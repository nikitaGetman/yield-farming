import { ethers, run } from "hardhat";

async function main() {
  console.log("Start deploying...");

  const deployArguments = "Hello, Hardhat!";
  const Greeter = await ethers.getContractFactory("Greeter");
  const greeter = await Greeter.deploy(deployArguments);

  await greeter.deployed();

  console.log("Greeter deployed to:", greeter.address);
  console.log("Waiting for few confirmations to verify contract...");

  await ethers.provider.waitForTransaction(
    greeter.deployTransaction.hash,
    5,
    150000
  );

  console.log("Verifying...");

  await run("verify:verify", {
    address: greeter.address,
    contract: "contracts/Greeter.sol:Greeter",
    constructorArguments: [deployArguments],
  });

  console.log("Deploying done!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
