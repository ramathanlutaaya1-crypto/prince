//+------------------------------------------------------------------+
//|                                    Professional Scalping Bot v2.0 |
//|                    Multi-Pair Scalping with Dynamic Lot Sizing    |
//|                           Compatible: FBS, XM, Just Markets       |
//+------------------------------------------------------------------+
#property copyright "ramathanlutaaya1-crypto"
#property link      "https://github.com/ramathanlutaaya1-crypto/prince"
#property version   "2.0"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| TRADING PAIRS CONFIGURATION                                       |
//+------------------------------------------------------------------+
enum TRADING_PAIR
{
   PAIR_XAUUSD = 0,    // Gold
   PAIR_EURUSD = 1,    // Euro
   PAIR_GBPUSD = 2     // British Pound
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// === DAILY PROFIT TARGET ===
input double DailyProfitTarget = 50.0;           // Daily profit target ($)

// === ACCOUNT SCALING TARGETS ===
input double Stage1_Target = 100.0;              // Stage 1: $2 to $100
input double Stage2_Target = 1000.0;             // Stage 2: $100 to $1000
input double Stage3_Target = 5000.0;             // Stage 3: $1000 to $5000

// === SCALPING PARAMETERS ===
input int TakeProfit_Pips = 15;                  // Take profit in pips
input int StopLoss_Pips = 10;                    // Stop loss in pips
input int RSI_Period = 14;                       // RSI period
input int RSI_Overbought = 70;                   // RSI overbought
input int RSI_Oversold = 30;                     // RSI oversold

// === TRADING PAIRS SELECTION ===
input bool Trade_XAUUSD = true;                 // Trade Gold
input bool Trade_EURUSD = true;                 // Trade Euro
input bool Trade_GBPUSD = true;                 // Trade GBP/USD

// === RISK MANAGEMENT ===
input double MaxDailyLossPercent = 5.0;         // Max daily loss (%)
input int MaxOpenTrades = 3;                    // Max concurrent trades per pair
input bool UseBreakEven = true;                 // Enable break-even stops
input bool CloseOnProfitTarget = true;          // Close all when daily target hit

// === BROKER COMPATIBILITY ===
input int MagicNumber = 2024001;                // Magic number for orders
input bool SubmitReversal = false;              // Submit reversals for MT4 compatibility

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CSymbolInfo symbolInfo;
CPositionInfo positionInfo;

struct DailyStats
{
   double openingBalance;
   double dailyProfit;
   double dailyLoss;
   datetime sessionStart;
   bool dailyTargetReached;
};

DailyStats stats;
double lastClosePrice[3];  // Track last close for each pair
datetime lastTradeTime[3]; // Prevent multiple trades same bar

string tradingPairs[] = {"XAUUSD", "EURUSD", "GBPUSD"};
bool pairEnabled[] = {true, true, true};
int pairMagic[] = {2024001, 2024002, 2024003};

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Initialize broker symbols
   if (!SymbolSelect("XAUUSD", Trade_XAUUSD))
      Print("Warning: Could not select XAUUSD");
   if (!SymbolSelect("EURUSD", Trade_EURUSD))
      Print("Warning: Could not select EURUSD");
   if (!SymbolSelect("GBPUSD", Trade_GBPUSD))
      Print("Warning: Could not select GBPUSD");
   
   // Set pair enabled status
   pairEnabled[0] = Trade_XAUUSD;
   pairEnabled[1] = Trade_EURUSD;
   pairEnabled[2] = Trade_GBPUSD;
   
   // Initialize daily stats
   stats.openingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   stats.dailyProfit = 0;
   stats.dailyLoss = 0;
   stats.sessionStart = TimeCurrent();
   stats.dailyTargetReached = false;
   
   Print("=== Professional Scalping Bot v2.0 ===");
   Print("Opening Balance: $", stats.openingBalance);
   Print("Daily Profit Target: $", DailyProfitTarget);
   Print("Stage 1 Target: $", Stage1_Target);
   Print("Stage 2 Target: $", Stage2_Target);
   Print("Stage 3 Target: $", Stage3_Target);
   Print("Trading Pairs: XAUUSD(", Trade_XAUUSD, ") EURUSD(", Trade_EURUSD, ") GBPUSD(", Trade_GBPUSD, ")");
   Print("Bot Initialized Successfully!");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== Bot Stopped ===");
   Print("Final Balance: $", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("Session Profit: $", stats.dailyProfit);
}

//+------------------------------------------------------------------+
//| EXPERT TICK FUNCTION                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if daily target reached
   if (CloseOnProfitTarget && stats.dailyTargetReached)
   {
      CloseAllTradesOnTarget();
      return;
   }
   
