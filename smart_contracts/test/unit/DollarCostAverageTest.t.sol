// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {AutomationLayer} from "../../src/AutomationLayer.sol";
import {DollarCostAverage, IDollarCostAverage} from "../../src/DollarCostAverage.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DollarCostAverageTest is Test {
    /* solhint-disable */
    Deploy deployer;
    HelperConfig config;
    AutomationLayer automation;
    DollarCostAverage dca;
    address token1;
    address token2;
    address defaultRouter;
    address wrapNative;
    address signer;

    address public user = makeAddr("user");
    address public PAYMENT_INTERFACE = makeAddr("userInterface");

    uint256 public constant INITAL_DEX_ERC20_FUNDS = 100 ether;
    uint256 public constant INITAL_USER_ERC20_FUNDS = 100 ether;
    uint256 public constant INITAL_USER_FUNDS = 100 ether;

    /* solhint-enable */

    /// -----------------------------------------------------------------------
    /// Events to test
    /// -----------------------------------------------------------------------

    event RecurringBuyCreated(
        uint256 indexed recBuyId,
        address indexed sender,
        IDollarCostAverage.RecurringBuy buy
    );

    event RecurringBuyCancelled(
        uint256 indexed recBuyId,
        address indexed sender
    );

    event PaymentTransferred(
        uint256 indexed recBuyId,
        address indexed sender,
        uint256[] amounts
    );

    event AutomationLayerSet(
        address indexed caller,
        address indexed automationLayerAddress
    );

    event DefaultRouterSet(
        address indexed caller,
        address indexed defaultRouter
    );

    event AcceptingRecurringBuysSet(
        address indexed caller,
        bool acceptingRecurringBuys
    );

    /// -----------------------------------------------------------------------
    /// Tests set-up
    /// -----------------------------------------------------------------------

    function setUp() public {
        deployer = new Deploy();
        deployer.run();

        automation = deployer.automation();
        dca = deployer.dca();
        config = deployer.config();
        token1 = deployer.token1();
        token2 = deployer.token2();
        defaultRouter = deployer.defaultRouter();

        (address wNative, , , , , , , , , uint256 deployerPk) = config
            .activeNetworkConfig();
        wrapNative = wNative;
        signer = vm.addr(deployerPk);

        ERC20Mock(token1).mint(defaultRouter, INITAL_DEX_ERC20_FUNDS);
        ERC20Mock(token2).mint(defaultRouter, INITAL_DEX_ERC20_FUNDS);
        ERC20Mock(wNative).mint(defaultRouter, INITAL_DEX_ERC20_FUNDS);
        ERC20Mock(token1).mint(user, INITAL_USER_ERC20_FUNDS);
        ERC20Mock(wNative).mint(user, INITAL_USER_ERC20_FUNDS);

        vm.deal(user, INITAL_USER_FUNDS);
    }

    /// -----------------------------------------------------------------------
    /// Test for: constructor
    /// -----------------------------------------------------------------------

    function testConstructorSuccess() public {
        address router = dca.getDefaultRouter();
        address automationLayer = address(dca.getAutomationLayer());
        bool acceptingBuys = dca.getAcceptingNewRecurringBuys();
        address wNative = dca.getWrapNative();

        (, address defaultRouter_, , , , , , , , ) = config
            .activeNetworkConfig();

        assertEq(router, defaultRouter_);
        assertEq(automationLayer, address(automation));
        assertEq(acceptingBuys, true);
        assertEq(wNative, wrapNative);
    }

    function testConstructorRevertsIfDefaultRouterAddressIs0() public {
        address defaultRouter_ = address(0);
        address automationLayer = address(automation);

        vm.startBroadcast(user);
        vm.expectRevert(
            IDollarCostAverage
                .DollarCostAverage__InvalidDefaultRouterAddress
                .selector
        );
        new DollarCostAverage(defaultRouter_, automationLayer, wrapNative);
        vm.stopBroadcast();
    }

    function testConstructorRevertsIfAutomationLayerAddressIs0() public {
        (, address defaultRouter_, , , , , , , , ) = config
            .activeNetworkConfig();
        address automationLayer = address(0);

        vm.startBroadcast(user);
        vm.expectRevert(
            IDollarCostAverage
                .DollarCostAverage__InvalidAutomationLayerAddress
                .selector
        );
        new DollarCostAverage(defaultRouter_, automationLayer, wrapNative);
        vm.stopBroadcast();
    }

    /// -----------------------------------------------------------------------
    /// Test for: createRecurringBuy
    /// -----------------------------------------------------------------------

    function testCreateRecurringBuySuccess() public {
        uint256 amountToSpend = 1 ether;
        address tokenToSpend = token1;
        address tokenToBuy = token2;
        uint256 timeIntervalInSeconds = 2 minutes;
        address paymentInterface = address(0);
        address dexRouter = defaultRouter;

        vm.prank(user);
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );

        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;
        uint256 accountNumber = automation.getNextAccountNumber() - 1;

        IDollarCostAverage.RecurringBuy memory buy = dca.getRecurringBuy(
            currRecurringBuyId
        );

        assertEq(buy.sender, user);
        assertEq(buy.amountToSpend, amountToSpend);
        assertEq(buy.tokenToSpend, tokenToSpend);
        assertEq(buy.tokenToBuy, tokenToBuy);
        assertEq(buy.timeIntervalInSeconds, timeIntervalInSeconds);
        assertEq(buy.paymentInterface, paymentInterface);
        assertEq(buy.dexRouter, dexRouter);
        assertEq(buy.paymentDue, block.timestamp);
        assertEq(buy.accountNumber, accountNumber);
        assertEq(uint8(buy.status), uint8(IDollarCostAverage.Status.SET));
    }

    function testCreateRecurringBuyEvent() public {
        uint256 amountToSpend = 1 ether;
        address tokenToSpend = token1;
        address tokenToBuy = token2;
        uint256 timeIntervalInSeconds = 2 minutes;
        address paymentInterface = address(0);
        address dexRouter = defaultRouter;

        IDollarCostAverage.RecurringBuy memory buy = IDollarCostAverage
            .RecurringBuy(
                user,
                amountToSpend,
                tokenToSpend,
                tokenToBuy,
                timeIntervalInSeconds,
                paymentInterface,
                dexRouter,
                block.timestamp,
                0,
                IDollarCostAverage.Status.SET
            );

        vm.expectEmit(true, true, false, true, address(dca));
        emit RecurringBuyCreated(0, user, buy);

        vm.prank(user);
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );
    }

    function testCreateRecurringBuyRevertsIfAmountToSpendIsZero() public {
        uint256 amountToSpend = 0;
        address tokenToSpend = token1;
        address tokenToBuy = token2;
        uint256 timeIntervalInSeconds = 2 minutes;
        address paymentInterface = address(0);
        address dexRouter = defaultRouter;

        vm.prank(user);
        vm.expectRevert(
            IDollarCostAverage.DollarCostAverage__AmountIsZero.selector
        );
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );
    }

    function testCreateRecurringBuyRevertsIfNotAccepintgNewRecurringBuys()
        public
    {
        uint256 amountToSpend = 1 ether;
        address tokenToSpend = token1;
        address tokenToBuy = token2;
        uint256 timeIntervalInSeconds = 2 minutes;
        address paymentInterface = address(0);
        address dexRouter = defaultRouter;

        vm.prank(signer);
        dca.setAcceptingNewRecurringBuys(false);

        vm.prank(user);
        vm.expectRevert(
            IDollarCostAverage
                .DollarCostAverage__NotAcceptingNewRecurringBuys
                .selector
        );
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );
    }

    function testCreateRecurringBuyRevertsIfEitherTokenIs0() public {
        uint256 amountToSpend = 1 ether;
        address tokenToSpend = address(0);
        address tokenToBuy = token2;
        uint256 timeIntervalInSeconds = 2 minutes;
        address paymentInterface = address(0);
        address dexRouter = defaultRouter;

        vm.prank(user);
        vm.expectRevert(
            IDollarCostAverage.DollarCostAverage__InvalidTokenAddresses.selector
        );
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );

        tokenToSpend = token1;
        tokenToBuy = address(0);

        vm.prank(user);
        vm.expectRevert(
            IDollarCostAverage.DollarCostAverage__InvalidTokenAddresses.selector
        );
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );
    }

    function testCreateRecurringBuyRevertsIfTimeIntervalIs0() public {
        uint256 amountToSpend = 1 ether;
        address tokenToSpend = token1;
        address tokenToBuy = token2;
        uint256 timeIntervalInSeconds = 0;
        address paymentInterface = address(0);
        address dexRouter = defaultRouter;

        vm.prank(user);
        vm.expectRevert(
            IDollarCostAverage.DollarCostAverage__InvalidTimeInterval.selector
        );
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );
    }

    function testCreateRecurringBuyRevertsIfContractPaused() public {
        uint256 amountToSpend = 1 ether;
        address tokenToSpend = token1;
        address tokenToBuy = token2;
        uint256 timeIntervalInSeconds = 0;
        address paymentInterface = address(0);
        address dexRouter = defaultRouter;

        vm.prank(signer);
        dca.pause();

        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );
    }

    /// -----------------------------------------------------------------------
    /// Test for: cancelRecurringPayment
    /// -----------------------------------------------------------------------

    modifier createRecurringBuy(
        address tokenToSpend,
        address tokenToBuy,
        address paymentInterface
    ) {
        uint256 amountToSpend = 1 ether;
        uint256 timeIntervalInSeconds = 2 minutes;
        address dexRouter = defaultRouter;

        vm.prank(user);
        dca.createRecurringBuy(
            amountToSpend,
            tokenToSpend,
            tokenToBuy,
            timeIntervalInSeconds,
            paymentInterface,
            dexRouter
        );
        _;
    }

    function testCancelRecurringPaymentSuccess()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.prank(user);
        dca.cancelRecurringPayment(currRecurringBuyId);

        IDollarCostAverage.RecurringBuy memory buy = dca.getRecurringBuy(
            currRecurringBuyId
        );

        assertEq(uint8(buy.status), uint8(IDollarCostAverage.Status.CANCELLED));
    }

    function testCancelRecurringPaymentEvent()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.expectEmit(true, true, false, false, address(dca));
        emit RecurringBuyCancelled(currRecurringBuyId, user);

        vm.prank(user);
        dca.cancelRecurringPayment(currRecurringBuyId);
    }

    function testCancelRecurringPaymentRevertsIfInvalidRecurringBuyId() public {
        vm.prank(user);
        vm.expectRevert(
            IDollarCostAverage.DollarCostAverage__InvalidRecurringBuyId.selector
        );
        dca.cancelRecurringPayment(0);
    }

    function testCancelRecurringPaymentRevertsIfCallerNotSender()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        vm.prank(address(1));
        vm.expectRevert(
            IDollarCostAverage
                .DollarCostAverage__CallerNotRecurringBuySender
                .selector
        );
        dca.cancelRecurringPayment(0);
    }

    function testCancelRecurringBuyRevertsIfContractPaused()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.prank(signer);
        dca.pause();

        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        dca.cancelRecurringPayment(currRecurringBuyId);
    }

    /// -----------------------------------------------------------------------
    /// Test for: transferFunds
    /// -----------------------------------------------------------------------

    modifier transferFundsApproves() {
        vm.startPrank(user);
        ERC20Mock(token1).approve(defaultRouter, type(uint256).max);
        ERC20Mock(token1).approve(address(dca), type(uint256).max);
        ERC20Mock(wrapNative).approve(defaultRouter, type(uint256).max);
        ERC20Mock(wrapNative).approve(address(dca), type(uint256).max);
        vm.stopPrank();
        _;
    }

    function testTransferFundsSuccess()
        public
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, PAYMENT_INTERFACE)
        createRecurringBuy(wrapNative, token2, address(0))
        createRecurringBuy(token1, wrapNative, address(0))
        transferFundsApproves
    {
        // paymentInterface = address(0)
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 4;

        uint256 tokenToSpendBalanceBefore = ERC20Mock(token1).balanceOf(user);
        uint256 tokenToBuyBalanceBefore = ERC20Mock(token2).balanceOf(user);

        vm.prank(user);
        dca.transferFunds(currRecurringBuyId);

        uint256 tokenToSpendBalanceAfter = ERC20Mock(token1).balanceOf(user);
        uint256 tokenToBuyBalanceAfter = ERC20Mock(token2).balanceOf(user);

        IDollarCostAverage.RecurringBuy memory buy = dca.getRecurringBuy(
            currRecurringBuyId
        );

        uint256 fee = (buy.amountToSpend * 100) / 10000;
        uint256 currTimestamp = dca.getCurrentBlockTimestamp();

        assertEq(
            tokenToSpendBalanceAfter,
            tokenToSpendBalanceBefore - (buy.amountToSpend - fee / 2)
        );
        assertGt(tokenToBuyBalanceAfter, tokenToBuyBalanceBefore);
        assertEq(buy.paymentDue, currTimestamp + buy.timeIntervalInSeconds);

        // paymentInterface != address(0)

        currRecurringBuyId = dca.getNextRecurringBuyId() - 3;

        tokenToSpendBalanceBefore = ERC20Mock(token1).balanceOf(user);
        tokenToBuyBalanceBefore = ERC20Mock(token2).balanceOf(user);
        uint256 paymentInterfaceBalanceBefore = ERC20Mock(token1).balanceOf(
            PAYMENT_INTERFACE
        );

        vm.prank(user);
        dca.transferFunds(currRecurringBuyId);

        tokenToSpendBalanceAfter = ERC20Mock(token1).balanceOf(user);
        tokenToBuyBalanceAfter = ERC20Mock(token2).balanceOf(user);
        uint256 paymentInterfaceBalanceAfter = ERC20Mock(token1).balanceOf(
            PAYMENT_INTERFACE
        );

        buy = dca.getRecurringBuy(currRecurringBuyId);

        fee = (buy.amountToSpend * 100) / 10000;
        currTimestamp = dca.getCurrentBlockTimestamp();

        assertEq(
            tokenToSpendBalanceAfter,
            tokenToSpendBalanceBefore - buy.amountToSpend
        );
        assertGt(tokenToBuyBalanceAfter, tokenToBuyBalanceBefore);
        assertEq(buy.paymentDue, currTimestamp + buy.timeIntervalInSeconds);
        assertEq(
            paymentInterfaceBalanceAfter,
            paymentInterfaceBalanceBefore + fee / 2
        );

        // tokenToSpend = wrapNative

        currRecurringBuyId = dca.getNextRecurringBuyId() - 2;

        tokenToSpendBalanceBefore = ERC20Mock(wrapNative).balanceOf(user);
        tokenToBuyBalanceBefore = ERC20Mock(token2).balanceOf(user);

        vm.prank(user);
        dca.transferFunds(currRecurringBuyId);

        tokenToSpendBalanceAfter = ERC20Mock(wrapNative).balanceOf(user);
        tokenToBuyBalanceAfter = ERC20Mock(token2).balanceOf(user);

        buy = dca.getRecurringBuy(currRecurringBuyId);

        fee = (buy.amountToSpend * 100) / 10000;
        currTimestamp = dca.getCurrentBlockTimestamp();

        assertEq(
            tokenToSpendBalanceAfter,
            tokenToSpendBalanceBefore - (buy.amountToSpend - fee / 2)
        );
        assertGt(tokenToBuyBalanceAfter, tokenToBuyBalanceBefore);
        assertEq(buy.paymentDue, currTimestamp + buy.timeIntervalInSeconds);

        // tokenToBuy = wrapNative

        currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        tokenToSpendBalanceBefore = ERC20Mock(token1).balanceOf(user);
        tokenToBuyBalanceBefore = ERC20Mock(wrapNative).balanceOf(user);

        vm.prank(user);
        dca.transferFunds(currRecurringBuyId);

        tokenToSpendBalanceAfter = ERC20Mock(token1).balanceOf(user);
        tokenToBuyBalanceAfter = ERC20Mock(wrapNative).balanceOf(user);

        buy = dca.getRecurringBuy(currRecurringBuyId);

        fee = (buy.amountToSpend * 100) / 10000;
        currTimestamp = dca.getCurrentBlockTimestamp();

        assertEq(
            tokenToSpendBalanceAfter,
            tokenToSpendBalanceBefore - (buy.amountToSpend - fee / 2)
        );
        assertGt(tokenToBuyBalanceAfter, tokenToBuyBalanceBefore);
        assertEq(buy.paymentDue, currTimestamp + buy.timeIntervalInSeconds);
    }

    function testTrasnferFundsEvent()
        public
        createRecurringBuy(token1, token2, address(0))
        transferFundsApproves
    {
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.expectEmit(true, true, false, false, address(dca));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = uint256(0);
        amounts[1] = uint256(0);

        emit PaymentTransferred(currRecurringBuyId, user, amounts);

        vm.prank(user);
        dca.transferFunds(currRecurringBuyId);
    }

    function testTransferFundsRevertsIfStatusIsNotSetOrIfPaymentIsNotDue()
        public
        createRecurringBuy(token1, token2, address(0))
        transferFundsApproves
    {
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.startPrank(user);
        dca.transferFunds(currRecurringBuyId);
        vm.expectRevert(
            IDollarCostAverage.DollarCostAverage__InvalidRecurringBuy.selector
        );
        dca.transferFunds(currRecurringBuyId);

        vm.warp(block.timestamp + 1 hours);
        dca.cancelRecurringPayment(currRecurringBuyId);
        vm.expectRevert(
            IDollarCostAverage.DollarCostAverage__InvalidRecurringBuy.selector
        );
        dca.transferFunds(currRecurringBuyId);
        vm.stopPrank();
    }

    function testTransferFundsRevertsIfContractPaused()
        public
        createRecurringBuy(token1, token2, address(0))
        transferFundsApproves
    {
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.prank(signer);
        dca.pause();

        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        dca.transferFunds(currRecurringBuyId);
    }

    function testTrasferFundsRevertsIfNotEnoughAllowance()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.prank(user);
        vm.expectRevert(
            IDollarCostAverage
                .DollarCostAverage__TokenNotEnoughAllowance
                .selector
        );
        dca.transferFunds(currRecurringBuyId);
    }

    /// -----------------------------------------------------------------------
    /// Test for: simpleAutomation
    /// -----------------------------------------------------------------------

    function testSimpleAutomationSuccess()
        public
        createRecurringBuy(token1, token2, address(0))
        transferFundsApproves
    {
        address random = makeAddr("random");
        uint256 currRecurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.prank(random);
        dca.simpleAutomation(currRecurringBuyId);

        IDollarCostAverage.RecurringBuy memory buy = dca.getRecurringBuy(
            currRecurringBuyId
        );

        assertEq(buy.paymentDue, block.timestamp + buy.timeIntervalInSeconds);
    }

    /// -----------------------------------------------------------------------
    /// Test for: setAutomationLayer
    /// -----------------------------------------------------------------------

    function testSetAutomationLayerSuccess() public {
        address newAutomationLayerAddress = makeAddr("newAutomationLayer");

        address automationLayerBefore = address(dca.getAutomationLayer());

        vm.prank(signer);
        dca.setAutomationLayer(newAutomationLayerAddress);

        address automationLayerAfter = address(dca.getAutomationLayer());

        assertEq(automationLayerBefore, address(automation));
        assertEq(automationLayerAfter, newAutomationLayerAddress);
    }

    function testSetAutomationLayerEvent() public {
        address newAutomationLayerAddress = makeAddr("newAutomationLayer");

        vm.expectEmit(true, true, false, false, address(dca));
        emit AutomationLayerSet(signer, newAutomationLayerAddress);

        vm.prank(signer);
        dca.setAutomationLayer(newAutomationLayerAddress);
    }

    function testSetAutomationLayerRevertsIfGivenAddressIs0() public {
        address newAutomationLayerAddress = address(0);

        vm.prank(signer);
        vm.expectRevert(
            IDollarCostAverage
                .DollarCostAverage__InvalidAutomationLayerAddress
                .selector
        );
        dca.setAutomationLayer(newAutomationLayerAddress);
    }

    function testSetAutomationLayerRevertsIfCallerNotOwner() public {
        address newAutomationLayerAddress = makeAddr("newAutomationLayer");

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dca.setAutomationLayer(newAutomationLayerAddress);
    }

    function testSetAutomationLayerRevertsIfContractPaused() public {
        address newAutomationLayerAddress = makeAddr("newAutomationLayer");

        vm.startPrank(signer);
        dca.pause();
        vm.expectRevert("Pausable: paused");
        dca.setAutomationLayer(newAutomationLayerAddress);
        vm.stopPrank();
    }

    /// -----------------------------------------------------------------------
    /// Test for: setDefaultRouter
    /// -----------------------------------------------------------------------

    function testSetDefaultRouterSuccess() public {
        address newDefaultRouter = makeAddr("newDefaultRouter");

        address defaultRouterBefore = dca.getDefaultRouter();

        vm.prank(signer);
        dca.setDefaultRouter(newDefaultRouter);

        address defaultRouterAfter = dca.getDefaultRouter();

        assertEq(defaultRouterBefore, defaultRouter);
        assertEq(defaultRouterAfter, newDefaultRouter);
    }

    function testSetDefaultRouterEvent() public {
        address newDefaultRouter = makeAddr("newDefaultRouter");

        vm.expectEmit(true, true, false, false, address(dca));
        emit DefaultRouterSet(signer, newDefaultRouter);

        vm.prank(signer);
        dca.setDefaultRouter(newDefaultRouter);
    }

    function testSetDefaultRouterRevertsIfGivenAddressIs0() public {
        address newDefaultRouter = address(0);

        vm.prank(signer);
        vm.expectRevert(
            IDollarCostAverage
                .DollarCostAverage__InvalidDefaultRouterAddress
                .selector
        );
        dca.setDefaultRouter(newDefaultRouter);
    }

    function testSetDefaultRouterRevertsIfCallerNotOwner() public {
        address newDefaultRouter = makeAddr("newDefaultRouter");

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dca.setDefaultRouter(newDefaultRouter);
    }

    function testSetDefaultRouterRevertsIfContractPaused() public {
        address newDefaultRouter = makeAddr("newDefaultRouter");

        vm.startPrank(signer);
        dca.pause();
        vm.expectRevert("Pausable: paused");
        dca.setDefaultRouter(newDefaultRouter);
        vm.stopPrank();
    }

    /// -----------------------------------------------------------------------
    /// Test for: setAcceptingNewRecurringBuys
    /// -----------------------------------------------------------------------

    function testSetAcceptingNewRecurringBuysSuccess() public {
        bool newAcceptingNewRecurringBuys = false;

        bool acceptingNewRecurringBuysBefore = dca
            .getAcceptingNewRecurringBuys();

        vm.prank(signer);
        dca.setAcceptingNewRecurringBuys(newAcceptingNewRecurringBuys);

        bool acceptingNewRecurringBuysAfter = dca
            .getAcceptingNewRecurringBuys();

        assertEq(acceptingNewRecurringBuysBefore, true);
        assertEq(acceptingNewRecurringBuysAfter, newAcceptingNewRecurringBuys);
    }

    function testSetAcceptingNewRecurringBuysEvent() public {
        bool newAcceptingNewRecurringBuys = false;

        vm.expectEmit(true, false, false, true, address(dca));
        emit AcceptingRecurringBuysSet(signer, newAcceptingNewRecurringBuys);

        vm.prank(signer);
        dca.setAcceptingNewRecurringBuys(newAcceptingNewRecurringBuys);
    }

    function testSetAcceptingNewRecurringBuysRevertsIfCallerNotOwner() public {
        bool newAcceptingNewRecurringBuys = false;

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dca.setAcceptingNewRecurringBuys(newAcceptingNewRecurringBuys);
    }

    function testSetAcceptingNewRecurringBuysRevertsIfContractPaused() public {
        bool newAcceptingNewRecurringBuys = false;

        vm.startPrank(signer);
        dca.pause();
        vm.expectRevert("Pausable: paused");
        dca.setAcceptingNewRecurringBuys(newAcceptingNewRecurringBuys);
        vm.stopPrank();
    }

    /// -----------------------------------------------------------------------
    /// Test for: pause
    /// -----------------------------------------------------------------------

    function testPause() public {
        bool pausedBefore = dca.paused();

        vm.prank(signer);
        dca.pause();

        bool pausedAfter = dca.paused();

        assertEq(pausedBefore, false);
        assertEq(pausedAfter, true);
    }

    function testPauseRevertsIfCallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dca.pause();
    }

    /// -----------------------------------------------------------------------
    /// Test for: unpause
    /// -----------------------------------------------------------------------

    function testUnpause() public {
        vm.prank(signer);
        dca.pause();

        bool pausedBefore = dca.paused();

        vm.prank(signer);
        dca.unpause();

        bool pausedAfter = dca.paused();

        assertEq(pausedBefore, true);
        assertEq(pausedAfter, false);
    }

    function testUnpauseRevertsIfCallerNotOwner() public {
        vm.prank(signer);
        dca.pause();

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dca.unpause();
    }

    /// -----------------------------------------------------------------------
    /// Test for: getNextRecurringBuyId
    /// -----------------------------------------------------------------------

    function testGetNextRecurringBuyId()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        uint256 nextRecurringBuyId = dca.getNextRecurringBuyId();

        assertEq(nextRecurringBuyId, 1);
    }

    /// -----------------------------------------------------------------------
    /// Test for: getDefaultRouter
    /// -----------------------------------------------------------------------

    function testGetDefaultRouter() public {
        address currDefaultRouter = dca.getDefaultRouter();

        assertEq(currDefaultRouter, defaultRouter);
    }

    /// -----------------------------------------------------------------------
    /// Test for: getAutomationLayer
    /// -----------------------------------------------------------------------

    function testGetAutomationLayer() public {
        address currAutomationLayerAddress = address(dca.getAutomationLayer());

        assertEq(currAutomationLayerAddress, address(automation));
    }

    /// -----------------------------------------------------------------------
    /// Test for: checkSimpleAutomation
    /// -----------------------------------------------------------------------

    function testCheckSimpleAutomationSuccess()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        uint256 recurringBuyId = dca.getNextRecurringBuyId() - 1;
        bool canAutomate = dca.checkSimpleAutomation(recurringBuyId);

        assertEq(canAutomate, true);
    }

    function testCheckSimpleAutomationFalsePath1()
        public
        createRecurringBuy(token1, token2, address(0))
        transferFundsApproves
    {
        uint256 recurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.prank(user);
        dca.transferFunds(recurringBuyId);

        bool canAutomate = dca.checkSimpleAutomation(recurringBuyId);

        assertEq(canAutomate, false);
    }

    function testCheckSimpleAutomationFalsePath2()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        uint256 recurringBuyId = dca.getNextRecurringBuyId() - 1;

        vm.prank(user);
        dca.cancelRecurringPayment(recurringBuyId);

        bool canAutomate = dca.checkSimpleAutomation(recurringBuyId);

        assertEq(canAutomate, false);
    }

    /// -----------------------------------------------------------------------
    /// Test for: getCurrentBlockTimestamp
    /// -----------------------------------------------------------------------

    function testGetCurrentBlockTimestamp() public {
        uint256 blockTimestamp = dca.getCurrentBlockTimestamp();

        assertEq(blockTimestamp, block.timestamp);
    }

    /// -----------------------------------------------------------------------
    /// Test for: getRecurringBuy
    /// -----------------------------------------------------------------------

    function testGetRecurringBuy()
        public
        createRecurringBuy(token1, token2, address(0))
    {
        uint256 recurringBuyId = dca.getNextRecurringBuyId() - 1;

        IDollarCostAverage.RecurringBuy memory buy = dca.getRecurringBuy(
            recurringBuyId
        );

        uint256 amountToSpend = 1 ether;
        uint256 timeIntervalInSeconds = 2 minutes;
        address dexRouter = defaultRouter;

        assertEq(buy.sender, user);
        assertEq(buy.amountToSpend, amountToSpend);
        assertEq(buy.tokenToSpend, token1);
        assertEq(buy.tokenToBuy, token2);
        assertEq(buy.timeIntervalInSeconds, timeIntervalInSeconds);
        assertEq(buy.paymentInterface, address(0));
        assertEq(buy.dexRouter, dexRouter);
        assertEq(buy.paymentDue, block.timestamp);
        assertEq(buy.accountNumber, 0);
        assertEq(uint8(buy.status), uint8(IDollarCostAverage.Status.SET));
    }

    /// -----------------------------------------------------------------------
    /// Test for: getAcceptingNewRecurringBuys
    /// -----------------------------------------------------------------------

    function testGetAcceptingNewRecurringBuys() public {
        bool acceptingNewRecurringBuys = dca.getAcceptingNewRecurringBuys();

        assertEq(acceptingNewRecurringBuys, true);
    }

    /// -----------------------------------------------------------------------
    /// Test for: getWrapNative
    /// -----------------------------------------------------------------------

    function testGetWrapNative() public {
        address wNative = dca.getWrapNative();

        assertEq(wNative, wrapNative);
    }

    /// -----------------------------------------------------------------------
    /// Test for: getRangeOfRecurringBuys
    /// -----------------------------------------------------------------------

    function testGetRangeOfRecurringBuys()
        public
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
    {
        IDollarCostAverage.RecurringBuy[] memory buys = dca
            .getRangeOfRecurringBuys(1, 3);

        assertEq(buys.length, 3);
    }

    /// -----------------------------------------------------------------------
    /// Test for: getValidRangeOfRecurringBuys
    /// -----------------------------------------------------------------------

    // reformulate
    function testGetValidRangeOfRecurringBuys()
        public
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
        createRecurringBuy(token1, token2, address(0))
    {
        vm.prank(user);
        dca.cancelRecurringPayment(2);

        IDollarCostAverage.RecurringBuy[] memory buys = dca
            .getValidRangeOfRecurringBuys(1, 5);

        assertEq(buys.length, 4);
    }

    /// -----------------------------------------------------------------------
    /// Test for: isRecurringBuyValid
    /// -----------------------------------------------------------------------
}
