// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICourt {

    enum Phase {
        Discovery, 
        JurySelection, 
        Voting, 
        Ruling, 
        Verdict,
        DefaultJudgement, 
        Dismissed, 
        SettledExternally 
    }

    struct Petition {
        uint256 petitionId;
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