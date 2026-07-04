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

datetime LastBar=0;
int RSIHandle;

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

double LowestBuyPrice()
{
   double lowest=DBL_MAX;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber)
         {
            double p=PositionGetDouble(POSITION_PRICE_OPEN);
            if(p<lowest) lowest=p;
         }
      }
   }
   return (lowest==DBL_MAX)?0:lowest;
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
   double rsi[3];
   ArraySetAsSeries(rsi,true);
   if(CopyBuffer(RSIHandle,0,0,3,rsi)<3) return false;

   bool sig1=(rsi[2] < RSI_OverSold && rsi[1] > RSI_OverSold);
   bool sig2=(rsi[2] > RSI_OverBought && rsi[1] < RSI_OverBought);

   return sig1 || sig2;
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

void OnTick()
{
   double Ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double Bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double spread=(Ask-Bid)/_Point;
   if(spread>MaxSpreadPoints) return;

   datetime bar=iTime(_Symbol,_Period,0);
   if(bar==LastBar) return;
   LastBar=bar;

   int total=CountBuys();

   if(total>0 && BasketProfit()>=BasketTP(total))
   {
      CloseAll();
      return;
   }

   if(!BuySignal()) return;

   if(total>0)
   {
      if(BarsSinceLastOrder()<MinBarsBetweenOrders)
         return;

      double lowest=LowestBuyPrice();

      if(Ask > lowest - DistancePips*PipSize())
         return;
   }

   double lot=(total==0)?StartLot:NormalizeDouble(LastLot()+LotStep,2);

   trade.Buy(lot,_Symbol,Ask,0,0,"RSI DCA BUY");
}
