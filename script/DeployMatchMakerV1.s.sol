// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ConnectFourMatchMakerV1} from "src/ConnectFourMatchMakerV1.sol";

contract DeployMatchMakerV1 is Script {
    function run() external returns (ConnectFourMatchMakerV1) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ConnectFourMatchMakerV1 matchMaker = new ConnectFourMatchMakerV1();

        vm.stopBroadcast();
        return matchMaker;
    }
}