   // Update daily stats
   UpdateDailyStats();
   
   // Check daily loss limit
   if (stats.dailyLoss >= (stats.openingBalance * MaxDailyLossPercent / 100))
   {
      Print("Daily loss limit reached. Stopping trades...");
      return;
   }
   
   // Reset daily stats if new day
   if (TimeDayOfWeek(stats.sessionStart) != TimeDayOfWeek(TimeCurrent()))
   {
      ResetDailyStats();
   }
   
   // Process each trading pair
   for (int i = 0; i < 3; i++)
   {
      if (pairEnabled[i])
      {
         ProcessPair(tradingPairs[i], i);
      }
   }
   
   // Manage existing trades
   ManageAllTrades();
}

//+------------------------------------------------------------------+
//| PROCESS INDIVIDUAL TRADING PAIR                                   |
//+------------------------------------------------------------------+
void ProcessPair(string symbol, int pairIndex)
{
   // Avoid multiple trades on same bar
   if (lastTradeTime[pairIndex] == iTime(symbol, Period(), 0))
      return;
   
   // Check max open trades limit
   if (CountOpenTradesForPair(symbol) >= MaxOpenTrades)
      return;
   
   // Get RSI signal
   int signal = GetRSISignal(symbol);
   
   if (signal == 1)  // BUY signal
   {
      OpenScalpTrade(symbol, ORDER_TYPE_BUY, pairIndex);
      lastTradeTime[pairIndex] = iTime(symbol, Period(), 0);
   }
   else if (signal == -1)  // SELL signal
   {
      OpenScalpTrade(symbol, ORDER_TYPE_SELL, pairIndex);
      lastTradeTime[pairIndex] = iTime(symbol, Period(), 0);
   }
}

