// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test, stdError} from "forge-std/Test.sol";
import {DeployMatchMakerV1} from "../script/DeployMatchMakerV1.s.sol";
import {ConnectFourMatchMakerV1} from "../src/ConnectFourMatchMakerV1.sol";

contract DeployMatchMakerV1Test is Test {
    DeployMatchMakerV1 public deployer;
    ConnectFourMatchMakerV1 public matchMaker;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        deployer = new DeployMatchMakerV1();
        matchMaker = deployer.run();

        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
    }

    function test_SetUpState() public {
        ConnectFourMatchMakerV1 instance = deployer.run();
        assertNotEq(address(instance), address(0x0));
    }
}
