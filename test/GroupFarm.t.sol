// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GroupFarm} from "../contracts/GroupFarm.sol";
import {MockERC20} from "../contracts/MockERC20.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
}

contract GroupFarmTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    GroupFarm farm;
    MockERC20 rewardToken;
    MockERC20 lp0;
    MockERC20 lp1;
    MockERC20 lp2;

    address alice = address(0x1111);
    address bob = address(0x2222);

    uint256 constant DURATION = 7200; // 120 minutes
    uint256 constant REWARD_PER_POOL = 40_000 * 1e18;
    uint256 constant TOTAL_REWARD = 120_000 * 1e18;

    function setUp() public {
        rewardToken = new MockERC20("Group Fish", "GFSH");
        lp0 = new MockERC20("LP 0", "LP0");
        lp1 = new MockERC20("LP 1", "LP1");
        lp2 = new MockERC20("LP 2", "LP2");

        address[3] memory lps = [address(lp0), address(lp1), address(lp2)];
        farm = new GroupFarm(address(rewardToken), lps, DURATION, REWARD_PER_POOL);

        rewardToken.transfer(address(farm), TOTAL_REWARD);

        // Distribute LP tokens to test users
        lp0.mint(alice, 1000 * 1e18);
        lp0.mint(bob, 1000 * 1e18);
        lp1.mint(alice, 1000 * 1e18);
        lp1.mint(bob, 1000 * 1e18);
        lp2.mint(alice, 1000 * 1e18);
        lp2.mint(bob, 1000 * 1e18);

        vm.prank(alice);
        lp0.approve(address(farm), type(uint256).max);
        vm.prank(alice);
        lp1.approve(address(farm), type(uint256).max);
        vm.prank(alice);
        lp2.approve(address(farm), type(uint256).max);

        vm.prank(bob);
        lp0.approve(address(farm), type(uint256).max);
        vm.prank(bob);
        lp1.approve(address(farm), type(uint256).max);
        vm.prank(bob);
        lp2.approve(address(farm), type(uint256).max);
    }

    // 1. Viens steikotājs: Saņem visu atlīdzību par savu aktīvās dalības laiku
    function test1_SingleStakerReceivesFullReward() public {
        farm.startSession();
        uint256 start = block.timestamp;

        vm.prank(alice);
        farm.stake(0, 100 * 1e18);

        // Advance 180 seconds (3 minutes)
        // Rate per second = 40_000 * 1e18 / 7200 = 5.555... * 1e18
        // For 180 seconds = 1000 * 1e18
        vm.warp(start + 180);

        uint256 earned = farm.earned(alice, 0);
        uint256 expected = 1000 * 1e18;
        require(earned == expected, "Alice did not earn 1000 GFSH for 3 minutes");

        vm.prank(alice);
        farm.claim(0);
        require(rewardToken.balanceOf(alice) == expected, "Alice claim balance mismatch");
    }

    // 2. Otrs pievienojas vēlāk: Nesaņem atlīdzību par laiku pirms pievienošanās
    function test2_LateJoinerReceivesZeroPriorReward() public {
        farm.startSession();
        uint256 start = block.timestamp;

        // Alice stakes at start
        vm.prank(alice);
        farm.stake(0, 100 * 1e18);

        // 180 seconds pass
        vm.warp(start + 180);

        // Bob joins at t = 180 with equal stake
        vm.prank(bob);
        farm.stake(0, 100 * 1e18);

        require(farm.earned(bob, 0) == 0, "Bob should have 0 earned upon joining");

        // Advance another 180 seconds to t = 360
        vm.warp(start + 360);

        // Alice should have: 1000 (first 180s) + 500 (second 180s split 50/50) = 1500
        // Bob should have: 500 (second 180s split 50/50)
        uint256 aliceEarned = farm.earned(alice, 0);
        uint256 bobEarned = farm.earned(bob, 0);

        require(aliceEarned == 1500 * 1e18, "Alice earned mismatch after Bob joined");
        require(bobEarned == 500 * 1e18, "Bob earned mismatch after joining late");
    }

    // 3. Dalība vairākos pūlos: Katra pūla uzskaite ir neatkarīga
    function test3_MultiPoolIndependence() public {
        farm.startSession();
        uint256 start = block.timestamp;

        // Alice stakes in Pool 0 (100 LP), Bob stakes in Pool 1 (500 LP)
        vm.prank(alice);
        farm.stake(0, 100 * 1e18);

        vm.prank(bob);
        farm.stake(1, 500 * 1e18);

        // 180 seconds pass
        vm.warp(start + 180);

        // Both are sole stakers in their independent pools -> both receive exactly 1000 GFSH
        require(farm.earned(alice, 0) == 1000 * 1e18, "Pool 0 reward rate influenced");
        require(farm.earned(bob, 1) == 1000 * 1e18, "Pool 1 reward rate influenced");
        require(farm.earned(alice, 1) == 0, "Alice earned cross-pool leakage");
        require(farm.earned(bob, 0) == 0, "Bob earned cross-pool leakage");
    }

    // 4. Daļēja izņemšana: Turpmākā atlīdzība atbilst mazākam steikam
    function test4_PartialWithdrawReducesAccrual() public {
        farm.startSession();
        uint256 start = block.timestamp;

        // Alice: 100 LP, Bob: 100 LP in pool 0
        vm.prank(alice);
        farm.stake(0, 100 * 1e18);
        vm.prank(bob);
        farm.stake(0, 100 * 1e18);

        vm.warp(start + 180);
        // Each has 500 GFSH

        // Alice withdraws 50% (50 LP)
        vm.prank(alice);
        farm.withdraw(0, 50 * 1e18);

        // Alice now has 50 LP, Bob has 100 LP (Total: 150 LP). Alice share: 1/3, Bob share: 2/3
        vm.warp(start + 360);

        // During second 180s, 1000 GFSH is split 1/3 to Alice (333.333...) and 2/3 to Bob (666.666...)
        uint256 aliceEarned = farm.earned(alice, 0);
        uint256 bobEarned = farm.earned(bob, 0);

        // Alice total = 500 + 333.333333333333333333
        uint256 expectedAlice = 500 * 1e18 + (uint256(1000 * 1e18) * 50) / 150;
        uint256 expectedBob = 500 * 1e18 + (uint256(1000 * 1e18) * 100) / 150;

        uint256 diffAlice = aliceEarned > expectedAlice ? aliceEarned - expectedAlice : expectedAlice - aliceEarned;
        uint256 diffBob = bobEarned > expectedBob ? bobEarned - expectedBob : expectedBob - bobEarned;
        require(diffAlice <= 1000, "Alice earnings mismatch after partial withdraw");
        require(diffBob <= 1000, "Bob earnings mismatch after Alice partial withdraw");
    }

    // 5. Atkārtots claim: Jau izmaksāto nevar saņemt vēlreiz
    function test5_RepeatedClaimGivesZero() public {
        farm.startSession();
        uint256 start = block.timestamp;

        vm.prank(alice);
        farm.stake(0, 100 * 1e18);

        vm.warp(start + 180);

        vm.prank(alice);
        farm.claim(0);
        uint256 balAfterFirst = rewardToken.balanceOf(alice);
        require(balAfterFirst == 1000 * 1e18, "First claim failed");

        // Immediately claim again at same timestamp
        vm.prank(alice);
        farm.claim(0);
        uint256 balAfterSecond = rewardToken.balanceOf(alice);
        require(balAfterSecond == balAfterFirst, "Repeated claim paid out duplicate rewards");
    }

    // 6. Tukšs pūls: Tukšā laika atlīdzība nepienākas nākamajam steikotājam
    function test6_EmptyPoolTimeBudgetSkipped() public {
        farm.startSession();
        uint256 start = block.timestamp;

        // Pool 0 remains completely empty for first 180 seconds
        vm.warp(start + 180);

        // Alice stakes at t = 180
        vm.prank(alice);
        farm.stake(0, 100 * 1e18);

        // Another 180 seconds pass (t = 360)
        vm.warp(start + 360);

        // Alice must receive only 1000 GFSH (for t=180..360), NOT 2000 GFSH!
        uint256 earned = farm.earned(alice, 0);
        require(earned == 1000 * 1e18, "Empty pool budget wrongly awarded to future staker");
    }

    // 7. Kampaņas beigas: Jaunas atlīdzības neuzkrājas, bet claim un withdraw darbojas
    function test7_CampaignEndStopsAccrualAllowsWithdrawAndClaim() public {
        farm.startSession();
        uint256 start = block.timestamp;

        vm.prank(alice);
        farm.stake(0, 100 * 1e18);

        // Warp past end of campaign (7200 + 3600 seconds)
        vm.warp(start + DURATION + 3600);

        // Alice should have earned exactly full pool reward: 40_000 GFSH
        uint256 earned = farm.earned(alice, 0);
        require(earned == REWARD_PER_POOL, "Earned exceeds or does not match full pool cap");

        // Alice can withdraw her LP principal in full
        uint256 lpBefore = lp0.balanceOf(alice);
        vm.prank(alice);
        farm.withdraw(0, 100 * 1e18);
        require(lp0.balanceOf(alice) == lpBefore + 100 * 1e18, "LP principal recovery failed");

        // Alice can claim her earned reward in full
        vm.prank(alice);
        farm.claim(0);
        require(rewardToken.balanceOf(alice) == REWARD_PER_POOL, "Reward claim at campaign end failed");
    }

    // 8. Nepareizs tokens: To nevar iesniegt kā reģistrēto LP
    function test8_InvalidPoolReverts() public {
        farm.startSession();
        vm.prank(alice);
        (bool success, ) = address(farm).call(abi.encodeWithSignature("stake(uint256,uint256)", 3, 100));
        require(!success, "Staking to non-existent pool 3 succeeded unexpectedly");
    }

    // 9. Fonda pārbaude: Izmaksātais un vēl pienākošais nepārsniedz finansēto budžetu
    function test9_FundConservationInvariant() public {
        farm.startSession();
        uint256 start = block.timestamp;

        vm.prank(alice);
        farm.stake(0, 100 * 1e18);
        vm.prank(bob);
        farm.stake(1, 200 * 1e18);

        vm.warp(start + 3600); // 1 hour into session

        vm.prank(alice);
        farm.claim(0);

        vm.warp(start + DURATION + 1000); // After end

        vm.prank(bob);
        farm.claim(1);

        uint256 totalClaimed = farm.totalRewardsClaimed();
        uint256 farmBal = rewardToken.balanceOf(address(farm));

        // Conservation of funds: totalClaimed + farmBal == TOTAL_REWARD
        require(totalClaimed + farmBal == TOTAL_REWARD, "Token balance invariant violated");
        require(totalClaimed <= TOTAL_REWARD, "Total claimed exceeds funded budget");
    }
}
