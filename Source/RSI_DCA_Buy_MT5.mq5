#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double StartLot=0.01;
input double LotStep=0.02;
input int RSI_Period=14;
input double RSI_OverSold=30;
input double RSI_OverBought=70;
input int DistancePips=26;
input int MinBarsBetweenOrders=18;
input double MaxSpreadPoints=50;
input ulong MagicNumber=20260522;

input double TP1=3;
input double TP2=8;
input double TP3=16;
input double TP4=24;
input double TP_Add_After4=16;
bool WasOversold=false;
bool WasOverbought=false;

datetime LastBar=0;
int RSIHandle;

//==================================================
// Cycle Statistics
//==================================================

int      CycleID = 1;

datetime CycleStartTime = 0;

double   WorstFloating = 0.0;

double   LowestPriceReached = DBL_MAX;

int      MaxOrdersCurrentCycle = 0;

double TotalLotsCurrentCycle = 0.0;

double PipSize(){ return (_Digits==3 || _Digits==5) ? _Point*10 : _Point; }

int OnInit()
{
   RSIHandle=iRSI(_Symbol,_Period,RSI_Period,PRICE_CLOSE);
   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
}

double BasketTP(int n)
{
   if(n<=0) return 0;
   if(n==1) return TP1;
   if(n==2) return TP2;
   if(n==3) return TP3;
   if(n==4) return TP4;
   return TP4 + (n-4)*TP_Add_After4;
}

int CountBuys()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber)
            c++;
      }
   }
   return c;
}

double BasketProfit()
{
   double p=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber)
            p+=PositionGetDouble(POSITION_PROFIT);
      }
   }
   return p;
}

double LastBuyPrice()
{
   double price=0;
   datetime latest=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);

      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber)
         {
            datetime tm=
               (datetime)PositionGetInteger(POSITION_TIME);

            if(tm>latest)
            {
               latest=tm;
               price=PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }

   return price;
}

double LastLot()
{
   datetime latest=0;
   double lot=StartLot;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber)
         {
            datetime tm=(datetime)PositionGetInteger(POSITION_TIME);
            if(tm>latest)
            {
               latest=tm;
               lot=PositionGetDouble(POSITION_VOLUME);
            }
         }
      }
   }
   return lot;
}

int BarsSinceLastOrder()
{
   datetime latest=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber)
         {
            datetime tm=(datetime)PositionGetInteger(POSITION_TIME);
            if(tm>latest) latest=tm;
         }
      }
   }
   if(latest==0) return 9999;
   return iBarShift(_Symbol,_Period,latest,false);
}

bool BuySignal()
{
   double rsi[2];
   ArraySetAsSeries(rsi,true);

   if(CopyBuffer(RSIHandle,0,0,2,rsi) < 2)
      return false;

   double rsiClosed = rsi[1];

   bool signal=false;

   // Ghi nhớ quá bán
   if(rsiClosed < RSI_OverSold)
      WasOversold=true;

   if(WasOversold && rsiClosed > RSI_OverSold)
   {
      signal=true;
      WasOversold=false;
   }

   // Ghi nhớ quá mua
   if(rsiClosed > RSI_OverBought)
      WasOverbought=true;

   if(WasOverbought && rsiClosed < RSI_OverBought)
   {
      signal=true;
      WasOverbought=false;
   }

   return signal;
}

void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber)
            trade.PositionClose(t);
      }
   }
}
void ResetCycleStats()
{
   CycleID++;

   CycleStartTime = 0;

   WorstFloating = 0.0;

   LowestPriceReached = DBL_MAX;

   MaxOrdersCurrentCycle = 0;
   
   TotalLotsCurrentCycle = 0.0;
}
string FormatDuration(datetime startTime)
{
   if(startTime == 0)
      return "0m";

   int sec = (int)(TimeCurrent() - startTime);

   int days = sec / 86400;
   int hours = (sec % 86400) / 3600;
   int minutes = (sec % 3600) / 60;

   return StringFormat("%dd %02dh %02dm", days, hours, minutes);
}
double CalculateTotalLots()
{
   double totalLots = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
         continue;

      totalLots += PositionGetDouble(POSITION_VOLUME);
   }

   return totalLots;
}
void OnTick()
{
   double Ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double Bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double currentProfit = BasketProfit();
   double spread=(Ask-Bid)/_Point;
   if(spread>MaxSpreadPoints) return;

   datetime bar=iTime(_Symbol,_Period,0);
   if(bar==LastBar) return;
   LastBar=bar;

   int total=CountBuys();
   //==================================================
   // Update Cycle Statistics
   //==================================================
   
   if(total > 0)
   { 
      // Bắt đầu một Cycle mới
      if(CycleStartTime == 0)
      {
         CycleStartTime = TimeCurrent();
   
         WorstFloating = currentProfit;
   
         LowestPriceReached = Bid;
   
         MaxOrdersCurrentCycle = total;
      }
   
      // Floating thấp nhất
      if(currentProfit < WorstFloating)
         WorstFloating = currentProfit;
   
      // Giá thấp nhất
      if(Bid < LowestPriceReached)
         LowestPriceReached = Bid;
   
      // Số lệnh lớn nhất
      if(total > MaxOrdersCurrentCycle)
         MaxOrdersCurrentCycle = total;
         
      TotalLotsCurrentCycle = CalculateTotalLots();   
   }
   if(total>0 && currentProfit>=BasketTP(total))
   {
      Print("========================================");
      Print("Cycle #", CycleID);
      Print("Orders = ", MaxOrdersCurrentCycle);
      Print("Worst Floating = ", DoubleToString(WorstFloating,2));
      Print("Lowest Price = ", DoubleToString(LowestPriceReached,_Digits));
      Print("Basket Profit = ", DoubleToString(currentProfit,2));
      Print("Duration = ", FormatDuration(CycleStartTime));
      Print("========================================");
      CloseAll();
      ResetCycleStats();
      return;
   }

   if(!BuySignal()) return;

   if(total>0)
   {
      if(BarsSinceLastOrder()<MinBarsBetweenOrders)
         return;

      double lastPrice=LastBuyPrice();

      double distance=(lastPrice-Ask)/PipSize();
      
      if(distance < DistancePips)
         return;
   }

   double lot=(total==0)?StartLot:NormalizeDouble(LastLot()+LotStep,2);
   
   trade.Buy(lot,_Symbol);
}
