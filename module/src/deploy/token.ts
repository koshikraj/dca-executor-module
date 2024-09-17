import { DeployFunction } from 'hardhat-deploy/types'

const deploy: DeployFunction = async ({ deployments, getNamedAccounts, network }) => {
  if (!network.tags.dev && !network.tags.test) {
    return
  }

  const { deployer } = await getNamedAccounts()
  const { deploy } = deployments

  await deploy('HariWillibaldToken', {
    from: deployer,
    args: [deployer],
    log: true,
    deterministicDeployment: true,
  })

  await deploy('TestVault', {
    from: deployer,
    args: ["0x28F53bA70E5c8ce8D03b1FaD41E9dF11Bb646c36"],
    log: true,
    deterministicDeployment: true,
  })
  
}

export default deploy
