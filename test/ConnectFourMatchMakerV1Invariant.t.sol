// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {ConnectFour as ConnectFourBase} from "connect4-sol/ConnectFour.sol";
import {ConnectFourMatchMakerV1} from "../src/ConnectFourMatchMakerV1.sol";
import {TestToken} from "../src/TestToken.sol";

address constant CURRENCY = address(0);
uint256 constant UINT96_MAX = type(uint96).max;

contract ConnectFourMakerV1InvariantTest is Test {
    ConnectFourMatchMakerV1 internal matchMaker;
    TestToken internal token;
    Handler internal handler;

    function setUp() public {
        matchMaker = new ConnectFourMatchMakerV1();
        token = new TestToken("Test Token", "TEST");
        handler = new Handler(matchMaker, token);

        targetContract(address(handler));
    }

    function test_invariant_balance_GreaterThanOrEqualToDeposits() public {
        uint256 balance = handler.deposits();
        assertGe(balance, 0, "Invariant violated: balance must always be greater than or equal to deposits");
    }

    function test_invariant_balanceOf_GreaterThanOrEqualToDeposits() public {
        assertGe(
            token.balanceOf(address(matchMaker)),
            0,
            "Invariant violated: balanceOf must always be greater than or equal to deposits"
        );
    }
}

contract Handler is Test {
    ConnectFourMatchMakerV1 internal matchMaker;
    TestToken internal token;
    address internal user;
    address internal opponent;

    uint256 public deposits;

    constructor(ConnectFourMatchMakerV1 _matchMaker, TestToken _testToken) {
        matchMaker = _matchMaker;
        token = _testToken;

        user = address(1);
        vm.label(user, "user");

        opponent = address(2);
        vm.label(opponent, "opponent");
    }

    receive() external payable {}

    function testRequestAndAccept(uint256 amount) public {
        amount = bound(amount, 0, UINT96_MAX);
        vm.deal(user, amount);
        vm.deal(opponent, amount);

        vm.prank(user);
        uint256 requestId = matchMaker.request{value: amount}(opponent, CURRENCY, amount);

        vm.prank(opponent);
        matchMaker.acceptRequest{value: amount}(requestId);
        deposits += amount * 2;
    }

    function testRequestAndCancel(uint256 amount) public {
        amount = bound(amount, 0, UINT96_MAX);
        vm.deal(user, amount);
        vm.deal(opponent, amount);

        vm.prank(user);
        uint256 requestId = matchMaker.request{value: amount}(opponent, CURRENCY, amount);

        vm.prank(opponent);
        matchMaker.cancelRequest(requestId);
        deposits += amount;
    }

    function testRequestAndWithdraw(uint256 amount) public {
        amount = bound(amount, 0, UINT96_MAX);
        vm.deal(user, amount);
        vm.deal(opponent, amount);

        vm.startPrank(user);
        uint256 requestId = matchMaker.request{value: amount}(opponent, CURRENCY, amount);

        matchMaker.cancelRequest(requestId);
    }

    function testPlay(uint256 amount) public {
        amount = bound(amount, 0, UINT96_MAX);
        vm.prank(user);
        vm.deal(user, amount);
        uint256 requestId = matchMaker.request{value: amount}(opponent, CURRENCY, amount);

        vm.prank(opponent);
        vm.deal(opponent, amount);
        matchMaker.acceptRequest{value: amount}(requestId);

        vm.prank(user);
        uint256 gameId = matchMaker.startMatch(requestId);

        vm.prank(opponent);
        matchMaker.move(gameId, 4);

        vm.prank(user);
        matchMaker.move(gameId, 3);

        vm.prank(opponent);
        matchMaker.move(gameId, 4);

        vm.prank(user);
        matchMaker.move(gameId, 3);

        vm.prank(opponent);
        matchMaker.move(gameId, 4);

        vm.prank(user);
        matchMaker.move(gameId, 3);

        vm.prank(opponent);
        matchMaker.move(gameId, 4);

        vm.prank(opponent);
        matchMaker.claim(gameId);
    }

    function testPlayWithTokens(uint256 amount) public {
        amount = bound(amount, 1, UINT96_MAX);
        token.mint(user, amount);
        token.mint(opponent, amount);
        vm.deal(user, 1 ether);
        vm.deal(opponent, 1 ether);

        vm.startPrank(user);
        token.approve(address(matchMaker), amount);
        uint256 requestId = matchMaker.request(opponent, address(token), amount);
        vm.stopPrank();

        vm.startPrank(opponent);
        token.approve(address(matchMaker), amount);
        matchMaker.acceptRequest(requestId);
        vm.stopPrank();

        vm.prank(user);
        uint256 gameId = matchMaker.startMatch(requestId);

        vm.prank(opponent);
        matchMaker.move(gameId, 4);

        vm.prank(user);
        matchMaker.move(gameId, 3);

        vm.prank(opponent);
        matchMaker.move(gameId, 4);

        vm.prank(user);
        matchMaker.move(gameId, 3);

        vm.prank(opponent);
        matchMaker.move(gameId, 4);

        vm.prank(user);
        matchMaker.move(gameId, 3);

        vm.prank(opponent);
        matchMaker.move(gameId, 4);

        vm.prank(opponent);
        matchMaker.claim(gameId);
    }
}
