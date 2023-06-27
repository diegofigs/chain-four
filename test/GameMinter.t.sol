// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../src/ConnectFourMatchMakerV1.sol";
import "../src/GameMinter.sol";

contract GameMinterTest is Test {
    GameMinter internal nft;
    ConnectFourMatchMakerV1 internal game;
    address internal user;

    function setUp() public {
        user = address(1);
        vm.label(user, "user");

        game = new ConnectFourMatchMakerV1();
        nft = new GameMinter(game);
    }

    function test_mint_CanMintFinishedGame() public {
        uint256 gameId = _getFinishedGame();

        vm.expectRevert("NOT_MINTED");
        nft.ownerOf(gameId);

        nft.mint(gameId);

        assertEq(nft.ownerOf(gameId), address(this));

        string memory uri = nft.tokenURI(gameId);
        assertNotEq(uri, "");
    }

    function test_RevertWhen_mint_UserCannotMintUnfinishedGame() public {
        vm.prank(user);

        uint256 gameId = 0;
        vm.expectRevert("NOT_MINTED");
        nft.ownerOf(gameId);

        vm.expectRevert(GameMinter.CannotMintGame.selector);
        nft.mint(gameId);
    }

    function test_RevertWhen_mint_LoserCannotMintFinishedGame() public {
        uint256 gameId = _getFinishedGame();

        vm.expectRevert("NOT_MINTED");
        nft.ownerOf(gameId);

        vm.prank(user);
        vm.expectRevert(GameMinter.CannotMintGame.selector);
        nft.mint(gameId);

        vm.expectRevert("NOT_MINTED");
        nft.ownerOf(gameId);
    }

    function _getFinishedGame() internal returns (uint256) {
        uint256 value = 1 ether;
        vm.prank(user);
        vm.deal(user, value);
        uint256 requestId = game.request{value: value}(address(this), address(0), value);

        game.acceptRequest{value: value}(requestId);

        vm.prank(user);
        uint256 gameId = game.startMatch(requestId);

        game.move(gameId, 4);

        vm.prank(user);
        game.move(gameId, 3);

        game.move(gameId, 4);

        vm.prank(user);
        game.move(gameId, 3);

        game.move(gameId, 4);

        vm.prank(user);
        game.move(gameId, 3);

        game.move(gameId, 4);

        game.claim(gameId);

        return gameId;
    }

    receive() external payable {}
}
