// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICourt {

    enum Phase {
        Discovery, // fees + evidence
        JurySelection, // drawing jurors
        Voting, // jurors must commit votes
        Ruling, // jurors must reveal votes
        Verdict,
        DefaultJudgement, // one party doesn't pay - arbitration fee refunded - jury not drawn 
        Dismissed, // case is invalid, Marketplace reverts to original project conditions
        SettledExternally // case was settled by change order in marketplace (arbitration does not progress)
    }

    struct Petition {
        uint256 petitionId;
        address marketplace;
        uint256 projectId;
        uint256 adjustedProjectFee;
        uint256 providerStakeForfeit;
        address plaintiff;
        address defendant;
        uint256 arbitrationFee;
        bool feePaidPlaintiff;
        bool feePaidDefendant;
        uint256 discoveryStart;
        uint256 selectionStart;
        uint256 votingStart;
        uint256 rulingStart;
        uint256 verdictRenderedDate;
        bool isAppeal;
        bool petitionGranted;
        Phase phase;
        string[] evidence;
    }

    function createPetition(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        address _plaintiff,
        address _defendant
    ) external returns (uint256);
    function appeal(uint256 _projectId) external returns (uint256);
    function settledExternally(uint256 _petitionId) external;
    function getPetition(uint256 _petitionId) external view returns (Petition memory);


}