//+------------------------------------------------------------------+
//| GET RSI TRADING SIGNAL                                            |
//+------------------------------------------------------------------+
int GetRSISignal(string symbol)
{
   int rsiHandle = iRSI(symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   
   if (rsiHandle == INVALID_HANDLE)
      return 0;
   
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   
   if (CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) <= 0)
      return 0;
   
   double rsi = rsiBuffer[0];
   
   // BUY signal: RSI crosses below oversold
   if (rsi < RSI_Oversold)
      return 1;
   
   // SELL signal: RSI crosses above overbought
   if (rsi > RSI_Overbought)
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| OPEN SCALPING TRADE WITH DYNAMIC LOT SIZING                      |
//+------------------------------------------------------------------+
void OpenScalpTrade(string symbol, ENUM_ORDER_TYPE orderType, int pairIndex)
{
   double lotSize = CalculateDynamicLotSize(symbol);
   
   if (lotSize <= 0)
   {
      Print("Error: Invalid lot size calculated for ", symbol);
      return;
   }
   
   // Get current prices
   MqlTick tick;
   SymbolInfoTick(symbol, tick);
   double bid = tick.bid;
   double ask = tick.ask;
   
   // Calculate SL and TP
   double stopLoss, takeProfit;
   
   if (orderType == ORDER_TYPE_BUY)
   {
      stopLoss = bid - (StopLoss_Pips * SymbolInfoDouble(symbol, SYMBOL_POINT));
      takeProfit = ask + (TakeProfit_Pips * SymbolInfoDouble(symbol, SYMBOL_POINT));
   }
   else
   {
      stopLoss = ask + (StopLoss_Pips * SymbolInfoDouble(symbol, SYMBOL_POINT));
      takeProfit = bid - (TakeProfit_Pips * SymbolInfoDouble(symbol, SYMBOL_POINT));
   }
   
   // Normalize prices
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   stopLoss = NormalizeDouble(stopLoss, digits);
   takeProfit = NormalizeDouble(takeProfit, digits);
   
   // Execute trade
   trade.SetExpertMagicNumber(pairMagic[pairIndex]);
   
   if (orderType == ORDER_TYPE_BUY)
   {
      if (trade.Buy(lotSize, symbol, ask, stopLoss, takeProfit))
      {
         Print("BUY opened: ", symbol, " | Lot: ", lotSize, " | SL: ", stopLoss, " | TP: ", takeProfit);
      }
      else
      {
         Print("BUY failed for ", symbol, ". Error: ", trade.ResultRetcodeDescription());
      }
   }
   else
   {
      if (trade.Sell(lotSize, symbol, bid, stopLoss, takeProfit))
      {
         Print("SELL opened: ", symbol, " | Lot: ", lotSize, " | SL: ", stopLoss, " | TP: ", takeProfit);
      }
      else
      {
         Print("SELL failed for ", symbol, ". Error: ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| CALCULATE DYNAMIC LOT SIZE BASED ON ACCOUNT STAGE                |
//+------------------------------------------------------------------+
double CalculateDynamicLotSize(string symbol)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   double calculatedLot = 0;
   
   // Dynamic lot sizing based on account balance stages
   if (balance < Stage1_Target)
   {
      // Stage 1: $2 to $100 - Micro lots
      calculatedLot = 0.01 * (balance / 10);  // Scale up gradually
   }
   else if (balance < Stage2_Target)
   {
      // Stage 2: $100 to $1000 - Mini lots
      calculatedLot = 0.1 * (balance / 100);
   }
   else if (balance < Stage3_Target)
   {
      // Stage 3: $1000 to $5000 - Standard lots
      calculatedLot = 0.5 * (balance / 1000);
   }
   else
   {
      // Stage 4: $5000+ - Full lot scaling
      calculatedLot = 1.0 * (balance / 5000);
   }
   
   // Ensure within broker limits
   if (calculatedLot < minLot)
      calculatedLot = minLot;
   if (calculatedLot > maxLot)
      calculatedLot = maxLot;
   
   // Round to lot step
   calculatedLot = NormalizeDouble(MathFloor(calculatedLot / lotStep) * lotStep, 2);
   
   return calculatedLot;
}

//+------------------------------------------------------------------+
//| COUNT OPEN TRADES FOR SPECIFIC PAIR                               |
//+------------------------------------------------------------------+
int CountOpenTradesForPair(string symbol)
{
   int count = 0;
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == symbol)
         {
            ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
            if (positionMagic == pairMagic[0] || positionMagic == pairMagic[1] || positionMagic == pairMagic[2])
               count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| MANAGE ALL OPEN TRADES - BREAK EVEN & OPTIMIZATION                |
//+------------------------------------------------------------------+
void ManageAllTrades()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      
      if (PositionSelectByTicket(ticket))
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double stopLoss = PositionGetDouble(POSITION_SL);
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // Apply break-even stop
         if (UseBreakEven)
         {
            if (posType == POSITION_TYPE_BUY && currentPrice > openPrice)
            {
               double newStop = openPrice + (2 * SymbolInfoDouble(symbol, SYMBOL_POINT));
               if (newStop > stopLoss)
               {
                  trade.PositionModify(ticket, newStop, PositionGetDouble(POSITION_TP));
               }
            }
            else if (posType == POSITION_TYPE_SELL && currentPrice < openPrice)
            {
               double newStop = openPrice - (2 * SymbolInfoDouble(symbol, SYMBOL_POINT));
               if (newStop < stopLoss)
               {
                  trade.PositionModify(ticket, newStop, PositionGetDouble(POSITION_TP));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| UPDATE DAILY STATISTICS                                           |
//+------------------------------------------------------------------+
void UpdateDailyStats()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   stats.dailyProfit = currentBalance - stats.openingBalance;
   
   if (stats.dailyProfit >= DailyProfitTarget)
   {
      stats.dailyTargetReached = true;
      Print("✓ DAILY PROFIT TARGET REACHED: $", stats.dailyProfit);
   }
}

//+------------------------------------------------------------------+
//| RESET DAILY STATISTICS AT NEW DAY                                 |
//+------------------------------------------------------------------+
void ResetDailyStats()
{
   stats.openingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   stats.dailyProfit = 0;
   stats.dailyLoss = 0;
   stats.sessionStart = TimeCurrent();
   stats.dailyTargetReached = false;
   
   Print("=== NEW TRADING DAY ===");
   Print("Opening Balance: $", stats.openingBalance);
}

//+------------------------------------------------------------------+
//| CLOSE ALL TRADES WHEN DAILY TARGET REACHED                        |
//+------------------------------------------------------------------+
void CloseAllTradesOnTarget()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      
      if (PositionSelectByTicket(ticket))
      {
         ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
         if (positionMagic == pairMagic[0] || positionMagic == pairMagic[1] || positionMagic == pairMagic[2])
         {
            trade.PositionClose(ticket);
            Print("Closed position for daily target: Ticket ", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
// END OF SCRIPT
//+------------------------------------------------------------------+
