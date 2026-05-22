//+------------------------------------------------------------------+
//|                                                    ScalpingBot.mq5 |
//|                                  Forex Trading Scalping Bot v1.0   |
//+------------------------------------------------------------------+
#property copyright "ramathanlutaaya1-crypto"
#property link      "https://github.com/ramathanlutaaya1-crypto/prince"
#property version   "1.0"
#property strict

//--- Input parameters
input double RiskPercentage = 1.0;           // Risk per trade (%)
input double LotSize = 0.1;                  // Lot size for trading
input int RSIPeriod = 14;                    // RSI period
input int RSIOverbought = 70;                // RSI overbought level
input int RSIOversold = 30;                  // RSI oversold level
input int StopLossPips = 20;                 // Stop loss in pips
input int TakeProfitPips = 10;               // Take profit in pips
input int MagicNumber = 123456;              // Magic number for orders
input bool UseRiskManagement = true;         // Use risk management
input int MaxOpenTrades = 3;                 // Maximum open trades

//--- Global variables
double Bid, Ask;
int lastBarTime = 0;
double accountBalance = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("ScalpingBot v1.0 initialized");
   Print("Symbol: ", Symbol());
   Print("Timeframe: ", Period());
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("ScalpingBot stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update bid/ask
   Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   
   // Check if new bar formed
   if (lastBarTime == iTime(Symbol(), Period(), 0))
      return;
   
   lastBarTime = iTime(Symbol(), Period(), 0);
   
   // Get signal
   int signal = GetScalpingSignal();
   
   // Check if we can open new trades
   if (CountOpenTrades() < MaxOpenTrades)
   {
      if (signal == 1)  // BUY signal
      {
         OpenBuyOrder();
      }
      else if (signal == -1)  // SELL signal
      {
         OpenSellOrder();
      }
   }
   
   // Close pending orders (optional risk management)
   ManageTrades();
}

//+------------------------------------------------------------------+
//| Get scalping signal using RSI                                    |
//+------------------------------------------------------------------+
int GetScalpingSignal()
{
   // Calculate RSI
   double rsi = iRSI(Symbol(), Period(), RSIPeriod, PRICE_CLOSE);
   
   // Avoid invalid RSI values
   if (rsi == EMPTY_VALUE)
      return 0;
   
   // BUY signal: RSI oversold
   if (rsi < RSIOversold)
      return 1;
   
   // SELL signal: RSI overbought
   if (rsi > RSIOverbought)
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Open BUY order                                                    |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
   double lots = CalculateLotSize();
   double stopLoss = Bid - (StopLossPips * Point());
   double takeProfit = Ask + (TakeProfitPips * Point());
   
   // Create market buy order
   CTrade trade;
   trade.Buy(lots, Symbol(), Ask, stopLoss, takeProfit);
   
   if (trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      Print("BUY order opened successfully. Ticket: ", trade.ResultOrder());
   }
   else
   {
      Print("BUY order failed. Error: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Open SELL order                                                   |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
   double lots = CalculateLotSize();
   double stopLoss = Ask + (StopLossPips * Point());
   double takeProfit = Bid - (TakeProfitPips * Point());
   
   // Create market sell order
   CTrade trade;
   trade.Sell(lots, Symbol(), Bid, stopLoss, takeProfit);
   
   if (trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      Print("SELL order opened successfully. Ticket: ", trade.ResultOrder());
   }
   else
   {
      Print("SELL order failed. Error: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk management                      |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if (!UseRiskManagement)
      return LotSize;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercentage / 100.0);
   double pipsRisk = StopLossPips;
   
   // Calculate lot size
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   
   if (tickSize == 0 || tickValue == 0)
      return LotSize;
   
   double lots = riskAmount / (pipsRisk * tickSize * tickValue);
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   
   // Ensure lot size is within limits
   if (lots < minLot)
      lots = minLot;
   if (lots > maxLot)
      lots = maxLot;
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count open trades                                                |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionSelectByTicket(PositionGetTicket(i)))
      {
         if (PositionGetString(POSITION_SYMBOL) == Symbol() && 
             PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Manage open trades                                               |
//+------------------------------------------------------------------+
void ManageTrades()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionSelectByTicket(PositionGetTicket(i)))
      {
         if (PositionGetString(POSITION_SYMBOL) == Symbol() && 
             PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            // Additional trade management logic can be added here
            // E.g., trailing stop loss, break-even stops, etc.
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Custom utility functions                                         |
//+------------------------------------------------------------------+

// Calculate RSI indicator
double iRSI(string symbol, int timeframe, int period, int applied_price)
{
   int handle = iRSI(symbol, timeframe, period, applied_price);
   if (handle == INVALID_HANDLE)
      return EMPTY_VALUE;
   
   double buffer[];
   if (CopyBuffer(handle, 0, 0, 1, buffer) <= 0)
   {
      IndicatorRelease(handle);
      return EMPTY_VALUE;
   }
   
   IndicatorRelease(handle);
   return buffer[0];
}

//+------------------------------------------------------------------+
// END OF SCRIPT
//+------------------------------------------------------------------+
