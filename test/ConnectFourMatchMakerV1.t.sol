// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {Counters} from "@openzeppelin/utils/Counters.sol";
import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ConnectFour as ConnectFourBase} from "connect4-sol/ConnectFour.sol";
import {ConnectFourMatchMakerV1} from "../src/ConnectFourMatchMakerV1.sol";
import {TestToken} from "../src/TestToken.sol";

address constant CURRENCY = address(0);
uint256 constant UINT96_MAX = type(uint96).max;

contract ConnectFourMakerV1Test is Test {
    event RequestCreated(
        address indexed challenger, address indexed challenged, address indexed token, uint256 value, uint256 requestId
    );
    event RequestAccepted(uint256 indexed requestId);
    event RequestCanceled(uint256 indexed requestId);
    event RequestWithdrawn(uint256 indexed requestId);
    event MatchStarted(
        address indexed challenger, address indexed challenged, address indexed token, uint256 value, uint256 requestId
    );
    event MatchClaimed(address indexed winner, uint256 gameId);

    ConnectFourMatchMakerV1 internal matchMaker;
    TestToken internal testToken;
    address internal user;
    address internal opponent;

    function setUp() public {
        user = address(1);
        vm.label(user, "user");

        opponent = address(2);
        vm.label(opponent, "opponent");

        matchMaker = new ConnectFourMatchMakerV1();
        testToken = new TestToken("Test Token", "TEST");
    }

    // function test_RevertWhen_initialize_CalledTwice() public {
    //     vm.expectRevert("Initializable: contract is already initialized");
    //     matchMaker.initialize();
    // }

    function test_request_UsersCanCreateWithValue() public {
        uint256 value = 1 ether;
        vm.deal(user, value);

        vm.startPrank(user);
        vm.expectRevert(ConnectFourMatchMakerV1.InvalidTransferValue.selector);
        matchMaker.request(opponent, CURRENCY, value);

        vm.expectEmit();
        emit RequestCreated(user, opponent, CURRENCY, value, 1);

        uint256 requestId = matchMaker.request{value: value}(opponent, CURRENCY, value);
        vm.stopPrank();

        (address player1, address player2, address token, uint256 amount, ConnectFourMatchMakerV1.RequestStatus status)
        = matchMaker.getRequest(requestId);

        assertEq(player1, opponent, "player1");
        assertEq(player2, user, "player2");
        assertEq(token, CURRENCY, "token");
        assertEq(amount, value, "amount");
        assertEq(status == ConnectFourMatchMakerV1.RequestStatus.New, true, "status");
    }

    function test_request_UsersCanCreateWithTokens() public {
        uint256 value = 1e18;
        vm.startPrank(user);

        vm.expectRevert();
        matchMaker.request(opponent, address(testToken), 0);

        vm.expectRevert();
        matchMaker.request(opponent, address(testToken), value);

        testToken.approve(address(matchMaker), value);

        vm.expectRevert();
        matchMaker.request(opponent, address(testToken), value);

        testToken.mint(user, value);
        vm.mockCall(address(testToken), abi.encodeWithSelector(ERC20.transferFrom.selector), abi.encode(false));
        vm.expectRevert();
        matchMaker.request(opponent, address(testToken), value);
        vm.clearMockedCalls();

        vm.expectEmit(true, true, true, false);
        emit RequestCreated(user, opponent, address(testToken), value, 1);

        uint256 requestId = matchMaker.request(opponent, address(testToken), value);
        vm.stopPrank();

        (address player1, address player2, address token, uint256 amount, ConnectFourMatchMakerV1.RequestStatus status)
        = matchMaker.getRequest(requestId);

        assertEq(player1, opponent, "player1");
        assertEq(player2, user, "player2");
        assertEq(token, address(testToken), "token");
        assertEq(amount, value, "amount");
        assertEq(status == ConnectFourMatchMakerV1.RequestStatus.New, true, "status");
    }

    function testFuzz_request_UsersCanSupplyValue(uint128 fuzzed) public {
        vm.prank(user);
        vm.deal(user, fuzzed);
        uint256 balance = address(user).balance;
        uint256 requestId = matchMaker.request{value: fuzzed}(opponent, CURRENCY, fuzzed);

        (,,, uint256 amount,) = matchMaker.getRequest(requestId);

        assertEq(amount, fuzzed, "amount");
        assertEq(user.balance, balance - fuzzed, "balance");
    }

    function testFuzz_request_UsersCanSupplyTokens(uint128 fuzzed) public {
        vm.assume(fuzzed > 0);
        testToken.mint(user, fuzzed);
        uint256 balance = testToken.balanceOf(user);

        vm.startPrank(user);
        testToken.approve(address(matchMaker), fuzzed);
        uint256 requestId = matchMaker.request(opponent, address(testToken), fuzzed);
        vm.stopPrank();

        (,,, uint256 amount,) = matchMaker.getRequest(requestId);

        assertEq(amount, fuzzed, "amount");
        assertEq(user.balance, balance - fuzzed, "balance");
    }

    function test_acceptRequest_UsersCanAcceptWithValue() public {
        uint256 value = 1 ether;
        vm.deal(user, value);
        vm.deal(opponent, value);

        vm.prank(user);
        uint256 requestId = matchMaker.request{value: value}(opponent, CURRENCY, value);

        vm.prank(user);
        vm.expectRevert(ConnectFourBase.Unauthorized.selector);
        matchMaker.acceptRequest(requestId);

        vm.prank(opponent);
        vm.expectRevert(ConnectFourMatchMakerV1.InvalidTransferValue.selector);
        matchMaker.acceptRequest{value: 0}(requestId);

        vm.prank(opponent);
        vm.expectEmit();
        emit RequestAccepted(requestId);
        matchMaker.acceptRequest{value: value}(requestId);

        (,,,, ConnectFourMatchMakerV1.RequestStatus status) = matchMaker.getRequest(requestId);
        assertEq(status == ConnectFourMatchMakerV1.RequestStatus.Accepted, true, "status");
    }

    function test_acceptRequest_UsersCanAcceptWithTokens() public {
        uint256 value = 1e18;
        vm.deal(user, value);
        vm.deal(opponent, value);

        vm.startPrank(user);
        testToken.mint(user, value);
        testToken.approve(address(matchMaker), value);
        uint256 requestId = matchMaker.request{value: value}(opponent, address(testToken), value);
        vm.stopPrank();

        vm.startPrank(opponent);
        vm.expectRevert();
        matchMaker.acceptRequest(requestId);

        testToken.approve(address(matchMaker), value);

        testToken.mint(opponent, value);
        vm.mockCall(address(testToken), abi.encodeWithSelector(ERC20.transferFrom.selector), abi.encode(false));
        vm.expectRevert();
        matchMaker.acceptRequest(requestId);
        vm.clearMockedCalls();

        vm.expectEmit();
        emit RequestAccepted(requestId);
        matchMaker.acceptRequest(requestId);
        vm.stopPrank();

        (,,,, ConnectFourMatchMakerV1.RequestStatus status) = matchMaker.getRequest(requestId);
        assertEq(status == ConnectFourMatchMakerV1.RequestStatus.Accepted, true, "status");
    }

    function testFuzz_acceptRequest_UsersCanSupplyValue(uint128 fuzzed) public {
        vm.prank(user);
        vm.deal(user, fuzzed);
        uint256 requestId = matchMaker.request{value: fuzzed}(opponent, CURRENCY, fuzzed);

        vm.prank(opponent);
        vm.deal(opponent, fuzzed);
        matchMaker.acceptRequest{value: fuzzed}(requestId);

        (,,,, ConnectFourMatchMakerV1.RequestStatus status) = matchMaker.getRequest(requestId);
        assertEq(status == ConnectFourMatchMakerV1.RequestStatus.Accepted, true, "status");
    }

    function testFuzz_acceptRequest_UsersCanSupplyTokens(uint128 fuzzed) public {
        vm.assume(fuzzed > 0);
        testToken.mint(user, fuzzed);
        testToken.mint(opponent, fuzzed);

        vm.startPrank(user);
        testToken.approve(address(matchMaker), fuzzed);
        uint256 requestId = matchMaker.request(opponent, address(testToken), fuzzed);
        vm.stopPrank();

        vm.startPrank(opponent);
        testToken.approve(address(matchMaker), fuzzed);
        matchMaker.acceptRequest(requestId);
        vm.stopPrank();

        (,,,, ConnectFourMatchMakerV1.RequestStatus status) = matchMaker.getRequest(requestId);
        assertEq(status == ConnectFourMatchMakerV1.RequestStatus.Accepted, true, "status");
    }

    function test_cancelRequest_TakersCanCancel() public {
        vm.prank(user);
        uint256 requestId = matchMaker.request(opponent, CURRENCY, 0);

        vm.prank(address(3));
        vm.expectRevert(ConnectFourBase.Unauthorized.selector);
        matchMaker.cancelRequest(requestId);

        vm.prank(opponent);
        vm.expectEmit();
        emit RequestCanceled(requestId);
        matchMaker.cancelRequest(requestId);

        (,,,, ConnectFourMatchMakerV1.RequestStatus status) = matchMaker.getRequest(requestId);
        assertEq(status == ConnectFourMatchMakerV1.RequestStatus.Canceled, true, "status");
    }

    function test_cancelRequest_MakersCanCancel() public {
        uint256 value = 1 ether;
        vm.deal(user, 1 ether);

        vm.prank(user);
        uint256 requestId = matchMaker.request{value: value}(opponent, CURRENCY, value);

        uint256 balanceBeforeWithdraw = user.balance;
        vm.prank(user);
        matchMaker.cancelRequest(requestId);

        assertEq(user.balance, balanceBeforeWithdraw + value, "user.balance");
    }

    function test_withdrawRequest_MakersCanWithdraw() public {
        uint256 value = 1 ether;
        vm.deal(user, 1 ether + value);

        vm.prank(user);
        uint256 requestId = matchMaker.request{value: value}(opponent, CURRENCY, value);

        vm.prank(opponent);
        vm.expectRevert(ConnectFourBase.Unauthorized.selector);
        matchMaker.withdrawRequest(requestId);

        vm.prank(user);
        vm.expectRevert(ConnectFourBase.Unauthorized.selector);
        matchMaker.withdrawRequest(requestId);

        vm.prank(opponent);
        matchMaker.cancelRequest(requestId);

        vm.prank(user);
        vm.expectEmit();
        emit RequestWithdrawn(requestId);
        matchMaker.withdrawRequest(requestId);
    }

    function testFuzz_withdrawRequest_UsersCanWithdrawValue(uint128 fuzzed) public {
        vm.prank(user);
        vm.deal(user, fuzzed);
        uint256 requestId = matchMaker.request{value: fuzzed}(opponent, CURRENCY, fuzzed);

        vm.prank(opponent);
        matchMaker.cancelRequest(requestId);

        uint256 balanceBeforeWithdraw = user.balance;
        vm.prank(user);
        matchMaker.withdrawRequest(requestId);

        assertEq(user.balance, balanceBeforeWithdraw + fuzzed, "user.balance");
    }

    function testFuzz_withdrawRequest_UsersCanWithdrawTokens(uint128 fuzzed) public {
        vm.assume(fuzzed > 0);
        testToken.mint(user, fuzzed);
        testToken.mint(opponent, fuzzed);

        vm.startPrank(user);
        testToken.approve(address(matchMaker), fuzzed);
        uint256 requestId = matchMaker.request(opponent, address(testToken), fuzzed);
        vm.stopPrank();

        vm.prank(opponent);
        matchMaker.cancelRequest(requestId);

        uint256 balanceBeforeWithdraw = testToken.balanceOf(user);
        vm.prank(user);
        matchMaker.withdrawRequest(requestId);

        assertEq(testToken.balanceOf(user), balanceBeforeWithdraw + fuzzed, "user.balance");
    }

    function test_startMatch_UsersCanStart() public {
        vm.prank(user);
        uint256 requestId = matchMaker.request(opponent, CURRENCY, 0);

        vm.prank(user);
        vm.expectRevert(ConnectFourBase.Unauthorized.selector);
        matchMaker.startMatch(requestId);

        vm.prank(opponent);
        vm.expectRevert(ConnectFourBase.Unauthorized.selector);
        matchMaker.startMatch(requestId);

        vm.prank(opponent);
        matchMaker.acceptRequest(requestId);

        vm.prank(user);
        vm.expectEmit();
        emit MatchStarted(user, opponent, CURRENCY, 0, requestId);
        matchMaker.startMatch(requestId);

        (,, uint32 lastInteracted,) = matchMaker.getMatch(requestId);
        assertEq(lastInteracted, block.number, "lastInteracted");
    }

    function test_move_UsersCanMove() public {
        vm.prank(user);
        uint256 requestId = matchMaker.request(opponent, CURRENCY, 0);

        vm.prank(opponent);
        matchMaker.acceptRequest(requestId);

        vm.prank(user);
        vm.expectEmit();
        emit MatchStarted(user, opponent, CURRENCY, 0, requestId);
        uint256 gameId = matchMaker.startMatch(requestId);

        /// 1 block past 3 days
        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(opponent);
        vm.expectRevert(ConnectFourMatchMakerV1.MatchFinished.selector);
        matchMaker.move(gameId, 4);
    }

    function test_claim_UsersCanClaimByWin() public {
        uint256 value = 1 ether;
        vm.prank(user);
        vm.deal(user, value);
        uint256 requestId = matchMaker.request{value: value}(opponent, CURRENCY, value);

        vm.prank(opponent);
        vm.deal(opponent, value);
        matchMaker.acceptRequest{value: value}(requestId);

        vm.prank(user);
        uint256 gameId = matchMaker.startMatch(requestId);

        vm.prank(opponent);
        matchMaker.move(gameId, 1);

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

        vm.prank(user);
        vm.expectRevert(ConnectFourMatchMakerV1.MatchInProgress.selector);
        matchMaker.claim(gameId);

        vm.prank(user);
        matchMaker.move(gameId, 3);

        vm.prank(user);
        matchMaker.claim(gameId);

        vm.prank(user);
        vm.expectRevert(ConnectFourMatchMakerV1.AlreadyClaimed.selector);
        matchMaker.claim(gameId);

        (,, uint32 lastInteracted, bool claimed) = matchMaker.getMatch(requestId);
        assertEq(lastInteracted, block.number, "lastInteracted");
        assertEq(claimed, true, "claimed");
    }

    function test_claim_UsersCanClaimByTie() public {
        uint256 value = 1 ether;
        vm.prank(user);
        vm.deal(user, value);
        uint256 requestId = matchMaker.request{value: value}(opponent, CURRENCY, value);

        vm.prank(opponent);
        vm.deal(opponent, value);
        matchMaker.acceptRequest{value: value}(requestId);

        vm.prank(user);
        uint256 gameId = matchMaker.startMatch(requestId);
        uint8[42] memory moves = [
            0,
            1,
            0,
            1,
            0,
            1,
            2,
            3,
            2,
            3,
            2,
            3,
            4,
            5,
            4,
            5,
            4,
            5,
            1,
            0,
            1,
            0,
            1,
            0,
            3,
            2,
            3,
            2,
            3,
            2,
            5,
            4,
            5,
            4,
            5,
            4,
            6,
            6,
            6,
            6,
            6,
            6
        ];
        for (uint8 i = 0; i < moves.length; i++) {
            bool isOpponent = i % 2 == 0;
            vm.prank(isOpponent ? opponent : user);
            matchMaker.move(gameId, moves[i]);
        }

        vm.prank(user);
        matchMaker.claim(gameId);

        (,, uint32 lastInteracted, bool claimed) = matchMaker.getMatch(requestId);
        assertEq(lastInteracted, block.number, "lastInteracted");
        assertEq(claimed, true, "claimed");
    }

    function test_claim_UsersCanClaimByForfeit() public {
        uint256 value = 1e18;
        vm.deal(user, value);
        vm.deal(opponent, value);

        vm.startPrank(user);
        testToken.mint(user, value);
        testToken.approve(address(matchMaker), value);
        uint256 requestId = matchMaker.request(opponent, address(testToken), value);
        vm.stopPrank();

        vm.startPrank(opponent);
        testToken.mint(opponent, value);
        testToken.approve(address(matchMaker), value);
        matchMaker.acceptRequest(requestId);
        vm.stopPrank();

        vm.prank(user);
        uint256 gameId = matchMaker.startMatch(requestId);
        uint256 matchStartedAt = block.number;

        /// 1 block past 3 days
        vm.warp(block.timestamp + 3 days + 1);
        assertEq(matchMaker.didPlayerForfeit(gameId, 0), true, "forfeitP1");
        assertEq(matchMaker.didPlayerForfeit(gameId, 1), false, "forfeitP2");

        vm.prank(user);
        matchMaker.claim(gameId);

        (,, uint32 lastInteracted, bool claimed) = matchMaker.getMatch(requestId);
        assertEq(lastInteracted, matchStartedAt, "lastInteracted");
        assertEq(claimed, true, "claimed");

        vm.startPrank(user);
        testToken.mint(user, value);
        testToken.approve(address(matchMaker), value);
        uint256 requestId2 = matchMaker.request(opponent, address(testToken), value);
        vm.stopPrank();

        vm.startPrank(opponent);
        testToken.mint(opponent, value);
        testToken.approve(address(matchMaker), value);
        matchMaker.acceptRequest(requestId2);
        vm.stopPrank();

        vm.prank(user);
        uint256 gameId2 = matchMaker.startMatch(requestId2);

        vm.prank(opponent);
        matchMaker.move(gameId2, 4);

        /// 1 block past 3 days
        vm.warp(block.timestamp + 3 days + 1);
        assertEq(matchMaker.didPlayerForfeit(gameId2, 0), false, "forfeit2P1");
        assertEq(matchMaker.didPlayerForfeit(gameId2, 1), true, "forfeit2P2");

        vm.prank(user);
        matchMaker.claim(gameId2);

        (,,, bool claimed2) = matchMaker.getMatch(requestId2);
        assertEq(claimed2, true, "claimed2");
    }

    function testFuzz_claim_UsersCanClaimValue(uint96 fuzzed) public {
        vm.prank(user);
        vm.deal(user, fuzzed);
        uint256 requestId = matchMaker.request{value: fuzzed}(opponent, CURRENCY, fuzzed);

        vm.prank(opponent);
        vm.deal(opponent, fuzzed);
        matchMaker.acceptRequest{value: fuzzed}(requestId);

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

        (,,, bool claimed) = matchMaker.getMatch(requestId);
        assertEq(claimed, true, "claimed");
    }

    function testFuzz_claim_UsersCanClaimTokens(uint96 fuzzed) public {
        vm.assume(fuzzed > 0);
        testToken.mint(user, fuzzed);
        testToken.mint(opponent, fuzzed);
        vm.deal(user, 1 ether);
        vm.deal(opponent, 1 ether);

        vm.startPrank(user);
        testToken.approve(address(matchMaker), fuzzed);
        uint256 requestId = matchMaker.request(opponent, address(testToken), fuzzed);
        vm.stopPrank();

        vm.startPrank(opponent);
        testToken.approve(address(matchMaker), fuzzed);
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

        (,,, bool claimed) = matchMaker.getMatch(requestId);
        assertEq(claimed, true, "claimed");
    }
}
