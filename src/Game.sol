// contracts/GameLeaderboard.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./GameLeaderboard.sol";
import "./MinimalForwarder.sol";
import "./GameTicket.sol";

contract Game is Ownable {
    uint public gameId;
    string public gameName;
    GameTicket public gameTicket;
    Round public round;
    MinimalForwarder public minimalForwarder;
    address public gameDev;
    address public lotto;

    uint public constant PLATFORM_SHARE = 0; // We are not apple store. We give away 100% to the community to start with.
    uint public constant GAME_DEV_SHARE = 1; // This can be configured later.
    uint public constant FIRST = 3; // 30% prize goes to 1st ranked player
    uint public constant SECOND = 2; // 20% prize goes to 2nd ranked player
    uint public constant THIRD = 1; // 10% prize goes to 3rd ranked player
    uint public constant OTHERS = 3; // 30% prize goes to other ranked players

    uint gameDevPrize;
    uint firstPrize;
    uint secondPrize;
    uint thirdPrize;
    uint sharedPrize;

    IBlast public constant BLAST_YIELD =
        IBlast(0x4300000000000000000000000000000000000002);
    IERC20Rebasing public constant USDB =
        IERC20Rebasing(0x4200000000000000000000000000000000000022);
    IERC20Rebasing public constant WETH =
        IERC20Rebasing(0x4200000000000000000000000000000000000023);

    struct Round {
        uint256 length; // in seconds
        uint256 gameRound; // current game round
        uint256 end; // timestamp
        uint claimPeriod; // the time period the players can claim reward
        GameLeaderboard gameLeaderBoard;
        bool hasClaimedBySomeone;
        uint rewardPool;
    }

    event ScoreUpdated(
        address indexed user,
        uint gameId,
        Round round,
        string gameName,
        GameLeaderboard.User[] gameLeaderboardInfo,
        uint score
    );

    event ClaimReward (
        address indexed user,
        uint totalClaimedPrize,
        Round round,
        uint _gameId,
        string _gameName
    );

    event NewRound (
        uint indexed gameId, 
        string gameName, 
        Round round
    );

    event RedeemTicket(
        address indexed player, 
        uint _ticketType, 
        uint ticketPrice, 
        uint gameId, 
        string gameName, 
        Round round
    );

    constructor(
        uint _gameId,
        string memory _gameName,
        uint _roundLength,
        uint _claimPeriod,
        address _minimalForwader,
        address _gameTicket,
        address _gameDev,
        address _lotto
    ) {
        gameId = _gameId;
        gameName = _gameName;
        minimalForwarder = MinimalForwarder(_minimalForwader);
        gameTicket = GameTicket(_gameTicket);

        gameDev = _gameDev;

        lotto = _lotto;

        round = Round({
            length: _roundLength,
            gameRound: 1,
            end: block.timestamp + _roundLength,
            claimPeriod: _claimPeriod,
            gameLeaderBoard: new GameLeaderboard(_gameId, _gameName),
            hasClaimedBySomeone: false,
            rewardPool: address(this).balance
        });

        BLAST_YIELD.configureClaimableGas();
        BLAST_YIELD.configureClaimableYield();
        BLAST_YIELD.configureGovernor(address(this));
    }

    modifier onlyTrustedForwarder() {
        require(
            msg.sender == address(minimalForwarder),
            "only trusted sender can add score"
        );
        _;
    }

    /**
     * Helper functions to update game period and endTime  
     */
    function updateGamePeriodAndEndTime(uint length) external onlyOwner {
        round = Round({
            length: length,
            gameRound: round.gameRound,
            end: block.timestamp + length,
            claimPeriod: round.claimPeriod,
            gameLeaderBoard: getCurrentGameBoard(),
            hasClaimedBySomeone: false,
            rewardPool: address(this).balance
        });
    }

    /**
     * Helper functions to update claim period
     */
    function updateClaimPeriod(uint newClaimPeriod) external onlyOwner {
        round = Round({
            length: round.length,
            gameRound: round.gameRound,
            end: round.end,
            claimPeriod: newClaimPeriod,
            gameLeaderBoard: getCurrentGameBoard(),
            hasClaimedBySomeone: false,
            rewardPool: address(this).balance
        });
    }

    /**
     * This function should only be called from trusted backend and trusted forwarder address
     */
    function addScore(address user, uint score) external onlyTrustedForwarder {
        require(isGameRunning(), "Game is not running");

        GameLeaderboard _gameLeaderBoard = getCurrentGameBoard();
        _gameLeaderBoard.addScore(user, score);

        GameLeaderboard.User[] memory _gameLeaderboardInfo = _gameLeaderBoard
            .getLeaderBoardInfo();

        emit ScoreUpdated(
            user,
            gameId,
            round,
            gameName,
            _gameLeaderboardInfo,
            score
        );
    }

    /**
     * The user can claim game prize if they are top 10 players
     */
    function claimReward() external {
        require(isClaiming(), "It is not in the claim prize period");

        GameLeaderboard _gameLeaderBoard = getCurrentGameBoard();

        uint leaderBoardLength = _gameLeaderBoard.leaderboardLength();

        uint256 totalBalance = address(this).balance;
        uint totalClaimedPrize = 0;
        if (!round.hasClaimedBySomeone) {
            gameDevPrize = (totalBalance * GAME_DEV_SHARE) / 10;
            firstPrize = (totalBalance * FIRST) / 10;
            secondPrize = (totalBalance * SECOND) / 10;
            thirdPrize = (totalBalance * THIRD) / 10;
            sharedPrize = (totalBalance * OTHERS) / (10 * 7);
            totalClaimedPrize += gameDevPrize;
            (bool sent, ) = gameDev.call{value: gameDevPrize}(""); // send to gamedev money
            require(sent, "Failed to send Ether");
            round.hasClaimedBySomeone = true;

            emit ClaimReward(gameDev, totalClaimedPrize, getCurrentGameRound(), gameId, gameName);
        }

        
        for (uint i = 0; i < leaderBoardLength; i++) {
            GameLeaderboard.User memory currentUser = _gameLeaderBoard.getUser(
                i
            );

            if (currentUser.user == msg.sender) {
                require(
                    currentUser.prizeClaimed == false,
                    "You already claimed Prize"
                );

                if (i == 0) {
                    // 1st player
                    totalClaimedPrize += firstPrize;
                    (bool sent, ) = msg.sender.call{value: firstPrize}("");
                    require(sent, "Failed to send Ether");
                } else if (i == 1) {
                    // 2nd player
                    totalClaimedPrize += secondPrize;
                    (bool sent, ) = msg.sender.call{value: secondPrize}("");
                    require(sent, "Failed to send Ether");
                } else if (i == 2) {
                    // third player
                    totalClaimedPrize += thirdPrize;
                    (bool sent, ) = msg.sender.call{value: thirdPrize}("");
                    require(sent, "Failed to send Ether");
                } else {
                    // others
                    totalClaimedPrize += sharedPrize;
                    (bool sent, ) = msg.sender.call{value: sharedPrize}("");
                    require(sent, "Failed to send Ether");
                }

                currentUser.prizeClaimed = true;
            }
        }

        emit ClaimReward(msg.sender, totalClaimedPrize, getCurrentGameRound(), gameId, gameName);
    }

    function isGameRunning() public view returns (bool) {
        return block.timestamp < round.end;
    }

    function isClaiming() public view returns (bool) {
        return
            block.timestamp > round.end &&
            block.timestamp < round.end + round.claimPeriod;
    }

    function secondsToNextRound() public view returns (uint256 seconds_) {
        if (round.end <= block.timestamp) {
            return 0;
        } else {
            return round.end - block.timestamp;
        }
    }

    function getCurrentGameBoard()
        public
        view
        returns (GameLeaderboard gameLeaderboard)
    {
        return round.gameLeaderBoard;
    }

    function getCurrentGameRound() public view returns (Round memory) {
        return round;
    }

    function getLeaderBoardInfo()
        public
        view
        returns (GameLeaderboard.User[] memory)
    {
        GameLeaderboard _gameLeaderBoard = getCurrentGameBoard();
        return _gameLeaderBoard.getLeaderBoardInfo();
    }

    function startNewGameRound() private {
        require(
            block.timestamp > round.end + round.claimPeriod,
            "Pending on claim prize"
        );

        BLAST_YIELD.claimAllGas(address(this), lotto);
        BLAST_YIELD.claimAllYield(address(this), lotto);

        round = Round({
            length: round.length,
            gameRound: round.gameRound + 1,
            end: block.timestamp + round.length,
            claimPeriod: round.claimPeriod,
            gameLeaderBoard: new GameLeaderboard(gameId, gameName),
            hasClaimedBySomeone: false,
            rewardPool: address(this).balance
        });

        emit NewRound(gameId, gameName, round);
    }

    function redeemTicket(uint8 _ticketType) external returns (uint8) {
        require(
            _ticketType == gameTicket.BRONZE() ||
                _ticketType == gameTicket.SILVER() ||
                _ticketType == gameTicket.GOLD(),
            "The ticket type is wrong!"
        );
        require(
            gameTicket.balanceOf(msg.sender, _ticketType) >= 1,
            "You don't own the ticket"
        );

        if (!isGameRunning() && !isClaiming()) {
            startNewGameRound();
        }

        //need to setApprovalForAll or override burn function
        gameTicket.burn(msg.sender, _ticketType, 1);
        uint ticketPrice = gameTicket.getTicketPrice(_ticketType);
        round.rewardPool += ticketPrice;

        gameTicket.sendPrize(_ticketType, payable(address(this)));

        emit RedeemTicket(msg.sender, _ticketType, ticketPrice, gameId, gameName, round);

        return _ticketType;
    }

    function configureGovernor(address _governor) external onlyOwner {
        BLAST_YIELD.configureGovernor(_governor);
    }

    function claimAllYield(address recipient) external onlyOwner {
        BLAST_YIELD.claimAllYield(address(this), recipient);
    }

    function claimAllGas(address recipient) external onlyOwner {
        BLAST_YIELD.claimAllGas(address(this), recipient);
    }

    function claimMaxGas(address recipient) external onlyOwner {
        BLAST_YIELD.claimMaxGas(address(this), recipient);
    }

    function withdrawAll() public payable onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }

    receive() external payable {}
}
