// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ConnectFour} from "connect4-sol/ConnectFour.sol";

/// @title ConnectFourMatchMakerV1
/// @author Diego Figueroa
/// @notice A match maker contract to enable wagers in Connect Four.
contract ConnectFourMatchMakerV1 is ConnectFour {
    /// @notice Thrown when trying to accept request with non exact amount
    error InvalidTransferValue();

    /// @notice Thrown when trying to claim before game has ended
    error MatchInProgress();

    /// @notice Thrown when trying to move after game has ended
    error MatchFinished();

    /// @notice Thrown when trying to claim more than once
    error AlreadyClaimed();

    /// @notice Emitted when a match request is created
    event RequestCreated(
        address indexed challenger, address indexed challenged, address indexed token, uint256 amount, uint256 requestId
    );

    /// @notice Emitted when a match request is accepted
    event RequestAccepted(uint256 indexed requestId);

    /// @notice Emitted when a match request is canceled
    event RequestCanceled(uint256 indexed requestId);

    /// @notice Emitted when a match request is withdrawn
    event RequestWithdrawn(uint256 indexed requestId);

    /// @notice Emitted when a match is started
    event MatchStarted(
        address indexed challenger, address indexed challenged, address indexed token, uint256 amount, uint256 requestId
    );

    /// @notice Emitted when a match wager is settled
    event MatchClaimed(address indexed winner, uint256 gameId);

    /// @notice Used to represent status of requests
    enum RequestStatus {
        New,
        Accepted,
        Canceled
    }

    /// @notice Used to represent player match requests
    /// @dev Data layer for securing match deposits from players
    struct Request {
        address player1;
        address player2;
        address token;
        uint128 amount;
        RequestStatus status;
    }

    /// @notice Used to represent a game match, an extension enabling wagers
    /// for the base game struct
    struct GameMatch {
        address token;
        uint128 amount;
        uint32 lastInteracted;
        bool claimed;
    }

    /// @notice Used to represent internally player 1
    uint8 internal constant PLAYER1 = 0;

    /// @notice Used to represent internally player 2
    uint8 internal constant PLAYER2 = 1;

    /// @notice Maximum amount of moves, reaching this number means game is a tie
    uint8 internal constant MAX_MOVES = 42;

    /// @notice Address used to represent currency deposits
    address internal constant CURRENCY = address(0);

    /// @notice Counter used to represent next request's index
    uint256 internal requestId;

    /// @notice A list of requests indexed by requestId
    mapping(uint256 => Request) public getRequest;

    /// @notice A list of matches indexed by gameId
    mapping(uint256 => GameMatch) public getMatch;

    constructor() {
        requestId = 1;
    }

    /// @notice Request to start a match with an opponent
    /// @param opponent Address of the first player
    /// @param token The token address, use zero address for eth deposits
    /// @param amount Amount of tokens being wagered
    /// @return reqId The ID of the created request
    function request(address opponent, address token, uint256 amount) external payable returns (uint256 reqId) {
        bool isTokenDeposit = token != CURRENCY;
        if (isTokenDeposit) {
            require(amount > 0);
            require(IERC20(token).allowance(msg.sender, address(this)) >= amount);
        } else if (!isTokenDeposit && msg.value != amount) {
            revert InvalidTransferValue();
        }

        uint256 _requestId = requestId;
        requestId++;
        getRequest[_requestId] = Request({
            player1: opponent,
            player2: msg.sender,
            amount: SafeCastLib.safeCastTo128(amount),
            status: RequestStatus.New,
            token: token
        });
        emit RequestCreated(msg.sender, opponent, token, amount, _requestId);

        if (isTokenDeposit) {
            require(IERC20(token).transferFrom(msg.sender, address(this), amount));
        }
        return _requestId;
    }

    /// @notice Accept request for match
    /// @param reqId The ID of the request to accept
    function acceptRequest(uint256 reqId) external payable {
        Request memory req = getRequest[reqId];
        bool isP1 = msg.sender == req.player1;
        if (!isP1 || req.status != RequestStatus.New) {
            revert Unauthorized();
        }
        bool isTokenDeposit = req.token != CURRENCY;
        if (isTokenDeposit) {
            require(IERC20(req.token).allowance(msg.sender, address(this)) >= req.amount);
        } else if (!isTokenDeposit && msg.value != req.amount) {
            revert InvalidTransferValue();
        }

        getRequest[reqId].status = RequestStatus.Accepted;
        emit RequestAccepted(reqId);

        if (isTokenDeposit) {
            require(IERC20(req.token).transferFrom(msg.sender, address(this), req.amount));
        }
    }

    /// @notice Cancel request for match, will withdraw if maker of request
    /// @param reqId The ID of the request to cancel
    function cancelRequest(uint256 reqId) external {
        Request memory req = getRequest[reqId];
        bool isP1 = msg.sender == req.player1;
        bool isP2 = msg.sender == req.player2;
        if ((!isP1 && !isP2) || req.status != RequestStatus.New) {
            revert Unauthorized();
        }

        getRequest[reqId].status = RequestStatus.Canceled;
        emit RequestCanceled(reqId);
        if (isP2) {
            delete getRequest[reqId];
            emit RequestWithdrawn(reqId);

            _send(msg.sender, req.token, req.amount);
        }
    }

    /// @notice Withdraw wager from request
    /// @param reqId The ID of the request to withdraw wager from
    function withdrawRequest(uint256 reqId) external {
        Request memory req = getRequest[reqId];
        bool isP2 = msg.sender == req.player2;
        if (!isP2 || req.status != RequestStatus.Canceled) {
            revert Unauthorized();
        }

        delete getRequest[reqId];
        emit RequestWithdrawn(reqId);

        _send(msg.sender, req.token, req.amount);
    }

    /// @notice Start game after securing bets
    /// @param reqId The ID of the request to start match for
    /// @return id The ID of the newly created game
    function startMatch(uint256 reqId) external returns (uint256 id) {
        Request memory req = getRequest[reqId];
        bool isPlayer = msg.sender == req.player2;
        if (!isPlayer || req.status != RequestStatus.Accepted) {
            revert Unauthorized();
        }

        uint256 gId = super.challenge(req.player1);
        getMatch[gId] = GameMatch({
            amount: req.amount,
            lastInteracted: SafeCastLib.safeCastTo32(block.timestamp),
            claimed: false,
            token: req.token
        });
        delete getRequest[reqId];
        emit MatchStarted(req.player2, req.player1, req.token, req.amount, gId);
        return gId;
    }

    /// @notice Perform a move on an active game
    /// @param id The ID of the game you want to perform your move on
    /// @param row The row on where you want to drop your piece
    function move(uint256 id, uint8 row) external {
        GameMatch memory _match = getMatch[id];
        if (didForfeit(_match.lastInteracted)) {
            revert MatchFinished();
        }

        super.makeMove(id, row);
        getMatch[id].lastInteracted = SafeCastLib.safeCastTo32(block.timestamp);
    }

    /// @notice Claim wager of finished match
    /// @param id The ID of the game to claim match wager for
    function claim(uint256 id) external {
        GameMatch memory _match = getMatch[id];
        Game memory game = getGame[id];
        bool forfeit = didForfeit(_match.lastInteracted);
        if (!game.finished && !forfeit && game.moves != MAX_MOVES) {
            revert MatchInProgress();
        }
        if (_match.claimed) {
            revert AlreadyClaimed();
        }

        getMatch[id].claimed = true;

        uint256 payout = _match.amount * 2;
        if (super.didPlayerWin(id, PLAYER1)) {
            emit MatchClaimed(game.player1, id);

            _send(game.player1, _match.token, payout);
        } else if (super.didPlayerWin(id, PLAYER2)) {
            emit MatchClaimed(game.player2, id);

            _send(game.player2, _match.token, payout);
        } else if (forfeit) {
            address recipient = game.moves & 1 == PLAYER1 ? game.player2 : game.player1;
            emit MatchClaimed(recipient, id);

            _send(recipient, _match.token, payout);
        } else {
            emit MatchClaimed(address(0), id);

            _send(game.player1, _match.token, _match.amount);
            _send(game.player2, _match.token, _match.amount);
        }
    }

    /// @notice External view function for clients to query forfeiture state
    /// @param id The ID of the game to query forfeit state
    /// @param side Value representing player1 (0) or player2 (1)
    function didPlayerForfeit(uint256 id, uint8 side) external view returns (bool) {
        if (getGame[id].moves & 1 == side) {
            return didForfeit(getMatch[id].lastInteracted);
        }
        return false;
    }

    /// @notice Internal function responsible for any value transfer
    /// @param recipient Address to send funds to
    /// @param token Address of token, zero address means currency
    /// @param amount amount to transfer
    function _send(address recipient, address token, uint256 amount) private returns (bool) {
        if (token == CURRENCY) {
            SafeTransferLib.safeTransferETH(recipient, amount);
            return true;
        } else {
            bool sent = IERC20(token).transfer(recipient, amount);
            return sent;
        }
    }

    /// @notice Internal function that encapsulates forfeit condition
    /// @param lastInteracted timestamp of last player interaction
    function didForfeit(uint32 lastInteracted) private view returns (bool) {
        unchecked {
            return block.timestamp - lastInteracted > 3 days;
        }
    }
}
